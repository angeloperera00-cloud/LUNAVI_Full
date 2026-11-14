import Foundation

/// Original plan versus its delayed copy, evaluated with identical requirements.
struct MissionComparison: Hashable, Sendable {
    var original: PlanEvaluation
    var delayed: PlanEvaluation

    var shift: TimeInterval {
        delayed.plan.start.timeIntervalSince(original.plan.start)
    }

    /// Conditions met by the original plan but not by the delayed plan.
    var newlyAffectedConditions: [VisibilityCondition] {
        VisibilityCondition.allCases.filter { condition in
            original.assessment(for: condition).status == .met
                && delayed.assessment(for: condition).status != .met
        }
    }

    var firstFailure: FailureEvent? { delayed.firstFailure }
}
