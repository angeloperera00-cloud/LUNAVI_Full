import SwiftUI

enum PreviewPhase {
    case original
    case delayed
    case rescueOptions
    case rescuePreview
    case applied
}

/// Centralised preview fixtures: every preview drives the same bundled scenario through real
/// store actions, so previews and screenshots stay consistent with the running app.
@MainActor
enum PreviewFixtures {
    static func container(phase: PreviewPhase) -> AppContainer {
        let container = AppContainer(configuration: AppConfiguration(arguments: []))
        do {
            let scenario = try DatasetRepository().loadDemoScenario()
            container.missionStore.install(scenario)
            drive(container.missionStore, to: phase)
        } catch {
            container.missionStore.failLoading(error.localizedDescription)
        }
        return container
    }

    static func drive(_ store: MissionStore, to phase: PreviewPhase) {
        switch phase {
        case .original:
            break
        case .delayed:
            store.simulateDelay()
        case .rescueOptions:
            store.simulateDelay()
            store.findRecoveryOptions()
        case .rescuePreview:
            store.simulateDelay()
            store.findRecoveryOptions()
            store.selectCandidate(.alternativeSite)
        case .applied:
            store.simulateDelay()
            store.findRecoveryOptions()
            store.selectCandidate(.alternativeSite)
            store.applySelectedCandidate()
        }
    }
}

/// Injects a preconfigured container into a preview.
struct PreviewHost<Content: View>: View {
    @State private var container: AppContainer
    private let content: Content

    init(phase: PreviewPhase, @ViewBuilder content: () -> Content) {
        _container = State(initialValue: PreviewFixtures.container(phase: phase))
        self.content = content()
    }

    var body: some View {
        content
            .environment(container)
            .environment(container.missionStore)
            .environment(container.mapState)
            .environment(container.navigation)
            .preferredColorScheme(.dark)
            .tint(LunaviColors.selectedTime)
    }
}

#Preview("Workspace — original plan", traits: .landscapeLeft) {
    PreviewHost(phase: .original) {
        MissionWorkspaceView()
    }
}

#Preview("Workspace — delayed plan", traits: .landscapeLeft) {
    PreviewHost(phase: .delayed) {
        MissionWorkspaceView()
    }
}

#Preview("Mission Rescue — options", traits: .landscapeLeft) {
    PreviewHost(phase: .rescueOptions) {
        MissionWorkspaceView()
    }
}

#Preview("Mission Rescue — selected preview", traits: .landscapeLeft) {
    PreviewHost(phase: .rescuePreview) {
        MissionWorkspaceView()
    }
}

#Preview("Workspace — recovery applied", traits: .landscapeLeft) {
    PreviewHost(phase: .applied) {
        MissionWorkspaceView()
    }
}
