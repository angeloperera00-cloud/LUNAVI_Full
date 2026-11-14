import Foundation
import PDFKit
import Testing
@testable import Lunavi

/// Acceptance scenarios A–E on the REAL bundled `ComputedScenario.json` (NASA LOLA + NAIF SPICE), using the
/// running app's store. Skipped automatically when no computed scenario is bundled (simulated fixture only).
/// The same scenarios can be printed from the pipeline: `python -m lunavi_science acceptance --scenario …`.
enum RealData {
    static var isBundled: Bool {
        Bundle.main.url(forResource: "ComputedScenario", withExtension: "json") != nil
    }

    static let siteID = "pgda78-site01"                          // Connecting Ridge
    static let start = TestTime.utc("2026-11-29T15:00:00Z")
    static let hours = 24
}

@Suite("Acceptance on real bundled data", .enabled(if: RealData.isBundled, "ComputedScenario.json is not bundled"))
@MainActor
struct RealDataAcceptanceTests {
    private func store() throws -> MissionStore {
        let store = MissionStore()
        let scenario = try DatasetRepository().loadScenario()
        #expect(scenario.metadata.source != .simulatedFixture)
        store.install(scenario)
        return store
    }

    /// Commits the scenario-A plan through the same actions the user takes.
    private func planA(_ store: MissionStore) throws {
        store.planMission(at: RealData.siteID)
        #expect(store.updateStart(RealData.start), "29 Nov 2026 15:00 UTC must be inside the computed coverage")
        store.updateDuration(RealData.hours)
        let plan = try #require(store.committedPlan)
        #expect(plan.siteID == RealData.siteID && plan.start == RealData.start && plan.durationHours == RealData.hours)
    }

    @Test("Dataset declares its period and every site's coverage lies inside it")
    func datasetCoverage() throws {
        let scenario = try DatasetRepository().loadScenario()
        let period = try #require(scenario.declaredPeriod)
        for data in scenario.visibility.values {
            for range in data.coverage {
                #expect(range.start >= period.start.addingTimeInterval(-60) && range.end <= period.end.addingTimeInterval(60))
            }
        }
        #expect(scenario.site(id: RealData.siteID)?.coordinate != nil)
    }

    @Test("Schema 3: terrain characteristics present for every computed site (rebuild with the current pipeline if this fails)")
    func terrainPresent() throws {
        let scenario = try DatasetRepository().loadScenario()
        let computed = scenario.sites.filter { $0.kind == .computed }
        #expect(!computed.isEmpty)
        for site in computed {
            let terrain = try #require(scenario.terrain[site.id], "No terrain for \(site.id): regenerate with scripts/build_real_data.sh")
            #expect(terrain.isPhysicallyValid)
        }
    }

    @Test("A — Connecting Ridge, 29 Nov 2026 15:00 UTC, 24 h meets both requirements")
    func scenarioA() throws {
        let store = try store()
        try planA(store)
        let evaluation = try #require(store.committedEvaluation)
        #expect(evaluation.sunlight.status == .met)
        #expect(evaluation.earth.status == .met)
        #expect(evaluation.overall == .met)
    }

    @Test("B — The delayed plan fails at a computed transition, and the app names that requirement and time")
    func scenarioB() throws {
        let store = try store()
        try planA(store)
        store.simulateDelay()
        let delayed = try #require(store.delayedEvaluation)
        #expect(delayed.overall == .notMet)
        let failure = try #require(delayed.firstFailure)
        // Documented finding for this dataset: Earth line of sight is the requirement that fails.
        #expect(failure.condition == .earthLineOfSight)
        // The failure time is exactly where the failing condition's interval ends in the data…
        let data = try #require(store.visibility(for: RealData.siteID))
        let containing = data.intervals(for: failure.condition).first { $0.contains(delayed.plan.start) }
        #expect(containing?.end == failure.time)
        // …and it is backed by a computed obstruction event, not a coverage edge.
        let event = try #require(failure.explanation)
        #expect(event.kind == .obstructionBegins)
        #expect(abs(event.time.timeIntervalSince(failure.time)) < 60)
        #expect(store.timelineCursor == failure.time)
    }

    @Test("C — Mission Rescue: every option meets both requirements; preview never commits; Apply commits")
    func scenarioC() throws {
        let store = try store()
        try planA(store)
        store.simulateDelay()
        store.findRecoveryOptions()
        guard !store.candidates.isEmpty else {
            // Honest outcome: no qualifying alternative in the computed data.
            #expect(store.footerNote?.contains("No recovery option") == true)
            return
        }
        for candidate in store.candidates {
            let recheck = VisibilityEvaluator.evaluate(candidate.plan, data: store.visibility(for: candidate.plan.siteID))
            #expect(recheck.overall == .met)
            #expect(candidate.plan.durationHours == RealData.hours)
        }
        let committedBefore = store.committedPlan
        let kind = try #require(store.candidates.first?.kind)
        store.selectCandidate(kind)
        #expect(store.phase == .recoveryPreview)
        #expect(store.committedPlan == committedBefore)
        #expect(store.primaryAction == .applyCandidate(enabled: true))
        store.applySelectedCandidate()
        #expect(store.phase == .recoveryApplied)
        #expect(store.committedPlan == store.appliedCandidate?.plan)
        #expect(store.committedEvaluation?.overall == .met)
    }

    @Test("D — A window running past the data shows Unknown, never Available")
    func scenarioD() throws {
        let store = try store()
        let data = try #require(store.visibility(for: RealData.siteID))
        let coverageEnd = try #require(data.coverage.map(\.end).max())
        store.planMission(at: RealData.siteID)
        #expect(store.updateStart(coverageEnd.addingTimeInterval(-12 * 3600)))
        store.updateDuration(24)
        let evaluation = try #require(store.committedEvaluation)
        #expect(evaluation.overall != .met)
        #expect(evaluation.sunlight.status != .met && evaluation.earth.status != .met)
        #expect(evaluation.sunlight.unknownDuration >= 12 * 3600 - 1)
        #expect(evaluation.earth.unknownDuration >= 12 * 3600 - 1)
        // Starting after the data ends is refused outright.
        #expect(store.updateStart(coverageEnd.addingTimeInterval(3600)) == false)
    }

    @Test("E — The PDF report matches the evaluated mission after a rescue")
    func scenarioE() throws {
        let store = try store()
        try planA(store)
        store.simulateDelay()
        store.findRecoveryOptions()
        if let kind = store.candidates.first?.kind {
            store.selectCandidate(kind)
            store.applySelectedCandidate()
        }
        let report = try #require(MissionReportGenerator.makeReport(store: store))
        let committed = try #require(store.committedPlan)
        #expect(report.plan.siteID == committed.siteID && report.plan.start == committed.start)
        #expect(report.plan.overall == store.committedEvaluation?.overall)
        #expect(report.rescue.delayedFailure?.contains("Earth Line of Sight") == true)
        #expect(report.rescue.candidates.count == store.candidates.count)
        #expect(report.science.isSimulated == false)
        let document = try #require(PDFDocument(data: MissionReportGenerator.renderPDF(report)))
        let text = document.string ?? ""
        #expect(text.contains(UTCFormat.full(committed.start)))
        #expect(text.contains("Known limitations"))
        #expect(!text.contains("SIMULATED DEMO"))
    }
}
