import Foundation

/// One bundled computed scenario: a separately generated date range from the science pipeline.
struct ScenarioCatalogEntry: Identifiable, Hashable, Sendable {
    /// Resource name without extension, e.g. `ComputedScenario` or `ComputedScenario_2026-12`.
    var resourceName: String
    var metadataID: String
    var title: String
    /// Span of computed data (declared period, else the hull of all site coverage).
    var coverage: UTCRange
    var generatedAt: Date?
    var stepSeconds: Double?

    var id: String { resourceName }
}

/// Lists the computed scenarios bundled with the app. Each is a complete, independently computed
/// pipeline output; the app switches between them and never stitches, shifts or extrapolates one
/// into another's dates.
enum ScenarioCatalog {
    static let resourcePrefix = "ComputedScenario"

    /// Just the fields needed to describe a scenario file.
    private struct Header: Decodable {
        struct Metadata: Decodable {
            var id: String
            var title: String
            var generatedAt: Date?
            var timeStepSeconds: Double?
        }
        struct Visibility: Decodable {
            var coverage: [UTCRange]
        }
        var period: ScenarioPeriod?
        var metadata: Metadata
        var visibility: [Visibility]
    }

    static func entry(fromJSON data: Data, resourceName: String) throws -> ScenarioCatalogEntry {
        let header: Header
        do {
            header = try DatasetRepository.makeDecoder().decode(Header.self, from: data)
        } catch {
            throw DatasetError.decodingFailed(resource: resourceName, detail: String(describing: error))
        }
        let hull = EarthCommunicationWindowService.hull(header.visibility.flatMap(\.coverage))
        guard let coverage = header.period?.range ?? hull else {
            throw DatasetError.invalidData("\(resourceName) has no computed coverage.")
        }
        return ScenarioCatalogEntry(resourceName: resourceName, metadataID: header.metadata.id, title: header.metadata.title,
                                    coverage: coverage, generatedAt: header.metadata.generatedAt,
                                    stepSeconds: header.period?.stepSeconds ?? header.metadata.timeStepSeconds)
    }

    /// Every `ComputedScenario*.json` in `bundle`, sorted by coverage start. Unreadable files are skipped.
    static func entries(in bundle: Bundle = .main) -> [ScenarioCatalogEntry] {
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return urls
            .filter { $0.deletingPathExtension().lastPathComponent.hasPrefix(resourcePrefix) }
            .compactMap { url -> ScenarioCatalogEntry? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? entry(fromJSON: data, resourceName: url.deletingPathExtension().lastPathComponent)
            }
            .sorted { $0.coverage.start < $1.coverage.start }
    }
}
