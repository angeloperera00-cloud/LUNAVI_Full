import Foundation

/// User-facing wording for condition results. Wording depends on the data mode: simulated
/// results never mention a modeled horizon, because no terrain model exists in that mode.
enum ConditionCopy {
    static func badgeText(condition: VisibilityCondition, status: ConditionStatus) -> String {
        switch (condition, status) {
        case (.sunlight, .met):
            return "Available"
        case (.earthLineOfSight, .met):
            return "Clear throughout"
        case (_, .partial):
            return "Partially obstructed"
        case (.sunlight, .unavailable):
            return "Unavailable"
        case (.earthLineOfSight, .unavailable):
            return "Obstructed"
        case (_, .unknown):
            return "Unknown"
        }
    }

    static func explanation(for assessment: ConditionAssessment, isSimulated: Bool) -> String {
        let hours = Int((assessment.window.duration / 3600).rounded())
        let windowText = "\(hours) h window"
        switch assessment.status {
        case .met:
            switch assessment.condition {
            case .sunlight:
                return isSimulated
                    ? "Sunlight covers the entire \(windowText) in this simulated scenario."
                    : "Sun remains above the modeled terrain horizon throughout this operating window."
            case .earthLineOfSight:
                return isSimulated
                    ? "Earth is geometrically visible for the entire \(windowText) in this simulated scenario."
                    : "Earth remains geometrically visible above the modeled local horizon."
            }
        case .partial:
            let when = assessment.firstFailure.map { UTCFormat.dayMonthTime($0) } ?? "—"
            let lead = assessment.condition == .sunlight ? "Sunlight is unavailable" : "Earth is obstructed"
            let suffix = isSimulated ? " Simulated values." : ""
            return "\(lead) from \(when) UTC — \(UTCFormat.duration(assessment.obstructedDuration)) of the \(windowText).\(suffix)"
        case .unavailable:
            return assessment.condition == .sunlight
                ? "No sunlight at any point in the known part of this window."
                : "Earth is obstructed throughout the known part of this window."
        case .unknown:
            let from = assessment.firstUnknown.map { UTCFormat.dayMonthTime($0) } ?? "—"
            return "Data unavailable from \(from) UTC — visibility cannot be confirmed for the full window."
        }
    }

    static func detail(for assessment: ConditionAssessment) -> String {
        let window = UTCFormat.duration(assessment.window.duration)
        switch assessment.status {
        case .met:
            return "Covered: \(window) of \(window)"
        case .partial, .unavailable:
            return "Uninterrupted from start: \(UTCFormat.duration(assessment.validFromStart)) · Unavailable: \(UTCFormat.duration(assessment.obstructedDuration))"
        case .unknown:
            return "Known: \(UTCFormat.duration(assessment.visibleDuration)) · No data: \(UTCFormat.duration(assessment.unknownDuration))"
        }
    }

    static func overallSubtitle(for evaluation: PlanEvaluation, isSimulated: Bool) -> String {
        let suffix = isSimulated ? " (simulated values)" : ""
        switch evaluation.overall {
        case .met:
            return "Both conditions hold for the entire \(evaluation.plan.durationHours) h window\(suffix)."
        case .notMet:
            if let failure = evaluation.firstFailure {
                return "\(failure.condition.title) fails from \(UTCFormat.dayMonthTime(failure.time)) UTC\(suffix)."
            }
            return "At least one condition does not cover the window\(suffix)."
        case .unknown:
            return evaluation.hasSiteData
                ? "Part of the window has no data, so success cannot be confirmed."
                : "No visibility data exists for this site in this session."
        }
    }
}
