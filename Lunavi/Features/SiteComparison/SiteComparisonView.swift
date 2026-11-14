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
    @Environment(MapState.self) private var mapState
    @Environment(\.dismiss) private var dismiss
    @State private var source: WindowSource = .committed
    /// Site previewed in this screen. Previewing never changes the mission plan.
    @State private var previewSiteID: String?
    @State private var commitNote: String?

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
            content
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

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .idle, .loading:
            VStack(spacing: LunaviSpacing.m) {
                ProgressView()
                Text("Loading mission data…").font(LunaviTypography.body).foregroundStyle(LunaviColors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("comparison.loading")
        case .failed(let message):
            ContentUnavailableView("Comparison unavailable", systemImage: "exclamationmark.triangle", description: Text(message))
                .accessibilityIdentifier("comparison.error")
        case .loaded:
            if plan == nil || rows.isEmpty {
                ContentUnavailableView("No sites to compare", systemImage: "square.split.3x1",
                                       description: Text("The scenario has no mapped sites or no mission plan."))
                    .accessibilityIdentifier("comparison.empty")
            } else {
                results
            }
        }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LunaviSpacing.l) {
                if store.isSimulated {
                    Label("Simulated demo — illustrative intervals, not lunar data.", systemImage: "info.circle")
                        .font(LunaviTypography.captionEmphasis)
                        .foregroundStyle(LunaviColors.selectedTime)
                }
                windowHeader
                if let previewSiteID, let row = rows.first(where: { $0.siteID == previewSiteID }) {
                    previewBanner(row)
                }
                if let commitNote {
                    NoticeBanner(text: commitNote)
                        .accessibilityIdentifier("comparison.commitNote")
                }
                ForEach(rows) { row in
                    SiteComparisonCard(
                        row: row,
                        isPlanSite: row.siteID == plan?.siteID,
                        isPreviewed: row.siteID == previewSiteID,
                        commit: SiteComparisonService.commitAvailability(for: row, planSiteID: store.committedPlan?.siteID,
                                                                         canEditPlan: store.canEditParameters && source == .committed),
                        onPreview: { previewSiteID = (previewSiteID == row.siteID) ? nil : row.siteID },
                        onCommit: { commit(row) }
                    )
                }
                rulesFooter
            }
            .font(LunaviTypography.body)
            .foregroundStyle(LunaviColors.textSecondary)
            .frame(maxWidth: 880, alignment: .leading)
            .padding(LunaviSpacing.xl)
            .frame(maxWidth: .infinity)
        }
    }

    private func previewBanner(_ row: SiteComparisonRow) -> some View {
        PanelCard(strokeColor: LunaviColors.selectedTime.opacity(0.6)) {
            VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                HStack {
                    PreviewTag()
                    Text("\(row.siteName) at the same UTC window")
                        .font(LunaviTypography.bodyEmphasis)
                        .foregroundStyle(LunaviColors.textPrimary)
                }
                Text("Preview only — the mission plan is unchanged. Show it on the map, or commit it with Use for Plan.")
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    mapState.inspectedSiteID = row.siteID
                    if let point = store.site(id: row.siteID)?.mapPosition {
                        mapState.center(on: point)
                    }
                    dismiss()
                } label: {
                    Label("Show on Map", systemImage: "map")
                }
                .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                .accessibilityIdentifier("comparison.showOnMap")
            }
        }
        .accessibilityIdentifier("comparison.previewBanner")
    }

    private func commit(_ row: SiteComparisonRow) {
        guard SiteComparisonService.commitAvailability(for: row, planSiteID: store.committedPlan?.siteID,
                                                       canEditPlan: store.canEditParameters && source == .committed) == .available else { return }
        store.planMission(at: row.siteID)
        previewSiteID = nil
        if let plan = store.committedPlan, plan.siteID == row.siteID {
            commitNote = "Plan updated: \(row.siteName), \(UTCFormat.full(plan.start)) for \(plan.durationHours) h."
        }
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
    var isPreviewed = false
    var commit: ComparisonCommitAvailability = .noData
    var onPreview: () -> Void = {}
    var onCommit: () -> Void = {}

    var body: some View {
        PanelCard(strokeColor: isPlanSite || isPreviewed ? LunaviColors.selectedTime.opacity(0.7) : LunaviColors.border) {
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
                    KeyValueRow("Continuous from start", "Sun \(UTCFormat.duration(row.continuousFromStart(.sunlight))) · Earth \(UTCFormat.duration(row.continuousFromStart(.earthLineOfSight)))")
                    obstructionList
                } else {
                    Text("No computed data for this site — not analysed. Shown as Unknown, never as suitable.")
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textMuted)
                }
                actions
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comparison.site.\(row.siteID)")
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: LunaviSpacing.s) {
                if row.hasData && !isPlanSite {
                    Button(isPreviewed ? "End Preview" : "Preview", action: onPreview)
                        .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                        .accessibilityIdentifier("comparison.preview.\(row.siteID)")
                }
                Button("Use for Plan", action: onCommit)
                    .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                    .disabled(commit != .available)
                    .accessibilityHint(commit.reason ?? "Changes the committed mission plan to this site at the same UTC window.")
                    .accessibilityIdentifier("comparison.commit.\(row.siteID)")
            }
            if let reason = commit.reason, commit != .alreadyPlanSite {
                Text(reason)
                    .font(LunaviTypography.micro)
                    .foregroundStyle(LunaviColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
