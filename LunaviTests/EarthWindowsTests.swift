import Foundation
import Testing
@testable import Lunavi

@Suite("Earth visibility windows")
struct EarthWindowsTests {
    private func report(coverage: [UTCRange], earth: [UTCRange], period: UTCRange, reference: String,
                        mission: UTCRange? = nil) -> EarthWindowReport {
        let data = siteData(coverage: coverage, sunlight: coverage, earth: earth)
        return EarthCommunicationWindowService.report(siteID: "test-site", data: data, period: period,
                                                      reference: TestTime.utc(reference), missionWindow: mission)
    }

    @Test("Continuous visibility: one window; coverage edges are not transitions; mission met")
    func continuous() {
        let all = range("2026-11-20T00:00:00Z", "2026-11-22T00:00:00Z")
        let r = report(coverage: [all], earth: [all], period: all, reference: "2026-11-20T06:00:00Z",
                       mission: range("2026-11-20T06:00:00Z", "2026-11-21T06:00:00Z"))
        #expect(r.windows.count == 1)
        #expect(r.obstructions.isEmpty)
        #expect(r.windows[0].startBoundary == .coverageEdge)
        #expect(r.windows[0].endBoundary == .coverageEdge)
        #expect(r.windows[0].isDurationComplete == false)
        #expect(r.stateAtReference == .visible)
        #expect(r.mission?.status == .met)
        // Visible until the data ends; nothing is known after it.
        #expect(r.next == .unknown(reason: NextEarthWindow.insufficientDataMessage))
    }

    @Test("Multiple windows: obstructions between them, transitions at both ends, next window and wait")
    func multipleWindows() {
        let period = range("2026-11-20T00:00:00Z", "2026-11-23T00:00:00Z")
        let earth = [range("2026-11-20T00:00:00Z", "2026-11-20T10:00:00Z"),
                     range("2026-11-20T14:00:00Z", "2026-11-21T02:00:00Z"),
                     range("2026-11-21T20:00:00Z", "2026-11-22T08:00:00Z")]
        let r = report(coverage: [period], earth: earth, period: period, reference: "2026-11-20T11:00:00Z")
        #expect(r.windows.map(\.range) == earth)
        #expect(r.obstructions.map(\.range) == [range("2026-11-20T10:00:00Z", "2026-11-20T14:00:00Z"),
                                                range("2026-11-21T02:00:00Z", "2026-11-21T20:00:00Z"),
                                                range("2026-11-22T08:00:00Z", "2026-11-23T00:00:00Z")])
        let middle = r.windows[1]
        #expect(middle.startBoundary == .transition && middle.endBoundary == .transition)
        #expect(middle.duration == 12 * 3600)
        #expect(r.longestCompleteWindow?.range == earth[1])
        #expect(r.stateAtReference == .obstructed)
        #expect(r.next == .upcoming(middle, wait: 3 * 3600))
        #expect(r.unknowns.isEmpty)
    }

    @Test("A window that began before the requested period keeps its full extent")
    func windowBeginsBeforePeriod() {
        let coverage = range("2026-11-20T00:00:00Z", "2026-11-21T00:00:00Z")
        let r = report(coverage: [coverage], earth: [range("2026-11-20T02:00:00Z", "2026-11-20T10:00:00Z")],
                       period: range("2026-11-20T06:00:00Z", "2026-11-20T12:00:00Z"), reference: "2026-11-20T06:00:00Z")
        let window = r.windows[0]
        #expect(window.range == range("2026-11-20T02:00:00Z", "2026-11-20T10:00:00Z"))
        #expect(window.extendsBeforePeriod)
        #expect(window.extendsAfterPeriod == false)
        #expect(window.startBoundary == .transition)
        #expect(r.visibleDurationInPeriod == 4 * 3600)
    }

    @Test("A window that ends after the requested period is flagged")
    func windowEndsAfterPeriod() {
        let coverage = range("2026-11-20T00:00:00Z", "2026-11-22T00:00:00Z")
        let r = report(coverage: [coverage], earth: [range("2026-11-20T14:00:00Z", "2026-11-21T02:00:00Z")],
                       period: range("2026-11-21T00:00:00Z", "2026-11-21T06:00:00Z"), reference: "2026-11-21T00:00:00Z")
        #expect(r.windows.count == 1)
        #expect(r.windows[0].extendsAfterPeriod)
        #expect(r.windows[0].extendsBeforePeriod)
        #expect(r.visibleDurationInPeriod == 2 * 3600)
        #expect(r.obstructedDurationInPeriod == 4 * 3600)
    }

    @Test("Gaps: missing data is its own segment, its edges are not transitions, and the next window is unknown")
    func gapsAndMissingData() {
        let coverage = [range("2026-11-20T00:00:00Z", "2026-11-21T00:00:00Z"), range("2026-11-21T12:00:00Z", "2026-11-22T00:00:00Z")]
        let earth = [range("2026-11-20T00:00:00Z", "2026-11-20T06:00:00Z"), range("2026-11-21T18:00:00Z", "2026-11-22T00:00:00Z")]
        let period = range("2026-11-20T00:00:00Z", "2026-11-22T00:00:00Z")
        let r = report(coverage: coverage, earth: earth, period: period, reference: "2026-11-20T08:00:00Z")
        #expect(r.unknowns.map(\.range) == [range("2026-11-21T00:00:00Z", "2026-11-21T12:00:00Z")])
        let beforeGap = r.obstructions.first { $0.range.end == TestTime.utc("2026-11-21T00:00:00Z") }
        #expect(beforeGap?.endBoundary == .coverageEdge)
        let afterGap = r.obstructions.first { $0.range.start == TestTime.utc("2026-11-21T12:00:00Z") }
        #expect(afterGap?.startBoundary == .coverageEdge)
        // A window may hide inside the gap, so the next window cannot be stated.
        #expect(r.next == .unknown(reason: NextEarthWindow.insufficientDataMessage))
        #expect(r.unknownDurationInPeriod == 12 * 3600)
    }

    @Test("Exact boundaries use half-open intervals")
    func exactBoundaries() {
        let period = range("2026-11-20T00:00:00Z", "2026-11-21T00:00:00Z")
        let earth = [range("2026-11-20T00:00:00Z", "2026-11-20T10:00:00Z"), range("2026-11-20T14:00:00Z", "2026-11-21T00:00:00Z")]
        let atEnd = report(coverage: [period], earth: earth, period: period, reference: "2026-11-20T10:00:00Z")
        #expect(atEnd.stateAtReference == .obstructed)
        #expect(atEnd.next == .upcoming(atEnd.windows[1], wait: 4 * 3600))
        let atStart = report(coverage: [period], earth: earth, period: period, reference: "2026-11-20T14:00:00Z")
        #expect(atStart.stateAtReference == .visible)
        #expect(atStart.windows[0].endBoundary == .transition)
        // Mission ending exactly where the window ends is met; one minute longer is not.
        let fits = VisibilityEvaluator.assess(.earthLineOfSight, data: siteData(coverage: [period], sunlight: [period], earth: earth),
                                              window: range("2026-11-20T14:00:00Z", "2026-11-21T00:00:00Z"))
        #expect(fits.status == .met)
    }

    @Test("No future window inside the coverage gives the insufficient-data message")
    func noFutureWindow() {
        let coverage = range("2026-11-20T00:00:00Z", "2026-11-21T00:00:00Z")
        let r = report(coverage: [coverage], earth: [range("2026-11-20T00:00:00Z", "2026-11-20T06:00:00Z")],
                       period: coverage, reference: "2026-11-20T08:00:00Z")
        guard case .unknown(let reason) = r.next else {
            Issue.record("Expected an unknown next window")
            return
        }
        #expect(reason == "Next visibility window unknown — insufficient computed data.")
    }

    @Test("No site data: the whole period is unknown, never visible")
    func noData() {
        let period = range("2026-11-20T00:00:00Z", "2026-11-21T00:00:00Z")
        let r = EarthCommunicationWindowService.report(siteID: "x", data: nil, period: period,
                                                       reference: period.start, missionWindow: period)
        #expect(r.windows.isEmpty)
        #expect(r.unknowns.map(\.range) == [period])
        #expect(r.mission?.status == .unknown)
        #expect(r.hasData == false)
    }

    @Test("Mission result agrees with VisibilityEvaluator on the bundled scenario")
    @MainActor
    func agreesWithEvaluator() throws {
        let store = try makeDemoStore()
        store.simulateDelay()
        let plan = try #require(store.delayedPlan)
        let r = EarthCommunicationWindowService.report(siteID: plan.siteID, data: store.visibility(for: plan.siteID),
                                                       period: plan.window, reference: plan.start, missionWindow: plan.window)
        #expect(r.mission?.status == store.delayedEvaluation?.earth.status)
    }

    @Test("UTC formatting is independent of the device time zone")
    func utcFormatting() {
        let date = TestTime.utc("2026-11-20T23:05:00Z")
        #expect(UTCFormat.full(date) == "20 NOV 2026 23:05 UTC")
        #expect(UTCFormat.iso(date) == "2026-11-20T23:05:00Z")
        #expect(UTCFormat.dayMonthTime(date) == "20 NOV 23:05")
    }
}
