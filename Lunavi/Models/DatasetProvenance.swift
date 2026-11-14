import Foundation

/// Where this session's visibility data comes from. Exactly one source per session; sources are never mixed.
enum DataSourceKind: String, Codable, CaseIterable, Sendable {
    case simulatedFixture
    case computedBundled
    case computedLive
    case imported

    var label: String {
        switch self {
        case .simulatedFixture:
            return "Simulated fixture"
        case .computedBundled:
            return "Computed (bundled)"
        case .computedLive:
            return "Computed (live service)"
        case .imported:
            return "Imported results"
        }
    }

    var badgeText: String {
        switch self {
        case .simulatedFixture:
            return "SIMULATED DEMO"
        case .computedBundled:
            return "COMPUTED"
        case .computedLive:
            return "LIVE SERVICE"
        case .imported:
            return "IMPORTED"
        }
    }

    var sessionDescription: String {
        switch self {
        case .simulatedFixture:
            return "Simulated fixture data — illustrative values bundled with the app"
        case .computedBundled:
            return "Cached scientific data computed by the LUNAVI pipeline"
        case .computedLive:
            return "Real computation backend (LUNAVI science service)"
        case .imported:
            return "Imported scientific results"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .simulatedFixture:
            return "Data mode: simulated demo, illustrative values"
        case .computedBundled:
            return "Data mode: computed results bundled with the app"
        case .computedLive:
            return "Data mode: live science service"
        case .imported:
            return "Data mode: imported results"
        }
    }
}

enum ValidationLevel: String, Codable, Sendable {
    case notApplicable
    case notValidated
    case ephemerisChecked
    case horizonCompared
    case validatedAgainstReference

    var label: String {
        switch self {
        case .notApplicable:
            return "Not applicable — simulated values"
        case .notValidated:
            return "Computed — not independently validated"
        case .ephemerisChecked:
            return "Ephemeris checked against JPL Horizons"
        case .horizonCompared:
            return "Horizon model compared with PGDA product 69"
        case .validatedAgainstReference:
            return "Validated against reference data"
        }
    }

    var rank: Int {
        switch self {
        case .notApplicable:
            return 0
        case .notValidated:
            return 1
        case .ephemerisChecked:
            return 2
        case .horizonCompared:
            return 3
        case .validatedAgainstReference:
            return 4
        }
    }
}

/// Validation is recorded per component: ephemeris, terrain horizon, intervals.
struct ValidationRecord: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var component: String
    var level: ValidationLevel
    var detail: String
}

struct ProvenanceRecord: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var role: String
    var name: String
    var provider: String
    var version: String
    var resolution: String
    var coordinateSystem: String
    var status: String
    var link: String?
}

struct DatasetMetadata: Codable, Hashable, Sendable {
    var id: String
    var title: String
    var source: DataSourceKind
    var generatedAt: Date?
    var timeStepSeconds: Double?
    var observerHeightMeters: Double?
    var minimumClearanceDeg: Double?
    var sunCriterion: String
    var earthCriterion: String
    var referenceFrame: String
    var ephemeris: String
    var assumptions: [String]
    var limitations: [String]
    var provenance: [ProvenanceRecord]
    var validation: [ValidationRecord]
    var disclaimer: String

    var bestValidation: ValidationLevel {
        validation.map(\.level).max(by: { $0.rank < $1.rank }) ?? .notValidated
    }
}
