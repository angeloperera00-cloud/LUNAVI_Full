import SwiftUI

/// Elevated panel with a thin border and restrained corners.
struct PanelCard<Content: View>: View {
    var padding: CGFloat = 14
    var strokeColor: Color = LunaviColors.border
    var strokeWidth: CGFloat = 1
    var fill: Color = LunaviColors.surfaceElevated
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
            .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium).stroke(strokeColor, lineWidth: strokeWidth))
    }
}

/// Label/value row with tabular numerals for the value.
struct KeyValueRow: View {
    let key: String
    let value: String
    var valueColor: Color = LunaviColors.textPrimary

    init(_ key: String, _ value: String, valueColor: Color = LunaviColors.textPrimary) {
        self.key = key
        self.value = value
        self.valueColor = valueColor
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LunaviSpacing.s) {
            Text(key)
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
            Spacer(minLength: LunaviSpacing.s)
            Text(value)
                .font(LunaviTypography.measurementSmall)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Icon-only or title-and-icon, chosen at runtime.
struct AdaptiveLabelStyle: LabelStyle {
    let iconOnly: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }
        }
    }
}

/// Thin horizontal or vertical rule.
struct Hairline: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(LunaviColors.border)
            .frame(width: vertical ? LunaviSpacing.hairline : nil, height: vertical ? nil : LunaviSpacing.hairline)
            .accessibilityHidden(true)
    }
}
