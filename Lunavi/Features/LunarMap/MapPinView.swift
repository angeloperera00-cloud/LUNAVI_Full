import SwiftUI

/// Site marker. Each role differs in shape and text, not just colour:
/// active = amber dot with ring, failing = clay triangle with "!", alternative = sage diamond,
/// preview = sage diamond with ring, other = small grey dot, no data = dashed hollow ring.
struct MapPinView: View {
    let site: LunarSite
    let role: MapPinRole
    let detail: String
    let isInspected: Bool
    let onTap: () -> Void

    private var roleColor: Color {
        switch role {
        case .active:
            return LunaviColors.activeSite
        case .failing:
            return LunaviColors.failure
        case .alternative, .preview:
            return LunaviColors.alternativeSite
        case .unselected, .noData:
            return LunaviColors.unselectedSite
        }
    }

    var body: some View {
        Button(action: onTap) {
            marker
                .frame(width: LunaviSpacing.minimumTouchTarget, height: LunaviSpacing.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            callout
                .fixedSize()
                .offset(x: 34)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("\(site.name), \(detail)")
        .accessibilityHint("Shows a site preview. Does not change the mission plan.")
        .accessibilityIdentifier("map.pin.\(site.id)")
    }

    @ViewBuilder
    private var marker: some View {
        switch role {
        case .active:
            ZStack {
                Circle()
                    .stroke(LunaviColors.activeSite.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 30, height: 30)
                Circle()
                    .fill(LunaviColors.activeSite)
                    .frame(width: 14, height: 14)
                Circle()
                    .stroke(LunaviColors.background, lineWidth: 2)
                    .frame(width: 14, height: 14)
            }
        case .failing:
            ZStack {
                TriangleShape()
                    .fill(LunaviColors.failureFill)
                    .frame(width: 24, height: 21)
                TriangleShape()
                    .stroke(LunaviColors.background, lineWidth: 1.5)
                    .frame(width: 24, height: 21)
                Text("!")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LunaviColors.background)
                    .offset(y: 2)
            }
        case .alternative, .preview:
            ZStack {
                if role == .preview {
                    Circle()
                        .stroke(LunaviColors.alternativeSite, lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                }
                Rectangle()
                    .fill(LunaviColors.alternativeSite)
                    .frame(width: 13, height: 13)
                    .rotationEffect(.degrees(45))
                Rectangle()
                    .stroke(LunaviColors.background, lineWidth: 1.5)
                    .frame(width: 13, height: 13)
                    .rotationEffect(.degrees(45))
            }
        case .unselected:
            Circle()
                .fill(LunaviColors.unselectedSite)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(LunaviColors.background, lineWidth: 1.5))
        case .noData:
            Circle()
                .stroke(LunaviColors.unselectedSite, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .frame(width: 12, height: 12)
        }
    }

    private var callout: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(roleColor.opacity(0.7))
                .frame(width: 10, height: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(site.name)
                    .font(LunaviTypography.captionEmphasis)
                    .foregroundStyle(LunaviColors.textPrimary)
                Text(detail)
                    .font(LunaviTypography.micro)
                    .foregroundStyle(roleColor)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(LunaviColors.mapPlate, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall)
                    .stroke(roleColor.opacity(isInspected ? 0.95 : 0.45), lineWidth: isInspected ? 1.5 : 1)
            )
        }
        .accessibilityHidden(true)
    }
}
