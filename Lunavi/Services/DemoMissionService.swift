import Foundation

/// Offline service backed by bundled resources.
///
/// Loads `ComputedScenario.json` when the science pipeline's output has been added to the app,
/// otherwise the simulated demo fixture. Works with no network and no backend.
struct DemoMissionService: MissionAnalysisService {
    /// UI tests pin the simulated fixture so the scripted journey stays deterministic
    /// even when a computed scenario has been added to the bundle.
    var fixtureOnly = false

    func loadScenario() async throws -> ScenarioBundle {
        let repository = DatasetRepository()
        return try fixtureOnly ? repository.loadDemoScenario() : repository.loadScenario()
    }
}
