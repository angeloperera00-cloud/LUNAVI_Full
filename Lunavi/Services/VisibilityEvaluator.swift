import Foundation

/// Shared, pure evaluation rules. Views never decide statuses themselves.
///
/// A requirement is met only if visibility covers the *entire* required window without
/// interruption. Total visible minutes are never used to infer success, and missing data is
/// never treated as visible.
enum VisibilityEvaluator {
    static func assess(_ condition: VisibilityCondition, data: SiteVisibility?, window: OperatingWindow) -> ConditionAssessment {
        guard let data else {
            return ConditionAssessment(
                condition: condition,
                window: window,
                status: .unknown,
                firstFailure: nil,
                firstUnknown: window.isEmpty ? nil : window.start,
                visibleDuration: 0,
                obstructedDuration: 0,
                unknownDuration: window.duration,
                validFromStart: 0,
                obstructedSegments: [],
                unknownSegments: window.isEmpty ? [] : [window]
            )
        }

        let covered = IntervalMath.clip(data.coverage, to: window)
        let visible = IntervalMath.intersect(IntervalMath.clip(data.intervals(for: condition), to: window), covered)
        let obstructed = IntervalMath.intersect(IntervalMath.complement(of: visible, within: window), covered)
        let unknown = IntervalMath.complement(of: covered, within: window)

        let visibleDuration = IntervalMath.totalDuration(visible)
        let obstructedDuration = IntervalMath.totalDuration(obstructed)
        let unknownDuration = IntervalMath.totalDuration(unknown)

        let validFromStart: TimeInterval
        if let first = visible.first, first.start <= window.start {
            validFromStart = first.end.timeIntervalSince(window.start)
        } else {
            validFromStart = 0
        }

        let status: ConditionStatus
        if obstructedDuration > 0 {
            status = visibleDuration > 0 ? .partial : .unavailable
        } else if unknownDuration > 0 {
            status = .unknown
        } else {
            status = .met
        }

        return ConditionAssessment(
            condition: condition,
            window: window,
            status: status,
            firstFailure: obstructed.first?.start,
            firstUnknown: unknown.first?.start,
            visibleDuration: visibleDuration,
            obstructedDuration: obstructedDuration,
            unknownDuration: unknownDuration,
            validFromStart: validFromStart,
            obstructedSegments: obstructed,
            unknownSegments: unknown
        )
    }

    static func evaluate(_ plan: MissionPlan, data: SiteVisibility?) -> PlanEvaluation {
        let window = plan.window
        let sunlight = assess(.sunlight, data: data, window: window)
        let earth = assess(.earthLineOfSight, data: data, window: window)
        let both = [sunlight, earth]

        let overall: OverallStatus
        if both.contains(where: { $0.status == .partial || $0.status == .unavailable }) {
            overall = .notMet
        } else if both.contains(where: { $0.status == .unknown }) {
            overall = .unknown
        } else {
            overall = .met
        }

        return PlanEvaluation(
            plan: plan,
            sunlight: sunlight,
            earth: earth,
            overall: overall,
            firstFailure: firstFailure(among: both, window: window, data: data),
            hasSiteData: data != nil
        )
    }

    private static func firstFailure(among assessments: [ConditionAssessment], window: OperatingWindow, data: SiteVisibility?) -> FailureEvent? {
        var earliest: (assessment: ConditionAssessment, time: Date)?
        for assessment in assessments {
            guard let time = assessment.firstFailure else { continue }
            if earliest == nil || time < earliest!.time {
                earliest = (assessment, time)
            }
        }
        guard let earliest else { return nil }
        let condition = earliest.assessment.condition
        let time = earliest.time

        let candidates = data?.events.filter { $0.condition == condition && $0.kind == .obstructionBegins } ?? []
        let exact = candidates.first { abs($0.time.timeIntervalSince(time)) < 60 }
        let preceding = candidates.filter { $0.time <= time }.max(by: { $0.time < $1.time })

        return FailureEvent(
            condition: condition,
            time: time,
            affectedDuration: earliest.assessment.obstructedDuration,
            windowDuration: window.duration,
            validBeforeFailure: time.timeIntervalSince(window.start),
            explanation: exact ?? preceding
        )
    }

    /// Instants where sunlight and Earth line of sight are both visible, inside data coverage.
    static func combinedIntervals(_ data: SiteVisibility) -> [UTCRange] {
        IntervalMath.intersect(IntervalMath.intersect(data.sunlight, data.earthLineOfSight), data.coverage)
    }

    /// Earliest start at or after `notBefore` with `duration` of uninterrupted combined visibility.
    /// Pure interval arithmetic: no time stepping, so the result is exact for the given intervals.
    static func earliestStart(data: SiteVisibility, notBefore: Date, duration: TimeInterval) -> Date? {
        for range in combinedIntervals(data) where range.end > notBefore {
            let start = max(range.start, notBefore)
            if range.end.timeIntervalSince(start) >= duration {
                return start
            }
        }
        return nil
    }

    /// All interval boundaries in a site's data, sorted and de-duplicated.
    static func transitions(in data: SiteVisibility?) -> [Date] {
        guard let data else { return [] }
        let boundaries = (data.coverage + data.sunlight + data.earthLineOfSight).flatMap { [$0.start, $0.end] }
        return Array(Set(boundaries)).sorted()
    }
}
