import Foundation
import Observation

/// Owns the app's state objects and wires the data source for the session.
@MainActor
@Observable
final class AppContainer {
    let configuration: AppConfiguration
    let missionStore: MissionStore
    let mapState: MapState
    let navigation: AppNavigationState

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        self.missionStore = MissionStore()
        self.mapState = MapState()
        self.navigation = AppNavigationState()
    }

    /// Loads the session's scenario: the live science service if configured and reachable,
    /// otherwise bundled data. The chosen source is shown in the UI; sources are never mixed.
    func bootstrap(force: Bool = false) async {
        if !force, missionStore.loadState != .idle {
            return
        }
        missionStore.beginLoading()
        var notice: String?
        if let url = configuration.scienceServiceURL {
            do {
                let scenario = try await RemoteScienceService(baseURL: url).loadScenario()
                missionStore.install(scenario, notice: "Connected to the LUNAVI science service at \(url.absoluteString).")
                presentTutorialIfFirstLaunch()
                return
            } catch {
                notice = "Science service unavailable (\(error.localizedDescription)) — using bundled data."
            }
        }
        do {
            let scenario = try await DemoMissionService(fixtureOnly: configuration.isUITesting).loadScenario()
            missionStore.install(scenario, notice: notice)
        } catch {
            missionStore.failLoading(error.localizedDescription)
        }
        presentTutorialIfFirstLaunch()
    }

    /// Opens the beginner tutorial once, on first launch. Completion is stored locally.
    func presentTutorialIfFirstLaunch(progress: TutorialProgress = TutorialProgress()) {
        guard configuration.opensTutorialOnFirstLaunch, !progress.isCompleted else { return }
        navigation.isTutorialPresented = true
    }

    /// Switches the session to another bundled computed scenario (a different generated date range).
    /// The mission is reset to that scenario's defaults; data from two scenarios is never mixed.
    func switchScenario(to entry: ScenarioCatalogEntry) {
        do {
            let scenario = try DatasetRepository().loadComputedScenario(resource: entry.resourceName)
            missionStore.install(scenario, notice: "Using computed data for \(UTCFormat.dayMonthYear(entry.coverage.start)) – \(UTCFormat.dayMonthYear(entry.coverage.end)).")
            mapState.reset()
        } catch {
            // Keep the current scenario; just report the failure.
            missionStore.showNotice("Could not load \(entry.resourceName): \(error.localizedDescription)")
        }
    }

    // MARK: - Choosing dates across computed ranges

    @ObservationIgnored private var cachedCatalog: [ScenarioCatalogEntry]?

    /// Every computed date range bundled with the app (each one a separate pipeline run).
    var catalog: [ScenarioCatalogEntry] {
        if let cachedCatalog { return cachedCatalog }
        let entries = ScenarioCatalog.entries()
        cachedCatalog = entries
        return entries
    }

    /// Start times the date editor offers: the span of all bundled computed ranges (real data only).
    /// The simulated fixture keeps its own coverage so it is never mixed with computed files.
    var selectableStartRange: ClosedRange<Date>? {
        let current = missionStore.allowedStartRange
        guard !missionStore.isSimulated, !catalog.isEmpty else { return current }
        let starts = catalog.map(\.coverage.start) + [current?.lowerBound].compactMap { $0 }
        let ends = catalog.map { $0.coverage.end.addingTimeInterval(-60) } + [current?.upperBound].compactMap { $0 }
        guard let lower = starts.min(), let upper = ends.max(), upper > lower else { return current }
        return lower...upper
    }

    /// One line per computed range, for the date editor.
    var computedRangesDescription: String? {
        guard !missionStore.isSimulated, catalog.count > 1 else { return nil }
        let list = catalog.map { "\(UTCFormat.dayMonthYear($0.coverage.start)) – \(UTCFormat.dayMonthYear($0.coverage.end))" }
        return "Computed ranges: " + list.joined(separator: "; ") + ". Dates between ranges have no data."
    }

    enum StartChange: Equatable {
        case applied
        case switchedDataset(String)
        case noData
    }

    /// Sets the mission start. If the date lies in another bundled computed range, that dataset is loaded
    /// first (site and duration are kept); if no computed data covers it, nothing changes and a notice says so.
    @discardableResult
    func setMissionStart(_ date: Date) -> StartChange {
        if missionStore.updateStart(date) { return .applied }
        let message = "No computed data for \(UTCFormat.full(date)). Add that period with ScienceService/scripts/build_real_data.sh --start … --end … (see docs/DATE_RANGES.md)."
        guard !missionStore.isSimulated, missionStore.canEditParameters, let plan = missionStore.committedPlan,
              let entry = catalog.first(where: { $0.metadataID != missionStore.metadata?.id
                                                 && $0.coverage.start <= date && date < $0.coverage.end.addingTimeInterval(-59) }) else {
            missionStore.showNotice(message)
            return .noData
        }
        switchScenario(to: entry)
        guard missionStore.metadata?.id == entry.metadataID else { return .noData }
        if missionStore.site(id: plan.siteID) != nil {
            missionStore.planMission(at: plan.siteID)
        }
        missionStore.updateDuration(plan.durationHours)
        guard missionStore.updateStart(date) else {
            missionStore.showNotice(message)
            return .noData
        }
        return .switchedDataset(entry.resourceName)
    }

    /// Reset Demo: mission state, map viewport and any open sheets.
    func resetAll() {
        missionStore.resetDemo()
        mapState.reset()
        navigation.dismissAll()
    }
}
