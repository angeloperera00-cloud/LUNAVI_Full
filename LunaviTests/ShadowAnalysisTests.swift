import Foundation
import Testing
@testable import Lunavi

/// Synthetic geometry for tests only (not lunar data): a 1° horizon everywhere except a 3° wall
/// between azimuths 90° and 100°, and a Sun moving 1° of azimuth per hour at 1.5° elevation.
private func syntheticGeometry(
    siteID: String = "test-site",
    wall: Range<Int> = 90..<100,
    wallHeight: Double = 3,
    incomplete: Range<Int> = 200..<210,
    start: String = "2026-11-20T00:00:00Z",
    hours: Int = 13,
    sunAzimuthStart: Double = 80
) -> ShadowGeometry {
    let elevations = (0..<360).map { wall.contains($0) ? wallHeight : 1.0 }
    let complete = (0..<360).map { !incomplete.contains($0) }
    let sunAzimuths = (0..<hours).map { ShadowAnalysisService.normalized(sunAzimuthStart + Double($0)) }
    var earthAzimuths = Array(repeating: 1.0, count: hours)
    earthAzimuths[0] = 359.5
    earthAzimuths[1] = 0.5
    return ShadowGeometry(
        siteID: siteID,
        observerHeightMeters: 2,
        surfaceHeightMeters: 0,
        sunMinimumDiscFraction: 0.5,
        minimumClearanceDeg: 0,
        horizon: .init(azimuthStepDeg: 1, maxDistanceMeters: 150_000, elevationsDeg: elevations, complete: complete),
        samples: .init(
            start: TestTime.utc(start),
            stepSeconds: 3600,
            count: hours,
            sun: .init(azimuthDeg: sunAzimuths, elevationDeg: Array(repeating: 1.5, count: hours), angularRadiusDeg: Array(repeating: 0.27, count: hours)),
            earth: .init(azimuthDeg: earthAzimuths, elevationDeg: Array(repeating: 2.0, count: hours), angularRadiusDeg: Array(repeating: 0.95, count: hours))
        )
    )
}

/// Intervals matching the synthetic geometry: sunlight ends when the Sun reaches the wall (~09:52).
private let syntheticVisibility = siteData(
    coverage: [range("2026-11-20T00:00:00Z", "2026-11-20T12:00:00Z")],
    sunlight: [range("2026-11-20T00:00:00Z", "2026-11-20T09:52:00Z")],
    earth: [range("2026-11-20T00:00:00Z", "2026-11-20T12:00:00Z")]
)

@Suite("Lunar shadow analysis")
struct ShadowAnalysisTests {
    @Test("Sun is blocked once less than the required half of its disc clears the terrain")
    func discThreshold() {
        #expect(abs(ShadowAnalysisService.discFraction(elevation: 1.0, horizon: 1.0, radius: 0.27) - 0.5) < 1e-12)
        #expect(ShadowAnalysisService.discFraction(elevation: 0.99, horizon: 1.0, radius: 0.27) < 0.5)
        #expect(ShadowAnalysisService.discVisibility(fraction: ShadowAnalysisService.discFraction(elevation: 1.30, horizon: 1, radius: 0.27)) == .fullyVisible)
        #expect(ShadowAnalysisService.discVisibility(fraction: ShadowAnalysisService.discFraction(elevation: 1.10, horizon: 1, radius: 0.27)) == .partiallyVisible)
        #expect(ShadowAnalysisService.discVisibility(fraction: ShadowAnalysisService.discFraction(elevation: 0.70, horizon: 1, radius: 0.27)) == .obstructed)
        // Minimum clearance raises the effective horizon.
        #expect(ShadowAnalysisService.discFraction(elevation: 1.2, horizon: 1, radius: 0.27, clearance: 0.5) < 0.5)
    }

    @Test("Visibility changes as the Sun crosses the terrain horizon")
    func crossing() throws {
        let geometry = syntheticGeometry()
        let before = ShadowAnalysisService.reading(.sunlight, at: TestTime.utc("2026-11-20T09:00:00Z"), geometry: geometry, visibility: syntheticVisibility)
        let after = ShadowAnalysisService.reading(.sunlight, at: TestTime.utc("2026-11-20T11:00:00Z"), geometry: geometry, visibility: syntheticVisibility)
        #expect(before.disc == .fullyVisible)
        #expect(abs(try #require(before.clearanceDeg) - 0.5) < 1e-9)
        #expect(before.requirementState == .visible)
        #expect(after.disc == .obstructed)
        #expect(abs(try #require(after.clearanceDeg) + 1.5) < 1e-9)
        #expect(after.requirementState == .obstructed)
        #expect(after.isAboveIdealHorizon == true)          // terrain obstruction, not sunset
    }

    @Test("Unknown data is never treated as visible")
    func unknownIsNotSuccess() {
        let geometry = syntheticGeometry()
        let outside = ShadowAnalysisService.reading(.sunlight, at: TestTime.utc("2026-11-20T12:30:00Z"), geometry: geometry, visibility: syntheticVisibility)
        #expect(outside.direction == nil)
        #expect(outside.disc == nil)
        #expect(outside.requirementState == .unknown)
        #expect(outside.unavailableReason != nil)

        let noGeometry = ShadowAnalysisService.reading(.sunlight, at: TestTime.utc("2026-11-20T06:00:00Z"), geometry: nil, visibility: nil)
        #expect(noGeometry.requirementState == .unknown)
        #expect(noGeometry.hasGeometry == false)

        // The Sun pointing into a sector with no terrain data has no terrain verdict.
        let blind = syntheticGeometry(sunAzimuthStart: 195)
        let reading = ShadowAnalysisService.reading(.sunlight, at: TestTime.utc("2026-11-20T08:00:00Z"), geometry: blind, visibility: syntheticVisibility)
        #expect(reading.direction != nil)
        #expect(reading.terrainHorizonDeg == nil)
        #expect(reading.disc == nil)
    }

    @Test("Directions are interpolated only between samples, never extrapolated")
    func noExtrapolation() throws {
        let geometry = syntheticGeometry()
        #expect(ShadowAnalysisService.direction(geometry, condition: .sunlight, at: TestTime.utc("2026-11-19T23:59:00Z")) == nil)
        #expect(ShadowAnalysisService.direction(geometry, condition: .sunlight, at: TestTime.utc("2026-11-20T12:00:00Z")) != nil)
        #expect(ShadowAnalysisService.direction(geometry, condition: .sunlight, at: TestTime.utc("2026-11-20T12:01:00Z")) == nil)
        let half = try #require(ShadowAnalysisService.direction(geometry, condition: .sunlight, at: TestTime.utc("2026-11-20T00:30:00Z")))
        #expect(abs(half.azimuthDeg - 80.5) < 1e-9)
    }

    @Test("Azimuth wraparound in the horizon, the target track and the 360° chart")
    func wraparound() throws {
        var geometry = syntheticGeometry()
        geometry.horizon.elevationsDeg[359] = 2
        geometry.horizon.elevationsDeg[0] = 4
        #expect(abs(try #require(ShadowAnalysisService.horizonElevation(geometry, at: 359.5)) - 3) < 1e-9)
        #expect(abs(try #require(ShadowAnalysisService.horizonElevation(geometry, at: -0.5)) - 3) < 1e-9)

        // Earth moves 359.5° -> 0.5°: the halfway point is 0°, not 180°.
        let earth = try #require(ShadowAnalysisService.direction(geometry, condition: .earthLineOfSight, at: TestTime.utc("2026-11-20T00:30:00Z")))
        #expect(earth.azimuthDeg < 1e-9 || abs(earth.azimuthDeg - 360) < 1e-9)

        // Chart window centred on 0°: 359° plots at −1°, 1° at +1°; the profile is closed and sorted.
        #expect(abs(ShadowAnalysisService.chartX(for: 359, centeredOn: 0) + 1) < 1e-9)
        #expect(abs(ShadowAnalysisService.chartX(for: 1, centeredOn: 0) - 1) < 1e-9)
        #expect(abs(ShadowAnalysisService.chartX(for: 90, centeredOn: 180) - 90) < 1e-9)
        let points = ShadowAnalysisService.chartPoints(geometry, centeredOn: 0)
        #expect(points.count == 361)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.x < $1.x })
        let first = try #require(points.first)
        let last = try #require(points.last)
        #expect(abs(last.x - first.x - 360) < 1e-9)
        #expect(last.elevationDeg == first.elevationDeg)
    }

    @Test("Changing site or time changes the readings consistently")
    func siteAndTimeConsistency() throws {
        let siteA = syntheticGeometry(siteID: "a")
        let siteB = syntheticGeometry(siteID: "b", wall: 140..<150)       // no wall in the Sun's path
        let time = TestTime.utc("2026-11-20T11:00:00Z")
        let a = ShadowAnalysisService.reading(.sunlight, at: time, geometry: siteA, visibility: nil)
        let b = ShadowAnalysisService.reading(.sunlight, at: time, geometry: siteB, visibility: nil)
        #expect(a.disc == .obstructed)
        #expect(b.disc == .fullyVisible)
        #expect(a.direction == b.direction)                               // same Sun, different terrain

        for hour in [1, 5, 9, 10, 11] {
            let date = TestTime.utc("2026-11-20T00:00:00Z").addingTimeInterval(Double(hour) * 3600)
            let reading = ShadowAnalysisService.reading(.sunlight, at: date, geometry: siteA, visibility: nil)
            let direction = try #require(ShadowAnalysisService.direction(siteA, condition: .sunlight, at: date))
            #expect(reading.direction == direction)
            #expect(reading.terrainHorizonDeg == ShadowAnalysisService.horizonElevation(siteA, at: direction.azimuthDeg))
        }
    }

    @Test("Minimum clearance over a window uses every sample inside it")
    func minimumClearance() throws {
        let geometry = syntheticGeometry()
        let clear = try #require(ShadowAnalysisService.minimumClearance(.sunlight, over: range("2026-11-20T00:00:00Z", "2026-11-20T06:00:00Z"), geometry: geometry))
        #expect(abs(clear - 0.5) < 1e-9)
        let blocked = try #require(ShadowAnalysisService.minimumClearance(.sunlight, over: range("2026-11-20T06:00:00Z", "2026-11-20T12:00:00Z"), geometry: geometry))
        #expect(abs(blocked + 1.5) < 1e-9)
        #expect(ShadowAnalysisService.minimumClearance(.sunlight, over: range("2026-11-20T06:00:00Z", "2026-11-21T06:00:00Z"), geometry: geometry) == nil)
    }

    @Test("Inconsistent or unknown-site geometry is dropped on load")
    func repositoryFiltersGeometry() throws {
        let sites = try DatasetRepository().loadDemoScenario().sites
        var broken = syntheticGeometry(siteID: "demo-point-a")
        broken.samples.count = 99                                         // arrays no longer match
        let index = DatasetRepository.geometryIndex(
            [syntheticGeometry(siteID: "ridge-site-b"), broken, syntheticGeometry(siteID: "nowhere")],
            sites: sites
        )
        #expect(Set(index.keys) == ["ridge-site-b"])
    }
}

@Suite("Shadow analysis inside Mission Rescue")
@MainActor
struct ShadowRescueIntegrationTests {
    @Test("Mission Rescue still finds both options when geometry is attached")
    func rescueStillWorks() throws {
        var scenario = try DatasetRepository().loadDemoScenario()
        scenario.geometry = ["demo-point-a": syntheticGeometry(siteID: "demo-point-a")]
        let store = MissionStore()
        store.install(scenario)
        #expect(store.shadowGeometry(for: "demo-point-a") != nil)
        #expect(store.shadowGeometry(for: "ridge-site-b") == nil)
        store.simulateDelay()
        store.findRecoveryOptions()
        #expect(store.candidates.map(\.kind) == [.sameSiteLaterTime, .alternativeSite])
        #expect(store.candidates.allSatisfy { $0.evaluation.overall == .met })
    }

    @Test("The simulated demo has no geometry, so readings are unavailable, not invented")
    func simulatedHasNoGeometry() throws {
        let store = try makeDemoStore()
        store.simulateDelay()
        let failure = try #require(store.delayedEvaluation?.firstFailure)
        let reading = ShadowAnalysisService.reading(failure.condition, at: failure.time,
                                                    geometry: store.shadowGeometry(for: "demo-point-a"),
                                                    visibility: store.visibility(for: "demo-point-a"))
        #expect(reading.requirementState == .obstructed)                  // from the intervals
        #expect(reading.direction == nil)
        #expect(reading.unavailableReason != nil)
    }

    @Test("Obstruction episode: begins at the failure; its end is unknown across a data gap")
    func episodeAcrossGap() throws {
        let store = try makeDemoStore()
        let episode = try #require(ShadowAnalysisService.obstructionEpisode(
            .sunlight, at: TestTime.utc("2026-11-21T08:00:00Z"), visibility: store.visibility(for: "demo-point-a")))
        #expect(episode.start == TestTime.utc("2026-11-21T08:00:00Z"))
        #expect(episode.end == nil)        // 22 Nov 06:00 – 24 Nov 00:00 has no data, so no return time is claimed

        let contiguous = try #require(ShadowAnalysisService.obstructionEpisode(
            .sunlight, at: TestTime.utc("2026-11-20T10:30:00Z"), visibility: syntheticVisibility))
        #expect(contiguous.start == TestTime.utc("2026-11-20T09:52:00Z"))
        #expect(contiguous.end == nil)     // sunlight does not return before coverage ends
    }
}
