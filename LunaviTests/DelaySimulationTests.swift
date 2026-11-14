import Foundation
import Testing
@testable import Lunavi

@Suite("Six-hour delay on the bundled demo fixture")
@MainActor
struct DelaySimulationTests {
    @Test("The original demo window satisfies both requirements")
    func originalMeetsBoth() throws {
        let store = try makeDemoStore()
        let evaluation = try #require(store.committedEvaluation)
        #expect(evaluation.plan.start == TestTime.utc("2026-11-20T06:00:00Z"))
        #expect(evaluation.plan.durationHours == 24)
        #expect(evaluation.sunlight.status == .met)
        #expect(evaluation.earth.status == .met)
        #expect(evaluation.overall == .met)
        #expect(store.primaryAction == .simulateDelay)
    }

    @Test("The delay starts exactly six hours later with the same duration and site")
    func delayIsExactlySixHours() throws {
        let store = try makeDemoStore()
        let original = try #require(store.committedPlan)
        store.simulateDelay()
        let delayed = try #require(store.delayedPlan)
        #expect(delayed.start.timeIntervalSince(original.start) == 6 * 3600)
        #expect(delayed.start == TestTime.utc("2026-11-20T12:00:00Z"))
        #expect(delayed.durationHours == original.durationHours)
        #expect(delayed.siteID == original.siteID)
        #expect(store.originalPlan == original)
        #expect(store.committedPlan == original)
        #expect(store.phase == .delayed)
    }

    @Test("The sunlight failure begins at the configured event time")
    func firstFailureTime() throws {
        let store = try makeDemoStore()
        store.simulateDelay()
        let failure = try #require(store.delayedEvaluation?.firstFailure)
        #expect(failure.condition == .sunlight)
        #expect(failure.time == TestTime.utc("2026-11-21T08:00:00Z"))
        #expect(failure.affectedDuration == 4 * 3600)
        #expect(failure.validBeforeFailure == 20 * 3600)
        #expect(failure.explanation?.id == "a-sun-obstruction")
        #expect(store.primaryAction == .findRecoveryOptions)
    }

    @Test("Earth line of sight remains available across the delayed window")
    func earthStaysAvailable() throws {
        let store = try makeDemoStore()
        store.simulateDelay()
        let evaluation = try #require(store.delayedEvaluation)
        #expect(evaluation.earth.status == .met)
        #expect(evaluation.sunlight.status == .partial)
        #expect(evaluation.overall == .notMet)
    }

    @Test("6 h and 12 h durations absorb the delay", arguments: [6, 12])
    func shortDurationsAbsorbDelay(hours: Int) throws {
        let store = try makeDemoStore()
        store.updateDuration(hours)
        store.simulateDelay()
        #expect(store.delayedEvaluation?.overall == .met)
        #expect(store.primaryAction == .acceptDelayedPlan)
    }

    @Test("A 48 h original window already fails and the delayed one has an unknown tail")
    func fortyEightHours() throws {
        let store = try makeDemoStore()
        store.updateDuration(48)
        #expect(store.committedEvaluation?.overall == .notMet)
        #expect(store.primaryAction == .findRecoveryOptions)
    }
}
