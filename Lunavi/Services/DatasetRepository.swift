import Foundation

enum DatasetError: LocalizedError, Equatable, Sendable {
    case missingResource(String)
    case decodingFailed(resource: String, detail: String)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "Missing bundled resource \(name)."
        case .decodingFailed(let resource, let detail):
            return "Could not read \(resource): \(detail)"
        case .invalidData(let message):
            return message
        }
    }
}

/// Loads scenario data from the app bundle.
///
/// If the science pipeline's `ComputedScenario.json` has been added to the bundle it is used;
/// otherwise the simulated demo fixture (`DemoMission.json`, `DemoSites.json`, `DemoVisibility.json`).
/// The two are never mixed.
struct DatasetRepository: Sendable {
    func loadScenario() throws -> ScenarioBundle {
        if let url = Bundle.main.url(forResource: "ComputedScenario", withExtension: "json") {
            let data = try Self.read(url, name: "ComputedScenario.json")
            return try Self.scenario(fromComputedJSON: data, resourceName: "ComputedScenario.json")
        }
        return try loadDemoScenario()
    }

    func loadDemoScenario() throws -> ScenarioBundle {
        let missionFile: DemoMissionFile = try Self.decodeResource("DemoMission")
        let sitesFile: DemoSitesFile = try Self.decodeResource("DemoSites")
        let visibilityFile: DemoVisibilityFile = try Self.decodeResource("DemoVisibility")
        let scenario = ScenarioBundle(
            mission: missionFile.mission,
            sites: sitesFile.sites,
            visibility: Self.index(visibilityFile.sites),
            metadata: visibilityFile.metadata,
            basemap: missionFile.basemap,
            sensitivity: visibilityFile.sensitivity ?? []
        )
        try Self.validate(scenario)
        return scenario
    }

    static func scenario(fromComputedJSON data: Data, resourceName: String = "scenario", overridingSource: DataSourceKind? = nil) throws -> ScenarioBundle {
        let file: ComputedScenarioFile = try decode(data, name: resourceName)
        var metadata = file.metadata
        // A simulated fixture stays labelled as simulated, wherever it is loaded from.
        if let overridingSource, metadata.source != .simulatedFixture {
            metadata.source = overridingSource
        }
        let scenario = ScenarioBundle(
            mission: file.mission,
            sites: file.sites,
            visibility: index(file.visibility),
            metadata: metadata,
            basemap: file.basemap,
            sensitivity: file.sensitivity ?? [],
            geometry: geometryIndex(file.geometry ?? [], sites: file.sites)
        )
        try validate(scenario)
        return scenario
    }

    /// Keeps only geometry that belongs to a known site and whose arrays are consistent; anything else
    /// is dropped so shadow analysis shows Data Unavailable instead of reading malformed arrays.
    static func geometryIndex(_ items: [ShadowGeometry], sites: [LunarSite]) -> [String: ShadowGeometry] {
        let known = Set(sites.map(\.id))
        let valid = items.filter { known.contains($0.siteID) && $0.isConsistent }
        return Dictionary(valid.map { ($0.siteID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func validate(_ scenario: ScenarioBundle) throws {
        guard !scenario.sites.isEmpty else {
            throw DatasetError.invalidData("The site catalogue is empty.")
        }
        guard scenario.site(id: scenario.mission.siteID) != nil else {
            throw DatasetError.invalidData("Default mission site '\(scenario.mission.siteID)' is not in the site catalogue.")
        }
        guard scenario.mission.durationHours > 0, scenario.mission.delayHours > 0,
              !scenario.mission.durationOptions.isEmpty, scenario.mission.durationOptions.allSatisfy({ $0 > 0 }) else {
            throw DatasetError.invalidData("Mission durations and delay must be positive.")
        }
        for (siteID, data) in scenario.visibility {
            guard scenario.site(id: siteID) != nil else {
                throw DatasetError.invalidData("Visibility data references unknown site '\(siteID)'.")
            }
            for range in data.coverage + data.sunlight + data.earthLineOfSight where range.end <= range.start {
                throw DatasetError.invalidData("Invalid interval for site '\(siteID)': end must be after start.")
            }
        }
    }

    private static func decodeResource<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw DatasetError.missingResource("\(name).json")
        }
        let data = try read(url, name: "\(name).json")
        return try decode(data, name: "\(name).json")
    }

    private static func read(_ url: URL, name: String) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw DatasetError.missingResource(name)
        }
    }

    private static func decode<T: Decodable>(_ data: Data, name: String) throws -> T {
        do {
            return try makeDecoder().decode(T.self, from: data)
        } catch {
            throw DatasetError.decodingFailed(resource: name, detail: String(describing: error))
        }
    }

    private static func index(_ items: [SiteVisibility]) -> [String: SiteVisibility] {
        Dictionary(items.map { ($0.siteID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
