import SwiftUI

/// Every mapped site evaluated over the same UTC window with the same rules as Mission Rescue.
/// Model results only: the screen does not rank sites. Mission Rescue's recovery rule is stated
/// separately so a result is never mistaken for a recommendation.
struct SiteComparisonView: View {
    enum WindowSource: String, CaseIterable, Identifiable {
        case committed = "Committed plan"
        case delayed = "Delayed plan"
        var id: String { rawValue }
    }

    @Environment(MissionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var source: WindowSource = .committed

    private var plan: MissionPlan? {
        switch source {
        case .committed:
            return store.committedPlan
        case .delayed:
            return store.delayedPlan ?? store.committedPlan
        }
    }

    private var rows: [SiteComparisonRow] {
        guard let plan, let scenario = store.scenario else { return [] }
        return SiteComparisonService.rows(start: plan.start, durationHours: plan.durationHours, sites: scenario.sites,
                                          visibility: scenario.visibility, geometry: scenario.geometry)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LunaviSpacing.l) {
                    if store.isSimulated {
                        Label("Simulated demo — illustrative intervals, not lunar data.", systemImage: "info.circle")
                            .font(LunaviTypography.captionEmphasis)
                            .foregroundStyle(LunaviColors.selectedTime)
                    }
                    windowHeader
                    ForEach(rows) { row in
                        SiteComparisonCard(row: row, isPlanSite: row.siteID == plan?.siteID)
                    }
                    rulesFooter
                }
                .font(LunaviTypography.body)
                .foregroundStyle(LunaviColors.textSecondary)
                .frame(maxWidth: 880, alignment: .leading)
                .padding(LunaviSpacing.xl)
            }
            .background(LunaviColors.backgroundSecondary)
            .navigationTitle("Site Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("comparison.done")
                }
            }
        }
        .presentationBackground(LunaviColors.backgroundSecondary)
    }

    private var windowHeader: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                HStack {
                    Text("Same window for every site").lunaviSectionLabel()
                    Spacer()
                    if store.delayedPlan != nil {
                        Picker("Window", selection: $source) {
                            ForEach(WindowSource.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)
                        .accessibilityIdentifier("comparison.windowPicker")
                    }
                }
                if let plan {
                    Text("\(UTCFormat.full(plan.start)) → \(UTCFormat.full(plan.end))")
                        .font(LunaviTypography.measurement)
                        .foregroundStyle(LunaviColors.selectedTime)
                    Text("\(plan.durationHours) h required, uninterrupted. A requirement is met only if it holds for the whole window; time without data counts as unknown, never as visible.")
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var rulesFooter: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            Text("Results, not recommendations").lunaviSectionLabel()
            Text("This screen shows model results for each site over the same window. It does not rank sites or judge landing safety. Mission Rescue uses one stated rule: the nearest other site that meets both requirements for the whole delayed window.")
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Earth line of sight is geometric only — not a radio-link prediction.")
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
        }
    }
}

struct SiteComparisonCard: View {
    let row: SiteComparisonRow
    let isPlanSite: Bool

    var body: some View {
        PanelCard(strokeColor: isPlanSite ? LunaviColors.selectedTime.opacity(0.7) : LunaviColors.border) {
            VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        title
                        Spacer(minLength: LunaviSpacing.s)
                        OverallStatusBadge(overall: row.evaluation.overall)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        title
                        OverallStatusBadge(overall: row.evaluation.overall)
                    }
                }
                if row.hasData {
                    conditionRow(row.evaluation.sunlight, color: LunaviColors.sunTrack, lowest: row.lowestSunClearanceDeg)
                    conditionRow(row.evaluation.earth, color: LunaviColors.earthTrack, lowest: row.lowestEarthClearanceDeg)
                    KeyValueRow("Data completeness", UTCFormat.percent(row.dataCompleteness),
                                valueColor: row.dataCompleteness < 1 ? LunaviColors.unknown : LunaviColors.textPrimary)
                    obstructionList
                } else {
                    Text("No computed data for this site — not analysed. Shown as Unknown, never as suitable.")
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textMuted)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comparison.site.\(row.siteID)")
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(row.siteName)
                    .font(LunaviTypography.headline)
                    .foregroundStyle(LunaviColors.textPrimary)
                if isPlanSite {
                    Text("PLAN SITE")
                        .font(LunaviTypography.micro.weight(.semibold))
                        .foregroundStyle(LunaviColors.selectedTime)
                }
            }
            Text(row.coordinate?.displayString ?? "No lunar coordinate — illustrative position")
                .font(LunaviTypography.measurementSmall)
                .foregroundStyle(LunaviColors.textMuted)
        }
    }

    private func conditionRow(_ assessment: ConditionAssessment, color: Color, lowest: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(assessment.condition.title, systemImage: assessment.condition.symbolName)
                    .font(LunaviTypography.captionEmphasis)
                    .foregroundStyle(color)
                Spacer()
                ConditionStatusBadge(condition: assessment.condition, status: assessment.status)
            }
            ComparisonBar(segments: SiteComparisonService.segments(for: assessment), visibleColor: color, window: assessment.window)
            HStack {
                Text("Visible \(UTCFormat.duration(assessment.visibleDuration)) · obstructed \(UTCFormat.duration(assessment.obstructedDuration)) · no data \(UTCFormat.duration(assessment.unknownDuration))")
                Spacer()
                if let lowest {
                    Text("lowest clearance \(ShadowAnalysisService.degrees(lowest))")
                        .foregroundStyle(lowest < 0 ? LunaviColors.failure : LunaviColors.textSecondary)
                }
            }
            .font(LunaviTypography.measurementSmall)
            .foregroundStyle(LunaviColors.textMuted)
        }
    }

    @ViewBuilder
    private var obstructionList: some View {
        let blocked = row.evaluation.assessments.flatMap { a in a.obstructedSegments.map { (a.condition, $0) } }
        if !blocked.isEmpty {
            Text("Obstruction intervals").lunaviSectionLabel()
            ForEach(Array(blocked.enumerated()), id: \.offset) { _, item in
                KeyValueRow(item.0.shortTitle, "\(UTCFormat.dayMonthTime(item.1.start)) → \(UTCFormat.dayMonthTime(item.1.end)) UTC (\(UTCFormat.duration(item.1.duration)))",
                            valueColor: LunaviColors.failure)
            }
        }
    }
}

/// Window bar: visible in the condition colour, obstructed in coral, no data in grey.
struct ComparisonBar: View {
    let segments: [ComparisonSegment]
    let visibleColor: Color
    let window: UTCRange

    var body: some View {
        Canvas { context, size in
            let total = max(window.duration, 1)
            for segment in segments {
                let x0 = CGFloat(segment.range.start.timeIntervalSince(window.start) / total) * size.width
                let x1 = CGFloat(segment.range.end.timeIntervalSince(window.start) / total) * size.width
                let rect = CGRect(x: x0, y: 0, width: max(x1 - x0, 1), height: size.height)
                context.fill(Path(rect), with: .color(color(for: segment.state)))
            }
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.map { "\($0.state.label) \(UTCFormat.dayMonthTime($0.range.start)) to \(UTCFormat.dayMonthTime($0.range.end))" }.joined(separator: ", "))
    }

    private func color(for state: PointState) -> Color {
        switch state {
        case .visible:
            return visibleColor
        case .obstructed:
            return LunaviColors.obstructionTrack
        case .unknown:
            return LunaviColors.unknown.opacity(0.35)
        }
    }
}

#Preview("Site Comparison — simulated", traits: .landscapeLeft) {
    PreviewHost(phase: .delayed) {
        SiteComparisonView()
    }
}
