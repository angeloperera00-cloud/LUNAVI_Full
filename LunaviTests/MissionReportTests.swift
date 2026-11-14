import Foundation
import PDFKit
import Testing
@testable import Lunavi

@Suite("Mission report")
@MainActor
struct MissionReportTests {
    @Test("Report data matches the store after Mission Rescue")
    func matchesStore() throws {
        let store = try makeDemoStore()
        store.simulateDelay()
        store.findRecoveryOptions()
        store.selectCandidate(.alternativeSite)
        store.applySelectedCandidate()
        let report = try #require(MissionReportGenerator.makeReport(store: store))
        let committed = try #require(store.committedPlan)
        #expect(report.plan.siteID == committed.siteID)
        #expect(report.plan.start == committed.start)
        #expect(report.plan.end == committed.end)
        #expect(report.plan.durationHours == committed.durationHours)
        #expect(report.plan.overall == store.committedEvaluation?.overall)
        #expect(report.planContext == "Updated plan")
        #expect(report.rescue.originalPlan?.start == store.originalPlan?.start)
        #expect(report.rescue.delayedPlan?.start == store.delayedPlan?.start)
        #expect(report.rescue.candidates.count == store.candidates.count)
        #expect(report.rescue.applied?.letter == "B")
        #expect(report.sunlight.status == store.committedEvaluation?.sunlight.status)
        #expect(report.earth.status == store.committedEvaluation?.earth.status)
        #expect(report.fileName == "Lunavi_Mission_Report_Ridge_Site_B.pdf")
    }

    @Test("No recovery options are reported before a search")
    func noInventedRecovery() throws {
        let store = try makeDemoStore()
        let report = try #require(MissionReportGenerator.makeReport(store: store))
        #expect(report.rescue.hasSearched == false)
        #expect(report.rescue.candidates.isEmpty)
        #expect(report.rescue.applied == nil)
        #expect(report.rescue.delayedPlan == nil)
    }

    @Test("UTC timestamps are preserved exactly")
    func utcPreserved() throws {
        let store = try makeDemoStore()
        store.simulateDelay()
        let report = try #require(MissionReportGenerator.makeReport(store: store))
        #expect(report.plan.start == TestTime.utc("2026-11-20T06:00:00Z"))
        let rows = MissionReportGenerator.intervalRows(report.sunlight)
        #expect(rows.first?[1] == "20 NOV 2026 06:00 UTC")
        #expect(rows.allSatisfy { $0[1].hasSuffix("UTC") && $0[2].hasSuffix("UTC") })
    }

    @Test("Unknown values remain unknown")
    func unknownStaysUnknown() throws {
        let store = try makeDemoStore()
        store.planMission(at: "demo-point-c")   // no computed data
        let report = try #require(MissionReportGenerator.makeReport(store: store))
        #expect(report.plan.overall == .unknown)
        #expect(report.sunlight.status == .unknown)
        #expect(report.earth.status == .unknown)
        #expect(report.siteCoverage == nil)
        #expect(report.sunlight.visible.isEmpty)
        #expect(MissionReportGenerator.intervalRows(report.earth).allSatisfy { $0[0] == "No data (Unknown)" })
        #expect(MissionReportGenerator.degrees(nil) == "Unknown")
        #expect(MissionReportGenerator.meters(nil) == "Unknown")
    }

    @Test("PDF is created, readable, shareable as a file, and includes the limitations")
    func pdfCreatedWithLimitations() throws {
        let store = try makeDemoStore()
        let report = try #require(MissionReportGenerator.makeReport(store: store))
        #expect(report.science.limitations.contains(MissionReport.standardLimitations[0]))
        let data = MissionReportGenerator.renderPDF(report)
        #expect(data.starts(with: Array("%PDF".utf8)))
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 1)
        let text = document.string ?? ""
        #expect(text.contains("Known limitations"))
        #expect(text.contains("not a radio-link"))
        #expect(text.contains("SIMULATED DEMO"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(report.fileName)
        try data.write(to: url, options: .atomic)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Long content flows onto multiple pages")
    func longContentPaginates() throws {
        let store = try makeDemoStore()
        var report = try #require(MissionReportGenerator.makeReport(store: store))
        let start = TestTime.utc("2026-11-20T00:00:00Z")
        report.sunlight.obstructed = (0..<160).map { UTCRange(start: start.addingTimeInterval(Double($0) * 3600), duration: 1800) }
        report.science.assumptions = Array(repeating: String(repeating: "A long assumption that wraps across several lines. ", count: 8), count: 20)
        let baseline = try #require(MissionReportGenerator.makeReport(store: store))
        let short = try #require(PDFDocument(data: MissionReportGenerator.renderPDF(baseline)))
        let long = try #require(PDFDocument(data: MissionReportGenerator.renderPDF(report)))
        #expect(long.pageCount > short.pageCount)
        #expect(long.pageCount >= 5)
        // The last interval row is present: nothing was clipped away.
        #expect((long.string ?? "").contains(UTCFormat.full(start.addingTimeInterval(159 * 3600))))
    }
}

@Suite("Tutorial")
@MainActor
struct TutorialTests {
    private func freshDefaults() -> UserDefaults {
        let name = "lunavi.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Twelve steps in the required order")
    func steps() {
        let titles = TutorialContent.steps.map(\.title)
        #expect(titles.count == 12)
        #expect(titles.first == "Welcome to LUNAVI")
        #expect(titles.last == "Use Mission Rescue")
        #expect(TutorialContent.steps.map(\.id) == Array(0..<12))
    }

    @Test("Back, Next and bounds")
    func navigation() {
        let tutorial = TutorialState(progress: TutorialProgress(defaults: freshDefaults()))
        #expect(tutorial.isFirst)
        tutorial.back()
        #expect(tutorial.index == 0)
        for _ in 0..<20 { tutorial.next() }
        #expect(tutorial.isLast)
        #expect(tutorial.index == 11)
        #expect(tutorial.positionLabel == "Step 12 of 12")
        #expect(tutorial.fraction == 1)
        tutorial.go(to: -3)
        #expect(tutorial.index == 0)
    }

    @Test("Finish and Skip store completion locally")
    func completion() {
        let defaults = freshDefaults()
        let progress = TutorialProgress(defaults: defaults)
        #expect(progress.isCompleted == false)
        TutorialState(progress: progress).skip()
        #expect(progress.isCompleted)
        progress.reset()
        #expect(progress.isCompleted == false)
        TutorialState(progress: progress).finish()
        #expect(TutorialProgress(defaults: defaults).isCompleted)
    }

    @Test("Opening the tutorial never changes the active mission")
    func preservesMission() throws {
        let store = try makeDemoStore()
        store.simulateDelay()
        let phase = store.phase
        let plan = store.committedPlan
        let tutorial = TutorialState(progress: TutorialProgress(defaults: freshDefaults()))
        for _ in 0..<12 { tutorial.next() }
        tutorial.finish()
        #expect(store.phase == phase)
        #expect(store.committedPlan == plan)
    }

    @Test("First-launch tutorial opens once and never in UI tests")
    func firstLaunch() {
        let defaults = freshDefaults()
        let container = AppContainer(configuration: AppConfiguration(arguments: []))
        container.presentTutorialIfFirstLaunch(progress: TutorialProgress(defaults: defaults))
        #expect(container.navigation.isTutorialPresented)
        let completed = TutorialProgress(defaults: defaults)
        completed.markCompleted()
        let again = AppContainer(configuration: AppConfiguration(arguments: []))
        again.presentTutorialIfFirstLaunch(progress: completed)
        #expect(again.navigation.isTutorialPresented == false)
        let uiTest = AppContainer(configuration: AppConfiguration(arguments: ["-uiTesting"]))
        uiTest.presentTutorialIfFirstLaunch(progress: TutorialProgress(defaults: freshDefaults()))
        #expect(uiTest.navigation.isTutorialPresented == false)
    }
}

@Suite("Computed scenario switching")
@MainActor
struct ScenarioSwitchingTests {
    /// A computed-format JSON built from the fixture with its coverage shifted into another period —
    /// a stand-in for a second pipeline run, used only to test switching.
    private func computedJSON(title: String, period: UTCRange, shift: TimeInterval) throws -> Data {
        let demo = try DatasetRepository().loadDemoScenario()
        var metadata = demo.metadata
        metadata.id = "test-\(title)"
        metadata.title = title
        metadata.source = .computedBundled
        let visibility = demo.visibility.values.sorted { $0.siteID < $1.siteID }.map { site in
            SiteVisibility(siteID: site.siteID, coverage: site.coverage.map { $0.shifted(by: shift) },
                           sunlight: site.sunlight.map { $0.shifted(by: shift) },
                           earthLineOfSight: site.earthLineOfSight.map { $0.shifted(by: shift) }, events: [])
        }
        var mission = demo.mission
        mission.start = mission.start.addingTimeInterval(shift)
        let file = ComputedScenarioFile(schemaVersion: 3, mission: mission, basemap: demo.basemap, sites: demo.sites,
                                        metadata: metadata, visibility: visibility, sensitivity: nil, geometry: nil,
                                        period: ScenarioPeriod(start: period.start, end: period.end, stepSeconds: 600, sampleCount: nil),
                                        terrain: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    @Test("Catalog entries describe each file's computed period")
    func catalogEntry() throws {
        let period = range("2026-11-19T00:00:00Z", "2026-11-28T00:00:00Z")
        let entry = try ScenarioCatalog.entry(fromJSON: try computedJSON(title: "November", period: period, shift: 0),
                                              resourceName: "ComputedScenario_20261119_20261128")
        #expect(entry.coverage == period)
        #expect(entry.stepSeconds == 600)
        #expect(entry.metadataID == "test-November")
    }

    @Test("Switching scenarios replaces all data and resets to the new defaults")
    func switching() throws {
        let store = MissionStore()
        let november = try DatasetRepository.scenario(fromComputedJSON: try computedJSON(
            title: "November", period: range("2026-11-19T00:00:00Z", "2026-11-28T00:00:00Z"), shift: 0))
        let december = try DatasetRepository.scenario(fromComputedJSON: try computedJSON(
            title: "December", period: range("2026-12-17T00:00:00Z", "2026-12-26T00:00:00Z"), shift: 28 * 86_400))
        store.install(november)
        store.simulateDelay()
        store.install(december)
        #expect(store.metadata?.id == "test-December")
        #expect(store.phase == .original)
        #expect(store.committedPlan?.start == TestTime.utc("2026-12-18T06:00:00Z"))
        #expect(store.dataCoverage == range("2026-12-17T06:00:00Z", "2026-12-25T00:00:00Z"))
        // November dates are now outside the computed data: refused, and Unknown if evaluated.
        #expect(store.updateStart(TestTime.utc("2026-11-20T06:00:00Z")) == false)
        let old = VisibilityEvaluator.evaluate(plan("2026-11-20T06:00:00Z", hours: 24, site: "demo-point-a"),
                                               data: store.visibility(for: "demo-point-a"))
        #expect(old.overall == .unknown)
    }
}
