import Foundation

/// The two geometric visibility requirements LUNAVI evaluates.
enum VisibilityCondition: String, Codable, CaseIterable, Identifiable, Sendable {
    case sunlight
    case earthLineOfSight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunlight:
            return "Sunlight"
        case .earthLineOfSight:
            return "Earth Line of Sight"
        }
    }

    var shortTitle: String {
        switch self {
        case .sunlight:
            return "Sunlight"
        case .earthLineOfSight:
            return "Earth LOS"
        }
    }

    var symbolName: String {
        switch self {
        case .sunlight:
            return "sun.max"
        case .earthLineOfSight:
            return "globe.europe.africa"
        }
    }
}

/// State of one condition at a single instant.
enum PointState: String, Sendable {
    case visible
    case obstructed
    case unknown

    var label: String {
        switch self {
        case .visible:
            return "Visible"
        case .obstructed:
            return "Obstructed"
        case .unknown:
            return "No data"
        }
    }
}

/// Timestamped visibility data for one site.
///
/// `coverage` lists the periods where the dataset has information. Inside coverage, any instant
/// not inside a visibility interval is a *known* obstruction. Outside coverage the state is unknown
/// and is never treated as visible.
struct SiteVisibility: Codable, Hashable, Sendable {
    var siteID: String
    var coverage: [UTCRange]
    var sunlight: [UTCRange]
    var earthLineOfSight: [UTCRange]
    var events: [ExplanationEvent]

    func intervals(for condition: VisibilityCondition) -> [UTCRange] {
        switch condition {
        case .sunlight:
            return sunlight
        case .earthLineOfSight:
            return earthLineOfSight
        }
    }

    func state(of condition: VisibilityCondition, at date: Date) -> PointState {
        guard coverage.contains(where: { $0.contains(date) }) else { return .unknown }
        return intervals(for: condition).contains(where: { $0.contains(date) }) ? .visible : .obstructed
    }
}
