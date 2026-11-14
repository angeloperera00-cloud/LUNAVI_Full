import Foundation

/// What lies at one end of a visibility segment.
enum SegmentBoundary: String, Hashable, Sendable {
    /// A modeled change between visible and obstructed (bisected to about ±30 s by the pipeline).
    case transition
    /// The edge of the computed data coverage. Visibility may continue past it; it is *not* a transition.
    case coverageEdge

    var note: String {
        switch self {
        case .transition:
            return "modeled transition"
        case .coverageEdge:
            return "data-coverage edge — not a modeled transition"
        }
    }
}

/// One maximal stretch of a single state (visible, obstructed or no data) in a site's Earth data.
///
/// Segments keep their full extent inside the computed data even when they reach outside the
/// requested period; `extendsBeforePeriod` / `extendsAfterPeriod` say so.
struct EarthVisibilitySegment: Identifiable, Hashable, Sendable {
    var range: UTCRange
    var state: PointState
    var startBoundary: SegmentBoundary
    var endBoundary: SegmentBoundary
    var extendsBeforePeriod: Bool
    var extendsAfterPeriod: Bool

    var id: String { "\(state.rawValue)|\(range.start.timeIntervalSince1970)" }
    var duration: TimeInterval { range.duration }

    /// True when both ends are modeled transitions, so `duration` is the full uninterrupted length.
    /// Otherwise the stretch may be longer than shown (it reaches the edge of the computed data).
    var isDurationComplete: Bool { startBoundary == .transition && endBoundary == .transition }
}

/// The next Earth-visible interval after a reference time, or why it cannot be determined.
enum NextEarthWindow: Hashable, Sendable {
    case upcoming(EarthVisibilitySegment, wait: TimeInterval)
    case unknown(reason: String)

    static let insufficientDataMessage = "Next visibility window unknown — insufficient computed data."
}

/// Everything the Earth Visibility Windows panel shows for one site and period.
struct EarthWindowReport: Hashable, Sendable {
    var siteID: String
    var period: UTCRange
    var reference: Date
    /// All segments that intersect `period`, in time order (full extent inside the data).
    var segments: [EarthVisibilitySegment]
    /// State at `reference` and the segment containing it (nil when `reference` has no data).
    var stateAtReference: PointState
    var currentSegment: EarthVisibilitySegment?
    var next: NextEarthWindow
    /// Mission-window result from the shared `VisibilityEvaluator` (same rule as the condition cards).
    var mission: ConditionAssessment?
    var hasData: Bool

    var windows: [EarthVisibilitySegment] { segments.filter { $0.state == .visible } }
    var obstructions: [EarthVisibilitySegment] { segments.filter { $0.state == .obstructed } }
    var unknowns: [EarthVisibilitySegment] { segments.filter { $0.state == .unknown } }

    /// Visible time inside `period` only (segments clipped to the period).
    var visibleDurationInPeriod: TimeInterval {
        IntervalMath.totalDuration(windows.compactMap { $0.range.intersection(period) })
    }

    var obstructedDurationInPeriod: TimeInterval {
        IntervalMath.totalDuration(obstructions.compactMap { $0.range.intersection(period) })
    }

    var unknownDurationInPeriod: TimeInterval {
        IntervalMath.totalDuration(unknowns.compactMap { $0.range.intersection(period) })
    }

    /// Longest visible window whose length is fully known (both ends are modeled transitions).
    var longestCompleteWindow: EarthVisibilitySegment? {
        windows.filter(\.isDurationComplete).max { $0.duration < $1.duration }
    }
}

/// Derives Earth geometric line-of-sight windows from a site's exported intervals.
///
/// Semantics match `VisibilityEvaluator`: half-open UTC ranges; outside coverage the state is
/// unknown and never treated as visible; inside coverage any instant outside an Earth interval is a
/// known obstruction. A coverage boundary is never reported as a visibility transition.
enum EarthCommunicationWindowService {
    /// Segments of `data` over `domain`, classified at both ends.
    static func segments(_ data: SiteVisibility?, over domain: UTCRange) -> [EarthVisibilitySegment] {
        guard !domain.isEmpty else { return [] }
        guard let data else {
            return [EarthVisibilitySegment(range: domain, state: .unknown, startBoundary: .coverageEdge, endBoundary: .coverageEdge,
                                           extendsBeforePeriod: false, extendsAfterPeriod: false)]
        }
        let covered = IntervalMath.clip(data.coverage, to: domain)
        let visible = IntervalMath.intersect(IntervalMath.clip(data.earthLineOfSight, to: domain), covered)
        let obstructed = IntervalMath.intersect(IntervalMath.complement(of: visible, within: domain), covered)
        let unknown = IntervalMath.complement(of: covered, within: domain)
        let pieces = (visible.map { ($0, PointState.visible) } + obstructed.map { ($0, PointState.obstructed) }
                      + unknown.map { ($0, PointState.unknown) })
            .sorted { $0.0.start < $1.0.start }

        var result: [EarthVisibilitySegment] = []
        for (index, piece) in pieces.enumerated() {
            let previous = index > 0 ? pieces[index - 1] : nil
            let next = index + 1 < pieces.count ? pieces[index + 1] : nil
            result.append(EarthVisibilitySegment(
                range: piece.0,
                state: piece.1,
                startBoundary: boundary(between: previous, and: piece),
                endBoundary: boundary(between: piece, and: next),
                extendsBeforePeriod: false,
                extendsAfterPeriod: false
            ))
        }
        return result
    }

    /// A boundary is a transition only when known data lies on both sides and the state changes there.
    private static func boundary(between first: (UTCRange, PointState)?, and second: (UTCRange, PointState)?) -> SegmentBoundary {
        guard let first, let second, first.0.end == second.0.start,
              first.1 != .unknown, second.1 != .unknown, first.1 != second.1 else { return .coverageEdge }
        return .transition
    }

    /// The full report for `period`, with "next window" measured from `reference`.
    static func report(siteID: String, data: SiteVisibility?, period: UTCRange, reference: Date,
                       missionWindow: OperatingWindow?) -> EarthWindowReport {
        // Segments are computed over the period together with all coverage, so a window that began
        // before the period (or ends after it) keeps its true extent inside the computed data.
        let coverageHull = data.flatMap { hull($0.coverage) }
        let domain = [period, coverageHull].compactMap { $0 }.reduce(period) { union($0, $1) }
        let all = segments(data, over: domain)

        let inPeriod = all.filter { $0.range.intersection(period) != nil }.map { segment -> EarthVisibilitySegment in
            var copy = segment
            copy.extendsBeforePeriod = segment.range.start < period.start
            copy.extendsAfterPeriod = segment.range.end > period.end
            return copy
        }

        let current = all.first { $0.range.contains(reference) }
        let state = current?.state ?? .unknown
        let next = nextWindow(after: reference, in: all)
        let mission = missionWindow.map { VisibilityEvaluator.assess(.earthLineOfSight, data: data, window: $0) }

        return EarthWindowReport(siteID: siteID, period: period, reference: reference, segments: inPeriod,
                                 stateAtReference: state, currentSegment: current, next: next,
                                 mission: mission, hasData: data != nil)
    }

    /// First visible segment starting after `reference`, reached through known data only.
    /// If any no-data stretch lies between, an earlier window could hide inside it, so the answer is unknown.
    static func nextWindow(after reference: Date, in segments: [EarthVisibilitySegment]) -> NextEarthWindow {
        guard let currentIndex = segments.firstIndex(where: { $0.range.contains(reference) }) else {
            return .unknown(reason: NextEarthWindow.insufficientDataMessage)
        }
        if segments[currentIndex].state == .unknown {
            return .unknown(reason: NextEarthWindow.insufficientDataMessage)
        }
        for segment in segments[(currentIndex + 1)...] {
            switch segment.state {
            case .unknown:
                return .unknown(reason: NextEarthWindow.insufficientDataMessage)
            case .visible:
                // Reached only through known obstruction (or the end of the current window).
                return .upcoming(segment, wait: segment.range.start.timeIntervalSince(reference))
            case .obstructed:
                continue
            }
        }
        return .unknown(reason: NextEarthWindow.insufficientDataMessage)
    }

    // MARK: - Helpers

    static func hull(_ ranges: [UTCRange]) -> UTCRange? {
        guard let start = ranges.map(\.start).min(), let end = ranges.map(\.end).max(), end > start else { return nil }
        return UTCRange(start: start, end: end)
    }

    private static func union(_ a: UTCRange, _ b: UTCRange) -> UTCRange {
        UTCRange(start: min(a.start, b.start), end: max(a.end, b.end))
    }
}
