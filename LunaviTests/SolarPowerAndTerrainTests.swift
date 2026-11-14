import Foundation
import Testing
@testable import Lunavi

/// A minimal consistent geometry: 4 horizon rays at `horizonDeg`, constant Sun track.
private func geometry(horizonDeg: Double = 0, sunAzimuth: Double = 90, sunElevation: Double = 1.5,
                      sunRadius: Double = 0.2666, count: Int = 25, step: Double = 3600,
                      complete: Bool = true, start: String = "2026-11-20T00:00:00Z",
                      radiusTrack: [Double]? = nil) -> ShadowGeometry {
    let track = ShadowGeometry.Track(azimuthDeg: Array(repeating: sunAzimuth, count: count),
                                     elevationDeg: Array(repeating: sunElevation, count: count),
                                     angularRadiusDeg: radiusTrack ?? Array(repeating: sunRadius, count: count))
    let earth = ShadowGeometry.Track(azimuthDeg: Array(repeating: 0, count: count), elevationDeg: Array(repeating: 5, count: count),
                                     angularRadiusDeg: Array(repeating: 0.95, count: count))
    return ShadowGeometry(siteID: "test-site", observerHeightMeters: 2, surfaceHeightMeters: 0, sunMinimumDiscFraction: 0.5,
                          minimumClearanceDeg: 0,
                          horizon: .init(azimuthStepDeg: 90, maxDistanceMeters: 150_000, elevationsDeg: Array(repeating: horizonDeg, count: 4),
                                         complete: Array(repeating: complete, count: 4)),
                          samples: .init(start: TestTime.utc(start), stepSeconds: step, count: count, sun: track, earth: earth))
}

@Suite("Experimental solar power estimate")
struct SolarPowerTests {
    let window = range("2026-11-20T00:00:00Z", "2026-11-21T00:00:00Z")
    let config = SolarPanelConfiguration(areaSquareMeters: 2, efficiency: 0.25, orientation: .sunTracking)

    @Test("Zero illumination: Sun below the terrain gives 0 W, not unknown")
    func zeroIllumination() {
        let e = SolarPowerEstimator.estimate(window: window, geometry: geometry(horizonDeg: 3), configuration: config)
        #expect(e.status == .complete)
        #expect(e.energyWh == 0)
        #expect(e.peakPowerW == 0)
        #expect(e.illuminatedFractionOfKnownTime == 0)
    }

    @Test("Full illumination: S × A × η with the irradiance from the Sun's distance")
    func fullIllumination() throws {
        let e = SolarPowerEstimator.estimate(window: window, geometry: geometry(horizonDeg: -5), configuration: config)
        let s = SolarPowerEstimator.irradiance(angularRadiusDeg: 0.2666).value
        #expect(e.status == .complete)
        #expect(abs(try #require(e.peakPowerW) - s * 2 * 0.25) < 1e-9)
        #expect(abs(try #require(e.energyWh) - s * 2 * 0.25 * 24) < 1e-6)
        #expect(e.illuminatedFractionOfKnownTime == 1)
    }

    @Test("Half the solar disc behind the terrain halves the power (terrain factor ≠ incidence)")
    func halfDisc() throws {
        let e = SolarPowerEstimator.estimate(window: window, geometry: geometry(horizonDeg: 1.5, sunElevation: 1.5), configuration: config)
        let s = SolarPowerEstimator.irradiance(angularRadiusDeg: 0.2666).value
        #expect(abs(try #require(e.peakPowerW) - s * 0.5 * 0.5) < 1e-9)
        #expect(e.samples.allSatisfy { $0.incidenceFactor == 1 })
    }

    @Test("Grazing incidence: horizontal panel ≈ sin(elevation); vertical panel facing the Sun ≈ cos(elevation)")
    func grazingIncidence() {
        let flat = SolarPowerEstimator.incidenceFactor(.fixed(tiltDeg: 0, azimuthDeg: 0), sunAzimuthDeg: 90, sunElevationDeg: 1.5)
        #expect(abs(flat - sin(1.5 * .pi / 180)) < 1e-12)
        let facing = SolarPowerEstimator.incidenceFactor(.fixed(tiltDeg: 90, azimuthDeg: 90), sunAzimuthDeg: 90, sunElevationDeg: 1.5)
        #expect(abs(facing - cos(1.5 * .pi / 180)) < 1e-12)
        let behind = SolarPowerEstimator.incidenceFactor(.fixed(tiltDeg: 90, azimuthDeg: 270), sunAzimuthDeg: 90, sunElevationDeg: 1.5)
        #expect(behind == 0)
        let edgeOn = SolarPowerEstimator.incidenceFactor(.fixed(tiltDeg: 90, azimuthDeg: 0), sunAzimuthDeg: 90, sunElevationDeg: 0)
        #expect(abs(edgeOn) < 1e-12)
    }

    @Test("Invalid panel inputs are rejected without calculating")
    func invalidInputs() {
        for bad in [SolarPanelConfiguration(areaSquareMeters: 0, efficiency: 0.3),
                    SolarPanelConfiguration(areaSquareMeters: 1, efficiency: 1.5),
                    SolarPanelConfiguration(areaSquareMeters: .nan, efficiency: 0.3),
                    SolarPanelConfiguration(areaSquareMeters: 1, efficiency: 0.3, orientation: .fixed(tiltDeg: 120, azimuthDeg: 0))] {
            let e = SolarPowerEstimator.estimate(window: window, geometry: geometry(), configuration: bad)
            guard case .invalidInputs(let errors) = e.status else {
                Issue.record("Expected invalid inputs for \(bad)")
                continue
            }
            #expect(!errors.isEmpty)
            #expect(e.energyWh == nil && e.samples.isEmpty)
        }
    }

    @Test("Missing geometry: unavailable, or incomplete when part of the window lacks samples or horizon")
    func missingGeometry() {
        guard case .unavailable = SolarPowerEstimator.estimate(window: window, geometry: nil, configuration: config).status else {
            Issue.record("No geometry must be unavailable")
            return
        }
        let incomplete = SolarPowerEstimator.estimate(window: window, geometry: geometry(complete: false), configuration: config)
        guard case .unavailable = incomplete.status else {
            Issue.record("An incomplete horizon must be unavailable")
            return
        }
        // Samples stop after 12 h: the rest of the window is unknown, not assumed sunlit.
        let half = SolarPowerEstimator.estimate(window: window, geometry: geometry(horizonDeg: -5, count: 13), configuration: config)
        #expect(half.status == .partial)
        #expect(half.knownDuration == 12 * 3600)
        #expect(half.unknownDuration == 12 * 3600)
        let s = SolarPowerEstimator.irradiance(angularRadiusDeg: 0.2666).value
        #expect(abs((half.energyWh ?? 0) - s * 0.5 * 12) < 1e-6)
    }

    @Test("Irradiance follows the Sun's distance (inverse square) and falls back to 1361 W/m² when unusable")
    func variableIrradiance() {
        let oneAU = asin(SolarPowerEstimator.sunRadiusKm / SolarPowerEstimator.astronomicalUnitKm) * 180 / .pi
        #expect(abs(SolarPowerEstimator.irradiance(angularRadiusDeg: oneAU).value - 1361) < 1e-6)
        let closer = SolarPowerEstimator.irradiance(angularRadiusDeg: oneAU * 1.02)
        #expect(closer.source == .sunDistance)
        #expect(abs(closer.value / 1361 - 1.02 * 1.02) < 1e-3)
        #expect(SolarPowerEstimator.irradiance(angularRadiusDeg: 0).source == .referenceSolarConstant)
        // A varying radius track changes power sample by sample.
        let radii = (0..<25).map { oneAU * (1 + 0.001 * Double($0)) }
        let e = SolarPowerEstimator.estimate(window: window, geometry: geometry(horizonDeg: -5, radiusTrack: radii), configuration: config)
        let powers = e.samples.compactMap(\.powerW)
        #expect(zip(powers, powers.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("Time integration: trapezoid over a linear ramp is exact, including off-grid window edges")
    func timeIntegration() throws {
        // Elevation ramps so the disc fraction is constant (fully visible) while incidence on a flat panel rises.
        let count = 25
        let elevations = (0..<count).map { 10.0 + Double($0) }
        let track = ShadowGeometry.Track(azimuthDeg: Array(repeating: 0, count: count), elevationDeg: elevations,
                                         angularRadiusDeg: Array(repeating: 0.2666, count: count))
        var g = geometry(horizonDeg: -5)
        g.samples.sun = track
        let flat = SolarPanelConfiguration(areaSquareMeters: 1, efficiency: 1, orientation: .fixed(tiltDeg: 0, azimuthDeg: 0))
        let offGrid = range("2026-11-20T00:30:00Z", "2026-11-20T03:30:00Z")
        let e = SolarPowerEstimator.estimate(window: offGrid, geometry: g, configuration: flat)
        #expect(e.samples.map(\.time) == [TestTime.utc("2026-11-20T00:30:00Z"), TestTime.utc("2026-11-20T01:00:00Z"),
                                          TestTime.utc("2026-11-20T02:00:00Z"), TestTime.utc("2026-11-20T03:00:00Z"),
                                          TestTime.utc("2026-11-20T03:30:00Z")])
        // Reference: same trapezoid computed directly from the sample powers.
        let p = e.samples.compactMap(\.powerW)
        let t = e.samples.map { $0.time.timeIntervalSince1970 }
        let reference = (0..<(p.count - 1)).reduce(0.0) { $0 + 0.5 * (p[$1] + p[$1 + 1]) * (t[$1 + 1] - t[$1]) } / 3600
        #expect(abs(try #require(e.energyWh) - reference) < 1e-9)
        #expect(e.knownDuration == 3 * 3600)
    }

    @Test("Matches an independent Python computation on real DE421 Sun geometry")
    func matchesPythonReference() throws {
        let scenario = try DatasetRepository.scenario(fromComputedJSON: SyntheticPipelineFixture.data, resourceName: "fixture")
        let g = try #require(scenario.geometry["synthetic-a"])
        let window = UTCRange(start: TestTime.utc("2026-11-20T06:00:00Z"), duration: 24 * 3600)
        let tracking = SolarPowerEstimator.estimate(window: window, geometry: g, configuration: config)
        #expect(tracking.status == .complete)
        #expect(abs(try #require(tracking.energyWh) - 16_676.327_495) / 16_676.327_495 < 1e-6)
        #expect(abs(try #require(tracking.peakPowerW) - 695.015_806_557) < 1e-4)
        let vertical = SolarPowerEstimator.estimate(window: window, geometry: g, configuration:
            SolarPanelConfiguration(areaSquareMeters: 2, efficiency: 0.25, orientation: .fixed(tiltDeg: 90, azimuthDeg: 0)))
        #expect(abs(try #require(vertical.energyWh) - 13_713.616_422) / 13_713.616_422 < 1e-6)
        let offGrid = SolarPowerEstimator.estimate(window: UTCRange(start: TestTime.utc("2026-11-20T06:10:00Z"), duration: 12 * 3600),
                                                   geometry: g, configuration: SolarPanelConfiguration(areaSquareMeters: 1, efficiency: 0.3))
        #expect(abs(try #require(offGrid.energyWh) - 5_003.379_115) / 5_003.379_115 < 1e-6)
    }
}

@Suite("Terrain characteristics")
struct TerrainTests {
    @Test("Schema-3 pipeline output decodes, validates and keeps the exported values")
    func decodesPipelineOutput() throws {
        let scenario = try DatasetRepository.scenario(fromComputedJSON: SyntheticPipelineFixture.data, resourceName: "fixture")
        #expect(scenario.terrain.count == 2)
        let a = try #require(scenario.terrain["synthetic-a"])
        #expect(a.available && a.isPhysicallyValid)
        #expect(a.slopeDeg == 1.745)
        #expect(a.roughnessM == 0.247)
        #expect(a.radiusM == 1000 && a.resolutionM == 200 && a.sampleCount == 79)
        #expect(a.limitations?.first?.contains("not a landing safety") == true)
        #expect(scenario.declaredPeriod?.stepSeconds == 1800)
        #expect(scenario.declaredPeriod?.sampleCount == 625)
        #expect(scenario.geometry.count == 2)
    }

    @Test("Invalid terrain values are dropped; unavailable entries keep their reason")
    func invalidDropped() {
        let sites = [LunarSite(id: "s", name: "S", shortName: "S", kind: .computed, regionLabel: "", mapPosition: nil, coordinate: nil,
                               hasTerrainData: true, terrainDataNote: "", sourceNote: "")]
        var bad = TerrainCharacteristics(siteID: "s", available: true, radiusM: 25, elevationM: 10, slopeDeg: 95, roughnessM: 0.1,
                                         resolutionM: 5, sampleCount: 81)
        #expect(DatasetRepository.terrainIndex([bad], sites: sites).isEmpty)
        bad.slopeDeg = 12
        bad.roughnessM = -1
        #expect(DatasetRepository.terrainIndex([bad], sites: sites).isEmpty)
        let missing = TerrainCharacteristics(siteID: "s", available: false, radiusM: 25, reason: "No DEM layer has data at this site.")
        #expect(DatasetRepository.terrainIndex([missing], sites: sites)["s"]?.reason == "No DEM layer has data at this site.")
        let unknownSite = TerrainCharacteristics(siteID: "elsewhere", available: false, radiusM: 25, reason: "x")
        #expect(DatasetRepository.terrainIndex([unknownSite], sites: sites).isEmpty)
    }

    @Test("Display text never classifies safety and keeps unknowns explicit")
    func displayText() {
        let t = TerrainCharacteristics(siteID: "s", available: true, radiusM: 25, elevationM: 1234.5, slopeDeg: 7.25,
                                       slopeUncertaintyDeg: 0.4, roughnessM: 0.31, resolutionM: 5, sampleCount: 81)
        #expect(LunarTerrainAnalysis.slopeText(t) == "7.3° ± 0.4° (fit)" || LunarTerrainAnalysis.slopeText(t) == "7.2° ± 0.4° (fit)")
        #expect(LunarTerrainAnalysis.metersText(nil) == "Not available")
        #expect(LunarTerrainAnalysis.scopeText(t) == "Within 25 m of the site · 5 m/pixel · 81 DEM samples")
        #expect(!LunarTerrainAnalysis.disclaimer.lowercased().contains("safe to land"))
    }

    @Test("The simulated fixture has no terrain values")
    @MainActor
    func simulatedHasNone() throws {
        let store = try makeDemoStore()
        #expect(store.terrain(for: "demo-point-a") == nil)
    }
}
