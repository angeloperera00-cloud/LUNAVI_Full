import Foundation

/// A source of scenario data for one session.
///
/// Implementations: `DemoMissionService` (bundled data, offline) and `RemoteScienceService`
/// (the optional FastAPI science service). The app never blends their results.
protocol MissionAnalysisService: Sendable {
    func loadScenario() async throws -> ScenarioBundle
}
