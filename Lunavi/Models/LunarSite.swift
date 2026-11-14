import Foundation

/// A position on the bundled basemap image, normalised to 0...1 (x to the right, y downwards).
struct MapPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

/// Selenographic coordinate in the MOON_ME frame, degrees (east longitude), with its source.
struct GeographicCoordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var source: String

    var displayString: String {
        let lat = abs(latitude).formatted(.number.precision(.fractionLength(3)))
        // Normalise to (-180, 180] and show the hemisphere instead of a signed east longitude.
        var east = longitude.truncatingRemainder(dividingBy: 360)
        if east > 180 { east -= 360 }
        if east <= -180 { east += 360 }
        let lon = abs(east).formatted(.number.precision(.fractionLength(3)))
        return "\(lat)° \(latitude < 0 ? "S" : "N"), \(lon)° \(east < 0 ? "W" : "E")"
    }
}

enum SiteKind: String, Codable, Sendable {
    /// Illustrative demo site positioned on the illustrative map. Not a lunar coordinate.
    case illustrativeDemo
    /// A site named in a published catalogue. Listed for reference; no bundled analysis.
    case publishedCatalog
    /// A site analysed by the LUNAVI science pipeline from NASA data.
    case computed
}

struct LunarSite: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var shortName: String
    var kind: SiteKind
    var regionLabel: String
    var mapPosition: MapPoint?
    var coordinate: GeographicCoordinate?
    var hasTerrainData: Bool
    var terrainDataNote: String
    var sourceNote: String

    var kindDescription: String {
        switch kind {
        case .illustrativeDemo:
            return "Illustrative demo site"
        case .publishedCatalog:
            return "Published site — catalogue entry only"
        case .computed:
            return "Computed site"
        }
    }

    var positionDescription: String {
        if let coordinate {
            return coordinate.displayString
        }
        if let mapPosition {
            let x = mapPosition.x.formatted(.number.precision(.fractionLength(2)))
            let y = mapPosition.y.formatted(.number.precision(.fractionLength(2)))
            return "Map position x \(x), y \(y) (illustrative, not a lunar coordinate)"
        }
        return "Coordinates not bundled"
    }
}
