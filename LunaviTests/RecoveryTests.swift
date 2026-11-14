import Foundation
import Testing
@testable import Lunavi

@Suite("Mission rescue")
@MainActor
struct RecoveryTests {
    private func rescuedStore() throws -> MissionStore {
        let store = try makeDemoStore()
        store.simulateDelay()
        store.findRecoveryOptions()
        return store
    }

    @Test("Option A — same site, later time — meets both requirements")
    func sameSiteLaterTime() throws {
        let store = try rescuedStore()
        let candidate = try #require(store.candidates.first { $0.kind == .sameSiteLaterTime })
        #expect(candidate.plan.siteID == "demo-point-a")
        #expect(candidate.plan.start == TestTime.utc("2026-11-25T12:00:00Z"))
        #expect(candidate.plan.end == TestTime.utc("2026-11-26T12:00:00Z"))
        #expect(candidate.timeShift == 5 * 86_400)
        #expect(candidate.evaluation.sunlight.status == .met)
        #expect(candidate.evaluation.earth.status == .met)
        #expect(candidate.evaluation.overall == .met)
    }

    @Test("Option B — nearby site, same delayed time — meets both requirements")
    func alternativeSite() throws {
        let store = try rescuedStore()
        let candidate = try #require(store.candidates.first { $0.kind == .alternativeSite })
        #expect(candidate.plan.siteID == "ridge-site-b")
        #expect(candidate.plan.start == TestTime.utc("2026-11-20T12:00:00Z"))
        #expect(candidate.plan.durationHours == 24)
        #expect(candidate.evaluation.overall == .met)
        #expect(candidate.distanceDescription.contains("No distance"))
    }

    @Test("Exactly two options for the demo story")
    func twoOptions() throws {
        let store = try rescuedStore()
        #expect(store.candidates.count == 2)
        #expect(store.phase == .recoveryOptions)
    }

    @Test("No recovery is invented when the data cannot support one")
    func noRecoveryForFortyEightHours() throws {
        let store = try makeDemoStore()
        store.updateDuration(48)
        store.findRecoveryOptions()
        #expect(store.candidates.isEmpty)
        #expect(store.hasSearchedForRecovery)
        #expect(store.primaryAction == .applyCandidate(enabled: false))
    }
}
