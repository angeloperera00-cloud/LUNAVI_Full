import Foundation
import Testing
@testable import Lunavi

@Suite("Mission store state transitions")
@MainActor
struct MissionStoreTests {
    @Test("Previewing a candidate does not commit it")
    func previewIsolation() throws {
        let store = try makeDemoStore()
        let original = try #require(store.committedPlan)
        store.simulateDelay()
        store.findRecoveryOptions()
        store.selectCandidate(.alternativeSite)
        #expect(store.phase == .recoveryPreview)
        #expect(store.previewCandidate?.kind == .alternativeSite)
        #expect(store.committedPlan == original)
        #expect(store.appliedCandidate == nil)
        #expect(store.pinRole(for: "ridge-site-b") == .preview)
        #expect(store.primaryAction == .applyCandidate(enabled: true))
    }

    @Test("Applying a candidate updates the active plan and site")
    func applyUpdatesPlan() throws {
        let store = try makeDemoStore()
        store.simulateDelay()
        store.findRecoveryOptions()
        store.selectCandidate(.alternativeSite)
        store.applySelectedCandidate()
        let committed = try #require(store.committedPlan)
        #expect(store.phase == .recoveryApplied)
        #expect(committed.siteID == "ridge-site-b")
        #expect(committed.start == TestTime.utc("2026-11-20T12:00:00Z"))
        #expect(store.committedSite?.name == "Ridge Site B")
        #expect(store.committedEvaluation?.overall == .met)
        #expect(store.pinRole(for: "ridge-site-b") == .active)
        #expect(store.confirmationMessage != nil)
        #expect(store.originalPlan?.start == TestTime.utc("2026-11-20T06:00:00Z"))
    }

    @Test("Applying option A keeps the site and moves the window")
    func applySameSite() throws {
        let store = try makeDemoStore()
        store.simulateDelay()
        store.findRecoveryOptions()
        store.selectCandidate(.sameSiteLaterTime)
        store.applySelectedCandidate()
        #expect(store.committedPlan?.siteID == "demo-point-a")
        #expect(store.committedPlan?.start == TestTime.utc("2026-11-25T12:00:00Z"))
        #expect(store.committedEvaluation?.overall == .met)
    }

    @Test("Reset restores site, date, duration, selections, cursor and phase")
    func resetRestoresEverything() throws {
        let store = try makeDemoStore()
        let initial = try #require(store.committedPlan)
        store.simulateDelay()
        store.findRecoveryOptions()
        store.selectCandidate(.alternativeSite)
        store.applySelectedCandidate()
        store.moveCursor(to: TestTime.utc("2026-11-23T00:00:00Z"))
        store.resetDemo()
        #expect(store.phase == .original)
        #expect(store.committedPlan == initial)
        #expect(store.originalPlan == initial)
        #expect(store.committedPlan?.siteID == "demo-point-a")
        #expect(store.committedPlan?.start == TestTime.utc("2026-11-20T06:00:00Z"))
        #expect(store.committedPlan?.durationHours == 24)
        #expect(store.delayedPlan == nil)
        #expect(store.candidates.isEmpty)
        #expect(store.selectedCandidateKind == nil)
        #expect(store.appliedCandidate == nil)
        #expect(store.timelineCursor == initial.start)
        #expect(store.confirmationMessage == nil)
        #expect(store.primaryAction == .simulateDelay)
    }

    @Test("Reset also restores an edited duration and site")
    func resetAfterEdits() throws {
        let store = try makeDemoStore()
        store.updateDuration(12)
        store.planMission(at: "ridge-site-b")
        store.updateStart(TestTime.utc("2026-11-21T00:00:00Z"))
        store.resetDemo()
        #expect(store.committedPlan?.durationHours == 24)
        #expect(store.committedPlan?.siteID == "demo-point-a")
        #expect(store.committedPlan?.start == TestTime.utc("2026-11-20T06:00:00Z"))
    }

    @Test("Simulated results keep their simulated status")
    func simulatedLabelsPersist() throws {
        let store = try makeDemoStore()
        #expect(store.isSimulated)
        #expect(store.metadata?.source == .simulatedFixture)
        #expect(store.metadata?.bestValidation == .notApplicable)
        store.simulateDelay()
        store.findRecoveryOptions()
        for candidate in store.candidates {
            #expect(candidate.validationSummary.contains("Simulated"))
        }
        store.selectCandidate(.sameSiteLaterTime)
        store.applySelectedCandidate()
        #expect(store.isSimulated)
        #expect(store.dataSource?.badgeText == "SIMULATED DEMO")
    }

    @Test("Timeline scrubbing never commits a plan")
    func scrubbingDoesNotCommit() throws {
        let store = try makeDemoStore()
        let committed = store.committedPlan
        store.moveCursor(to: TestTime.utc("2026-11-25T12:00:00Z"))
        store.stepCursor(hours: 3)
        store.jumpToEvent(forward: true)
        #expect(store.committedPlan == committed)
        #expect(store.phase == .original)
    }

    @Test("Parameters are locked outside the original phase")
    func parametersLocked() throws {
        let store = try makeDemoStore()
        store.simulateDelay()
        #expect(store.canEditParameters == false)
        store.updateDuration(12)
        #expect(store.committedPlan?.durationHours == 24)
        store.returnToPlanEditing()
        #expect(store.phase == .original)
        #expect(store.delayedPlan == nil)
        store.updateDuration(12)
        #expect(store.committedPlan?.durationHours == 12)
    }

    @Test("A site without data evaluates as unknown, never met")
    func siteWithoutData() throws {
        let store = try makeDemoStore()
        store.planMission(at: "demo-point-c")
        #expect(store.committedEvaluation?.overall == .unknown)
        #expect(store.pinRole(for: "demo-point-c") == .active)
        #expect(store.primaryAction == .findRecoveryOptions)
    }

    @Test("The demo fixture loads with the expected catalogue")
    func fixtureLoads() throws {
        let scenario = try DatasetRepository().loadDemoScenario()
        #expect(scenario.mission.missionName == "LUNAVI South Pole Demonstration")
        #expect(scenario.basemap.isIllustrative)
        #expect(scenario.visibility.keys.sorted() == ["demo-point-a", "ridge-site-b"])
        #expect(scenario.sites.contains { $0.name == "Connecting Ridge" && $0.mapPosition == nil })
    }
}
