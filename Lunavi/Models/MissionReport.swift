import Foundation

/// A mission report assembled only from data already in the app (`MissionStore` + scenario metadata).
/// Values the app does not have stay `nil` and are printed as "Unknown" / "Not available";
/// nothing is computed here that the app does not already show.
struct MissionReport: Sendable {
    struct PlanSummary: Hashable, Sendable {
        var siteID: String
        var siteName: String
        var coordinateText: String
        var latitude: Double?
        var longitude: Double?
        var start: Date
        var end: Date
        var durationHours: Int
        var overall: OverallStatus
    }

    struct ConditionSection: Hashable, Sendable {
        var condition: VisibilityCondition
        var status: ConditionStatus
        var statusText: String
        var explanation: String
        var visible: [UTCRange]
        var obstructed: [UTCRange]
        var unknown: [UTCRange]
        var visibleDuration: TimeInterval
        var obstructedDuration: TimeInterval
        var unknownDuration: TimeInterval
        var continuousFromStart: TimeInterval
    }

    struct CandidateSummary: Hashable, Sendable {
        var letter: String
        var title: String
        var plan: PlanSummary
        var explanation: String
        var benefit: String
        var tradeoff: String
        var validation: String
    }

    struct RescueSection: Hashable, Sendable {
        var originalPlan: PlanSummary?
        var delayHours: Int
        var delayedPlan: PlanSummary?
        var delayedFailure: String?
        var hasSearched: Bool
        var candidates: [CandidateSummary]
        var applied: CandidateSummary?
        var acceptedDelayedPlan: Bool
    }

    struct ScienceSection: Hashable, Sendable {
        var datasetTitle: String
        var dataSource: String
        var isSimulated: Bool
        var generatedAt: Date?
        var timeStepSeconds: Double?
        var observerHeightMeters: Double?
        var minimumClearanceDeg: Double?
        var sunCriterion: String
        var earthCriterion: String
        var referenceFrame: String
        var ephemeris: String
        var spiceKernels: String?
        var sources: [ProvenanceRecord]
        var assumptions: [String]
        var validation: [ValidationRecord]
        var limitations: [String]
        var disclaimer: String
    }

    var createdAt: Date
    var missionName: String
    var plan: PlanSummary
    /// Context the plan is reported in ("Committed plan", "Updated plan", …).
    var planContext: String
    /// Computed data coverage at the plan site (hull) and over the whole scenario.
    var siteCoverage: UTCRange?
    var datasetCoverage: UTCRange?
    var sunlight: ConditionSection
    var earth: ConditionSection
    var rescue: RescueSection
    var science: ScienceSection

    /// "Lunavi_Mission_Report_Connecting_Ridge.pdf"
    var fileName: String {
        let safe = plan.siteName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return "Lunavi_Mission_Report_\(safe.isEmpty ? "Site" : safe).pdf"
    }

    /// Fixed limitations that apply to every report, in addition to the dataset's own list.
    static let standardLimitations = [
        "Geometric visibility only. Earth line of sight is not a radio-link, antenna or ground-station prediction.",
        "No landing-safety, hazard, thermal or power assessment is implied by any result in this report.",
        "Results are only as accurate as the elevation model and its resolution; time without computed data is reported as Unknown, never as visible.",
        "Not a NASA product and not an operational planning result.",
    ]
}
