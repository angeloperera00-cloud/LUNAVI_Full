import Foundation

/// Explicit mission phases. Previewing is a separate phase so the committed plan provably stays intact.
enum MissionPhase: String, Sendable {
    case original
    case delayed
    case recoveryOptions
    case recoveryPreview
    case recoveryApplied

    var title: String {
        switch self {
        case .original:
            return "Original plan"
        case .delayed:
            return "Delay impact"
        case .recoveryOptions:
            return "Recovery options"
        case .recoveryPreview:
            return "Recovery preview"
        case .recoveryApplied:
            return "Recovery applied"
        }
    }
}

/// How a site is drawn on the map. Every role differs in shape and text as well as colour.
enum MapPinRole: String, Sendable {
    case active
    case failing
    case alternative
    case preview
    case unselected
    case noData

    var label: String {
        switch self {
        case .active:
            return "Current site"
        case .failing:
            return "Requirements not met"
        case .alternative:
            return "Alternative site"
        case .preview:
            return "Preview"
        case .unselected:
            return "Supported site"
        case .noData:
            return "No data"
        }
    }
}
