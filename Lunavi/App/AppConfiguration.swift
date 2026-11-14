import Foundation

/// Launch configuration from process arguments.
///
/// - `-uiTesting`: disables UIKit animations and pins the simulated fixture for deterministic UI tests.
/// - `-scienceServiceURL http://127.0.0.1:8000`: try the optional LUNAVI science service first,
///   falling back to bundled data (with a visible notice) if it is unreachable.
struct AppConfiguration: Sendable {
    var isUITesting: Bool
    var scienceServiceURL: URL?

    init(arguments: [String]) {
        isUITesting = arguments.contains("-uiTesting")
        if let index = arguments.firstIndex(of: "-scienceServiceURL"), arguments.indices.contains(index + 1) {
            scienceServiceURL = URL(string: arguments[index + 1])
        } else {
            scienceServiceURL = nil
        }
    }

    static var current: AppConfiguration {
        AppConfiguration(arguments: ProcessInfo.processInfo.arguments)
    }
}
