import SwiftUI

/// Pinned footer with exactly one primary action for the current phase.
struct InspectorFooterView: View {
    @Environment(MissionStore.self) private var store

    var body: some View {
        VStack(spacing: LunaviSpacing.s) {
            if let note = store.footerNote {
                Text(note)
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("footer.note")
            }
            PrimaryActionButton(assignsDefaultShortcut: true)
            secondaryAction
        }
        .padding(LunaviSpacing.l)
        .background(LunaviColors.backgroundSecondary)
        .overlay(alignment: .top) {
            Hairline()
        }
    }

    @ViewBuilder
    private var secondaryAction: some View {
        switch store.phase {
        case .recoveryPreview:
            Button {
                store.clearPreview()
            } label: {
                Label("Clear Preview", systemImage: "xmark.circle")
            }
            .buttonStyle(LunaviSecondaryButtonStyle())
            .accessibilityIdentifier("action.clearPreview")
        case .recoveryApplied where store.canCompareAgain:
            Button {
                store.compareAgain()
            } label: {
                Label("Compare Again", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(LunaviSecondaryButtonStyle())
            .accessibilityIdentifier("action.compareAgain")
        default:
            EmptyView()
        }
    }
}

/// The single primary action for the current phase (shared by the inspector and the compact bar).
struct PrimaryActionButton: View {
    var assignsDefaultShortcut = true
    @Environment(MissionStore.self) private var store
    @Environment(AppContainer.self) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch store.primaryAction {
        case .simulateDelay:
            Button {
                perform { store.simulateDelay() }
            } label: {
                Label("Simulate +\(store.delayHours)h Delay", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(LunaviPrimaryButtonStyle())
            .keyboardShortcut(assignsDefaultShortcut ? KeyboardShortcut.defaultAction : nil)
            .accessibilityIdentifier("action.simulateDelay")
        case .findRecoveryOptions:
            Button {
                perform { store.findRecoveryOptions() }
            } label: {
                Label("Find Recovery Options", systemImage: "lifepreserver")
            }
            .buttonStyle(LunaviPrimaryButtonStyle())
            .keyboardShortcut(assignsDefaultShortcut ? KeyboardShortcut.defaultAction : nil)
            .accessibilityIdentifier("action.findRecovery")
        case .acceptDelayedPlan:
            Button {
                perform { store.acceptDelayedPlan() }
            } label: {
                Label("Accept Delayed Plan", systemImage: "checkmark.circle")
            }
            .buttonStyle(LunaviPrimaryButtonStyle())
            .keyboardShortcut(assignsDefaultShortcut ? KeyboardShortcut.defaultAction : nil)
            .accessibilityIdentifier("action.acceptDelayed")
        case .applyCandidate(let enabled):
            Button {
                perform { store.applySelectedCandidate() }
            } label: {
                Label(store.isSimulated ? "Apply to Demo Plan" : "Apply to Plan", systemImage: "checkmark.circle")
            }
            .buttonStyle(LunaviPrimaryButtonStyle())
            .disabled(!enabled)
            .keyboardShortcut(assignsDefaultShortcut ? KeyboardShortcut.defaultAction : nil)
            .accessibilityIdentifier("action.apply")
        case .resetDemo:
            Button {
                perform { container.resetAll() }
            } label: {
                Label(store.isSimulated ? "Reset Demo" : "Reset Plan", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(LunaviPrimaryButtonStyle())
            .accessibilityIdentifier("action.resetDemo")
        }
    }

    private func perform(_ action: () -> Void) {
        if reduceMotion {
            action()
        } else {
            withAnimation(.easeInOut(duration: 0.3), action)
        }
    }
}
