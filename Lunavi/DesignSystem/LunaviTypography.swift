import SwiftUI

/// SF Pro text styles (Dynamic Type) with tabular numerals for times, coordinates and durations.
enum LunaviTypography {
    static let wordmark = Font.system(.title3, design: .default, weight: .semibold)
    static let screenTitle = Font.system(.title2, design: .default, weight: .semibold)
    static let headline = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.subheadline)
    static let bodyEmphasis = Font.system(.subheadline, design: .default, weight: .semibold)
    static let caption = Font.system(.caption)
    static let captionEmphasis = Font.system(.caption, design: .default, weight: .semibold)
    static let micro = Font.system(.caption2)
    static let sectionLabel = Font.system(.caption, design: .default, weight: .semibold)
    static let measurementLarge = Font.system(.title3, design: .default, weight: .semibold).monospacedDigit()
    static let measurement = Font.system(.subheadline, design: .default, weight: .medium).monospacedDigit()
    static let measurementSmall = Font.system(.caption, design: .default, weight: .medium).monospacedDigit()
}

/// Compact uppercase technical label.
struct SectionLabelStyle: ViewModifier {
    var color: Color

    func body(content: Content) -> some View {
        content
            .font(LunaviTypography.sectionLabel)
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(color)
    }
}

extension View {
    func lunaviSectionLabel(color: Color = LunaviColors.textMuted) -> some View {
        modifier(SectionLabelStyle(color: color))
    }
}
