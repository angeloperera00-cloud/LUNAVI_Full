import Foundation
import Observation

/// Single source of truth for mission state.
///
/// The original plan is stored separately from every revision. Map panning/zooming and timeline
/// scrubbing never touch mission data; previewing never commits; Apply is a real state transition;
/// Reset restores every value from the scenario defaults.
@MainActor
@Observable
final class MissionStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum PrimaryAction: Equatable {
        case simulateDelay
        case findRecoveryOptions
        case acceptDelayedPlan
        case applyCandidate(enabled: Bool)
        case resetDemo
    }

    struct SensitivityRow: Identifiable, Hashable {
        var id: String
        var label: String
        var observerHeightMeters: Double
        var minimumClearanceDeg: Double
        var evaluation: PlanEvaluation
    }

    // MARK: - State

    private(set) var loadState: LoadState = .idle
    private(set) var scenario: ScenarioBundle?
    private(set) var phase: MissionPhase = .original
    /// Scenario default; Reset target.
    private(set) var defaultPlan: MissionPlan?
    /// Baseline the delay is derived from. Never overwritten by a delay, preview or apply.
    private(set) var originalPlan: MissionPlan?
    /// The plan currently committed to the demo.
    private(set) var committedPlan: MissionPlan?
    /// Separate delayed scenario.
    private(set) var delayedPlan: MissionPlan?
    private(set) var candidates: [RecoveryCandidate] = []
    private(set) var selectedCandidateKind: RecoveryCandidate.Kind?
    private(set) var appliedCandidate: RecoveryCandidate?
    private(set) var acceptedDelayedPlan = false
    private(set) var hasSearchedForRecovery = false
    private(set) var confirmationMessage: String?
    private(set) var dataNotice: String?
    private(set) var timelineCursor: Date?
    /// Range the timeline shows while a user-selected interval (e.g. an Earth visibility window) is focused.
    /// Display only: it never changes mission data.
    private(set) var timelineFocus: UTCRange?
    private(set) var failureFeedbackCount = 0
    private(set) var successFeedbackCount = 0

    @ObservationIgnored private let recoverySearch = RecoverySearchService()

    init() {}

    // MARK: - Loading

    func beginLoading() {
        loadState = .loading
    }

    func failLoading(_ message: String) {
        loadState = .failed(message)
    }

    func load(using service: any MissionAnalysisService, notice: String? = nil) async {
        loadState = .loading
        do {
            let scenario = try await service.loadScenario()
            install(scenario, notice: notice)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Replaces the data notice without touching the scenario or the plan.
    func showNotice(_ text: String?) {
        dataNotice = text
    }

    func install(_ scenario: ScenarioBundle, notice: String? = nil) {
        self.scenario = scenario
        dataNotice = notice
        loadState = .loaded
        resetDemo()
    }

    // MARK: - Lookups

    var sites: [LunarSite] { scenario?.sites ?? [] }
    var mapSites: [LunarSite] { sites.filter { $0.mapPosition != nil } }
    var metadata: DatasetMetadata? { scenario?.metadata }
    var basemap: BasemapManifest? { scenario?.basemap }
    var missionName: String { scenario?.mission.missionName ?? "LUNAVI" }
    var durationOptions: [Int] { scenario?.mission.durationOptions ?? [6, 12, 24, 48] }
    var delayHours: Int { scenario?.mission.delayHours ?? 6 }
    var dataSource: DataSourceKind? { metadata?.source }
    var isSimulated: Bool { metadata?.source == .simulatedFixture }

    func site(id: String?) -> LunarSite? {
        guard let id else { return nil }
        return sites.first { $0.id == id }
    }

    func visibility(for siteID: String?) -> SiteVisibility? {
        guard let siteID else { return nil }
        return scenario?.visibility[siteID]
    }

    /// Exported horizon and Sun/Earth geometry for shadow analysis, if the scenario has it.
    func shadowGeometry(for siteID: String?) -> ShadowGeometry? {
        guard let siteID else { return nil }
        return scenario?.geometry[siteID]
    }

    /// Terrain characteristics exported by the pipeline (schema 3), if any.
    func terrain(for siteID: String?) -> TerrainCharacteristics? {
        guard let siteID else { return nil }
        return scenario?.terrain[siteID]
    }

    /// Span of computed data over all sites. Plans are only edited to start inside it.
    var dataCoverage: UTCRange? { scenario?.coverageHull }
    var allowedStartRange: ClosedRange<Date>? { scenario?.allowedStartRange }

    func hasData(siteID: String) -> Bool {
        scenario?.visibility[siteID] != nil
    }

    func evaluate(_ plan: MissionPlan?) -> PlanEvaluation? {
        guard let plan else { return nil }
        return VisibilityEvaluator.evaluate(plan, data: visibility(for: plan.siteID))
    }

    // MARK: - Derived evaluations

    var committedSite: LunarSite? { site(id: committedPlan?.siteID) }
    var committedEvaluation: PlanEvaluation? { evaluate(committedPlan) }
    var originalEvaluation: PlanEvaluation? { evaluate(originalPlan) }
    var delayedEvaluation: PlanEvaluation? { evaluate(delayedPlan) }

    var comparison: MissionComparison? {
        guard let original = originalEvaluation, let delayed = delayedEvaluation else { return nil }
        return MissionComparison(original: original, delayed: delayed)
    }

    var previewCandidate: RecoveryCandidate? {
        guard phase == .recoveryPreview, let kind = selectedCandidateKind else { return nil }
        return candidates.first { $0.kind == kind }
    }

    /// The plan the inspector's condition cards describe in the current phase.
    var focusEvaluation: PlanEvaluation? {
        switch phase {
        case .original, .recoveryApplied:
            return committedEvaluation
        case .delayed, .recoveryOptions:
            return delayedEvaluation ?? committedEvaluation
        case .recoveryPreview:
            return previewCandidate?.evaluation ?? delayedEvaluation ?? committedEvaluation
        }
    }

    var focusContextLabel: String {
        switch phase {
        case .original:
            return "Committed plan"
        case .delayed, .recoveryOptions:
            return delayedPlan == nil ? "Committed plan" : "Delayed plan (+\(delayHours) h)"
        case .recoveryPreview:
            return "Preview · option \(previewCandidate?.kind.letter ?? "")"
        case .recoveryApplied:
            return "Updated plan"
        }
    }

    /// Site whose data the timeline tracks show.
    var focusSiteID: String? {
        previewCandidate?.plan.siteID ?? committedPlan?.siteID
    }

    var canEditParameters: Bool { phase == .original }
    var canCompareAgain: Bool { phase == .recoveryApplied && !candidates.isEmpty }

    var primaryAction: PrimaryAction {
        switch phase {
        case .original:
            return committedEvaluation?.overall == .met ? .simulateDelay : .findRecoveryOptions
        case .delayed:
            return delayedEvaluation?.overall == .met ? .acceptDelayedPlan : .findRecoveryOptions
        case .recoveryOptions:
            return .applyCandidate(enabled: false)
        case .recoveryPreview:
            return .applyCandidate(enabled: previewCandidate?.evaluation.overall == .met)
        case .recoveryApplied:
            return .resetDemo
        }
    }

    var footerNote: String? {
        switch phase {
        case .original:
            switch committedEvaluation?.overall {
            case .some(.notMet):
                return "The committed plan does not meet both requirements. Search for recovery options."
            case .some(.unknown):
                return "Data is unavailable for part of this window. Recovery search uses covered data only."
            default:
                return nil
            }
        case .delayed:
            return delayedEvaluation?.overall == .met ? "The delay is absorbed — both requirements still hold for the delayed window." : nil
        case .recoveryOptions:
            return candidates.isEmpty
                ? "No recovery option meets both requirements within the available data."
                : "Select a recovery option to preview it."
        case .recoveryPreview:
            return "Preview only — the committed plan is unchanged until you apply it."
        case .recoveryApplied:
            return nil
        }
    }

    // MARK: - Map support

    var failingSiteID: String? {
        switch phase {
        case .original:
            return committedEvaluation?.overall == .notMet ? committedPlan?.siteID : nil
        case .delayed, .recoveryOptions, .recoveryPreview:
            guard let evaluation = delayedEvaluation ?? committedEvaluation else { return nil }
            return evaluation.overall == .met ? nil : evaluation.plan.siteID
        case .recoveryApplied:
            return nil
        }
    }

    func pinRole(for siteID: String) -> MapPinRole {
        if let preview = previewCandidate, preview.kind == .alternativeSite, preview.plan.siteID == siteID {
            return .preview
        }
        if siteID == failingSiteID {
            if let preview = previewCandidate, preview.plan.siteID == siteID {
                return .active
            }
            return .failing
        }
        if siteID == committedPlan?.siteID {
            return .active
        }
        if phase == .recoveryOptions || phase == .recoveryPreview,
           candidates.contains(where: { $0.kind == .alternativeSite && $0.plan.siteID == siteID }) {
            return .alternative
        }
        return hasData(siteID: siteID) ? .unselected : .noData
    }

    func pinDetail(for siteID: String) -> String {
        switch pinRole(for: siteID) {
        case .failing:
            if let evaluation = focusEvaluation, evaluation.plan.siteID == siteID, let failure = evaluation.firstFailure {
                return "\(failure.condition.shortTitle) obstructed from \(UTCFormat.dayMonthTime(failure.time))"
            }
            return MapPinRole.failing.label
        case .active:
            if let preview = previewCandidate, preview.kind == .sameSiteLaterTime, preview.plan.siteID == siteID {
                return "Preview · later start \(UTCFormat.dayMonthTime(preview.plan.start))"
            }
            return MapPinRole.active.label
        case .alternative:
            return MapPinRole.alternative.label
        case .preview:
            return "Preview · alternative site"
        case .unselected:
            return MapPinRole.unselected.label
        case .noData:
            return MapPinRole.noData.label
        }
    }

    /// Alternative site to connect to the committed site with a dashed site-change preview line.
    var connectorTargetSite: LunarSite? {
        let targetID: String?
        switch phase {
        case .recoveryOptions:
            targetID = candidates.first(where: { $0.kind == .alternativeSite })?.plan.siteID
        case .recoveryPreview:
            targetID = previewCandidate?.kind == .alternativeSite ? previewCandidate?.plan.siteID : nil
        default:
            targetID = nil
        }
        guard let targetID, targetID != committedPlan?.siteID else { return nil }
        return site(id: targetID)
    }

    /// Preview of another site with the committed plan's timing. Never commits anything.
    func evaluationAtCommittedTiming(siteID: String) -> PlanEvaluation? {
        guard let plan = committedPlan else { return nil }
        let probe = MissionPlan(siteID: siteID, start: plan.start, durationHours: plan.durationHours, origin: plan.origin)
        return VisibilityEvaluator.evaluate(probe, data: visibility(for: siteID))
    }

    // MARK: - Sensitivity

    var sensitivityRows: [SensitivityRow] {
        guard let plan = committedPlan, let variants = scenario?.sensitivity else { return [] }
        return variants.filter { $0.siteID == plan.siteID }.map { variant in
            SensitivityRow(
                id: variant.id,
                label: variant.label,
                observerHeightMeters: variant.observerHeightMeters,
                minimumClearanceDeg: variant.minimumClearanceDeg,
                evaluation: VisibilityEvaluator.evaluate(plan, data: variant.asSiteVisibility)
            )
        }
    }

    // MARK: - Mission actions

    func simulateDelay() {
        guard phase == .original, let plan = committedPlan else { return }
        originalPlan = plan
        let delayed = plan.delayed(byHours: delayHours)
        delayedPlan = delayed
        candidates = []
        selectedCandidateKind = nil
        appliedCandidate = nil
        acceptedDelayedPlan = false
        hasSearchedForRecovery = false
        confirmationMessage = nil
        phase = .delayed
        if let failure = evaluate(delayed)?.firstFailure {
            timelineCursor = failure.time
            failureFeedbackCount += 1
        } else {
            timelineCursor = delayed.start
        }
    }

    func findRecoveryOptions() {
        guard let scenario else { return }
        guard phase == .original || phase == .delayed || phase == .recoveryApplied else { return }
        if delayedPlan == nil {
            originalPlan = committedPlan
        }
        guard let base = delayedPlan ?? committedPlan else { return }
        candidates = recoverySearch.candidates(for: base, in: scenario)
        hasSearchedForRecovery = true
        selectedCandidateKind = nil
        confirmationMessage = nil
        phase = .recoveryOptions
    }

    /// Preview a candidate. The committed plan is not modified.
    func selectCandidate(_ kind: RecoveryCandidate.Kind) {
        guard phase == .recoveryOptions || phase == .recoveryPreview,
              let candidate = candidates.first(where: { $0.kind == kind }) else { return }
        selectedCandidateKind = kind
        phase = .recoveryPreview
        timelineCursor = candidate.plan.start
    }

    func clearPreview() {
        guard phase == .recoveryPreview else { return }
        selectedCandidateKind = nil
        phase = .recoveryOptions
    }

    /// Commits the previewed candidate. Allowed only when it meets both requirements in the data.
    func applySelectedCandidate() {
        guard phase == .recoveryPreview, let candidate = previewCandidate, candidate.evaluation.overall == .met else { return }
        committedPlan = candidate.plan
        appliedCandidate = candidate
        acceptedDelayedPlan = false
        phase = .recoveryApplied
        timelineCursor = candidate.plan.start
        confirmationMessage = "Applied to demo plan: \(candidate.siteName), \(UTCFormat.dayMonthTime(candidate.plan.start)) UTC for \(candidate.plan.durationHours) h."
        successFeedbackCount += 1
    }

    /// Commits the delayed plan when the delay is absorbed.
    func acceptDelayedPlan() {
        guard phase == .delayed, let delayed = delayedPlan, evaluate(delayed)?.overall == .met else { return }
        committedPlan = delayed
        appliedCandidate = nil
        acceptedDelayedPlan = true
        phase = .recoveryApplied
        timelineCursor = delayed.start
        confirmationMessage = "Delayed plan accepted: \(UTCFormat.dayMonthTime(delayed.start)) UTC for \(delayed.durationHours) h."
        successFeedbackCount += 1
    }

    func compareAgain() {
        guard canCompareAgain else { return }
        selectedCandidateKind = nil
        confirmationMessage = nil
        phase = .recoveryOptions
    }

    func clearConfirmation() {
        confirmationMessage = nil
    }

    /// Restores the scenario defaults: site, date, duration, phase, selections and cursor.
    func resetDemo() {
        guard let scenario else { return }
        let plan = MissionPlan(
            siteID: scenario.mission.siteID,
            start: scenario.mission.start,
            durationHours: scenario.mission.durationHours,
            origin: .original
        )
        defaultPlan = plan
        originalPlan = plan
        committedPlan = plan
        delayedPlan = nil
        candidates = []
        selectedCandidateKind = nil
        appliedCandidate = nil
        acceptedDelayedPlan = false
        hasSearchedForRecovery = false
        confirmationMessage = nil
        phase = .original
        timelineCursor = plan.start
        timelineFocus = nil
    }

    // MARK: - Editing (original phase only)

    /// Changes the start time. A start outside the computed coverage is refused, so the app never
    /// evaluates a plan in a period where no scientific data was generated.
    @discardableResult
    func updateStart(_ date: Date) -> Bool {
        guard canEditParameters, var plan = committedPlan else { return false }
        let start = Self.floorToMinute(date)
        if let allowed = allowedStartRange, !allowed.contains(start) { return false }
        plan.start = start
        commitEdited(plan)
        return true
    }

    func updateDuration(_ hours: Int) {
        guard canEditParameters, hours > 0, var plan = committedPlan else { return }
        plan.durationHours = hours
        commitEdited(plan)
    }

    func planMission(at siteID: String) {
        guard canEditParameters, var plan = committedPlan, site(id: siteID) != nil else { return }
        plan.siteID = siteID
        commitEdited(plan)
    }

    /// Discards derived scenarios; the committed plan becomes the new editable baseline.
    func returnToPlanEditing() {
        guard let plan = committedPlan else { return }
        originalPlan = plan
        delayedPlan = nil
        candidates = []
        selectedCandidateKind = nil
        appliedCandidate = nil
        acceptedDelayedPlan = false
        hasSearchedForRecovery = false
        confirmationMessage = nil
        phase = .original
        timelineCursor = plan.start
    }

    private func commitEdited(_ plan: MissionPlan) {
        committedPlan = plan
        originalPlan = plan
        timelineCursor = plan.start
    }

    private static func floorToMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    // MARK: - Timeline cursor (preview only; never commits)

    func moveCursor(to date: Date) {
        timelineCursor = date
    }

    func stepCursor(hours: Double) {
        guard let base = timelineCursor ?? committedPlan?.start else { return }
        timelineCursor = base.addingTimeInterval(hours * 3600)
    }

    var timelineEventTimes: [Date] {
        var times = VisibilityEvaluator.transitions(in: visibility(for: focusSiteID))
        for plan in [originalPlan, delayedPlan, previewCandidate?.plan, committedPlan].compactMap({ $0 }) {
            times.append(plan.start)
            times.append(plan.end)
        }
        if let failure = focusEvaluation?.firstFailure?.time {
            times.append(failure)
        }
        return Array(Set(times)).sorted()
    }

    func jumpToEvent(forward: Bool) {
        guard let current = timelineCursor ?? committedPlan?.start else { return }
        let times = timelineEventTimes
        if forward {
            if let next = times.first(where: { $0 > current.addingTimeInterval(1) }) {
                timelineCursor = next
            }
        } else if let previous = times.last(where: { $0 < current.addingTimeInterval(-1) }) {
            timelineCursor = previous
        }
    }

    /// Focuses the timeline on `range` and moves the cursor to `cursor` (default: the range start).
    func focusTimeline(on range: UTCRange, cursor: Date? = nil) {
        guard !range.isEmpty else { return }
        timelineFocus = range
        timelineCursor = cursor ?? range.start
    }

    func clearTimelineFocus() {
        timelineFocus = nil
    }

    func jumpToFirstFailure() {
        if let time = focusEvaluation?.firstFailure?.time {
            timelineCursor = time
        }
    }
}
