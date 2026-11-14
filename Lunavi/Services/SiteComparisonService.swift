import Foundation

/// One site evaluated over a shared operating window. Every number is a model result taken from the
/// scenario's visibility intervals (and, where exported, its horizon geometry). Nothing here ranks or
/// recommends sites; the view keeps model results and the recovery rule visibly separate.
struct SiteComparisonRow: Identifiable, Hashable, Sendable {
    var siteID: String
    var siteName: String
    var coordinate: GeographicCoordinate?
    var evaluation: PlanEvaluation
    /// Fraction of the window covered by data (0…1). Below 1, success is impossible by definition.
    var dataCompleteness: Double
    /// Lowest Sun / Earth clearance above the modeled terrain over the window, from exported samples.
    var lowestSunClearanceDeg: Double?
    var lowestEarthClearanceDeg: Double?

    var id: String { siteID }
    var hasData: Bool { evaluation.hasSiteData }

    /// Uninterrupted visibility measured from the window start (never longer than the window).
    func continuousFromStart(_ condition: VisibilityCondition) -> TimeInterval {
        let assessment = evaluation.assessment(for: condition)
        return min(assessment.validFromStart, assessment.window.duration)
    }
}

/// Whether a compared site can be committed to the mission plan from the comparison screen.
/// Committing goes through `MissionStore.planMission(at:)`, so it is only possible while the plan is
/// editable; during a delay comparison or Mission Rescue the rescue flow owns the commit.
enum ComparisonCommitAvailability: Equatable, Sendable {
    case available
    case alreadyPlanSite
    case lockedByMissionPhase
    case noData

    var reason: String? {
        switch self {
        case .available:
            return nil
        case .alreadyPlanSite:
            return "This is already the plan site."
        case .lockedByMissionPhase:
            return "The plan is locked while a delay comparison or Mission Rescue is open. Use Mission Rescue to apply an option, or choose Edit Plan first."
        case .noData:
            return "No computed data for this site — it cannot be planned from the comparison."
        }
    }
}

enum SiteComparisonService {
    /// Evaluates every mapped site over the same window (same UTC start and duration), with the same
    /// evaluator Mission Rescue uses. Sites without data are kept and reported as Unknown.
    static func rows(start: Date, durationHours: Int, sites: [LunarSite],
                     visibility: [String: SiteVisibility], geometry: [String: ShadowGeometry]) -> [SiteComparisonRow] {
        sites.filter { $0.mapPosition != nil || visibility[$0.id] != nil }.map { site in
            let plan = MissionPlan(siteID: site.id, start: start, durationHours: durationHours, origin: .original)
            let evaluation = VisibilityEvaluator.evaluate(plan, data: visibility[site.id])
            let duration = plan.window.duration
            let completeness = duration > 0 ? max(0, min(1, (duration - evaluation.sunlight.unknownDuration) / duration)) : 0
            return SiteComparisonRow(
                siteID: site.id,
                siteName: site.name,
                coordinate: site.coordinate,
                evaluation: evaluation,
                dataCompleteness: completeness,
                lowestSunClearanceDeg: ShadowAnalysisService.minimumClearance(.sunlight, over: plan.window, geometry: geometry[site.id]),
                lowestEarthClearanceDeg: ShadowAnalysisService.minimumClearance(.earthLineOfSight, over: plan.window, geometry: geometry[site.id])
            )
        }
    }

    static func commitAvailability(for row: SiteComparisonRow, planSiteID: String?, canEditPlan: Bool) -> ComparisonCommitAvailability {
        if row.siteID == planSiteID { return .alreadyPlanSite }
        if !row.hasData { return .noData }
        return canEditPlan ? .available : .lockedByMissionPhase
    }

    /// Visible, obstructed and unknown pieces of the window for one condition, in time order.
    static func segments(for assessment: ConditionAssessment) -> [ComparisonSegment] {
        let window = assessment.window
        let blocked = assessment.obstructedSegments.map { ComparisonSegment(range: $0, state: .obstructed) }
        let unknown = assessment.unknownSegments.map { ComparisonSegment(range: $0, state: .unknown) }
        let visible = IntervalMath.complement(of: assessment.obstructedSegments + assessment.unknownSegments, within: window)
            .map { ComparisonSegment(range: $0, state: .visible) }
        return (blocked + unknown + visible)
            .filter { !$0.range.isEmpty }
            .sorted { $0.range.start < $1.range.start }
    }
}

struct ComparisonSegment: Hashable, Sendable {
    var range: UTCRange
    var state: PointState
}
