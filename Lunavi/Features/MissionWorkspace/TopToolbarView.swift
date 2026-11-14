import SwiftUI

/// Quiet top toolbar: brand, site and mission, data mode, Shadow Analysis, Data & Method, Reset.
///
/// It never grows wider than the window: the mission name truncates first, then the action labels
/// collapse to icons (`iconOnlyActions`), and below the compact breakpoint the mission name hides.
/// A toolbar wider than the window would otherwise widen the whole workspace and clip the inspector.
struct TopToolbarView: View {
    let isCompact: Bool
    var iconOnlyActions = false
    @Environment(MissionStore.self) private var store
    @Environment(AppNavigationState.self) private var navigation
    @Environment(AppContainer.self) private var container

    /// "Demo" only describes the simulated fixture; real computed data gets a neutral label.
    private var resetTitle: String { store.isSimulated ? "Reset Demo" : "Reset Plan" }

    var body: some View {
        HStack(spacing: LunaviSpacing.l) {
            brand
            Hairline(vertical: true)
                .frame(height: 32)
            siteButton
            if !isCompact {
                missionLabel
                    .layoutPriority(-1)
            }
            Spacer(minLength: LunaviSpacing.s)
            if let source = store.dataSource {
                DataModeBadge(source: source)
                    .accessibilityIdentifier("toolbar.dataMode")
            }
            Button {
                navigation.isShadowAnalysisPresented = true
            } label: {
                Label("Shadow Analysis", systemImage: "sun.horizon")
            }
            .buttonStyle(LunaviToolbarButtonStyle())
            .labelStyle(AdaptiveLabelStyle(iconOnly: isCompact || iconOnlyActions))
            .accessibilityLabel("Lunar Shadow Analysis")
            .accessibilityIdentifier("toolbar.shadowAnalysis")

            Button {
                navigation.isDataAndMethodPresented = true
            } label: {
                Label("Data & Method", systemImage: "books.vertical")
            }
            .buttonStyle(LunaviToolbarButtonStyle())
            .labelStyle(AdaptiveLabelStyle(iconOnly: isCompact || iconOnlyActions))
            .accessibilityLabel("Data and Method")
            .accessibilityIdentifier("toolbar.dataAndMethod")

            Button {
                container.resetAll()
            } label: {
                Label(resetTitle, systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(LunaviToolbarButtonStyle())
            .labelStyle(AdaptiveLabelStyle(iconOnly: isCompact || iconOnlyActions))
            .accessibilityLabel(resetTitle)
            .accessibilityIdentifier("toolbar.resetDemo")
        }
        .padding(.horizontal, LunaviSpacing.xl - 4)
        .frame(maxWidth: .infinity)
        .frame(height: LunaviSpacing.toolbarHeight)
        .clipped()
        .background(LunaviColors.navigationBar)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            LunaviLogoMark(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("LUNAVI")
                    .font(LunaviTypography.wordmark)
                    .tracking(2.4)
                    .foregroundStyle(LunaviColors.textPrimary)
                Text("Lunar Mission Navigator")
                    .font(LunaviTypography.micro)
                    .foregroundStyle(LunaviColors.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("LUNAVI, Lunar Mission Navigator")
    }

    private var siteButton: some View {
        Button {
            navigation.isSiteExplorerPresented = true
        } label: {
            HStack(spacing: LunaviSpacing.s) {
                Image(systemName: "mappin.circle")
                    .foregroundStyle(LunaviColors.selectedTime)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Site")
                        .lunaviSectionLabel()
                    Text(store.committedSite?.name ?? "—")
                        .font(LunaviTypography.bodyEmphasis)
                        .foregroundStyle(LunaviColors.textPrimary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LunaviColors.textMuted)
            }
            .padding(.horizontal, LunaviSpacing.m)
            .frame(minHeight: LunaviSpacing.minimumTouchTarget)
            .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium).stroke(LunaviColors.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Site: \(store.committedSite?.name ?? "none"). Open Site Explorer")
        .accessibilityIdentifier("toolbar.site")
    }

    private var missionLabel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mission")
                .lunaviSectionLabel()
            Text(store.missionName)
                .font(LunaviTypography.body)
                .foregroundStyle(LunaviColors.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
