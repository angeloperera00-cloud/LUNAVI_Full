import SwiftUI

/// Original vs delayed plan side by side, an impact alert, and the entry point to Explain This Change.
struct DelayImpactSection: View {
    @Environment(MissionStore.self) private var store
    @Environment(AppNavigationState.self) private var navigation

    var body: some View {
        if let comparison = store.comparison {
            VStack(alignment: .leading, spacing: LunaviSpacing.m) {
                Text("Delay impact")
                    .lunaviSectionLabel()
                HStack(alignment: .top, spacing: LunaviSpacing.s) {
                    ScenarioCardView(
                        title: "Original plan",
                        badge: nil,
                        evaluation: comparison.original,
                        siteName: store.site(id: comparison.original.plan.siteID)?.shortName ?? "—",
                        identifier: "comparison.original"
                    )
                    ScenarioCardView(
                        title: "Delayed plan",
                        badge: UTCFormat.signedDuration(comparison.shift),
                        evaluation: comparison.delayed,
                        siteName: store.site(id: comparison.delayed.plan.siteID)?.shortName ?? "—",
                        identifier: "comparison.delayed"
                    )
                }
                ImpactAlertCard(
                    comparison: comparison,
                    siteName: store.site(id: comparison.delayed.plan.siteID)?.name ?? "—",
                    isSimulated: store.isSimulated
                )
                Button {
                    navigation.isExplainPresented = true
                } label: {
                    Label("Explain This Change", systemImage: "text.magnifyingglass")
                }
                .buttonStyle(LunaviSecondaryButtonStyle())
                .accessibilityIdentifier("action.explain")
                if comparison.delayed.firstFailure != nil {
                    Button {
                        navigation.isShadowAnalysisPresented = true
                    } label: {
                        Label("Shadow Analysis", systemImage: "sun.horizon")
                    }
                    .buttonStyle(LunaviSecondaryButtonStyle())
                    .accessibilityIdentifier("action.shadowAnalysis")
                }
            }
        }
    }
}

/// Compact scenario summary for side-by-side comparison.
struct ScenarioCardView: View {
    let title: String
    let badge: String?
    let evaluation: PlanEvaluation
    let siteName: String
    let identifier: String

    private var failing: Bool { evaluation.overall != .met }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .lunaviSectionLabel(color: LunaviColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let badge {
                    Text(badge)
                        .font(LunaviTypography.captionEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(LunaviColors.selectedTime)
                }
            }
            Text(siteName)
                .font(LunaviTypography.captionEmphasis)
                .foregroundStyle(LunaviColors.textPrimary)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                row("Start", UTCFormat.dayMonthTime(evaluation.plan.start))
                row("End", UTCFormat.dayMonthTime(evaluation.plan.end))
                row("Duration", "\(evaluation.plan.durationHours) h")
            }
            HStack(spacing: 10) {
                mini(.sunlight, evaluation.sunlight.status)
                mini(.earthLineOfSight, evaluation.earth.status)
            }
            OverallStatusBadge(overall: evaluation.overall)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LunaviColors.surfaceElevated, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium)
                .stroke(failing ? LunaviColors.failure : LunaviColors.border, lineWidth: failing ? 1.5 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .foregroundStyle(LunaviColors.textMuted)
            Spacer(minLength: 2)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(LunaviColors.textPrimary)
        }
        .font(LunaviTypography.micro)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func mini(_ condition: VisibilityCondition, _ status: ConditionStatus) -> some View {
        HStack(spacing: 3) {
            Image(systemName: condition.symbolName)
                .foregroundStyle(condition == .sunlight ? LunaviColors.sunTrack : LunaviColors.earthTrack)
            Image(systemName: StatusStyle.symbol(for: status))
                .foregroundStyle(StatusStyle.color(for: status))
        }
        .font(LunaviTypography.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(condition.title): \(ConditionCopy.badgeText(condition: condition, status: status))")
    }
}

/// Restrained alert describing the impact of the delay.
struct ImpactAlertCard: View {
    let comparison: MissionComparison
    let siteName: String
    let isSimulated: Bool

    var body: some View {
        let delayed = comparison.delayed
        switch delayed.overall {
        case .met:
            card(
                color: LunaviColors.success,
                symbol: "checkmark.seal",
                title: "Delay absorbed",
                message: "Both requirements still hold for the delayed window\(isSimulated ? " in this simulated scenario" : "").",
                rows: analyzedRows
            )
        case .unknown:
            card(
                color: LunaviColors.unknown,
                symbol: "questionmark.diamond",
                title: "Visibility cannot be confirmed",
                message: "Part of the delayed window has no data, so the requirements cannot be confirmed. Unknown data is never treated as visible.",
                rows: analyzedRows
            )
        case .notMet:
            if let failure = delayed.firstFailure {
                card(
                    color: LunaviColors.failure,
                    symbol: "exclamationmark.triangle",
                    title: failure.condition == .sunlight ? "Sunlight interruption detected" : "Earth line-of-sight interruption detected",
                    message: explanation(for: failure),
                    rows: failureRows(failure) + analyzedRows
                )
            } else {
                card(color: LunaviColors.failure, symbol: "exclamationmark.triangle", title: "Requirements not met", message: "", rows: analyzedRows)
            }
        }
    }

    private var analyzedRows: [(String, String)] {
        let plan = comparison.delayed.plan
        return [("Analyzed", "Delayed plan · \(siteName) · \(UTCFormat.dayMonthTime(plan.start)) → \(UTCFormat.dayMonthTime(plan.end)) UTC")]
    }

    private func failureRows(_ failure: FailureEvent) -> [(String, String)] {
        [
            ("First failure", UTCFormat.full(failure.time)),
            ("Condition", failure.condition.title),
            ("Affected", "\(UTCFormat.duration(failure.affectedDuration)) of \(UTCFormat.duration(failure.windowDuration)) (\(UTCFormat.percent(failure.affectedFraction)))"),
        ]
    }

    private func explanation(for failure: FailureEvent) -> String {
        if let summary = failure.explanation?.summary {
            return summary
        }
        if isSimulated {
            return "In this simulated scenario, \(failure.condition.title.lowercased()) is unavailable from \(UTCFormat.dayMonthTime(failure.time)) UTC, before the delayed operating window ends."
        }
        return failure.condition == .sunlight
            ? "The Sun becomes obstructed by the modeled local horizon before the delayed operating window ends."
            : "Earth drops behind the modeled local horizon before the delayed operating window ends."
    }

    private func card(color: Color, symbol: String, title: String, message: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            Label(title, systemImage: symbol)
                .font(LunaviTypography.headline)
                .foregroundStyle(color)
            if isSimulated {
                Text("Simulated demo — illustrative conditions.")
                    .font(LunaviTypography.captionEmphasis)
                    .foregroundStyle(LunaviColors.selectedTime)
            }
            if !message.isEmpty {
                Text(message)
                    .font(LunaviTypography.body)
                    .foregroundStyle(LunaviColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                KeyValueRow(row.0, row.1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
        .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium).stroke(color.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("impact.alert")
    }
}
