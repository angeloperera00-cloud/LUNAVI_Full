import Foundation

/// Fixed UTC formatting for mission times. Everything is computed from a UTC Gregorian calendar,
/// independent of the device's time zone and locale, and cheap enough to call while scrubbing.
enum UTCFormat {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    static let timeZone: TimeZone = TimeZone(identifier: "UTC") ?? .gmt

    private static let monthsUpper = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    private struct Parts {
        var year: Int
        var month: Int
        var day: Int
        var hour: Int
        var minute: Int
    }

    private static func parts(_ date: Date) -> Parts {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return Parts(year: c.year ?? 0, month: min(max(c.month ?? 1, 1), 12), day: c.day ?? 1, hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    private static func pad2(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    /// "20 NOV 2026"
    static func dayMonthYear(_ date: Date) -> String {
        let p = parts(date)
        return "\(pad2(p.day)) \(monthsUpper[p.month - 1]) \(p.year)"
    }

    /// "20 NOV"
    static func dayMonth(_ date: Date) -> String {
        let p = parts(date)
        return "\(pad2(p.day)) \(monthsUpper[p.month - 1])"
    }

    /// "06:00"
    static func time(_ date: Date) -> String {
        let p = parts(date)
        return "\(pad2(p.hour)):\(pad2(p.minute))"
    }

    /// "06:00 UTC"
    static func timeUTC(_ date: Date) -> String {
        "\(time(date)) UTC"
    }

    /// "20 NOV 06:00"
    static func dayMonthTime(_ date: Date) -> String {
        "\(dayMonth(date)) \(time(date))"
    }

    /// "20 NOV 2026 06:00 UTC"
    static func full(_ date: Date) -> String {
        "\(dayMonthYear(date)) \(time(date)) UTC"
    }

    /// "20 November 2026, 06:00 UTC" — for VoiceOver.
    static func spoken(_ date: Date) -> String {
        let p = parts(date)
        return "\(p.day) \(monthNames[p.month - 1]) \(p.year), \(pad2(p.hour)):\(pad2(p.minute)) UTC"
    }

    /// "2026-11-20T06:00:00Z"
    static func iso(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return "\(c.year ?? 0)-\(pad2(c.month ?? 1))-\(pad2(c.day ?? 1))T\(pad2(c.hour ?? 0)):\(pad2(c.minute ?? 0)):\(pad2(c.second ?? 0))Z"
    }

    static func isMidnight(_ date: Date) -> Bool {
        let p = parts(date)
        return p.hour == 0 && p.minute == 0
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// "24 h", "4 h 30 m", "5 d 0 h", "45 m"
    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((abs(interval) / 60).rounded())
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return minutes > 0 ? "\(days) d \(hours) h \(minutes) m" : "\(days) d \(hours) h"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours) h \(minutes) m" : "\(hours) h"
        }
        return "\(minutes) m"
    }

    /// "+6 h", "−2 d 0 h"
    static func signedDuration(_ interval: TimeInterval) -> String {
        (interval < 0 ? "−" : "+") + duration(interval)
    }

    /// "17 %"
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded())) %"
    }
}
