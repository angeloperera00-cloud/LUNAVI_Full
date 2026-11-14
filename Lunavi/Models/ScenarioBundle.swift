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
    /// Terrain characteristics by site (schema 3). Empty for the simulated fixture and older files.
    var terrain: [String: TerrainCharacteristics] = [:]
    /// Declared computation period (pipeline `period`), when the file has one.
    var declaredPeriod: ScenarioPeriod? = nil

    func site(id: String) -> LunarSite? {
        sites.first { $0.id == id }
    }

    func siteName(_ id: String) -> String {
        site(id: id)?.name ?? id
    }

    /// Earliest coverage start to latest coverage end over every site: the only span in which the
    /// app evaluates plans. Gaps inside it stay Unknown. `nil` when no site has data.
    var coverageHull: UTCRange? {
        let all = visibility.values.flatMap(\.coverage)
        guard let start = all.map(\.start).min(), let end = all.map(\.end).max(), end > start else { return nil }
        return UTCRange(start: start, end: end)
    }

    /// Mission start times the editor accepts: inside the coverage hull, at least one minute before it ends.
    var allowedStartRange: ClosedRange<Date>? {
        guard let hull = coverageHull else { return nil }
        let last = hull.end.addingTimeInterval(-60)
        return last > hull.start ? hull.start...last : nil
    }
}

/// The computation period and sampling declared by the science pipeline.
struct ScenarioPeriod: Codable, Hashable, Sendable {
    var start: Date
    var end: Date
    /// Sample spacing in seconds (pipeline schema 3+).
    var stepSeconds: Double?
    var sampleCount: Int?

    var range: UTCRange { UTCRange(start: start, end: end) }
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
    /// Computation period (written by every pipeline build; optional so older files still decode).
    var period: ScenarioPeriod?
    /// Terrain characteristics per site (schema 3). Absent in older files.
    var terrain: [TerrainCharacteristics]?
}
