import Foundation

struct MissionDefaults: Codable, Hashable, Sendable {
    var missionName: String
    var siteID: String
    var start: Date
    var durationHours: Int
    var delayHours: Int
    var durationOptions: [Int]
}

/// Describes the basemap image. Only a georeferenced basemap (with `metersPerPixel`) gets a scale bar.
struct BasemapManifest: Codable, Hashable, Sendable {
    var imageResource: String
    var imageExtension: String
    var isIllustrative: Bool
    var title: String
    var attribution: String
    var pixelWidth: Int
    var pixelHeight: Int
    var metersPerPixel: Double?
    var projection: String?
}

/// Everything one session needs: mission defaults, sites, visibility data, provenance and basemap.
struct ScenarioBundle: Sendable {
    var mission: MissionDefaults
    var sites: [LunarSite]
    var visibility: [String: SiteVisibility]
    var metadata: DatasetMetadata
    var basemap: BasemapManifest
    var sensitivity: [SensitivityVariant]
    /// Shadow-analysis geometry by site (schema 2). Empty for the simulated fixture and older files.
    var geometry: [String: ShadowGeometry] = [:]

    func site(id: String) -> LunarSite? {
        sites.first { $0.id == id }
    }

    func siteName(_ id: String) -> String {
        site(id: id)?.name ?? id
    }
}

// MARK: - File formats

/// `DemoMission.json`
struct DemoMissionFile: Codable, Sendable {
    var mission: MissionDefaults
    var basemap: BasemapManifest
}

/// `DemoSites.json`
struct DemoSitesFile: Codable, Sendable {
    var sites: [LunarSite]
}

/// `DemoVisibility.json`
struct DemoVisibilityFile: Codable, Sendable {
    var metadata: DatasetMetadata
    var sites: [SiteVisibility]
    var sensitivity: [SensitivityVariant]?
}

/// `ComputedScenario.json`, written by the LUNAVI science pipeline (and served at `/api/v1/scenario`).
/// Schema 1 has no `geometry`; schema 2 adds it for shadow analysis. Both decode.
struct ComputedScenarioFile: Codable, Sendable {
    var schemaVersion: Int?
    var mission: MissionDefaults
    var basemap: BasemapManifest
    var sites: [LunarSite]
    var metadata: DatasetMetadata
    var visibility: [SiteVisibility]
    var sensitivity: [SensitivityVariant]?
    var geometry: [ShadowGeometry]?
}
