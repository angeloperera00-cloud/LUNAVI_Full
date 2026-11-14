import SwiftUI

/// Mission Rescue: two comparable recovery cards, integrated with the map and timeline.
/// Selecting a card previews it; the committed plan changes only on Apply.
struct MissionRescueSection: View {
    @Environment(MissionStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.m) {
            HStack {
                Text("Mission rescue")
                    .lunaviSectionLabel()
                Spacer()
                if store.phase == .recoveryPreview {
                    PreviewTag()
                }
            }
            if let delayed = store.delayedEvaluation {
                DelayedSummaryRow(evaluation: delayed, delayHours: store.delayHours)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Recovery options")
                    .font(LunaviTypography.headline)
                    .foregroundStyle(LunaviColors.textPrimary)
                Text(store.isSimulated
                     ? "Same requirements, evaluated against the simulated fixture."
                     : "Same requirements, evaluated against the bundled computed data.")
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textMuted)
            }
            if store.candidates.isEmpty {
                NoRecoveryView()
            } else {
                ForEach(store.candidates) { candidate in
                    RecoveryCandidateCard(
                        candidate: candidate,
                        isSelected: store.previewCandidate?.kind == candidate.kind
                    ) {
                        if reduceMotion {
                            store.selectCandidate(candidate.kind)
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                store.selectCandidate(candidate.kind)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rescue.section")
    }
}

struct DelayedSummaryRow: View {
    let evaluation: PlanEvaluation
    let delayHours: Int

    var body: some View {
        HStack(alignment: .top, spacing: LunaviSpacing.s) {
            Image(systemName: StatusStyle.symbol(for: evaluation.overall))
                .foregroundStyle(StatusStyle.color(for: evaluation.overall))
            Text(text)
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        let span = "\(UTCFormat.dayMonthTime(evaluation.plan.start)) → \(UTCFormat.dayMonthTime(evaluation.plan.end)) UTC"
        if let failure = evaluation.firstFailure {
            return "Delayed plan (+\(delayHours) h, \(span)) fails: \(failure.condition.title) from \(UTCFormat.dayMonthTime(failure.time)) UTC."
        }
        return "Rescuing plan \(span) — \(StatusStyle.title(for: evaluation.overall).lowercased())."
    }
}

struct RecoveryCandidateCard: View {
    let candidate: RecoveryCandidate
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                HStack(alignment: .center, spacing: LunaviSpacing.s) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isSelected ? LunaviColors.selectedTime : LunaviColors.textMuted)
                    Text("\(candidate.kind.letter) · \(candidate.kind.title)")
                        .font(LunaviTypography.bodyEmphasis)
                        .foregroundStyle(LunaviColors.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if isSelected {
                        PreviewTag()
                    }
                }
                Text(candidate.siteName)
                    .font(LunaviTypography.captionEmphasis)
                    .foregroundStyle(candidate.kind == .alternativeSite ? LunaviColors.alternativeSite : LunaviColors.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    KeyValueRow("UTC start", UTCFormat.full(candidate.plan.start))
                    KeyValueRow("UTC end", UTCFormat.full(candidate.plan.end))
                    if candidate.kind == .sameSiteLaterTime {
                        KeyValueRow("Change", "\(UTCFormat.signedDuration(candidate.timeShift)) vs delayed plan")
                    } else {
                        KeyValueRow("Change", candidate.siteChangeDescription ?? "Site change")
                        KeyValueRow("Distance", candidate.distanceDescription)
                    }
                    KeyValueRow("Duration", "\(candidate.plan.durationHours) h")
                }
                HStack(spacing: LunaviSpacing.s) {
                    ConditionStatusBadge(condition: .sunlight, status: candidate.evaluation.sunlight.status)
                    ConditionStatusBadge(condition: .earthLineOfSight, status: candidate.evaluation.earth.status)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Label(candidate.benefit, systemImage: "plus.circle")
                        .foregroundStyle(LunaviColors.success)
                    Label(candidate.tradeoff, systemImage: "minus.circle")
                        .foregroundStyle(LunaviColors.textSecondary)
                }
                .font(LunaviTypography.caption)
                Text(candidate.explanation)
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Label(candidate.validationSummary, systemImage: "checkmark.shield")
                    .font(LunaviTypography.micro)
                    .foregroundStyle(LunaviColors.textMuted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LunaviColors.surfaceElevated, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium)
                    .stroke(isSelected ? LunaviColors.selectedTime : LunaviColors.border, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Previews this option without committing it.")
        .accessibilityIdentifier("recovery.\(candidate.kind.rawValue)")
    }
}

struct NoRecoveryView: View {
    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 6) {
                Label("No recovery options found", systemImage: "magnifyingglass")
                    .font(LunaviTypography.bodyEmphasis)
                    .foregroundStyle(LunaviColors.textPrimary)
                Text("No later window at this site and no other site with data meets both requirements for the full duration within the available data. Try a shorter duration or another start time.")
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recovery.none")
    }
}

/// Shown after Apply: the committed update, never described as NASA-approved.
struct AppliedPlanSection: View {
    @Environment(MissionStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.m) {
            Text("Mission summary")
                .lunaviSectionLabel()
            if let plan = store.committedPlan, let evaluation = store.committedEvaluation {
                CombinedStatusView(evaluation: evaluation, isSimulated: store.isSimulated, titlePrefix: "Updated Plan — ")
                    .accessibilityIdentifier("applied.banner")
                PanelCard {
                    VStack(alignment: .leading, spacing: 4) {
                        KeyValueRow("Site", store.site(id: plan.siteID)?.name ?? plan.siteID)
                        KeyValueRow("UTC start", UTCFormat.full(plan.start))
                        KeyValueRow("UTC end", UTCFormat.full(plan.end))
                        KeyValueRow("Duration", "\(plan.durationHours) h")
                        if let original = store.originalPlan {
                            KeyValueRow("Original start", UTCFormat.full(original.start), valueColor: LunaviColors.textSecondary)
                        }
                        if let delayed = store.delayedPlan, !store.acceptedDelayedPlan {
                            KeyValueRow("Delayed start", UTCFormat.full(delayed.start), valueColor: LunaviColors.textSecondary)
                        }
                    }
                }
                Text(store.isSimulated
                     ? "Simulated demo values. This is a demo plan update, not a NASA-approved recovery."
                     : "Computed values, \(store.metadata?.bestValidation.label.lowercased() ?? "not validated"). Not an operational or NASA-approved recovery.")
                    .font(LunaviTypography.micro)
                    .foregroundStyle(LunaviColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = store.confirmationMessage {
                Label(message, systemImage: "checkmark.circle")
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.success)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("applied.confirmation")
            }
        }
    }
}
