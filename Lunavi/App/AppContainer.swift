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

    /// Reset Demo: mission state, map viewport and any open sheets.
    func resetAll() {
        missionStore.resetDemo()
        mapState.reset()
        navigation.dismissAll()
    }
}
