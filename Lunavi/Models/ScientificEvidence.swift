import Foundation

/// Computed geometry at an event: target direction versus the modeled terrain horizon.
/// Present only for computed data; simulated fixtures never carry geometry.
struct HorizonGeometry: Codable, Hashable, Sendable {
    var targetAzimuthDeg: Double
    var targetElevationDeg: Double
    var horizonElevationDeg: Double
    var clearanceDeg: Double
}

/// A visibility transition with its explanation.
struct ExplanationEvent: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case obstructionBegins
        case visibilityReturns
    }

    var id: String
    var condition: VisibilityCondition
    var kind: Kind
    var time: Date
    var summary: String
    var geometry: HorizonGeometry?
}

/// Visibility recomputed under alternative assumptions (observer height, clearance, time step).
/// Only the science pipeline produces these; simulated fixtures do not.
struct SensitivityVariant: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var label: String
    var siteID: String
    var observerHeightMeters: Double
    var minimumClearanceDeg: Double
    var timeStepSeconds: Double
    var coverage: [UTCRange]
    var sunlight: [UTCRange]
    var earthLineOfSight: [UTCRange]

    var asSiteVisibility: SiteVisibility {
        SiteVisibility(siteID: siteID, coverage: coverage, sunlight: sunlight, earthLineOfSight: earthLineOfSight, events: [])
    }
}
