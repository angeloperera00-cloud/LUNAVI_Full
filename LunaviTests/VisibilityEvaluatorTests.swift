import Foundation
import Testing
@testable import Lunavi

@Suite("Visibility evaluator")
struct VisibilityEvaluatorTests {
    @Test("A requirement fails if any part of the window is uncovered")
    func gapInsideWindowFails() {
        let data = siteData(
            coverage: [range("2026-11-20T00:00:00Z", "2026-11-22T00:00:00Z")],
            sunlight: [range("2026-11-20T00:00:00Z", "2026-11-20T10:00:00Z"), range("2026-11-20T10:30:00Z", "2026-11-22T00:00:00Z")],
            earth: [range("2026-11-20T00:00:00Z", "2026-11-22T00:00:00Z")]
        )
        let evaluation = VisibilityEvaluator.evaluate(plan("2026-11-20T06:00:00Z", hours: 24), data: data)
        #expect(evaluation.sunlight.status == .partial)
        #expect(evaluation.sunlight.firstFailure == TestTime.utc("2026-11-20T10:00:00Z"))
        #expect(evaluation.sunlight.obstructedDuration == 30 * 60)
        #expect(evaluation.overall == .notMet)
    }

    @Test("Total visible time never implies success")
    func totalVisibleTimeIsNotCoverage() {
        // 23 h 59 m visible out of 24 h — still not met.
        let data = siteData(
            coverage: [range("2026-11-20T00:00:00Z", "2026-11-22T00:00:00Z")],
            sunlight: [range("2026-11-20T00:00:00Z", "2026-11-20T12:00:00Z"), range("2026-11-20T12:01:00Z", "2026-11-22T00:00:00Z")],
            earth: [range("2026-11-20T00:00:00Z", "2026-11-22T00:00:00Z")]
        )
        let evaluation = VisibilityEvaluator.evaluate(plan("2026-11-20T06:00:00Z", hours: 24), data: data)
        #expect(evaluation.sunlight.visibleDuration == 24 * 3600 - 60)
        #expect(evaluation.sunlight.status == .partial)
        #expect(evaluation.overall == .notMet)
    }

    @Test("A window crossing UTC midnight is evaluated across the date boundary")
    func midnightBoundary() {
        let touching = siteData(
            coverage: [range("2026-11-20T00:00:00Z", "2026-11-22T00:00:00Z")],
            sunlight: [range("2026-11-20T22:00:00Z", "2026-11-21T00:00:00Z"), range("2026-11-21T00:00:00Z", "2026-11-21T02:00:00Z")],
            earth: [range("2026-11-20T00:00:00Z", "2026-11-22T00:00:00Z")]
        )
        let window = plan("2026-11-20T23:00:00Z", hours: 2)
        #expect(VisibilityEvaluator.evaluate(window, data: touching).overall == .met)

        let gapAfterMidnight = siteData(
            coverage: [range("2026-11-20T00:00:00Z", "2026-11-22T00:00:00Z")],
            sunlight: [range("2026-11-20T22:00:00Z", "2026-11-21T00:00:00Z"), range("2026-11-21T00:10:00Z", "2026-11-21T02:00:00Z")],
            earth: [range("2026-11-20T00:00:00Z", "2026-11-22T00:00:00Z")]
        )
        let evaluation = VisibilityEvaluator.evaluate(window, data: gapAfterMidnight)
        #expect(evaluation.overall == .notMet)
        #expect(evaluation.sunlight.firstFailure == TestTime.utc("2026-11-21T00:00:00Z"))
    }

    @Test("Missing coverage is unknown, never success")
    func missingCoverageIsUnknown() {
        let data = siteData(
            coverage: [range("2026-11-20T00:00:00Z", "2026-11-21T00:00:00Z")],
            sunlight: [range("2026-11-20T00:00:00Z", "2026-11-23T00:00:00Z")],
            earth: [range("2026-11-20T00:00:00Z", "2026-11-23T00:00:00Z")]
        )
        let evaluation = VisibilityEvaluator.evaluate(plan("2026-11-20T06:00:00Z", hours: 24), data: data)
        #expect(evaluation.sunlight.status == .unknown)
        #expect(evaluation.earth.status == .unknown)
        #expect(evaluation.overall == .unknown)
        #expect(evaluation.overall != .met)
        #expect(evaluation.sunlight.firstUnknown == TestTime.utc("2026-11-21T00:00:00Z"))
    }

    @Test("No site data at all is unknown")
    func noDataIsUnknown() {
        let evaluation = VisibilityEvaluator.evaluate(plan("2026-11-20T06:00:00Z", hours: 24), data: nil)
        #expect(evaluation.overall == .unknown)
        #expect(evaluation.hasSiteData == false)
    }

    @Test("A known obstruction outranks missing data")
    func obstructionOutranksUnknown() {
        let data = siteData(
            coverage: [range("2026-11-20T00:00:00Z", "2026-11-21T00:00:00Z")],
            sunlight: [range("2026-11-20T00:00:00Z", "2026-11-20T18:00:00Z")],
            earth: [range("2026-11-20T00:00:00Z", "2026-11-21T00:00:00Z")]
        )
        let evaluation = VisibilityEvaluator.evaluate(plan("2026-11-20T06:00:00Z", hours: 24), data: data)
        #expect(evaluation.sunlight.status == .partial)
        #expect(evaluation.earth.status == .unknown)
        #expect(evaluation.overall == .notMet)
    }

    @Test("Half-open intervals: an interval ending at the window end covers it")
    func halfOpenEnd() {
        let data = siteData(
            coverage: [range("2026-11-20T00:00:00Z", "2026-11-21T06:00:00Z")],
            sunlight: [range("2026-11-20T00:00:00Z", "2026-11-21T06:00:00Z")],
            earth: [range("2026-11-20T00:00:00Z", "2026-11-21T06:00:00Z")]
        )
        #expect(VisibilityEvaluator.evaluate(plan("2026-11-20T06:00:00Z", hours: 24), data: data).overall == .met)
    }

    @Test("Earliest start is exact interval arithmetic")
    func earliestStart() {
        let data = siteData(
            coverage: [range("2026-11-20T00:00:00Z", "2026-11-27T00:00:00Z")],
            sunlight: [range("2026-11-20T00:00:00Z", "2026-11-21T08:00:00Z"), range("2026-11-25T12:00:00Z", "2026-11-27T00:00:00Z")],
            earth: [range("2026-11-20T00:00:00Z", "2026-11-27T00:00:00Z")]
        )
        let start = VisibilityEvaluator.earliestStart(data: data, notBefore: TestTime.utc("2026-11-20T12:00:00Z"), duration: 24 * 3600)
        #expect(start == TestTime.utc("2026-11-25T12:00:00Z"))
        let early = VisibilityEvaluator.earliestStart(data: data, notBefore: TestTime.utc("2026-11-20T06:00:00Z"), duration: 24 * 3600)
        #expect(early == TestTime.utc("2026-11-20T06:00:00Z"))
    }
}
