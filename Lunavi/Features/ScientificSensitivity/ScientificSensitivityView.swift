import SwiftUI

/// How the committed plan's result changes under alternative assumptions.
/// Requires sensitivity variants from the science pipeline; otherwise shows an informative
/// unavailable state. No probability or confidence percentage is ever shown.
struct ScientificSensitivityView: View {
    @Environment(MissionStore.self) private var store

    var body: some View {
        let rows = store.sensitivityRows
        if rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Sensitivity results unavailable", systemImage: "slider.horizontal.3")
                    .font(LunaviTypography.bodyEmphasis)
                    .foregroundStyle(LunaviColors.textPrimary)
                Text(store.isSimulated
                     ? "This session uses a simulated fixture, which contains no sensitivity results. LUNAVI does not invent them. Generate variants for observer height and horizon clearance with the science pipeline (`python -m lunavi_science build`)."
                     : "The bundled computed data contains no sensitivity variants for this site.")
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall).stroke(LunaviColors.border, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sensitivity.unavailable")
        } else {
            VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                Text("Committed plan evaluated under each assumption set:")
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textMuted)
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: LunaviSpacing.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                                .font(LunaviTypography.bodyEmphasis)
                                .foregroundStyle(LunaviColors.textPrimary)
                            Text("Observer \(row.observerHeightMeters.formatted(.number.precision(.fractionLength(1)))) m · clearance \(row.minimumClearanceDeg.formatted(.number.precision(.fractionLength(2))))°")
                                .font(LunaviTypography.micro)
                                .monospacedDigit()
                                .foregroundStyle(LunaviColors.textMuted)
                        }
                        Spacer()
                        ConditionStatusBadge(condition: .sunlight, status: row.evaluation.sunlight.status)
                        ConditionStatusBadge(condition: .earthLineOfSight, status: row.evaluation.earth.status)
                        OverallStatusBadge(overall: row.evaluation.overall)
                    }
                    .padding(10)
                    .background(LunaviColors.surfaceElevated, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall))
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("sensitivity.table")
        }
    }
}
