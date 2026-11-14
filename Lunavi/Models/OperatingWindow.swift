import Foundation

/// A half-open UTC interval `[start, end)`.
///
/// Every visibility interval, coverage period and operating window in LUNAVI uses this type,
/// so an interval ending at 06:00 and another starting at 06:00 join without a gap or overlap.
struct UTCRange: Codable, Hashable, Sendable {
    var start: Date
    var end: Date

    init(start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    init(start: Date, duration: TimeInterval) {
        self.init(start: start, end: start.addingTimeInterval(duration))
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var isEmpty: Bool { end <= start }

    /// Half-open containment: `start <= date < end`.
    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    func intersection(_ other: UTCRange) -> UTCRange? {
        let lower = max(start, other.start)
        let upper = min(end, other.end)
        return lower < upper ? UTCRange(start: lower, end: upper) : nil
    }

    func shifted(by interval: TimeInterval) -> UTCRange {
        UTCRange(start: start.addingTimeInterval(interval), end: end.addingTimeInterval(interval))
    }
}

/// A mission operating window is a UTC range.
typealias OperatingWindow = UTCRange

/// Set operations on lists of half-open UTC ranges.
enum IntervalMath {
    /// Sorts ranges and merges overlapping or touching ones. Empty ranges are dropped.
    static func normalized(_ ranges: [UTCRange]) -> [UTCRange] {
        let sorted = ranges.filter { !$0.isEmpty }.sorted { $0.start < $1.start }
        var merged: [UTCRange] = []
        for range in sorted {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1].end = max(last.end, range.end)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Intersection of two range sets.
    static func intersect(_ first: [UTCRange], _ second: [UTCRange]) -> [UTCRange] {
        let a = normalized(first)
        let b = normalized(second)
        var i = 0
        var j = 0
        var result: [UTCRange] = []
        while i < a.count && j < b.count {
            if let overlap = a[i].intersection(b[j]) {
                result.append(overlap)
            }
            if a[i].end < b[j].end {
                i += 1
            } else {
                j += 1
            }
        }
        return result
    }

    static func clip(_ ranges: [UTCRange], to window: UTCRange) -> [UTCRange] {
        intersect(ranges, [window])
    }

    /// The parts of `window` not covered by `ranges`.
    static func complement(of ranges: [UTCRange], within window: UTCRange) -> [UTCRange] {
        var gaps: [UTCRange] = []
        var cursor = window.start
        for range in clip(ranges, to: window) {
            if range.start > cursor {
                gaps.append(UTCRange(start: cursor, end: range.start))
            }
            cursor = max(cursor, range.end)
        }
        if cursor < window.end {
            gaps.append(UTCRange(start: cursor, end: window.end))
        }
        return gaps
    }

    static func totalDuration(_ ranges: [UTCRange]) -> TimeInterval {
        normalized(ranges).reduce(0) { $0 + $1.duration }
    }

    /// True only when `ranges` cover every instant of `window` (no gap of any length).
    static func covers(_ ranges: [UTCRange], window: UTCRange) -> Bool {
        complement(of: ranges, within: window).isEmpty
    }
}
