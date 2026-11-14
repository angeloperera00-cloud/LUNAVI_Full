import SwiftUI

/// Lunar Shadow Analysis: why the Sun (and Earth) are or are not visible from a site at one instant.
///
/// The instant is the mission timeline cursor, so the map, timeline and this panel always agree.
/// Requirement states come from the visibility intervals; angles come from the exported geometry
/// (schema 2) and are interpolated only between computed samples. Missing data shows Data Unavailable.
struct ShadowAnalysisView: View {
    @Environment(MissionStore.self) private var store
    @Environment(MapState.self) private var mapState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSiteID: String?
    @State private var centeredOnSun = true

    /// Site chosen in the panel, else the site inspected on the map (if it has data), else the plan's site.
    private var siteID: String? {
        if let selectedSiteID { return selectedSiteID }
        if let inspected = mapState.inspectedSiteID, store.hasData(siteID: inspected) { return inspected }
        return store.focusSiteID
    }
    private var site: LunarSite? { store.site(id: siteID) }
    private var geometry: ShadowGeometry? { store.shadowGeometry(for: siteID) }
    private var visibility: SiteVisibility? { store.visibility(for: siteID) }
    private var time: Date { store.timelineCursor ?? store.committedPlan?.start ?? Date(timeIntervalSince1970: 0) }
    private var sun: ShadowReading { ShadowAnalysisService.reading(.sunlight, at: time, geometry: geometry, visibility: visibility) }
    private var earth: ShadowReading { ShadowAnalysisService.reading(.earthLineOfSight, at: time, geometry: geometry, visibility: visibility) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LunaviSpacing.xl) {
                    if store.isSimulated {
                        Label("Simulated demo — no computed terrain geometry exists, so angles are not shown.", systemImage: "info.circle")
                            .font(LunaviTypography.captionEmphasis)
                            .foregroundStyle(LunaviColors.selectedTime)
                    }
                    siteHeader
                    timeControl
                    readings
                    if let geometry, geometry.isConsistent {
                        horizonSection(geometry)
                        closeupSection(geometry)
                    }
                    if let delayed = store.delayedEvaluation, let failure = delayed.firstFailure {
                        RescueShadowSection(failure: failure, delayed: delayed) { siteID, time in
                            selectedSiteID = siteID
                            store.moveCursor(to: time)
                        }
                    }
                    methodFooter
                }
                .font(LunaviTypography.body)
                .foregroundStyle(LunaviColors.textSecondary)
                .frame(maxWidth: 880, alignment: .leading)
                .padding(LunaviSpacing.xl)
            }
            .background(LunaviColors.backgroundSecondary)
            .navigationTitle("Lunar Shadow Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("shadow.done")
                }
            }
        }
        .presentationBackground(LunaviColors.backgroundSecondary)
    }

    // MARK: - Site and time

    private var siteHeader: some View {
        HStack(alignment: .top, spacing: LunaviSpacing.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Analysis site").lunaviSectionLabel()
                Text(site?.name ?? "—")
                    .font(LunaviTypography.screenTitle)
                    .foregroundStyle(LunaviColors.textPrimary)
                    .accessibilityIdentifier("shadow.siteName")
                Text(site?.coordinate?.displayString ?? "No lunar coordinate — illustrative position")
                    .font(LunaviTypography.measurementSmall)
                    .foregroundStyle(LunaviColors.textMuted)
                if let geometry {
                    Text("Observer \(geometry.observerHeightMeters.formatted(.number.precision(.fractionLength(0...1)))) m above the DEM surface (\(geometry.surfaceHeightMeters.formatted(.number.precision(.fractionLength(1)))) m); horizon to \((geometry.horizon.maxDistanceMeters / 1000).formatted(.number.precision(.fractionLength(0)))) km")
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textMuted)
                }
            }
            Spacer()
            Menu {
                ForEach(store.sites.filter { store.hasData(siteID: $0.id) }) { option in
                    Button {
                        selectedSiteID = option.id
                    } label: {
                        if option.id == siteID {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(option.name)
                        }
                    }
                }
            } label: {
                Label("Change site", systemImage: "mappin.and.ellipse")
            }
            .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
            .accessibilityIdentifier("shadow.sitePicker")
        }
    }

    private var timeRange: ClosedRange<Date>? {
        if let geometry, geometry.isConsistent, geometry.firstSampleTime < geometry.lastSampleTime {
            return geometry.firstSampleTime...geometry.lastSampleTime
        }
        guard let coverage = visibility?.coverage, let first = coverage.map(\.start).min(),
              let last = coverage.map(\.end).max(), first < last else { return nil }
        return first...last
    }

    private var timeControl: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Inspection time (UTC)").lunaviSectionLabel()
                    Spacer()
                    Text(UTCFormat.full(time))
                        .font(LunaviTypography.measurement)
                        .foregroundStyle(LunaviColors.selectedTime)
                        .accessibilityIdentifier("shadow.time")
                }
                if let plan = store.focusEvaluation?.plan ?? store.committedPlan {
                    Text("Timeline cursor — moving it does not change the mission. Mission start: \(UTCFormat.full(plan.start)) for \(plan.durationHours) h.")
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("shadow.missionStart")
                }
                if let range = timeRange {
                    Slider(
                        value: Binding(
                            get: { min(max(time.timeIntervalSince1970, range.lowerBound.timeIntervalSince1970), range.upperBound.timeIntervalSince1970) },
                            set: { store.moveCursor(to: Date(timeIntervalSince1970: ($0 / 60).rounded() * 60)) }
                        ),
                        in: range.lowerBound.timeIntervalSince1970...range.upperBound.timeIntervalSince1970
                    )
                    .tint(LunaviColors.selectedTime)
                    .accessibilityLabel("UTC time")
                    .accessibilityValue(UTCFormat.spoken(time))
                    .accessibilityIdentifier("shadow.timeSlider")
                    HStack {
                        Text(UTCFormat.dayMonthTime(range.lowerBound))
                        Spacer()
                        Text(geometry != nil ? "Computed samples" : "Data coverage")
                        Spacer()
                        Text(UTCFormat.dayMonthTime(range.upperBound))
                    }
                    .font(LunaviTypography.micro)
                    .foregroundStyle(LunaviColors.textMuted)
                }
                HStack(spacing: LunaviSpacing.s) {
                    stepButton("−1 h", hours: -1)
                    stepButton("−10 min", hours: -1.0 / 6)
                    stepButton("+10 min", hours: 1.0 / 6)
                    stepButton("+1 h", hours: 1)
                    Spacer()
                    if let start = store.committedPlan?.start {
                        Button("Plan start") { store.moveCursor(to: start) }
                            .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                    }
                    if store.focusEvaluation?.firstFailure != nil {
                        Button("First failure") { store.jumpToFirstFailure() }
                            .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                            .accessibilityIdentifier("shadow.jumpToFailure")
                    }
                }
                Text("This is the mission timeline cursor: the map and timeline follow it. Moving it never changes the plan.")
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textMuted)
            }
        }
    }

    private func stepButton(_ title: String, hours: Double) -> some View {
        Button(title) { store.stepCursor(hours: hours) }
            .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
    }

    // MARK: - Readings

    private var readings: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: LunaviSpacing.l) {
                ShadowReadingCard(reading: sun)
                ShadowReadingCard(reading: earth)
            }
            VStack(spacing: LunaviSpacing.l) {
                ShadowReadingCard(reading: sun)
                ShadowReadingCard(reading: earth)
            }
        }
    }

    private func horizonSection(_ geometry: ShadowGeometry) -> some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            HStack {
                Text("360° horizon profile")
                    .font(LunaviTypography.headline)
                    .foregroundStyle(LunaviColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Picker("Chart window", selection: $centeredOnSun) {
                    Text("Centered on Sun").tag(true)
                    Text("0°–360°").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }
            Text("Grey columns are the modeled terrain horizon seen from the site, computed from LOLA elevation data out to \((geometry.horizon.maxDistanceMeters / 1000).formatted(.number.precision(.fractionLength(0)))) km with lunar curvature. A target is hidden when it sits inside the grey. The dashed line is the ideal horizon of a perfectly smooth Moon.")
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            PanelCard {
                HorizonProfileChart(geometry: geometry, sun: sun, earth: earth, centeredOnSun: centeredOnSun)
            }
            HStack(spacing: LunaviSpacing.l) {
                legend(color: LunaviColors.sunTrack, text: "Sun")
                legend(color: LunaviColors.earthTrack, text: "Earth")
                legend(color: LunaviColors.terrainFill, text: "Terrain")
                legend(color: LunaviColors.failureFill, text: "Terrain at target azimuth / blocked gap")
                legend(color: LunaviColors.unknown.opacity(0.4), text: "No terrain data")
            }
            .font(LunaviTypography.micro)
            .foregroundStyle(LunaviColors.textMuted)
        }
    }

    private func closeupSection(_ geometry: ShadowGeometry) -> some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            Text("Why is the Sun \(sun.disc == .fullyVisible ? "visible" : "blocked")?")
                .font(LunaviTypography.headline)
                .foregroundStyle(LunaviColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if sun.direction != nil {
                DiscCloseupView(geometry: geometry, reading: sun, color: LunaviColors.sunTrack)
                Text("Looking toward the Sun, drawn to scale (1° is the same length both ways). The terrain silhouette covers whatever part of the solar disc is hidden.")
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textMuted)
            }
            Text(ShadowAnalysisService.explanation(for: sun))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shadow.explanation")
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            Text(text)
        }
    }

    // MARK: - Method

    private var methodFooter: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            Text("Calculation, visualization and validation")
                .font(LunaviTypography.headline)
                .foregroundStyle(LunaviColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            KeyValueRow("Calculation", store.isSimulated ? "None — simulated fixture" : "LUNAVI science pipeline: NAIF SPICE directions + LOLA horizon masks")
            KeyValueRow("Ephemeris", store.metadata?.ephemeris ?? "—")
            KeyValueRow("Visualization", "Exported samples, linearly interpolated between samples only")
            ForEach(store.metadata?.validation ?? []) { record in
                KeyValueRow("Validation · \(record.component)", record.level.label)
            }
            Text("A working chart is not a validation. Each validation record above says what has been independently checked, and against what.")
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Reading card

struct ShadowReadingCard: View {
    let reading: ShadowReading

    private var name: String { reading.condition == .sunlight ? "Sun" : "Earth" }

    var body: some View {
        PanelCard(strokeColor: reading.requirementState == .obstructed ? LunaviColors.failure.opacity(0.7) : LunaviColors.border) {
            VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                HStack {
                    Label(reading.condition.title, systemImage: reading.condition.symbolName)
                        .font(LunaviTypography.bodyEmphasis)
                        .foregroundStyle(reading.condition == .sunlight ? LunaviColors.sunTrack : LunaviColors.earthTrack)
                    Spacer()
                    requirementBadge
                }
                if let direction = reading.direction {
                    KeyValueRow("\(name) azimuth", ShadowAnalysisService.degrees(direction.azimuthDeg, sign: false))
                    KeyValueRow("\(name) elevation", ShadowAnalysisService.degrees(direction.elevationDeg))
                    KeyValueRow("Ideal horizon (smooth Moon)", (reading.isAboveIdealHorizon ?? false) ? "Above 0°" : "Below 0°")
                    if let horizon = reading.terrainHorizonDeg, let clearance = reading.clearanceDeg,
                       let fraction = reading.discFraction, let disc = reading.disc {
                        KeyValueRow("Terrain horizon at that azimuth", ShadowAnalysisService.degrees(horizon))
                        KeyValueRow("Clearance above terrain", ShadowAnalysisService.degrees(clearance),
                                    valueColor: clearance < 0 ? LunaviColors.failure : LunaviColors.textPrimary)
                        KeyValueRow("Disc above terrain", "\((fraction * 100).formatted(.number.precision(.fractionLength(0)))) % · \(disc.label)",
                                    valueColor: disc == .obstructed ? LunaviColors.failure : LunaviColors.textPrimary)
                    } else {
                        KeyValueRow("Terrain horizon", "Data Unavailable", valueColor: LunaviColors.unknown)
                    }
                    KeyValueRow("Angular radius", ShadowAnalysisService.degrees(direction.angularRadiusDeg, sign: false))
                } else {
                    Text("Data Unavailable")
                        .font(LunaviTypography.bodyEmphasis)
                        .foregroundStyle(LunaviColors.unknown)
                }
                KeyValueRow("Requirement", reading.condition == .sunlight
                            ? "≥ \(Int((reading.requiredFraction * 100).rounded())) % of the disc above terrain"
                            : "Any part of the disc above terrain")
                if let reason = reading.unavailableReason {
                    Text(reason)
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = boundaryNote {
                    Text(note)
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shadow.reading.\(reading.condition.rawValue)")
    }

    private var requirementBadge: some View {
        let style = Self.badgeStyle(for: reading.requirementState)
        return Label(style.text, systemImage: style.symbol)
            .font(LunaviTypography.captionEmphasis)
            .foregroundStyle(style.color)
            .accessibilityIdentifier("shadow.state.\(reading.condition.rawValue)")
    }

    private static func badgeStyle(for state: PointState) -> (text: String, color: Color, symbol: String) {
        switch state {
        case .visible:
            return ("Requirement met", LunaviColors.success, "checkmark.circle")
        case .obstructed:
            return ("Obstructed", LunaviColors.failure, "exclamationmark.triangle")
        case .unknown:
            return ("Unknown", LunaviColors.unknown, "questionmark.circle")
        }
    }

    /// Interpolated geometry can disagree with the bisected intervals within one sample step of a
    /// transition. The badge always follows the intervals; this note says so when they differ.
    private var boundaryNote: String? {
        guard let fraction = reading.discFraction, reading.requirementState != .unknown else { return nil }
        let geometricallyMet = reading.condition == .sunlight ? fraction >= reading.requiredFraction : fraction > 0
        guard geometricallyMet != (reading.requirementState == .visible) else { return nil }
        return "This instant is within one sampling step of a computed transition. The status follows the transition time found by bisection (±30 s); the angles are interpolated between samples."
    }
}

// MARK: - Mission Rescue

/// Explains a delayed-plan failure in terms of terrain and compares the recovery options.
struct RescueShadowSection: View {
    @Environment(MissionStore.self) private var store
    let failure: FailureEvent
    let delayed: PlanEvaluation
    let show: (_ siteID: String, _ time: Date) -> Void

    private var siteID: String { delayed.plan.siteID }
    private var condition: VisibilityCondition { failure.condition }
    private var name: String { condition == .sunlight ? "Sun" : "Earth" }
    private var geometry: ShadowGeometry? { store.shadowGeometry(for: siteID) }
    private var reading: ShadowReading {
        ShadowAnalysisService.reading(condition, at: failure.time, geometry: geometry, visibility: store.visibility(for: siteID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.m) {
            Text("Mission Rescue — why the delayed plan fails")
                .font(LunaviTypography.headline)
                .foregroundStyle(LunaviColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            PanelCard(strokeColor: LunaviColors.failure.opacity(0.6)) {
                VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                    Label("\(condition.title) fails at \(store.site(id: siteID)?.name ?? siteID)", systemImage: "exclamationmark.triangle")
                        .font(LunaviTypography.bodyEmphasis)
                        .foregroundStyle(LunaviColors.failure)
                    Text(cause)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("shadow.rescue.cause")
                    if let episode = ShadowAnalysisService.obstructionEpisode(condition, at: failure.time, visibility: store.visibility(for: siteID)) {
                        KeyValueRow("Obstruction begins", UTCFormat.full(episode.start))
                        KeyValueRow("Obstruction ends", episode.end.map(UTCFormat.full) ?? "Not within the computed data")
                    }
                    if let clearance = reading.clearanceDeg, let direction = reading.direction {
                        KeyValueRow("\(name) at failure", "az \(ShadowAnalysisService.degrees(direction.azimuthDeg, sign: false)), el \(ShadowAnalysisService.degrees(direction.elevationDeg))")
                        KeyValueRow("Clearance above terrain", ShadowAnalysisService.degrees(clearance), valueColor: clearance < 0 ? LunaviColors.failure : LunaviColors.textPrimary)
                    }
                    Button {
                        show(siteID, failure.time)
                    } label: {
                        Label("Show the failure moment", systemImage: "scope")
                    }
                    .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                    .accessibilityIdentifier("shadow.rescue.showFailure")
                }
            }
            comparisons
        }
        .accessibilityIdentifier("shadow.rescue")
    }

    private var cause: String {
        guard let direction = reading.direction else {
            return "\(failure.condition.title) is unavailable from \(UTCFormat.full(failure.time)) according to the visibility data. The terrain geometry needed to show the cause is not available for this site or time."
        }
        if direction.elevationDeg <= 0 {
            return "The \(name) is below even the ideal (smooth-Moon) horizon at \(ShadowAnalysisService.degrees(direction.elevationDeg)). This is not a terrain effect: the \(name) has set for every site at this latitude."
        }
        if let clearance = reading.clearanceDeg, clearance < 0 || (reading.discFraction ?? 1) < reading.requiredFraction {
            return "Modeled terrain obstruction. The \(name) is above the ideal horizon, but terrain toward azimuth \(ShadowAnalysisService.degrees(direction.azimuthDeg, sign: false)) rises above it, so the \(condition == .sunlight ? "required half of the solar disc is" : "whole disc is") hidden."
        }
        return "The failure time is a computed transition; at that exact instant the \(name) is just at the terrain horizon (clearance \(ShadowAnalysisService.degrees(reading.clearanceDeg ?? 0)))."
    }

    @ViewBuilder
    private var comparisons: some View {
        let delayedClearance = ShadowAnalysisService.minimumClearance(condition, over: delayed.plan.window, geometry: geometry)
        if store.candidates.isEmpty {
            alternativeSitesAtFailure
        } else {
            Text("Recovery options compared").lunaviSectionLabel()
            ForEach(store.candidates) { candidate in
                let candidateGeometry = store.shadowGeometry(for: candidate.plan.siteID)
                let lowest = ShadowAnalysisService.minimumClearance(condition, over: candidate.plan.window, geometry: candidateGeometry)
                PanelCard {
                    VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                        Text("\(candidate.kind.letter) · \(candidate.siteName) · \(UTCFormat.dayMonthTime(candidate.plan.start)) → \(UTCFormat.dayMonthTime(candidate.plan.end)) UTC")
                            .font(LunaviTypography.bodyEmphasis)
                            .foregroundStyle(LunaviColors.textPrimary)
                        KeyValueRow("Lowest \(name) clearance in this window", lowest.map { ShadowAnalysisService.degrees($0) } ?? "Data Unavailable",
                                    valueColor: lowest == nil ? LunaviColors.unknown : LunaviColors.textPrimary)
                        KeyValueRow("Lowest in the delayed window", delayedClearance.map { ShadowAnalysisService.degrees($0) } ?? "Data Unavailable",
                                    valueColor: (delayedClearance ?? 0) < 0 ? LunaviColors.failure : LunaviColors.textPrimary)
                        Text(improvement(candidate: candidate, lowest: lowest))
                            .font(LunaviTypography.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            show(candidate.plan.siteID, candidate.kind == .alternativeSite ? failure.time : candidate.plan.start)
                        } label: {
                            Label(candidate.kind == .alternativeSite ? "Show this site at the failure time" : "Show the new start", systemImage: "scope")
                        }
                        .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                    }
                }
                .accessibilityIdentifier("shadow.rescue.\(candidate.kind.rawValue)")
            }
            Text("Clearances are taken at every computed sample inside each window. The requirement badges in Mission Rescue come from the bisected intervals.")
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
        }
    }

    private func improvement(candidate: RecoveryCandidate, lowest: Double?) -> String {
        guard let lowest else {
            return "No computed geometry covers this window, so the improvement cannot be shown in angles. The option is valid according to the visibility intervals."
        }
        switch candidate.kind {
        case .sameSiteLaterTime:
            return "Starting later moves the window past the obstruction: across the whole window the \(name) stays at least \(ShadowAnalysisService.degrees(lowest, sign: false)) \(lowest >= 0 ? "above" : "relative to") the modeled terrain."
        case .alternativeSite:
            return "Same time, different place: the terrain around \(candidate.siteName) is lower toward the \(name), which stays at least \(ShadowAnalysisService.degrees(lowest, sign: false)) \(lowest >= 0 ? "above" : "relative to") its horizon for the whole window."
        }
    }

    @ViewBuilder
    private var alternativeSitesAtFailure: some View {
        let others = store.sites.filter { $0.id != siteID && store.shadowGeometry(for: $0.id) != nil }
        if !others.isEmpty {
            Text("Other sites at the failure time").lunaviSectionLabel()
            ForEach(others) { other in
                let r = ShadowAnalysisService.reading(condition, at: failure.time,
                                                       geometry: store.shadowGeometry(for: other.id), visibility: store.visibility(for: other.id))
                KeyValueRow(other.name, r.clearanceDeg.map { "\(ShadowAnalysisService.degrees($0)) clearance · \(r.requirementState.label)" } ?? "Data Unavailable",
                            valueColor: r.requirementState == .visible ? LunaviColors.success : (r.requirementState == .obstructed ? LunaviColors.failure : LunaviColors.unknown))
            }
            Text("Use Find Recovery Options to check whole operating windows, not just this instant.")
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
        }
    }
}

#Preview("Shadow Analysis — simulated (Data Unavailable)", traits: .landscapeLeft) {
    PreviewHost(phase: .delayed) {
        ShadowAnalysisView()
    }
}
