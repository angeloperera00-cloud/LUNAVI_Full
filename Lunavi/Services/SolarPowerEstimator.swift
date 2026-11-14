import Foundation

/// User-editable panel assumptions. Defaults are placeholders the user is expected to change; they are
/// always displayed as assumptions, never as a spacecraft configuration.
struct SolarPanelConfiguration: Hashable, Sendable {
    enum Orientation: Hashable, Sendable {
        /// Panel normal always points at the Sun (ideal two-axis tracking): incidence factor 1.
        case sunTracking
        /// Fixed panel. Tilt from horizontal (0° = facing straight up, 90° = vertical);
        /// azimuth of the direction the panel faces, clockwise from local north.
        case fixed(tiltDeg: Double, azimuthDeg: Double)
    }

    var areaSquareMeters: Double = 1.0
    /// Conversion efficiency, 0…1.
    var efficiency: Double = 0.30
    var orientation: Orientation = .sunTracking

    /// Problems that make the configuration unusable. Empty when valid.
    var validationErrors: [String] {
        var errors: [String] = []
        if !areaSquareMeters.isFinite || areaSquareMeters <= 0 { errors.append("Panel area must be greater than 0 m².") }
        if areaSquareMeters > 1_000 { errors.append("Panel area above 1000 m² is outside this estimate's scope.") }
        if !efficiency.isFinite || efficiency <= 0 || efficiency > 1 { errors.append("Efficiency must be between 0 and 100 %.") }
        if case .fixed(let tilt, let azimuth) = orientation {
            if !tilt.isFinite || tilt < 0 || tilt > 90 { errors.append("Tilt must be between 0° and 90°.") }
            if !azimuth.isFinite { errors.append("Panel azimuth must be a number.") }
        }
        return errors
    }
}

/// Where the irradiance value comes from.
enum IrradianceSource: String, Sendable {
    /// Scaled from the solar constant by the Sun's distance, derived from its exported angular radius.
    case sunDistance
    /// The reference solar constant at 1 AU (used only if the angular radius is unusable).
    case referenceSolarConstant
}

/// One instant of the estimate. `nil` fields are unknown (missing geometry or incomplete horizon).
struct SolarPowerSample: Hashable, Sendable {
    var time: Date
    var irradianceWm2: Double?
    var incidenceFactor: Double?
    /// Fraction of the solar disc area above the modeled terrain horizon (terrain shadowing).
    var visibleFraction: Double?
    var powerW: Double?
    var irradianceSource: IrradianceSource?
}

struct SolarPowerEstimate: Hashable, Sendable {
    enum Status: Hashable, Sendable {
        /// Every instant of the window has the inputs needed.
        case complete
        /// Part of the window lacks inputs; energy covers the known part only.
        case partial
        /// No instant of the window can be estimated.
        case unavailable(String)
        /// The panel assumptions are invalid; nothing was calculated.
        case invalidInputs([String])
    }

    var status: Status
    var window: UTCRange
    var configuration: SolarPanelConfiguration
    var samples: [SolarPowerSample]
    /// Trapezoidal integral over the parts of the window where both neighbouring samples are known.
    var energyWh: Double?
    var knownDuration: TimeInterval
    var peakPowerW: Double?
    /// Fraction of the known time with any part of the Sun above the terrain.
    var illuminatedFractionOfKnownTime: Double?

    var unknownDuration: TimeInterval { max(0, window.duration - knownDuration) }
    var meanPowerW: Double? {
        guard let energyWh, knownDuration > 0 else { return nil }
        return energyWh * 3600 / knownDuration
    }
}

/// Experimental, simplified photovoltaic estimate:
///
///     P = S(t) × A × η × max(0, n̂·ŝ) × f_disc(t)
///
/// * S(t): solar irradiance at the Moon = S₀ (1 AU / r)², with r = R☉ / sin(α) from the Sun's exported
///   apparent angular radius α. S₀ = 1361 W/m² (Kopp & Lean 2011, TSIS/TIM total solar irradiance at 1 AU).
/// * A, η: user-editable panel area and efficiency (assumptions).
/// * n̂·ŝ: cosine of the incidence angle between the panel normal and the Sun direction (local ENU).
///   This is geometry only and is kept separate from terrain shadowing.
/// * f_disc: fraction of the solar disc *area* above the modeled terrain horizon (same formula as the
///   pipeline's sunlight criterion, without the requirement clearance), i.e. terrain shadowing.
///
/// Ignores temperature, dust, degradation, wiring and conversion losses, panel self-shadowing,
/// the spectrum, and diffuse/reflected light. Not a spacecraft power or battery model.
enum SolarPowerEstimator {
    static let solarConstantWm2 = 1361.0
    static let sunRadiusKm = 695_700.0          // IAU 2015 nominal solar radius
    static let astronomicalUnitKm = 149_597_870.7

    // MARK: - Physics

    /// Irradiance from the Sun's apparent angular radius (degrees). Falls back to S₀ when unusable.
    static func irradiance(angularRadiusDeg: Double) -> (value: Double, source: IrradianceSource) {
        let alpha = angularRadiusDeg * .pi / 180
        guard alpha.isFinite, alpha > 0, alpha < .pi / 2 else { return (solarConstantWm2, .referenceSolarConstant) }
        let distanceKm = sunRadiusKm / sin(alpha)
        let au = distanceKm / astronomicalUnitKm
        return (solarConstantWm2 / (au * au), .sunDistance)
    }

    /// Unit vector toward a target in local east-north-up from azimuth (clockwise from north) and elevation.
    static func enu(azimuthDeg: Double, elevationDeg: Double) -> (e: Double, n: Double, u: Double) {
        let az = azimuthDeg * .pi / 180
        let el = elevationDeg * .pi / 180
        return (sin(az) * cos(el), cos(az) * cos(el), sin(el))
    }

    /// cos(incidence angle), clamped at 0 when the Sun is behind the panel.
    static func incidenceFactor(_ orientation: SolarPanelConfiguration.Orientation, sunAzimuthDeg: Double, sunElevationDeg: Double) -> Double {
        switch orientation {
        case .sunTracking:
            return 1
        case .fixed(let tilt, let azimuth):
            let normal = enu(azimuthDeg: azimuth, elevationDeg: 90 - tilt)
            let sun = enu(azimuthDeg: sunAzimuthDeg, elevationDeg: sunElevationDeg)
            return max(0, normal.e * sun.e + normal.n * sun.n + normal.u * sun.u)
        }
    }

    static func power(irradiance: Double, configuration: SolarPanelConfiguration, incidence: Double, visibleFraction: Double) -> Double {
        irradiance * configuration.areaSquareMeters * configuration.efficiency * incidence * min(1, max(0, visibleFraction))
    }

    // MARK: - Samples

    static func sample(at time: Date, geometry: ShadowGeometry, configuration: SolarPanelConfiguration) -> SolarPowerSample {
        var result = SolarPowerSample(time: time)
        guard let sun = ShadowAnalysisService.direction(geometry, condition: .sunlight, at: time) else { return result }
        let (value, source) = irradiance(angularRadiusDeg: sun.angularRadiusDeg)
        result.irradianceWm2 = value
        result.irradianceSource = source
        let incidence = incidenceFactor(configuration.orientation, sunAzimuthDeg: sun.azimuthDeg, sunElevationDeg: sun.elevationDeg)
        result.incidenceFactor = incidence
        guard let horizon = ShadowAnalysisService.horizonElevation(geometry, at: sun.azimuthDeg) else { return result }
        let fraction = ShadowAnalysisService.discFraction(elevation: sun.elevationDeg, horizon: horizon, radius: sun.angularRadiusDeg)
        result.visibleFraction = fraction
        result.powerW = power(irradiance: value, configuration: configuration, incidence: incidence, visibleFraction: fraction)
        return result
    }

    /// Window start, every exported sample instant inside the window, and the window end.
    static func sampleTimes(window: UTCRange, geometry: ShadowGeometry) -> [Date] {
        var times = [window.start]
        let step = geometry.samples.stepSeconds
        var index = max(0, Int((window.start.timeIntervalSince(geometry.samples.start) / step).rounded(.up)))
        while index < geometry.samples.count {
            let time = geometry.samples.start.addingTimeInterval(Double(index) * step)
            if time >= window.end { break }
            if time > window.start { times.append(time) }
            index += 1
        }
        if window.end > window.start { times.append(window.end) }
        return times
    }

    // MARK: - Estimate

    static func estimate(window: UTCRange, geometry: ShadowGeometry?, configuration: SolarPanelConfiguration) -> SolarPowerEstimate {
        var result = SolarPowerEstimate(status: .unavailable(""), window: window, configuration: configuration, samples: [],
                                        energyWh: nil, knownDuration: 0, peakPowerW: nil, illuminatedFractionOfKnownTime: nil)
        let errors = configuration.validationErrors
        guard errors.isEmpty else {
            result.status = .invalidInputs(errors)
            return result
        }
        guard !window.isEmpty else {
            result.status = .unavailable("The operating window is empty.")
            return result
        }
        guard let geometry else {
            result.status = .unavailable("No computed Sun geometry for this site. The simulated demo has none; computed scenarios need pipeline schema 2 or later.")
            return result
        }
        guard geometry.isConsistent else {
            result.status = .unavailable("The exported geometry for this site is inconsistent and was not used.")
            return result
        }

        let samples = sampleTimes(window: window, geometry: geometry).map { sample(at: $0, geometry: geometry, configuration: configuration) }
        result.samples = samples

        var energyWs = 0.0
        var known: TimeInterval = 0
        var lit: TimeInterval = 0
        for (a, b) in zip(samples, samples.dropFirst()) {
            guard let pa = a.powerW, let pb = b.powerW else { continue }
            let dt = b.time.timeIntervalSince(a.time)
            energyWs += 0.5 * (pa + pb) * dt
            known += dt
            if (a.visibleFraction ?? 0) > 0 || (b.visibleFraction ?? 0) > 0 { lit += dt }
        }
        let powers = samples.compactMap(\.powerW)
        result.peakPowerW = powers.max()
        result.knownDuration = known
        if known > 0 {
            result.energyWh = energyWs / 3600
            result.illuminatedFractionOfKnownTime = lit / known
        }
        if known <= 0 {
            result.status = .unavailable("The window lies outside the computed Sun samples (\(UTCFormat.dayMonthTime(geometry.firstSampleTime)) – \(UTCFormat.dayMonthTime(geometry.lastSampleTime)) UTC) or the terrain horizon toward the Sun is incomplete.")
        } else if known < window.duration - 1 {
            result.status = .partial
        } else {
            result.status = .complete
        }
        return result
    }

    static let limitations = [
        "Experimental, simplified estimate — not a spacecraft power, battery or endurance prediction.",
        "Panel area, efficiency and orientation are user assumptions, not a mission configuration.",
        "Ignores temperature, dust, degradation, wiring and conversion losses, self-shadowing, spectrum, and reflected or diffuse light.",
        "Terrain shadowing uses the modeled horizon (LOLA DEM) and its resolution limits; times without geometry are excluded, never assumed sunlit.",
        "Irradiance is scaled from 1361 W/m² at 1 AU by the Sun's distance derived from its exported angular radius (rounded to 0.0001°, ≈ 0.04 % irradiance).",
    ]
}
