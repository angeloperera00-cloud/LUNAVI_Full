import Foundation

/// A recovery option found by `RecoverySearchService`, with its full evaluation.
struct RecoveryCandidate: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case sameSiteLaterTime
        case alternativeSite

        var title: String {
            switch self {
            case .sameSiteLaterTime:
                return "Same site · later time"
            case .alternativeSite:
                return "Nearby site · same delayed time"
            }
        }

        var letter: String {
            switch self {
            case .sameSiteLaterTime:
                return "A"
            case .alternativeSite:
                return "B"
            }
        }
    }

    var kind: Kind
    var plan: MissionPlan
    var evaluation: PlanEvaluation
    /// The plan being rescued (normally the delayed plan).
    var baseline: MissionPlan
    var siteName: String
    var baselineSiteName: String
    var timeShift: TimeInterval
    var siteChangeDescription: String?
    var distanceDescription: String
    var benefit: String
    var tradeoff: String
    var explanation: String
    var validationSummary: String

    var id: String { kind.rawValue }
}
