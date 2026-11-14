import Foundation

/// Result for one condition over a required window.
///
/// Precedence: a known obstruction anywhere in the window outranks missing data,
/// and missing data outranks success. Success requires uninterrupted visibility
/// over the entire window.
enum ConditionStatus: String, Sendable {
    /// Visible for the entire window.
    case met
    /// Visible for part of the window, with a known obstruction.
    case partial
    /// Known to be obstructed for the whole known part of the window.
    case unavailable
    /// No known obstruction, but part of the window has no data.
    case unknown
}

struct ConditionAssessment: Hashable, Sendable {
    var condition: VisibilityCondition
    var window: OperatingWindow
    var status: ConditionStatus
    /// First instant of a known obstruction inside the window.
    var firstFailure: Date?
    /// First instant inside the window without data coverage.
    var firstUnknown: Date?
    var visibleDuration: TimeInterval
    var obstructedDuration: TimeInterval
    var unknownDuration: TimeInterval
    /// Uninterrupted visibility measured from the window start.
    var validFromStart: TimeInterval
    var obstructedSegments: [UTCRange]
    var unknownSegments: [UTCRange]
}

enum OverallStatus: String, Sendable {
    case met
    case notMet
    case unknown
}

struct PlanEvaluation: Hashable, Sendable {
    var plan: MissionPlan
    var sunlight: ConditionAssessment
    var earth: ConditionAssessment
    var overall: OverallStatus
    var firstFailure: FailureEvent?
    var hasSiteData: Bool

    func assessment(for condition: VisibilityCondition) -> ConditionAssessment {
        switch condition {
        case .sunlight:
            return sunlight
        case .earthLineOfSight:
            return earth
        }
    }

    var assessments: [ConditionAssessment] { [sunlight, earth] }
}
