import SwiftUI

struct VisibilityConditionsSection: View {
    @Environment(MissionStore.self) private var store

    var body: some View {
        if let evaluation = store.focusEvaluation {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Visibility requirements")
                        .lunaviSectionLabel()
                    Spacer()
                    Text(store.focusContextLabel)
                        .font(LunaviTypography.micro)
                        .foregroundStyle(LunaviColors.textMuted)
                }
                ConditionCardView(
                    assessment: evaluation.sunlight,
                    isSimulated: store.isSimulated,
                    isHighlighted: evaluation.firstFailure?.condition == .sunlight
                )
                ConditionCardView(
                    assessment: evaluation.earth,
                    isSimulated: store.isSimulated,
                    isHighlighted: evaluation.firstFailure?.condition == .earthLineOfSight
                )
                CombinedStatusView(evaluation: evaluation, isSimulated: store.isSimulated)
            }
        }
    }
}

struct ConditionCardView: View {
    let assessment: ConditionAssessment
    let isSimulated: Bool
    var isHighlighted = false

    private var accent: Color {
        assessment.condition == .sunlight ? LunaviColors.sunTrack : LunaviColors.earthTrack
    }

    private var titleLabel: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: assessment.condition.symbolName)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(assessment.condition.title)
                .lunaviSectionLabel(color: LunaviColors.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            // Title and badge share a row when they fit; otherwise the badge moves under the title,
            // so neither the title nor the badge is ever broken mid-word.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    titleLabel
                    Spacer(minLength: LunaviSpacing.s)
                    ConditionStatusBadge(condition: assessment.condition, status: assessment.status)
                }
                VStack(alignment: .leading, spacing: 6) {
                    titleLabel
                    ConditionStatusBadge(condition: assessment.condition, status: assessment.status)
                }
            }
            Text(ConditionCopy.explanation(for: assessment, isSimulated: isSimulated))
                .font(LunaviTypography.body)
                .foregroundStyle(LunaviColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(ConditionCopy.detail(for: assessment))
                .font(LunaviTypography.measurementSmall)
                .foregroundStyle(LunaviColors.textMuted)
            if assessment.condition == .earthLineOfSight {
                Text("Geometric line of sight only — not a communication guarantee.")
                    .font(LunaviTypography.micro)
                    .foregroundStyle(LunaviColors.textMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LunaviColors.surfaceElevated, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium)
                .stroke(isHighlighted ? LunaviColors.failure : LunaviColors.border, lineWidth: isHighlighted ? 1.5 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("condition.\(assessment.condition.rawValue)")
    }
}

struct CombinedStatusView: View {
    let evaluation: PlanEvaluation
    let isSimulated: Bool
    var titlePrefix: String?

    var body: some View {
        let color = StatusStyle.color(for: evaluation.overall)
        HStack(alignment: .top, spacing: LunaviSpacing.m) {
            Image(systemName: StatusStyle.symbol(for: evaluation.overall))
                .font(.title2)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text((titlePrefix ?? "") + StatusStyle.title(for: evaluation.overall))
                    .font(LunaviTypography.headline)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ConditionCopy.overallSubtitle(for: evaluation, isSimulated: isSimulated))
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
        .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium).stroke(color.opacity(0.55), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inspector.combinedStatus")
    }
}
