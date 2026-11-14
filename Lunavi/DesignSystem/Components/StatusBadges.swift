import SwiftUI

/// Maps statuses to colour and symbol. Status is always shown with text and an icon, never colour alone.
enum StatusStyle {
    static func color(for status: ConditionStatus) -> Color {
        switch status {
        case .met:
            return LunaviColors.success
        case .partial, .unavailable:
            return LunaviColors.failure
        case .unknown:
            return LunaviColors.unknown
        }
    }

    static func symbol(for status: ConditionStatus) -> String {
        switch status {
        case .met:
            return "checkmark.circle.fill"
        case .partial:
            return "exclamationmark.triangle.fill"
        case .unavailable:
            return "xmark.octagon.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    static func color(for overall: OverallStatus) -> Color {
        switch overall {
        case .met:
            return LunaviColors.success
        case .notMet:
            return LunaviColors.failure
        case .unknown:
            return LunaviColors.unknown
        }
    }

    static func symbol(for overall: OverallStatus) -> String {
        switch overall {
        case .met:
            return "checkmark.seal.fill"
        case .notMet:
            return "exclamationmark.octagon.fill"
        case .unknown:
            return "questionmark.diamond"
        }
    }

    static func title(for overall: OverallStatus) -> String {
        switch overall {
        case .met:
            return "Visibility Requirements Met"
        case .notMet:
            return "Visibility Requirements Not Met"
        case .unknown:
            return "Data Unavailable — Requirements Not Confirmed"
        }
    }

    static func shortTitle(for overall: OverallStatus) -> String {
        switch overall {
        case .met:
            return "Met"
        case .notMet:
            return "Not met"
        case .unknown:
            return "Unknown"
        }
    }
}

struct ConditionStatusBadge: View {
    let condition: VisibilityCondition
    let status: ConditionStatus

    var body: some View {
        let color = StatusStyle.color(for: status)
        Label(ConditionCopy.badgeText(condition: condition, status: status), systemImage: StatusStyle.symbol(for: status))
            .font(LunaviTypography.captionEmphasis)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall))
            .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall).stroke(color.opacity(0.45), lineWidth: 1))
            .fixedSize()
    }
}

struct OverallStatusBadge: View {
    let overall: OverallStatus

    var body: some View {
        let color = StatusStyle.color(for: overall)
        Label(StatusStyle.shortTitle(for: overall), systemImage: StatusStyle.symbol(for: overall))
            .font(LunaviTypography.captionEmphasis)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall))
            .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall).stroke(color.opacity(0.45), lineWidth: 1))
            .fixedSize()
            .accessibilityLabel("Overall: \(StatusStyle.title(for: overall))")
    }
}

/// "SIMULATED DEMO" (or the computed source) — shown wherever results appear.
struct DataModeBadge: View {
    let source: DataSourceKind

    var body: some View {
        let color = source == .simulatedFixture ? LunaviColors.selectedTime : LunaviColors.textSecondary
        Text(source.badgeText)
            .font(LunaviTypography.captionEmphasis)
            .tracking(0.8)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall).stroke(color.opacity(0.6), lineWidth: 1))
            .fixedSize()
            .accessibilityLabel(source.accessibilityLabel)
    }
}

struct PreviewTag: View {
    var body: some View {
        Text("PREVIEW")
            .font(LunaviTypography.captionEmphasis)
            .tracking(0.8)
            .foregroundStyle(LunaviColors.success)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall).stroke(LunaviColors.success.opacity(0.7), lineWidth: 1))
            .fixedSize()
            .accessibilityLabel("Preview — not committed")
            .accessibilityIdentifier("preview.tag")
    }
}
