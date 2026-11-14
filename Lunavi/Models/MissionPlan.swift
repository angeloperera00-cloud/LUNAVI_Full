import Foundation

/// A mission plan: site, UTC start and the required uninterrupted operating duration.
struct MissionPlan: Codable, Hashable, Sendable, Identifiable {
    enum Origin: String, Codable, Sendable {
        case original
        case delayed
        case recoverySameSite
        case recoveryAlternativeSite
    }

    var siteID: String
    var start: Date
    var durationHours: Int
    var origin: Origin

    var id: String {
        "\(origin.rawValue)|\(siteID)|\(Int(start.timeIntervalSince1970))|\(durationHours)"
    }

    var duration: TimeInterval { TimeInterval(durationHours) * 3600 }
    var window: OperatingWindow { UTCRange(start: start, duration: duration) }
    var end: Date { window.end }

    /// A separate plan starting `hours` later with the same site and duration.
    func delayed(byHours hours: Int) -> MissionPlan {
        MissionPlan(
            siteID: siteID,
            start: start.addingTimeInterval(TimeInterval(hours) * 3600),
            durationHours: durationHours,
            origin: .delayed
        )
    }
}
