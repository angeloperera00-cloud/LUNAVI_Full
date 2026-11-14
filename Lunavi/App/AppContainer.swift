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
    }

    /// Reset Demo: mission state, map viewport and any open sheets.
    func resetAll() {
        missionStore.resetDemo()
        mapState.reset()
        navigation.dismissAll()
    }
}
