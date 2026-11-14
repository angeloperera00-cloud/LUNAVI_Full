import Foundation

/// How much of a target's disc is above the modeled terrain horizon (plus the minimum clearance).
enum DiscVisibility: String, Sendable {
    case fullyVisible
    case partiallyVisible
    case obstructed

    var label: String {
        switch self {
        case .fullyVisible:
            return "Fully visible"
        case .partiallyVisible:
            return "Partially visible"
        case .obstructed:
            return "Obstructed"
        }
    }
}

struct TargetDirection: Hashable, Sendable {
    var azimuthDeg: Double
    var elevationDeg: Double
    var angularRadiusDeg: Double
}

/// Everything shadow analysis shows for one condition at one instant.
///
/// `requirementState` always comes from the exported visibility intervals (bisected to ±30 s by the
/// pipeline). The geometry fields explain that state; they are interpolated between exported samples
/// and are `nil` whenever the data does not cover the instant or the horizon sector.
struct ShadowReading: Hashable, Sendable {
    var condition: VisibilityCondition
    var time: Date
    var requirementState: PointState
    var direction: TargetDirection?
    var terrainHorizonDeg: Double?
    var discFraction: Double?
    var disc: DiscVisibility?
    var requiredFraction: Double
    var minimumClearanceDeg: Double
    var unavailableReason: String?

    /// Target elevation minus terrain horizon at the target's azimuth (positive = above the terrain).
    var clearanceDeg: Double? {
        guard let direction, let terrainHorizonDeg else { return nil }
        return direction.elevationDeg - terrainHorizonDeg
    }

    /// Ideal-horizon geometry: above the local horizontal of a smooth Moon, ignoring all terrain.
    var isAboveIdealHorizon: Bool? {
        direction.map { $0.elevationDeg > 0 }
    }

    var hasGeometry: Bool { direction != nil }
}

/// One horizon ray positioned for a chart, with its azimuth mapped into the chart's window.
struct HorizonChartPoint: Identifiable, Hashable, Sendable {
    var id: Int
    /// Chart x position (degrees); equals the true azimuth modulo 360.
    var x: Double
    var azimuthDeg: Double
    var elevationDeg: Double
    var isComplete: Bool
}

/// A stretch during which a condition is not met, from the visibility intervals.
struct ObstructionEpisode: Hashable, Sendable {
    var condition: VisibilityCondition
    var start: Date
    /// When visibility returns; `nil` when it does not return inside the data coverage.
    var end: Date?
}

/// Pure shadow-analysis calculations shared by the panel, Mission Rescue and the tests.
enum ShadowAnalysisService {
    // MARK: - Disc criterion (same formula as the pipeline's visibility.py)

    /// Visible fraction of a disc of angular radius `radius` whose centre is at `elevation`, above a
    /// straight horizon at `horizon + clearance` (degrees).
    static func discFraction(elevation: Double, horizon: Double, radius: Double, clearance: Double = 0) -> Double {
        let line = horizon + clearance
        guard radius > 0 else { return elevation >= line ? 1 : 0 }
        let d = min(1, max(-1, (elevation - line) / radius))
        return (acos(-d) + d * (1 - d * d).squareRoot()) / .pi
    }

    static func discVisibility(fraction: Double) -> DiscVisibility {
        if fraction >= 0.999 { return .fullyVisible }
        if fraction <= 0.001 { return .obstructed }
        return .partiallyVisible
    }

    /// The fraction each requirement needs: half the solar disc (centre above the horizon) for the Sun;
    /// any part of the disc for Earth (the PGDA product 69 criterion).
    static func requiredFraction(for condition: VisibilityCondition, geometry: ShadowGeometry?) -> Double {
        switch condition {
        case .sunlight:
            return geometry?.sunMinimumDiscFraction ?? 0.5
        case .earthLineOfSight:
            return 0
        }
    }

    // MARK: - Angles

    /// Degrees normalised to [0, 360).
    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// Signed shortest difference `to - from`, in (-180, 180].
    static func signedDifference(from: Double, to: Double) -> Double {
        var delta = normalized(to - from)
        if delta > 180 { delta -= 360 }
        return delta
    }

    // MARK: - Horizon

    /// Terrain horizon elevation at `azimuth`, interpolated between the two neighbouring rays with 360°
    /// wraparound. `nil` if either ray is incomplete or the geometry is inconsistent.
    static func horizonElevation(_ geometry: ShadowGeometry, at azimuth: Double) -> Double? {
        guard geometry.isConsistent else { return nil }
        let rays = geometry.horizon.elevationsDeg
        let step = geometry.horizon.azimuthStepDeg
        let position = normalized(azimuth) / step
        let lower = Int(position.rounded(.down)) % rays.count
        let upper = (lower + 1) % rays.count
        guard geometry.horizon.complete[lower], geometry.horizon.complete[upper] else { return nil }
        let t = position - position.rounded(.down)
        return rays[lower] + (rays[upper] - rays[lower]) * t
    }

    /// Horizon rays positioned in a 360° chart window centred on `center` (180 gives 0…360).
    /// The window is closed with a copy of the first ray at its right edge, so the profile has no gap.
    static func chartPoints(_ geometry: ShadowGeometry, centeredOn center: Double = 180) -> [HorizonChartPoint] {
        guard geometry.isConsistent else { return [] }
        let step = geometry.horizon.azimuthStepDeg
        var points = geometry.horizon.elevationsDeg.indices.map { index -> HorizonChartPoint in
            let azimuth = Double(index) * step
            return HorizonChartPoint(
                id: index,
                x: chartX(for: azimuth, centeredOn: center),
                azimuthDeg: azimuth,
                elevationDeg: geometry.horizon.elevationsDeg[index],
                isComplete: geometry.horizon.complete[index]
            )
        }
        points.sort { $0.x < $1.x }
        if let first = points.first {
            var closing = first
            closing.id = geometry.horizon.elevationsDeg.count
            closing.x = first.x + 360
            points.append(closing)
        }
        return points
    }

    /// Chart x for an azimuth in a window [center − 180, center + 180).
    static func chartX(for azimuth: Double, centeredOn center: Double = 180) -> Double {
        center - 180 + normalized(azimuth - (center - 180))
    }

    // MARK: - Target directions

    /// Target direction at `date`, linearly interpolated between the two neighbouring samples
    /// (azimuth the short way round 360°). `nil` outside the sampled period: never extrapolated.
    static func direction(_ geometry: ShadowGeometry, condition: VisibilityCondition, at date: Date) -> TargetDirection? {
        guard geometry.isConsistent else { return nil }
        let samples = geometry.samples
        let offset = date.timeIntervalSince(samples.start) / samples.stepSeconds
        guard offset >= 0, offset <= Double(samples.count - 1) + 1e-9 else { return nil }
        let track = geometry.track(for: condition)
        if samples.count == 1 {
            return TargetDirection(azimuthDeg: track.azimuthDeg[0], elevationDeg: track.elevationDeg[0], angularRadiusDeg: track.angularRadiusDeg[0])
        }
        let index = min(Int(offset.rounded(.down)), samples.count - 2)
        let t = min(1, offset - Double(index))
        func lerp(_ values: [Double]) -> Double { values[index] + (values[index + 1] - values[index]) * t }
        let delta = signedDifference(from: track.azimuthDeg[index], to: track.azimuthDeg[index + 1])
        return TargetDirection(
            azimuthDeg: normalized(track.azimuthDeg[index] + delta * t),
            elevationDeg: lerp(track.elevationDeg),
            angularRadiusDeg: lerp(track.angularRadiusDeg)
        )
    }

    // MARK: - Readings

    static func reading(_ condition: VisibilityCondition, at date: Date,
                        geometry: ShadowGeometry?, visibility: SiteVisibility?) -> ShadowReading {
        var reading = ShadowReading(
            condition: condition,
            time: date,
            requirementState: visibility?.state(of: condition, at: date) ?? .unknown,
            requiredFraction: requiredFraction(for: condition, geometry: geometry),
            minimumClearanceDeg: geometry?.minimumClearanceDeg ?? 0
        )
        guard let geometry else {
            reading.unavailableReason = "No computed geometry for this site. The simulated demo has none; computed scenarios need pipeline schema 2."
            return reading
        }
        guard geometry.isConsistent else {
            reading.unavailableReason = "The exported geometry for this site is inconsistent and was not used."
            return reading
        }
        guard let direction = direction(geometry, condition: condition, at: date) else {
            reading.unavailableReason = "This time is outside the computed samples (\(UTCFormat.dayMonthTime(geometry.firstSampleTime)) – \(UTCFormat.dayMonthTime(geometry.lastSampleTime)) UTC)."
            return reading
        }
        reading.direction = direction
        guard let horizon = horizonElevation(geometry, at: direction.azimuthDeg) else {
            reading.unavailableReason = "The terrain horizon toward this azimuth is not fully covered by the elevation data."
            return reading
        }
        reading.terrainHorizonDeg = horizon
        let fraction = discFraction(elevation: direction.elevationDeg, horizon: horizon,
                                    radius: direction.angularRadiusDeg, clearance: geometry.minimumClearanceDeg)
        reading.discFraction = fraction
        reading.disc = discVisibility(fraction: fraction)
        return reading
    }

    // MARK: - Episodes and comparisons

    /// The not-visible stretch that contains (or starts at) `date`, taken from the intervals.
    static func obstructionEpisode(_ condition: VisibilityCondition, at date: Date, visibility: SiteVisibility?) -> ObstructionEpisode? {
        guard let visibility, visibility.state(of: condition, at: date) == .obstructed else { return nil }
        let intervals = visibility.intervals(for: condition).sorted { $0.start < $1.start }
        // Starts where the last visible interval ended (if that instant has data), else where coverage begins.
        let start: Date
        if let previousEnd = intervals.last(where: { $0.end <= date })?.end,
           visibility.coverage.contains(where: { $0.contains(previousEnd) }) {
            start = previousEnd
        } else {
            start = visibility.coverage.first(where: { $0.contains(date) })?.start ?? date
        }
        let next = intervals.first(where: { $0.start > date })
        let end: Date? = next.flatMap { candidate in
            // Visibility returns only if coverage is unbroken from the obstruction to the return.
            let span = UTCRange(start: date, end: candidate.start)
            return IntervalMath.covers(visibility.coverage, window: span) ? candidate.start : nil
        }
        return ObstructionEpisode(condition: condition, start: start, end: end)
    }

    /// Smallest clearance above the terrain over a window, from the exported samples inside it.
    /// `nil` unless every sample in the window has a complete reading.
    static func minimumClearance(_ condition: VisibilityCondition, over window: UTCRange, geometry: ShadowGeometry?) -> Double? {
        guard let geometry, geometry.isConsistent,
              window.start >= geometry.firstSampleTime, window.end <= geometry.lastSampleTime else { return nil }
        var times: [Date] = [window.start]
        let firstIndex = Int((window.start.timeIntervalSince(geometry.samples.start) / geometry.samples.stepSeconds).rounded(.up))
        var index = max(firstIndex, 0)
        while index < geometry.samples.count {
            let time = geometry.samples.start.addingTimeInterval(Double(index) * geometry.samples.stepSeconds)
            guard time < window.end else { break }
            times.append(time)
            index += 1
        }
        var lowest: Double?
        for time in times {
            guard let direction = direction(geometry, condition: condition, at: time),
                  let horizon = horizonElevation(geometry, at: direction.azimuthDeg) else { return nil }
            let clearance = direction.elevationDeg - horizon
            lowest = min(lowest ?? clearance, clearance)
        }
        return lowest
    }

    // MARK: - Plain-language explanation

    static func explanation(for reading: ShadowReading) -> String {
        let name = reading.condition == .sunlight ? "Sun" : "Earth"
        guard let direction = reading.direction else {
            return reading.unavailableReason ?? "Data unavailable."
        }
        let elevation = Self.degrees(direction.elevationDeg)
        let azimuth = Self.degrees(direction.azimuthDeg, sign: false)
        guard let horizon = reading.terrainHorizonDeg, let fraction = reading.discFraction else {
            return "The \(name) is at azimuth \(azimuth), elevation \(elevation). " + (reading.unavailableReason ?? "")
        }
        let ideal = direction.elevationDeg > 0
            ? "It is above the ideal (flat-Moon) horizon"
            : "It is below even the ideal (flat-Moon) horizon"
        let requirement = reading.condition == .sunlight
            ? "LUNAVI requires at least \(Int((reading.requiredFraction * 100).rounded())) % of the solar disc."
            : "LUNAVI requires any part of Earth's disc."
        let terrain: String
        if let clearance = reading.clearanceDeg, clearance >= 0 {
            terrain = "and \(Self.degrees(clearance, sign: false)) above the modeled terrain, which rises to \(Self.degrees(horizon)) toward azimuth \(azimuth)"
        } else {
            terrain = "but the modeled terrain toward azimuth \(azimuth) rises to \(Self.degrees(horizon)), \(Self.degrees(-(reading.clearanceDeg ?? 0), sign: false)) higher than the \(name)'s centre"
        }
        let disc = "\(Int((fraction * 100).rounded())) % of the disc is above the terrain."
        return "\(ideal) at \(elevation), \(terrain). \(disc) \(requirement)"
    }

    static func degrees(_ value: Double, sign: Bool = true) -> String {
        let text = abs(value).formatted(.number.precision(.fractionLength(2)))
        guard sign else { return "\(text)°" }
        return (value < 0 ? "−" : "+") + "\(text)°"
    }
}
