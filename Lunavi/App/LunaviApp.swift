import SwiftUI
import UIKit

@main
struct LunaviApp: App {
    @State private var container: AppContainer

    init() {
        let configuration = AppConfiguration.current
        if configuration.isUITesting {
            UIView.setAnimationsEnabled(false)
        }
        _container = State(initialValue: AppContainer(configuration: configuration))
    }

    var body: some Scene {
        WindowGroup {
            MissionWorkspaceView()
                .environment(container)
                .environment(container.missionStore)
                .environment(container.mapState)
                .environment(container.navigation)
                .preferredColorScheme(.dark)
                .tint(LunaviColors.selectedTime)
                .task {
                    await container.bootstrap()
                }
        }
    }
}

// MARK: - Preview

/// The whole app exactly as it launches: same container, same bootstrap, same data.
/// With ComputedScenario.json bundled it shows the real NASA-derived data (COMPUTED badge);
/// without it, the simulated demo.
private struct LunaviAppPreview: View {
    @State private var container = AppContainer(configuration: AppConfiguration(arguments: []))

    var body: some View {
        MissionWorkspaceView()
            .environment(container)
            .environment(container.missionStore)
            .environment(container.mapState)
            .environment(container.navigation)
            .preferredColorScheme(.dark)
            .tint(LunaviColors.selectedTime)
            .task {
                await container.bootstrap()
            }
    }
}

#Preview("Full app — bundled data", traits: .landscapeLeft) {
    LunaviAppPreview()
}
