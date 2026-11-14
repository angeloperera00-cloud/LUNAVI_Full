import SwiftUI

/// Text for Explain This Change, built from the comparison and dataset metadata.
/// Geometry rows appear only for computed data; simulated mode says so instead of inventing angles.
struct ExplanationContent: Sendable {
    struct Fact: Hashable, Sendable {
        var label: String
        var value: String
    }

    var whatChanged: String
    var whatChangedFacts: [Fact]
    var requirementAffected: String
    var issueBegins: String
    var issueFacts: [Fact]
    var why: String
    var geometryFacts: [Fact]
    var isSimulated: Bool
    var reliabilityFacts: [Fact]
    var assumptions: [String]
    var limitations: [String]

    static func make(comparison: MissionComparison, scenario: ScenarioBundle) -> ExplanationContent {
        let original = comparison.original.plan
        let delayed = comparison.delayed.plan
        let isSimulated = scenario.metadata.source == .simulatedFixture
        let siteName = scenario.siteName(delayed.siteID)
        let shiftText = UTCFormat.duration(abs(comparison.shift))
        let direction = comparison.shift >= 0 ? "later" : "earlier"

        let whatChanged = "The operating start moved \(shiftText) \(direction). Duration (\(delayed.durationHours) h) and site (\(siteName)) are unchanged."
        let changedFacts = [
            Fact(label: "Original window", value: "\(UTCFormat.dayMonthTime(original.start)) → \(UTCFormat.dayMonthTime(original.end)) UTC"),
            Fact(label: "Delayed window", value: "\(UTCFormat.dayMonthTime(delayed.start)) → \(UTCFormat.dayMonthTime(delayed.end)) UTC"),
        ]

        var requirement = "Both requirements still hold for the delayed window."
        var begins = "No requirement fails in the delayed window."
        var issueFacts: [Fact] = []
        var why = "No obstruction affects the delayed window."
        var geometry: [Fact] = []

        let unaffected = VisibilityCondition.allCases.filter { comparison.delayed.assessment(for: $0).status == .met }

        if let failure = comparison.delayed.firstFailure {
            let others = unaffected.map(\.title).joined(separator: " and ")
            requirement = "\(failure.condition.title) does not remain available for the entire delayed operating window."
                + (others.isEmpty ? "" : " \(others) remains available throughout.")
            begins = "\(UTCFormat.full(failure.time)) — \(UTCFormat.duration(failure.validBeforeFailure)) after the delayed start."
            issueFacts = [
                Fact(label: "Affected", value: "\(UTCFormat.duration(failure.affectedDuration)) of \(UTCFormat.duration(failure.windowDuration)) (\(UTCFormat.percent(failure.affectedFraction)))"),
                Fact(label: "Original window ended", value: "\(UTCFormat.full(original.end)) — \(UTCFormat.duration(abs(failure.time.timeIntervalSince(original.end)))) \(failure.time >= original.end ? "before" : "after") the failure"),
            ]
            if let event = failure.explanation {
                why = event.summary
                if let g = event.geometry {
                    geometry = [
                        Fact(label: "\(failure.condition == .sunlight ? "Sun" : "Earth") azimuth", value: degrees(g.targetAzimuthDeg)),
                        Fact(label: "\(failure.condition == .sunlight ? "Sun" : "Earth") elevation", value: degrees(g.targetElevationDeg)),
                        Fact(label: "Modeled horizon at that azimuth", value: degrees(g.horizonElevationDeg)),
                        Fact(label: "Clearance", value: degrees(g.clearanceDeg)),
                        Fact(label: "Horizon crossing", value: UTCFormat.full(event.time)),
                    ]
                }
            } else if isSimulated {
                why = "The simulated fixture defines an obstruction at this time. No terrain is modeled in simulated mode."
            } else {
                why = "The target falls below the modeled terrain horizon at this time."
            }
        } else if comparison.delayed.overall == .unknown {
            requirement = "Part of the delayed window has no data, so the requirements cannot be confirmed."
            begins = comparison.delayed.assessments.compactMap(\.firstUnknown).min().map { "Data ends at \(UTCFormat.full($0))." } ?? "—"
            why = "Missing data is never treated as visible."
        }

        let metadata = scenario.metadata
        var reliability = [
            Fact(label: "Data source", value: metadata.source.label),
            Fact(label: "Validation", value: metadata.bestValidation.label),
            Fact(label: "Dataset", value: metadata.title),
        ]
        if !isSimulated {
            reliability.append(Fact(label: "Ephemeris", value: metadata.ephemeris))
            reliability.append(Fact(label: "Frame", value: metadata.referenceFrame))
            if let step = metadata.timeStepSeconds {
                reliability.append(Fact(label: "Time step", value: "\(Int(step)) s"))
            }
            if let height = metadata.observerHeightMeters {
                reliability.append(Fact(label: "Observer height", value: "\(height.formatted(.number.precision(.fractionLength(1)))) m"))
            }
        }

        return ExplanationContent(
            whatChanged: whatChanged,
            whatChangedFacts: changedFacts,
            requirementAffected: requirement,
            issueBegins: begins,
            issueFacts: issueFacts,
            why: why,
            geometryFacts: geometry,
            isSimulated: isSimulated,
            reliabilityFacts: reliability,
            assumptions: metadata.assumptions,
            limitations: metadata.limitations
        )
    }

    private static func degrees(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(3))))°"
    }
}

struct ExplainChangeView: View {
    @Environment(MissionStore.self) private var store
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let comparison = store.comparison, let scenario = store.scenario {
                    content(ExplanationContent.make(comparison: comparison, scenario: scenario))
                        .padding(LunaviSpacing.xl)
                } else {
                    ContentUnavailableView(
                        "Nothing to explain yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Simulate a delay to compare the original and delayed plans.")
                    )
                    .padding(.top, 80)
                }
            }
            .background(LunaviColors.backgroundSecondary)
            .navigationTitle("Explain This Change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("explain.done")
                }
            }
        }
        .presentationBackground(LunaviColors.backgroundSecondary)
    }

    private func content(_ c: ExplanationContent) -> some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.xl) {
            if c.isSimulated {
                Label("Simulated demo — illustrative conditions. Not NASA-verified.", systemImage: "info.circle")
                    .font(LunaviTypography.captionEmphasis)
                    .foregroundStyle(LunaviColors.selectedTime)
            }
            section("What changed?", identifier: "explain.whatChanged") {
                Text(c.whatChanged)
                facts(c.whatChangedFacts)
            }
            section("Which requirement is affected?", identifier: "explain.requirement") {
                Text(c.requirementAffected)
            }
            section("When does the issue begin?", identifier: "explain.when") {
                Text(c.issueBegins)
                    .monospacedDigit()
                facts(c.issueFacts)
            }
            section("Why does it happen?", identifier: "explain.why") {
                Text(c.why)
                if c.geometryFacts.isEmpty {
                    Text(c.isSimulated
                         ? "Azimuth, elevation and horizon angles are not shown: simulated mode has no terrain model, and LUNAVI does not invent obstruction angles."
                         : "No computed geometry is attached to this event.")
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textMuted)
                } else {
                    facts(c.geometryFacts)
                }
            }
            section("What can be changed?", identifier: "explain.options") {
                VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                    Button {
                        dismiss()
                        store.findRecoveryOptions()
                    } label: {
                        Label("Open recovery options", systemImage: "lifepreserver")
                    }
                    .buttonStyle(LunaviSecondaryButtonStyle())
                    .accessibilityIdentifier("explain.openRecovery")
                    Button {
                        dismiss()
                        navigation.presentEditConfirmationAfterDismissal()
                    } label: {
                        Label("Change the operating start time", systemImage: "calendar.badge.clock")
                    }
                    .buttonStyle(LunaviSecondaryButtonStyle())
                    Button {
                        dismiss()
                        navigation.presentSiteExplorerAfterDismissal()
                    } label: {
                        Label("Compare another supported location", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(LunaviSecondaryButtonStyle())
                    Button {
                        dismiss()
                        navigation.presentEditConfirmationAfterDismissal()
                    } label: {
                        Label("Adjust operating duration (exploratory)", systemImage: "timer")
                    }
                    .buttonStyle(LunaviSecondaryButtonStyle())
                }
            }
            section("How reliable is this conclusion?", identifier: "explain.reliability") {
                facts(c.reliabilityFacts)
                if !c.assumptions.isEmpty {
                    Text("Assumptions").lunaviSectionLabel()
                    bullets(c.assumptions)
                }
                if !c.limitations.isEmpty {
                    Text("Known limitations").lunaviSectionLabel()
                    bullets(c.limitations)
                }
                Text("No numerical confidence percentage is given: the result depends on the data and assumptions above.")
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textMuted)
            }
        }
        .font(LunaviTypography.body)
        .foregroundStyle(LunaviColors.textSecondary)
        .frame(maxWidth: 720, alignment: .leading)
    }

    private func section<Content: View>(_ title: String, identifier: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            Text(title)
                .font(LunaviTypography.headline)
                .foregroundStyle(LunaviColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)
            content()
        }
    }

    private func facts(_ items: [ExplanationContent.Fact]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { fact in
                KeyValueRow(fact.label, fact.value)
            }
        }
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(LunaviTypography.caption)
            }
        }
    }
}

#Preview("Explain This Change", traits: .landscapeLeft) {
    PreviewHost(phase: .delayed) {
        ExplainChangeView()
    }
}
