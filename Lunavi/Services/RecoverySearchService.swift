import Foundation

/// Searches recovery options for a plan that fails, using exactly the same requirements.
///
/// - Option A keeps the site and finds the earliest later start with uninterrupted combined visibility.
/// - Option B keeps the start time and checks other sites that have data, nearest first.
///
/// Only candidates that evaluate as `.met` within the available data are returned.
struct RecoverySearchService: Sendable {
    func candidates(for base: MissionPlan, in scenario: ScenarioBundle) -> [RecoveryCandidate] {
        var result: [RecoveryCandidate] = []
        let baseName = scenario.siteName(base.siteID)
        let validation = Self.validationSummary(scenario.metadata)
        let isSimulated = scenario.metadata.source == .simulatedFixture
        let dataPhrase = isSimulated ? "in this simulated scenario" : "in the computed data"

        if let data = scenario.visibility[base.siteID],
           let start = VisibilityEvaluator.earliestStart(data: data, notBefore: base.start, duration: base.duration),
           start > base.start {
            let plan = MissionPlan(siteID: base.siteID, start: start, durationHours: base.durationHours, origin: .recoverySameSite)
            let evaluation = VisibilityEvaluator.evaluate(plan, data: data)
            if evaluation.overall == .met {
                let shift = start.timeIntervalSince(base.start)
                let returning = data.events.first { $0.kind == .visibilityReturns && abs($0.time.timeIntervalSince(start)) < 60 }
                let lead = returning?.summary
                    ?? "Both requirements hold for the full \(base.durationHours) h window starting \(UTCFormat.dayMonthTime(start)) UTC \(dataPhrase)."
                result.append(RecoveryCandidate(
                    kind: .sameSiteLaterTime,
                    plan: plan,
                    evaluation: evaluation,
                    baseline: base,
                    siteName: baseName,
                    baselineSiteName: baseName,
                    timeShift: shift,
                    siteChangeDescription: nil,
                    distanceDescription: "No site change",
                    benefit: "Keeps \(baseName)",
                    tradeoff: "Starts \(UTCFormat.duration(shift)) after the plan being rescued",
                    explanation: lead + " Earliest qualifying start within the available data.",
                    validationSummary: validation
                ))
            }
        }

        let baseSite = scenario.site(id: base.siteID)
        let alternatives = scenario.sites
            .filter { $0.id != base.siteID && scenario.visibility[$0.id] != nil }
            .sorted { SiteGeometry.proximity(from: baseSite, to: $0) < SiteGeometry.proximity(from: baseSite, to: $1) }

        for site in alternatives {
            let plan = MissionPlan(siteID: site.id, start: base.start, durationHours: base.durationHours, origin: .recoveryAlternativeSite)
            let evaluation = VisibilityEvaluator.evaluate(plan, data: scenario.visibility[site.id])
            guard evaluation.overall == .met else { continue }
            result.append(RecoveryCandidate(
                kind: .alternativeSite,
                plan: plan,
                evaluation: evaluation,
                baseline: base,
                siteName: site.name,
                baselineSiteName: baseName,
                timeShift: 0,
                siteChangeDescription: "\(baseName) → \(site.name)",
                distanceDescription: SiteGeometry.distanceDescription(from: baseSite, to: site),
                benefit: "Keeps the start at \(UTCFormat.dayMonthTime(base.start)) UTC",
                tradeoff: "Changes site: \(baseName) → \(site.name)",
                explanation: "Both requirements hold at \(site.name) for the full \(base.durationHours) h window \(dataPhrase).",
                validationSummary: validation
            ))
            break
        }
        return result
    }

    static func validationSummary(_ metadata: DatasetMetadata) -> String {
        if metadata.source == .simulatedFixture {
            return "Simulated demo — illustrative values, not NASA data"
        }
        return "\(metadata.source.label) · \(metadata.bestValidation.label)"
    }
}

/// Distances are shown only between sites with real selenographic coordinates.
enum SiteGeometry {
    static let lunarRadiusKm = 1737.4

    static func greatCircleKm(_ a: GeographicCoordinate, _ b: GeographicCoordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * lunarRadiusKm * asin(min(1, sqrt(h)))
    }

    /// Ordering key only. Uses great-circle distance when both sites have coordinates,
    /// otherwise unitless map distance, which is never displayed.
    static func proximity(from base: LunarSite?, to other: LunarSite) -> Double {
        guard let base else { return .infinity }
        if let a = base.coordinate, let b = other.coordinate {
            return greatCircleKm(a, b)
        }
        if let a = base.mapPosition, let b = other.mapPosition {
            return hypot(a.x - b.x, a.y - b.y) * 1_000
        }
        return .infinity
    }

    static func distanceDescription(from base: LunarSite?, to other: LunarSite) -> String {
        if let a = base?.coordinate, let b = other.coordinate {
            let km = greatCircleKm(a, b).formatted(.number.precision(.fractionLength(1)))
            return "≈ \(km) km great-circle (R = 1737.4 km)"
        }
        return "No distance shown — site positions are illustrative"
    }
}
