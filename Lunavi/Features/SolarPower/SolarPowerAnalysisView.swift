import Charts
import SwiftUI

/// Experimental Solar Power Estimate for the plan in focus. Panel inputs are user assumptions; Sun
/// geometry and terrain shadowing come from the scenario's exported samples. Missing inputs show an
/// unavailable or incomplete state instead of a number.
struct SolarPowerAnalysisView: View {
    enum OrientationChoice: String, CaseIterable, Identifiable {
        case tracking = "Sun-tracking"
        case fixed = "Fixed panel"
        var id: String { rawValue }
    }

    @Environment(MissionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var area = 1.0
    @State private var efficiencyPercent = 30.0
    @State private var orientation: OrientationChoice = .tracking
    @State private var tilt = 90.0
    @State private var panelAzimuth = 0.0

    private var plan: MissionPlan? { store.focusEvaluation?.plan ?? store.committedPlan }
    private var geometry: ShadowGeometry? { store.shadowGeometry(for: plan?.siteID) }

    private var configuration: SolarPanelConfiguration {
        SolarPanelConfiguration(
            areaSquareMeters: area,
            efficiency: efficiencyPercent / 100,
            orientation: orientation == .tracking ? .sunTracking : .fixed(tiltDeg: tilt, azimuthDeg: panelAzimuth)
        )
    }

    private var estimate: SolarPowerEstimate? {
        guard let plan else { return nil }
        return SolarPowerEstimator.estimate(window: plan.window, geometry: geometry, configuration: configuration)
    }

    private var cursorSample: SolarPowerSample? {
        guard let geometry, let time = store.timelineCursor, configuration.validationErrors.isEmpty else { return nil }
        return SolarPowerEstimator.sample(at: time, geometry: geometry, configuration: configuration)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LunaviSpacing.l) {
                    Label("Experimental Solar Power Estimate", systemImage: "flask")
                        .font(LunaviTypography.captionEmphasis)
                        .foregroundStyle(LunaviColors.selectedTime)
                    Text("A simplified physical estimate for learning and comparison. It is not a spacecraft power, battery or endurance prediction.")
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    planHeader
                    assumptionsCard
                    if let estimate {
                        resultsCard(estimate)
                    }
                    methodFooter
                }
                .font(LunaviTypography.body)
                .foregroundStyle(LunaviColors.textSecondary)
                .frame(maxWidth: 880, alignment: .leading)
                .padding(LunaviSpacing.xl)
                .frame(maxWidth: .infinity)
            }
            .background(LunaviColors.backgroundSecondary)
            .navigationTitle("Solar Power (Experimental)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("solar.done")
                }
            }
        }
        .presentationBackground(LunaviColors.backgroundSecondary)
    }

    private var planHeader: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.site(id: plan?.siteID)?.name ?? "No site")
                    .font(LunaviTypography.headline)
                    .foregroundStyle(LunaviColors.textPrimary)
                if let plan {
                    Text("\(UTCFormat.full(plan.start)) → \(UTCFormat.full(plan.end)) · \(plan.durationHours) h · \(store.focusContextLabel)")
                        .font(LunaviTypography.measurementSmall)
                        .foregroundStyle(LunaviColors.selectedTime)
                }
            }
        }
    }

    private var assumptionsCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: LunaviSpacing.m) {
                Text("Panel assumptions (editable)").lunaviSectionLabel()
                HStack {
                    Text("Area")
                    Spacer()
                    TextField("Area", value: $area, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .accessibilityLabel("Panel area in square metres")
                        .accessibilityIdentifier("solar.area")
                    Text("m²")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Efficiency \(Int(efficiencyPercent.rounded())) %")
                    Slider(value: $efficiencyPercent, in: 1...50, step: 1)
                        .accessibilityLabel("Panel efficiency")
                        .accessibilityValue("\(Int(efficiencyPercent.rounded())) percent")
                }
                Picker("Orientation", selection: $orientation) {
                    ForEach(OrientationChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("solar.orientation")
                if orientation == .fixed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tilt from horizontal \(Int(tilt.rounded()))° (90° = vertical)")
                        Slider(value: $tilt, in: 0...90, step: 1)
                            .accessibilityLabel("Panel tilt")
                        Text("Facing azimuth \(Int(panelAzimuth.rounded()))° (clockwise from north)")
                        Slider(value: $panelAzimuth, in: 0...359, step: 1)
                            .accessibilityLabel("Panel facing azimuth")
                    }
                } else {
                    Text("Assumes the panel always faces the Sun (ideal tracking): incidence factor 1.")
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textMuted)
                }
                Text("Defaults (1 m², 30 %) are placeholders to edit, not a mission configuration.")
                    .font(LunaviTypography.micro)
                    .foregroundStyle(LunaviColors.textMuted)
            }
        }
    }

    @ViewBuilder
    private func resultsCard(_ estimate: SolarPowerEstimate) -> some View {
        PanelCard {
            VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                Text("Estimate").lunaviSectionLabel()
                switch estimate.status {
                case .invalidInputs(let errors):
                    ForEach(errors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(LunaviColors.failure)
                    }
                case .unavailable(let reason):
                    Label("Calculation unavailable", systemImage: "questionmark.diamond")
                        .foregroundStyle(LunaviColors.unknown)
                    Text(reason)
                        .font(LunaviTypography.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("solar.unavailable")
                case .complete, .partial:
                    if estimate.status == .partial {
                        Label("Incomplete — \(UTCFormat.duration(estimate.unknownDuration)) of the window has no geometry; energy covers the known part only.",
                              systemImage: "exclamationmark.circle")
                            .foregroundStyle(LunaviColors.unknown)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let sample = cursorSample, let power = sample.powerW {
                        KeyValueRow("Power at cursor (\(UTCFormat.dayMonthTime(sample.time)) UTC)", watts(power))
                    } else {
                        KeyValueRow("Power at cursor", "Unknown", valueColor: LunaviColors.unknown)
                    }
                    KeyValueRow("Energy over the known window", estimate.energyWh.map(wattHours) ?? "Unknown")
                    KeyValueRow("Mean power (known time)", estimate.meanPowerW.map(watts) ?? "Unknown")
                    KeyValueRow("Peak power", estimate.peakPowerW.map(watts) ?? "Unknown")
                    KeyValueRow("Sunlit (any part of disc), share of known time", estimate.illuminatedFractionOfKnownTime.map(UTCFormat.percent) ?? "Unknown")
                    KeyValueRow("Data coverage", "\(UTCFormat.duration(estimate.knownDuration)) known · \(UTCFormat.duration(estimate.unknownDuration)) missing",
                                valueColor: estimate.unknownDuration > 0 ? LunaviColors.unknown : LunaviColors.textPrimary)
                    if let irradiance = estimate.samples.compactMap(\.irradianceWm2).first {
                        KeyValueRow("Solar irradiance at the Moon", "\(Int(irradiance.rounded())) W/m² (from Sun distance)")
                    }
                    powerChart(estimate)
                }
            }
        }
        .accessibilityIdentifier("solar.results")
    }

    private func powerChart(_ estimate: SolarPowerEstimate) -> some View {
        // Contiguous known runs become separate series, so missing data shows as a gap.
        var run = 0
        var points: [(run: Int, time: Date, power: Double)] = []
        for sample in estimate.samples {
            if let power = sample.powerW {
                points.append((run, sample.time, power))
            } else {
                run += 1
            }
        }
        return Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("UTC", point.time), y: .value("Power (W)", point.power), series: .value("Run", point.run))
                    .foregroundStyle(LunaviColors.sunTrack)
                    .interpolationMethod(.linear)
            }
        }
        .chartYAxisLabel("W")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(UTCFormat.dayMonthTime(date))
                    }
                }
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Estimated power over the operating window")
    }

    private var methodFooter: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            Text("Method").lunaviSectionLabel()
            Text("Power = solar irradiance × panel area × efficiency × incidence factor × visible solar fraction. Incidence is the angle between the panel and the Sun; the visible fraction is the share of the Sun's disc above the modeled terrain — two separate factors. Energy is integrated with the trapezoidal rule between exported Sun samples.")
            ForEach(SolarPowerEstimator.limitations, id: \.self) { item in
                Text("• \(item)")
            }
        }
        .font(LunaviTypography.caption)
        .foregroundStyle(LunaviColors.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func watts(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) W"
    }

    private func wattHours(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)))) Wh"
    }
}

#Preview("Solar power — simulated (no geometry)", traits: .landscapeLeft) {
    PreviewHost(phase: .original) {
        SolarPowerAnalysisView()
    }
}
