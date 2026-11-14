import SwiftUI

/// Earth Visibility Windows: every modeled Earth line-of-sight window, obstruction and no-data stretch
/// for the plan's site, with the next window measured from the timeline cursor.
///
/// All values come from the scenario's Earth intervals through `EarthCommunicationWindowService`;
/// the mission result comes from `VisibilityEvaluator`. Selecting a row focuses the timeline on it.
/// Geometric line of sight only — not a radio-link prediction.
struct EarthCommunicationWindowsView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case missionWindow = "Mission window"
        case fullCoverage = "All computed data"
        var id: String { rawValue }
    }

    @Environment(MissionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var scope: Scope = .missionWindow

    private var siteID: String? { store.focusSiteID }
    private var plan: MissionPlan? { store.focusEvaluation?.plan ?? store.committedPlan }
    private var data: SiteVisibility? { store.visibility(for: siteID) }
    private var reference: Date { store.timelineCursor ?? plan?.start ?? Date(timeIntervalSince1970: 0) }

    private var period: UTCRange? {
        guard let plan else { return nil }
        switch scope {
        case .missionWindow:
            return plan.window
        case .fullCoverage:
            return data.flatMap { EarthCommunicationWindowService.hull($0.coverage) } ?? plan.window
        }
    }

    private var report: EarthWindowReport? {
        guard let siteID, let period else { return nil }
        return EarthCommunicationWindowService.report(siteID: siteID, data: data, period: period,
                                                      reference: reference, missionWindow: plan?.window)
    }

    var body: some View {
        NavigationStack {
            content
                .background(LunaviColors.backgroundSecondary)
                .navigationTitle("Earth Visibility Windows")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("earthWindows.done")
                    }
                }
        }
        .presentationBackground(LunaviColors.backgroundSecondary)
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .idle, .loading:
            ProgressView("Loading mission data…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Earth windows unavailable", systemImage: "exclamationmark.triangle", description: Text(message))
        case .loaded:
            if let report {
                loaded(report)
            } else {
                ContentUnavailableView("No mission plan", systemImage: "globe.europe.africa",
                                       description: Text("Choose a site and UTC start to see Earth visibility windows."))
            }
        }
    }

    private func loaded(_ report: EarthWindowReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LunaviSpacing.l) {
                if store.isSimulated {
                    Label("Simulated demo — illustrative intervals, not lunar data.", systemImage: "info.circle")
                        .font(LunaviTypography.captionEmphasis)
                        .foregroundStyle(LunaviColors.selectedTime)
                }
                header(report)
                if !report.hasData {
                    PanelCard {
                        Text("No computed data for this site. Earth visibility is Unknown for the whole period — never assumed visible.")
                            .font(LunaviTypography.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                nextWindowCard(report)
                periodBar(report)
                list(title: "Earth-visible windows", items: report.windows, color: LunaviColors.earthTrack, empty: "No Earth-visible window in this period.")
                list(title: "Earth obstructions", items: report.obstructions, color: LunaviColors.obstructionTrack, empty: "No known obstruction in this period.")
                list(title: "No computed data", items: report.unknowns, color: LunaviColors.unknown, empty: "Data covers the whole period.")
                footer
            }
            .font(LunaviTypography.body)
            .foregroundStyle(LunaviColors.textSecondary)
            .frame(maxWidth: 880, alignment: .leading)
            .padding(LunaviSpacing.xl)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Sections

    private func header(_ report: EarthWindowReport) -> some View {
        PanelCard {
            VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        siteTitle
                        Spacer()
                        scopePicker
                    }
                    VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                        siteTitle
                        scopePicker
                    }
                }
                Text("\(UTCFormat.full(report.period.start)) → \(UTCFormat.full(report.period.end))")
                    .font(LunaviTypography.measurement)
                    .foregroundStyle(LunaviColors.selectedTime)
                if let mission = report.mission {
                    HStack {
                        Text("Mission window requirement (\(plan?.durationHours ?? 0) h, uninterrupted)")
                            .font(LunaviTypography.caption)
                            .foregroundStyle(LunaviColors.textMuted)
                        Spacer()
                        ConditionStatusBadge(condition: .earthLineOfSight, status: mission.status)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("earthWindows.missionStatus")
                }
                KeyValueRow("In this period", "visible \(UTCFormat.duration(report.visibleDurationInPeriod)) · obstructed \(UTCFormat.duration(report.obstructedDurationInPeriod)) · no data \(UTCFormat.duration(report.unknownDurationInPeriod))")
            }
        }
    }

    private var siteTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(store.site(id: siteID)?.name ?? "—")
                .font(LunaviTypography.headline)
                .foregroundStyle(LunaviColors.textPrimary)
            Text(store.focusContextLabel)
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
        }
    }

    private var scopePicker: some View {
        Picker("Period", selection: $scope) {
            ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
        .accessibilityIdentifier("earthWindows.scope")
    }

    private func nextWindowCard(_ report: EarthWindowReport) -> some View {
        PanelCard(strokeColor: LunaviColors.earthTrack.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 6) {
                Text("From \(UTCFormat.full(report.reference)) (timeline cursor)").lunaviSectionLabel()
                switch report.stateAtReference {
                case .visible:
                    Label("Earth in line of sight now", systemImage: "globe.europe.africa")
                        .foregroundStyle(LunaviColors.earthTrack)
                    if let current = report.currentSegment {
                        Text(current.endBoundary == .transition
                             ? "Line of sight ends in \(UTCFormat.duration(current.range.end.timeIntervalSince(report.reference))) (\(UTCFormat.dayMonthTime(current.range.end)) UTC)."
                             : "Visible at least until \(UTCFormat.dayMonthTime(current.range.end)) UTC, where computed data ends.")
                    }
                case .obstructed:
                    Label("Earth obstructed by terrain now", systemImage: "mountain.2")
                        .foregroundStyle(LunaviColors.failure)
                case .unknown:
                    Label("No computed data at this time", systemImage: "questionmark.circle")
                        .foregroundStyle(LunaviColors.unknown)
                }
                switch report.next {
                case .upcoming(let window, let wait):
                    Text("Next modeled Earth-visible window starts in \(UTCFormat.duration(wait)): \(UTCFormat.full(window.range.start)).")
                        .font(LunaviTypography.bodyEmphasis)
                        .foregroundStyle(LunaviColors.textPrimary)
                        .accessibilityIdentifier("earthWindows.next")
                case .unknown(let reason):
                    Text(reason)
                        .font(LunaviTypography.bodyEmphasis)
                        .foregroundStyle(LunaviColors.unknown)
                        .accessibilityIdentifier("earthWindows.next")
                }
            }
            .font(LunaviTypography.body)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func periodBar(_ report: EarthWindowReport) -> some View {
        let clipped = report.segments.compactMap { segment -> ComparisonSegment? in
            segment.range.intersection(report.period).map { ComparisonSegment(range: $0, state: segment.state) }
        }
        return VStack(alignment: .leading, spacing: 4) {
            ComparisonBar(segments: clipped, visibleColor: LunaviColors.earthTrack, window: report.period)
            HStack {
                Text(UTCFormat.dayMonthTime(report.period.start))
                Spacer()
                Text(UTCFormat.dayMonthTime(report.period.end))
            }
            .font(LunaviTypography.measurementSmall)
            .foregroundStyle(LunaviColors.textMuted)
        }
    }

    private func list(title: String, items: [EarthVisibilitySegment], color: Color, empty: String) -> some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            Text("\(title) (\(items.count))").lunaviSectionLabel()
            if items.isEmpty {
                Text(empty)
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textMuted)
            }
            ForEach(items) { item in
                Button {
                    store.focusTimeline(on: item.range)
                    dismiss()
                } label: {
                    EarthWindowRow(segment: item, color: color)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Focuses the timeline on this interval.")
                .accessibilityIdentifier("earthWindows.row.\(item.state.rawValue)")
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            Text("How to read this").lunaviSectionLabel()
            Text("Times are UTC. Window ends marked as a data-coverage edge are where the computed data stops — the window may continue beyond it, so they are never reported as transitions. Time without data is shown as no data, never as visible.")
            Text("Earth line of sight is geometric only: Earth's disc above the modeled terrain horizon. It is not a radio-link, antenna, ground-station or link-budget prediction.")
        }
        .font(LunaviTypography.caption)
        .foregroundStyle(LunaviColors.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct EarthWindowRow: View {
    let segment: EarthVisibilitySegment
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: LunaviSpacing.m) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(UTCFormat.full(segment.range.start)) → \(UTCFormat.full(segment.range.end))")
                    .font(LunaviTypography.measurement)
                    .foregroundStyle(LunaviColors.textPrimary)
                Text(durationText)
                    .font(LunaviTypography.measurementSmall)
                    .foregroundStyle(LunaviColors.textSecondary)
                if segment.state != .unknown {
                    Text("Start: \(segment.startBoundary.note) · End: \(segment.endBoundary.note)")
                        .font(LunaviTypography.micro)
                        .foregroundStyle(LunaviColors.textMuted)
                }
                if segment.extendsBeforePeriod || segment.extendsAfterPeriod {
                    Text([segment.extendsBeforePeriod ? "began before this period" : nil,
                          segment.extendsAfterPeriod ? "continues after this period" : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(LunaviTypography.micro)
                        .foregroundStyle(LunaviColors.textMuted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "scope")
                .foregroundStyle(LunaviColors.textMuted)
                .accessibilityHidden(true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LunaviColors.surfaceElevated, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall + 2))
        .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall + 2).stroke(LunaviColors.border, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var durationText: String {
        let length = UTCFormat.duration(segment.duration)
        switch segment.state {
        case .visible:
            return segment.isDurationComplete ? "Uninterrupted for \(length)" : "Uninterrupted for at least \(length) (reaches the data edge)"
        case .obstructed:
            return segment.isDurationComplete ? "Obstructed for \(length)" : "Obstructed for at least \(length) (reaches the data edge)"
        case .unknown:
            return "No computed data for \(length)"
        }
    }
}

#Preview("Earth Visibility Windows — simulated", traits: .landscapeLeft) {
    PreviewHost(phase: .original) {
        EarthCommunicationWindowsView()
    }
}
