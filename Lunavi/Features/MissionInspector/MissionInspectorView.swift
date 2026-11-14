import SwiftUI

/// Right-hand inspector: overview, parameters, condition cards, phase-specific content, and a pinned
/// footer holding the primary action so it is never scrolled out of reach.
struct MissionInspectorView: View {
    @Environment(MissionStore.self) private var store
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The footer is a bottom safe-area inset of the scroll view, so the last controls (e.g. Compare
        // Sites) can always be scrolled fully above the pinned primary action instead of ending under it.
        ScrollView {
                VStack(alignment: .leading, spacing: LunaviSpacing.l) {
                    InspectorHeaderView()
                    if let notice = store.dataNotice {
                        NoticeBanner(text: notice)
                    }
                    MissionParametersSection()
                    VisibilityConditionsSection()
                    Button {
                        navigation.presentSiteComparison()
                    } label: {
                        Label("Compare Sites for This Window", systemImage: "square.split.3x1")
                    }
                    .buttonStyle(LunaviSecondaryButtonStyle())
                    .accessibilityIdentifier("action.compareSites")
                    phaseContent
                    AnalysisToolsSection()
                    LandingTerrainView(siteID: store.focusSiteID)
                }
                .padding(.horizontal, LunaviSpacing.l + 2)
                .padding(.vertical, LunaviSpacing.l)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: store.phase)
        }
        .scrollIndicators(.visible)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InspectorFooterView()
        }
        .background(LunaviColors.backgroundSecondary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector")
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch store.phase {
        case .original:
            EmptyView()
        case .delayed:
            DelayImpactSection()
        case .recoveryOptions, .recoveryPreview:
            MissionRescueSection()
        case .recoveryApplied:
            AppliedPlanSection()
        }
    }
}

/// Secondary analyses for the plan in focus. Each opens its own panel; none changes the plan.
struct AnalysisToolsSection: View {
    @Environment(AppNavigationState.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            Text("Analysis").lunaviSectionLabel()
            Button {
                navigation.present(\.isEarthWindowsPresented)
            } label: {
                Label("View Earth Visibility Windows", systemImage: "globe.europe.africa")
            }
            .buttonStyle(LunaviSecondaryButtonStyle())
            .accessibilityIdentifier("action.earthWindows")
            Button {
                navigation.present(\.isSolarPowerPresented)
            } label: {
                Label("Experimental Solar Power Estimate", systemImage: "bolt")
            }
            .buttonStyle(LunaviSecondaryButtonStyle())
            .accessibilityIdentifier("action.solarPower")
            Button {
                navigation.present(\.isReportPresented)
            } label: {
                Label("Mission Report (PDF)", systemImage: "doc.richtext")
            }
            .buttonStyle(LunaviSecondaryButtonStyle())
            .accessibilityIdentifier("action.report")
        }
    }
}

struct InspectorHeaderView: View {
    @Environment(MissionStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text("Mission Overview")
                    .lunaviSectionLabel()
                Spacer()
                if let source = store.dataSource {
                    DataModeBadge(source: source)
                }
            }
            Text(store.committedSite?.name ?? "No site")
                .font(LunaviTypography.screenTitle)
                .foregroundStyle(LunaviColors.textPrimary)
                .accessibilityIdentifier("inspector.siteName")
            Text(store.committedSite?.regionLabel ?? "Lunar South Pole")
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textSecondary)
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.caption2)
                Text(store.phase.title)
                    .font(LunaviTypography.captionEmphasis)
            }
            .foregroundStyle(LunaviColors.selectedTime)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("inspector.phase")
        }
    }
}

struct NoticeBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: LunaviSpacing.s) {
            Image(systemName: "info.circle")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(LunaviTypography.caption)
        .foregroundStyle(LunaviColors.textSecondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall).stroke(LunaviColors.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Inspector — conditions met", traits: .fixedLayout(width: 340, height: 980)) {
    PreviewHost(phase: .original) {
        MissionInspectorView()
    }
}

#Preview("Inspector — conditions failed", traits: .fixedLayout(width: 340, height: 980)) {
    PreviewHost(phase: .delayed) {
        MissionInspectorView()
    }
}

#Preview("Inspector — compact portrait sheet", traits: .portrait) {
    PreviewHost(phase: .delayed) {
        Color.black
            .sheet(isPresented: .constant(true)) {
                MissionInspectorView()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(LunaviColors.backgroundSecondary)
            }
    }
}
