import Foundation

/// Terrain characteristics at one site, computed by the science pipeline from the LOLA DEM
/// (scenario schema 3, `terrain[]`). The app only displays these values; it never derives them from
/// imagery. When `available` is false, `reason` says why and no number is shown.
struct TerrainCharacteristics: Codable, Hashable, Sendable {
    var siteID: String
    var available: Bool
    var radiusM: Double
    var latitude: Double?
    var longitude: Double?
    /// Height above the 1737.4 km reference sphere at the site (bilinear DEM value).
    var elevationM: Double?
    /// Slope of the least-squares plane over the analysis disc, per ground metre.
    var slopeDeg: Double?
    /// Statistical plane-fit standard error only (excludes DEM error).
    var slopeUncertaintyDeg: Double?
    /// RMS of the residuals from that plane.
    var roughnessM: Double?
    /// Highest minus lowest DEM sample in the disc.
    var reliefM: Double?
    var resolutionM: Double?
    var sampleCount: Int?
    var validFraction: Double?
    var source: String?
    var method: String?
    var reason: String?
    var limitations: [String]?

    /// Values are only shown when they are physically meaningful and complete.
    var isPhysicallyValid: Bool {
        guard radiusM > 0 else { return false }
        guard available else { return reason != nil }
        guard let slopeDeg, let roughnessM, let elevationM, let resolutionM, let sampleCount else { return false }
        return slopeDeg.isFinite && (0...90).contains(slopeDeg)
            && roughnessM.isFinite && roughnessM >= 0
            && elevationM.isFinite
            && resolutionM > 0 && resolutionM <= radiusM
            && sampleCount >= 9
            && (slopeUncertaintyDeg.map { $0.isFinite && $0 >= 0 } ?? true)
    }
}

/// Display helpers. No classification into safe/unsafe: that needs a spacecraft-specific hazard model.
enum LunarTerrainAnalysis {
    private static let locale = Locale(identifier: "en_US_POSIX")
    static let disclaimer = "Terrain characterization only — not a landing safety certification."

    static func slopeText(_ terrain: TerrainCharacteristics) -> String {
        guard let slope = terrain.slopeDeg else { return "Not available" }
        let value = slope.formatted(.number.precision(.fractionLength(1)).locale(locale))
        if let uncertainty = terrain.slopeUncertaintyDeg {
            return "\(value)° ± \(uncertainty.formatted(.number.precision(.fractionLength(1)).locale(locale)))° (fit)"
        }
        return "\(value)°"
    }

    static func metersText(_ value: Double?, digits: Int = 1) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength(digits)).locale(locale))) m" } ?? "Not available"
    }

    static func scopeText(_ terrain: TerrainCharacteristics) -> String {
        let radius = terrain.radiusM.formatted(.number.precision(.fractionLength(0)).locale(locale))
        let resolution = terrain.resolutionM.map { "\($0.formatted(.number.precision(.fractionLength(0)).locale(locale))) m/pixel" } ?? "unknown resolution"
        let samples = terrain.sampleCount.map { "\($0) DEM samples" } ?? "samples not stated"
        return "Within \(radius) m of the site · \(resolution) · \(samples)"
    }
}
