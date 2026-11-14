import Foundation
@testable import Lunavi

enum TestTime {
    /// Parses "2026-11-20T06:00:00Z".
    static func utc(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: string) else {
            preconditionFailure("Invalid test date \(string)")
        }
        return date
    }
}

func range(_ start: String, _ end: String) -> UTCRange {
    UTCRange(start: TestTime.utc(start), end: TestTime.utc(end))
}

func siteData(coverage: [UTCRange], sunlight: [UTCRange], earth: [UTCRange]) -> SiteVisibility {
    SiteVisibility(siteID: "test-site", coverage: coverage, sunlight: sunlight, earthLineOfSight: earth, events: [])
}

func plan(_ start: String, hours: Int, site: String = "test-site") -> MissionPlan {
    MissionPlan(siteID: site, start: TestTime.utc(start), durationHours: hours, origin: .original)
}

@MainActor
func makeDemoStore() throws -> MissionStore {
    let store = MissionStore()
    store.install(try DatasetRepository().loadDemoScenario())
    return store
}
