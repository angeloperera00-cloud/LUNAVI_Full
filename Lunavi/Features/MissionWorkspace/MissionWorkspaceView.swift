import SwiftUI

/// One landscape workspace: toolbar, dominant map with the timeline beneath it, and a fixed-width
/// inspector. Below 900 pt of width (portrait 11", narrow windows) the inspector becomes a sheet.
struct MissionWorkspaceView: View {
    @Environment(MissionStore.self) private var store
    @Environment(AppNavigationState.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        GeometryReader { proxy in
            let width = proxy.size.width
            let isCompact = width < LunaviSpacing.compactWidthBreakpoint
            VStack(spacing: 0) {
                TopToolbarView(isCompact: isCompact, iconOnlyActions: width < LunaviSpacing.labeledToolbarMinimumWidth)
                Hairline()
                content(isCompact: isCompact, width: width)
            }
            // Nothing inside may widen the workspace past the window.
            .frame(width: width, height: proxy.size.height)
            .clipped()
            .background(LunaviColors.background.ignoresSafeArea())
        }
        .sheet(isPresented: $navigation.isDataAndMethodPresented) {
            DataAndMethodView()
        }
        .sheet(isPresented: $navigation.isExplainPresented) {
            ExplainChangeView()
        }
        .sheet(isPresented: $navigation.isSiteExplorerPresented) {
            SiteExplorerView()
        }
        .sheet(isPresented: $navigation.isShadowAnalysisPresented) {
            ShadowAnalysisView()
        }
        .sheet(isPresented: $navigation.isSiteComparisonPresented) {
            SiteComparisonView()
        }
        .sheet(isPresented: $navigation.isEarthWindowsPresented) {
            EarthCommunicationWindowsView()
        }
        .sheet(isPresented: $navigation.isReportPresented) {
            MissionReportView()
        }
        .sheet(isPresented: $navigation.isSolarPowerPresented) {
            SolarPowerAnalysisView()
        }
        .fullScreenCover(isPresented: $navigation.isTutorialPresented) {
            LunaviTutorialView()
        }
        .sheet(isPresented: $navigation.isCompactInspectorPresented) {
            MissionInspectorView()
                .presentationDetents([.medium, .large])
                .presentationBackground(LunaviColors.backgroundSecondary)
        }
        .alert("Edit the mission plan?", isPresented: $navigation.isEditConfirmationPresented) {
            Button("Edit Plan", role: .destructive) {
                store.returnToPlanEditing()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Editing clears the delay comparison and recovery options. The committed plan becomes the new baseline.")
        }
        .sensoryFeedback(.warning, trigger: store.failureFeedbackCount)
        .sensoryFeedback(.success, trigger: store.successFeedbackCount)
    }

    @ViewBuilder
    private func content(isCompact: Bool, width: CGFloat) -> some View {
        switch store.loadState {
        case .idle, .loading:
            LoadingStateView()
        case .failed(let message):
            DataLoadFailureView(message: message)
        case .loaded:
            if isCompact {
                compactLayout
            } else {
                regularLayout(inspectorWidth: LunaviSpacing.inspectorWidth(forWindowWidth: width))
            }
        }
    }

    private func regularLayout(inspectorWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                LunarMapView()
                Hairline()
                VisibilityTimelineView()
                    .frame(height: LunaviSpacing.timelineHeight)
            }
            Hairline(vertical: true)
            MissionInspectorView()
                .frame(width: inspectorWidth)
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            LunarMapView()
            Hairline()
            VisibilityTimelineView()
                .frame(height: LunaviSpacing.timelineHeight)
            Hairline()
            CompactStatusBar()
        }
    }
}

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: LunaviSpacing.m) {
            ProgressView()
            Text("Loading mission data…")
                .font(LunaviTypography.body)
                .foregroundStyle(LunaviColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct DataLoadFailureView: View {
    let message: String
    @Environment(AppContainer.self) private var container

    var body: some View {
        ContentUnavailableView {
            Label("Mission data unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await container.bootstrap(force: true) }
            }
            .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Compact layouts: status and the primary action stay on screen; details open in a sheet.
struct CompactStatusBar: View {
    @Environment(MissionStore.self) private var store
    @Environment(AppNavigationState.self) private var navigation

    var body: some View {
        HStack(spacing: LunaviSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.committedSite?.name ?? "—")
                    .font(LunaviTypography.bodyEmphasis)
                    .foregroundStyle(LunaviColors.textPrimary)
                    .lineLimit(1)
                if let evaluation = store.focusEvaluation {
                    OverallStatusBadge(overall: evaluation.overall)
                }
            }
            Spacer(minLength: LunaviSpacing.s)
            PrimaryActionButton(assignsDefaultShortcut: false)
                .frame(maxWidth: 280)
            Button {
                navigation.isCompactInspectorPresented = true
            } label: {
                Label("Mission Details", systemImage: "sidebar.right")
            }
            .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
            .accessibilityIdentifier("compact.details")
        }
        .padding(.horizontal, LunaviSpacing.l)
        .padding(.vertical, LunaviSpacing.s)
        .background(LunaviColors.backgroundSecondary)
    }
}
