import Foundation

/// The exported inputs of one site's visibility flags (scenario schema 2): the terrain horizon mask
/// and the sampled Sun and Earth directions. Written by the science pipeline for the same observer
/// (DEM surface + observer height) and in the same MOON_ME convention (azimuth clockwise from local
/// north, elevation above the local horizontal) as the visibility intervals.
///
/// The simulated fixture has no geometry; shadow analysis then shows Data Unavailable.
struct ShadowGeometry: Codable, Hashable, Sendable {
    struct Horizon: Codable, Hashable, Sendable {
        /// Spacing of the horizon rays; ray `i` points at azimuth `i * azimuthStepDeg`.
        var azimuthStepDeg: Double
        var maxDistanceMeters: Double
        var elevationsDeg: [Double]
        /// False where the ray left the DEM before `maxDistanceMeters`; the horizon there is unknown.
        var complete: [Bool]
    }

    struct Track: Codable, Hashable, Sendable {
        var azimuthDeg: [Double]
        var elevationDeg: [Double]
        var angularRadiusDeg: [Double]
    }

    struct Samples: Codable, Hashable, Sendable {
        var start: Date
        var stepSeconds: Double
        var count: Int
        var sun: Track
        var earth: Track
    }

    var siteID: String
    var observerHeightMeters: Double
    var surfaceHeightMeters: Double
    /// Sunlight requirement: at least this fraction of the solar disc above the horizon (0.5 = centre).
    var sunMinimumDiscFraction: Double
    var minimumClearanceDeg: Double
    var horizon: Horizon
    var samples: Samples

    func track(for condition: VisibilityCondition) -> Track {
        switch condition {
        case .sunlight:
            return samples.sun
        case .earthLineOfSight:
            return samples.earth
        }
    }

    /// First and last sample instants. Readings exist only inside this closed range.
    var firstSampleTime: Date { samples.start }
    var lastSampleTime: Date {
        samples.start.addingTimeInterval(Double(max(samples.count - 1, 0)) * samples.stepSeconds)
    }

    /// Array lengths agree with the declared counts. Inconsistent geometry is never read.
    var isConsistent: Bool {
        let rays = horizon.elevationsDeg.count
        guard horizon.azimuthStepDeg > 0, rays > 1, horizon.complete.count == rays,
              abs(Double(rays) * horizon.azimuthStepDeg - 360) < 1e-6,
              samples.stepSeconds > 0, samples.count > 0 else { return false }
        return [samples.sun, samples.earth].allSatisfy { track in
            track.azimuthDeg.count == samples.count
                && track.elevationDeg.count == samples.count
                && track.angularRadiusDeg.count == samples.count
        }
    }
}
