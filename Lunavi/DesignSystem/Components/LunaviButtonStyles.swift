import SwiftUI

/// Main call to action: near-white fill with a near-black label, the clearest element on the black
/// interface (18:1). Disabled actions fall back to a raised charcoal surface.
struct LunaviPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LunaviTypography.bodyEmphasis)
            .foregroundStyle(isEnabled ? LunaviColors.primaryActionText : LunaviColors.textMuted)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, LunaviSpacing.m)
            .background(
                isEnabled ? LunaviColors.primaryActionFill.opacity(configuration.isPressed ? 0.82 : 1) : LunaviColors.surfaceRaised,
                in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium)
                    .stroke(LunaviColors.border, lineWidth: isEnabled ? 0 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
            .hoverEffect(.highlight)
    }
}

struct LunaviSecondaryButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? LunaviTypography.captionEmphasis : LunaviTypography.bodyEmphasis)
            .foregroundStyle(LunaviColors.textPrimary.opacity(isEnabled ? 1 : 0.45))
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 36 : 44)
            .padding(.horizontal, compact ? LunaviSpacing.m : LunaviSpacing.l)
            .background(
                LunaviColors.surfaceElevated.opacity(configuration.isPressed ? 0.6 : 1),
                in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium)
            )
            .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium).stroke(LunaviColors.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
            .hoverEffect(.highlight)
    }
}

/// Quiet toolbar button.
struct LunaviToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LunaviTypography.body)
            .foregroundStyle(LunaviColors.textSecondary)
            .padding(.horizontal, 10)
            .frame(minHeight: LunaviSpacing.minimumTouchTarget)
            .background(
                LunaviColors.surfaceRaised.opacity(configuration.isPressed ? 1 : 0),
                in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall)
            )
            .contentShape(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall))
            .hoverEffect(.highlight)
    }
}
