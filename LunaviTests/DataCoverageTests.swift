import Foundation
import Testing
@testable import Lunavi

@Suite("Data coverage boundaries")
@MainActor
struct DataCoverageTests {
    @Test("The coverage hull spans every site's data")
    func coverageHull() throws {
        let store = try makeDemoStore()
        #expect(store.dataCoverage == range("2026-11-19T06:00:00Z", "2026-11-27T00:00:00Z"))
        #expect(store.allowedStartRange?.lowerBound == TestTime.utc("2026-11-19T06:00:00Z"))
        #expect(store.allowedStartRange?.upperBound == TestTime.utc("2026-11-26T23:59:00Z"))
    }

    @Test("Start times outside the computed coverage are refused")
    func refusesOutsideCoverage() throws {
        let store = try makeDemoStore()
        let before = try #require(store.committedPlan)
        #expect(store.updateStart(TestTime.utc("2026-12-15T00:00:00Z")) == false)
        #expect(store.updateStart(TestTime.utc("2026-11-19T05:59:00Z")) == false)
        #expect(store.committedPlan == before)
        #expect(store.updateStart(TestTime.utc("2026-11-21T00:00:00Z")))
        #expect(store.committedPlan?.start == TestTime.utc("2026-11-21T00:00:00Z"))
    }

    @Test("No false success at the coverage boundary")
    func noFalseSuccessAtBoundary() {
        let coverage = range("2026-11-20T00:00:00Z", "2026-11-21T00:00:00Z")
        let data = siteData(coverage: [coverage], sunlight: [coverage], earth: [coverage])
        let inside = VisibilityEvaluator.evaluate(plan("2026-11-20T00:00:00Z", hours: 24), data: data)
        #expect(inside.overall == .met)
        let pastEnd = VisibilityEvaluator.evaluate(plan("2026-11-20T01:00:00Z", hours: 24), data: data)
        #expect(pastEnd.overall == .unknown)
        #expect(pastEnd.sunlight.unknownSegments == [range("2026-11-21T00:00:00Z", "2026-11-21T01:00:00Z")])
        let beyond = VisibilityEvaluator.evaluate(plan("2026-12-01T00:00:00Z", hours: 6), data: data)
        #expect(beyond.overall == .unknown)
        #expect(beyond.sunlight.visibleDuration == 0)
    }

    @Test("Coverage outside the declared computation period is rejected")
    func coverageOutsidePeriodRejected() throws {
        var scenario = try DatasetRepository().loadDemoScenario()
        scenario.declaredPeriod = ScenarioPeriod(start: TestTime.utc("2026-11-20T00:00:00Z"),
                                                 end: TestTime.utc("2026-11-21T00:00:00Z"), stepSeconds: 600, sampleCount: nil)
        #expect(throws: DatasetError.self) { try DatasetRepository.validateCoverage(scenario) }
        scenario.declaredPeriod = ScenarioPeriod(start: TestTime.utc("2026-11-19T00:00:00Z"),
                                                 end: TestTime.utc("2026-11-28T00:00:00Z"), stepSeconds: 600, sampleCount: nil)
        try DatasetRepository.validateCoverage(scenario)
    }

    @Test("Timeline focus is display-only and cleared by Reset")
    func timelineFocus() throws {
        let store = try makeDemoStore()
        let before = try #require(store.committedPlan)
        let window = range("2026-11-21T00:00:00Z", "2026-11-21T06:00:00Z")
        store.focusTimeline(on: window)
        #expect(store.timelineFocus == window)
        #expect(store.timelineCursor == window.start)
        #expect(store.committedPlan == before)
        let model = TimelineModel.make(store: store, zoom: .focus)
        #expect(model.range.start <= window.start && model.range.end >= window.end)
        store.resetDemo()
        #expect(store.timelineFocus == nil)
    }

    @Test("Choosing a start date: inside the data applies; with no computed data anywhere nothing changes and a notice explains")
    func containerStartSelection() throws {
        let container = AppContainer(configuration: AppConfiguration(arguments: ["-uiTesting"]))
        container.missionStore.install(try DatasetRepository().loadDemoScenario())
        let before = try #require(container.missionStore.committedPlan)
        #expect(container.setMissionStart(TestTime.utc("2027-03-01T00:00:00Z")) == .noData)
        #expect(container.missionStore.committedPlan == before)
        #expect(container.missionStore.dataNotice?.contains("No computed data") == true)
        #expect(container.setMissionStart(TestTime.utc("2026-11-21T00:00:00Z")) == .applied)
        #expect(container.missionStore.committedPlan?.start == TestTime.utc("2026-11-21T00:00:00Z"))
        // The simulated fixture never offers dates from computed files.
        #expect(container.selectableStartRange == container.missionStore.allowedStartRange)
    }
}
