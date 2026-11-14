import Foundation

/// The first known requirement failure inside a plan's window.
struct FailureEvent: Hashable, Sendable {
    var condition: VisibilityCondition
    var time: Date
    /// Known-obstructed time for that condition within the window.
    var affectedDuration: TimeInterval
    var windowDuration: TimeInterval
    /// Time between the window start and the failure.
    var validBeforeFailure: TimeInterval
    /// Matching explanation from the dataset (fixture-defined or computed), if any.
    var explanation: ExplanationEvent?

    var affectedFraction: Double {
        windowDuration > 0 ? affectedDuration / windowDuration : 0
    }
}
