import Foundation
import Observation

/// Presentation state for sheets and alerts.
@MainActor
@Observable
final class AppNavigationState {
    var isDataAndMethodPresented = false
    var isExplainPresented = false
    var isSiteExplorerPresented = false
    var isCompactInspectorPresented = false
    var isEditConfirmationPresented = false
    var isShadowAnalysisPresented = false
    var isSiteComparisonPresented = false

    func dismissAll() {
        isDataAndMethodPresented = false
        isExplainPresented = false
        isSiteExplorerPresented = false
        isCompactInspectorPresented = false
        isEditConfirmationPresented = false
        isShadowAnalysisPresented = false
        isSiteComparisonPresented = false
    }

    /// Shows the edit-plan confirmation once a sheet has finished dismissing.
    func presentEditConfirmationAfterDismissal() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.isEditConfirmationPresented = true
        }
    }

    /// Opens Site Comparison, first closing the compact inspector sheet if it is showing
    /// (one view cannot present two sheets at once).
    func presentSiteComparison() {
        guard isCompactInspectorPresented else {
            isSiteComparisonPresented = true
            return
        }
        isCompactInspectorPresented = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.isSiteComparisonPresented = true
        }
    }

    /// Opens the Site Explorer once a sheet has finished dismissing.
    func presentSiteExplorerAfterDismissal() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.isSiteExplorerPresented = true
        }
    }
}
