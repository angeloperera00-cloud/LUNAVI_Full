import CoreGraphics
import Foundation

enum TimelineZoom: String, CaseIterable, Identifiable, Sendable {
    case focus
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus:
            return "Focus"
        case .all:
            return "All data"
        }
    }
}

struct TimelineSegment: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case visible
        case obstructed
        case unknown
    }

    var range: UTCRange
    var kind: Kind
}

struct TimelineWindowMark: Hashable, Sendable, Identifiable {
    enum Style: Hashable, Sendable {
        case committed
        case original
        case delayedFailing
        case delayedOK
        case preview
        case applied
    }

    enum LabelAlignment: Hashable, Sendable {
        case leading
        case trailing
        case center
    }

    var id: String
    var range: UTCRange
    var style: Style
    var label: String
    var labelAlignment: LabelAlignment
}

struct TimelineFailureMark: Hashable, Sendable {
    var time: Date
    var condition: VisibilityCondition
}

/// Fixed vertical layout of the plot (points).
enum TimelineMetrics {
    static let plotHeight: CGFloat = 112
    static let dayLabelY: CGFloat = 0
    static let hourLabelY: CGFloat = 13
    static let windowTop: CGFloat = 31
    static let sunTop: CGFloat = 36
    static let earthTop: CGFloat = 64
    static let trackHeight: CGFloat = 20
    static let windowBottom: CGFloat = 89
    static let windowLabelY: CGFloat = 93
    static let horizontalInset: CGFloat = 8
}

/// Maps an absolute UTC axis to x positions.
struct TimelineLayout: Sendable {
    let width: CGFloat
    let range: UTCRange

    var plotWidth: CGFloat { max(1, width - 2 * TimelineMetrics.horizontalInset) }

    func x(_ date: Date) -> CGFloat {
        let total = max(range.duration, 1)
        return TimelineMetrics.horizontalInset + CGFloat(date.timeIntervalSince(range.start) / total) * plotWidth
    }

    func date(atX x: CGFloat) -> Date {
        let fraction = min(max((x - TimelineMetrics.horizontalInset) / plotWidth, 0), 1)
        return range.start.addingTimeInterval(range.duration * Double(fraction))
    }
}

/// Everything the timeline draws, computed from the store in one pass.
struct TimelineModel: Sendable {
    var range: UTCRange
    var trackSiteName: String
    var isPreviewTrack: Bool
    var sunSegments: [TimelineSegment]
    var earthSegments: [TimelineSegment]
    var windows: [TimelineWindowMark]
    var failures: [TimelineFailureMark]
    var cursor: Date?
    var cursorSun: PointState
    var cursorEarth: PointState
    var firstFailureTime: Date?

    var cursorAccessibilityValue: String {
        guard let cursor else { return "No cursor" }
        return "\(UTCFormat.spoken(cursor)). Sunlight \(cursorSun.label). Earth line of sight \(cursorEarth.label). Site \(trackSiteName)."
    }

    @MainActor
    static func make(store: MissionStore, zoom: TimelineZoom) -> TimelineModel {
        let trackSiteID = store.focusSiteID
        let data = store.visibility(for: trackSiteID)
        let windows = windowMarks(store: store)
        let range = visibleRange(store: store, zoom: zoom, data: data, windows: windows)
        var failures: [TimelineFailureMark] = []
        if let failure = store.focusEvaluation?.firstFailure {
            failures.append(TimelineFailureMark(time: failure.time, condition: failure.condition))
        }
        let cursor = store.timelineCursor
        let preview = store.previewCandidate
        return TimelineModel(
            range: range,
            trackSiteName: store.site(id: trackSiteID)?.name ?? "—",
            isPreviewTrack: preview != nil && preview?.plan.siteID != store.committedPlan?.siteID,
            sunSegments: segments(for: .sunlight, data: data, range: range),
            earthSegments: segments(for: .earthLineOfSight, data: data, range: range),
            windows: windows,
            failures: failures,
            cursor: cursor,
            cursorSun: cursor.map { data?.state(of: .sunlight, at: $0) ?? .unknown } ?? .unknown,
            cursorEarth: cursor.map { data?.state(of: .earthLineOfSight, at: $0) ?? .unknown } ?? .unknown,
            firstFailureTime: store.focusEvaluation?.firstFailure?.time
        )
    }

    static func segments(for condition: VisibilityCondition, data: SiteVisibility?, range: UTCRange) -> [TimelineSegment] {
        guard let data else {
            return [TimelineSegment(range: range, kind: .unknown)]
        }
        let covered = IntervalMath.clip(data.coverage, to: range)
        let visible = IntervalMath.intersect(IntervalMath.clip(data.intervals(for: condition), to: range), covered)
        let obstructed = IntervalMath.intersect(IntervalMath.complement(of: visible, within: range), covered)
        let unknown = IntervalMath.complement(of: covered, within: range)
        var result: [TimelineSegment] = []
        result += visible.map { TimelineSegment(range: $0, kind: .visible) }
        result += obstructed.map { TimelineSegment(range: $0, kind: .obstructed) }
        result += unknown.map { TimelineSegment(range: $0, kind: .unknown) }
        return result.sorted { $0.range.start < $1.range.start }
    }

    @MainActor
    static func windowMarks(store: MissionStore) -> [TimelineWindowMark] {
        var marks: [TimelineWindowMark] = []
        func span(_ plan: MissionPlan) -> String {
            "\(UTCFormat.time(plan.start))–\(UTCFormat.time(plan.end))"
        }
        switch store.phase {
        case .original:
            if let plan = store.committedPlan {
                marks.append(TimelineWindowMark(id: "committed", range: plan.window, style: .committed, label: "Plan \(span(plan)) (\(plan.durationHours) h)", labelAlignment: .center))
            }
        case .delayed, .recoveryOptions, .recoveryPreview, .recoveryApplied:
            if let original = store.originalPlan {
                marks.append(TimelineWindowMark(id: "original", range: original.window, style: .original, label: "Original \(span(original))", labelAlignment: .leading))
            }
            if let delayed = store.delayedPlan {
                let fails = store.delayedEvaluation?.overall != .met
                marks.append(TimelineWindowMark(id: "delayed", range: delayed.window, style: fails ? .delayedFailing : .delayedOK, label: "Delayed +\(store.delayHours) h \(span(delayed))", labelAlignment: .trailing))
            }
            if let preview = store.previewCandidate {
                marks.append(TimelineWindowMark(id: "preview", range: preview.plan.window, style: .preview, label: "Preview \(preview.kind.letter) · \(span(preview.plan))", labelAlignment: .center))
            }
            if store.phase == .recoveryApplied, let applied = store.committedPlan, applied != store.delayedPlan {
                marks.append(TimelineWindowMark(id: "applied", range: applied.window, style: .applied, label: "Applied \(span(applied))", labelAlignment: .center))
            }
        }
        return marks
    }

    @MainActor
    static func visibleRange(store: MissionStore, zoom: TimelineZoom, data: SiteVisibility?, windows: [TimelineWindowMark]) -> UTCRange {
        var ranges: [UTCRange] = []
        switch zoom {
        case .all:
            ranges += data?.coverage ?? []
            ranges += store.visibility(for: store.committedPlan?.siteID)?.coverage ?? []
            ranges += windows.map(\.range)
        case .focus:
            if let preview = store.previewCandidate {
                ranges = [preview.plan.window]
            } else {
                ranges = windows.map(\.range)
            }
        }
        guard let start = ranges.map(\.start).min(), let end = ranges.map(\.end).max() else {
            let anchor = store.committedPlan?.start ?? Date()
            return UTCRange(start: anchor.addingTimeInterval(-12 * 3600), end: anchor.addingTimeInterval(36 * 3600))
        }
        let span = end.timeIntervalSince(start)
        let pad: TimeInterval = zoom == .all ? 3 * 3600 : max(6 * 3600, span * 0.12)
        return UTCRange(start: start.addingTimeInterval(-pad), end: end.addingTimeInterval(pad))
    }
}
