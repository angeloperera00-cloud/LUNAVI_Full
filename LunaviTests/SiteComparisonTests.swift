import Foundation
import Testing
@testable import Lunavi

@Suite("Site comparison")
@MainActor
struct SiteComparisonTests {
    private func rows(start: String, hours: Int = 24) throws -> [SiteComparisonRow] {
        let scenario = try DatasetRepository().loadDemoScenario()
        return SiteComparisonService.rows(start: TestTime.utc(start), durationHours: hours, sites: scenario.sites,
                                          visibility: scenario.visibility, geometry: scenario.geometry)
    }

    @Test("Every mapped site is evaluated over the same window; catalogue-only sites are left out")
    func sameWindowForAll() throws {
        let result = try rows(start: "2026-11-20T06:00:00Z")
        #expect(result.map(\.siteID) == ["demo-point-a", "ridge-site-b", "demo-point-c"])
        #expect(Set(result.map(\.evaluation.plan.start)) == [TestTime.utc("2026-11-20T06:00:00Z")])
        #expect(Set(result.map(\.evaluation.plan.durationHours)) == [24])
    }

    @Test("Delayed window: Demo Point A fails sunlight, Ridge Site B meets both, Demo Point C is unknown")
    func delayedWindow() throws {
        let result = try rows(start: "2026-11-20T12:00:00Z")
        let a = try #require(result.first { $0.siteID == "demo-point-a" })
        let b = try #require(result.first { $0.siteID == "ridge-site-b" })
        let c = try #require(result.first { $0.siteID == "demo-point-c" })
        #expect(a.evaluation.overall == .notMet)
        #expect(a.evaluation.sunlight.obstructedSegments == [range("2026-11-21T08:00:00Z", "2026-11-21T12:00:00Z")])
        #expect(b.evaluation.overall == .met)
        #expect(b.dataCompleteness == 1)
        #expect(c.evaluation.overall == .unknown)
        #expect(c.dataCompleteness == 0)
        #expect(c.hasData == false)
    }

    @Test("Comparison agrees with Mission Rescue's alternative site")
    func agreesWithRescue() throws {
        let store = try makeDemoStore()
        store.simulateDelay()
        store.findRecoveryOptions()
        let rescue = try #require(store.candidates.first { $0.kind == .alternativeSite })
        let delayed = try #require(store.delayedPlan)
        let result = try rows(start: "2026-11-20T12:00:00Z")
        let row = try #require(result.first { $0.siteID == rescue.plan.siteID })
        #expect(row.evaluation.overall == .met)
        #expect(row.evaluation.plan.window == delayed.window)
    }

    @Test("Partial data coverage is reported and never counted as met")
    func partialCoverage() throws {
        let result = try rows(start: "2026-11-21T12:00:00Z")   // site B coverage ends 22 Nov 00:00
        let b = try #require(result.first { $0.siteID == "ridge-site-b" })
        #expect(b.evaluation.overall == .unknown)
        #expect(abs(b.dataCompleteness - 0.5) < 1e-9)
    }

    @Test("Window bar segments tile the window in time order")
    func segmentsTileTheWindow() throws {
        let a = try #require(try rows(start: "2026-11-20T12:00:00Z").first { $0.siteID == "demo-point-a" })
        let segments = SiteComparisonService.segments(for: a.evaluation.sunlight)
        #expect(segments.map(\.state) == [.visible, .obstructed])
        #expect(segments.first?.range.start == a.evaluation.plan.start)
        #expect(segments.last?.range.end == a.evaluation.plan.end)
        #expect(zip(segments, segments.dropFirst()).allSatisfy { $0.range.end == $1.range.start })
    }
}
