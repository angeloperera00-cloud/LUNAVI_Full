"""Shadow-analysis geometry: export consistency (real DE421 geometry, synthetic terrain) and reading rules."""
from __future__ import annotations

import datetime as dt

import pytest

from lunavi_science.schema import validate_scenario
from lunavi_science.shadow import closest_approach, disc_fraction, disc_state, horizon_at, interval_state, obstruction_example, reading, target_at
from lunavi_science.timeutil import UTC, parse_utc
from test_pipeline_synthetic import built  # noqa: F401  (module-scoped build fixture)


def t(day, hour, minute=0):
    return dt.datetime(2026, 11, day, hour, minute, tzinfo=UTC)


def handmade_scenario():
    """One site: flat 1° horizon except a 3° wall between azimuths 90° and 100°; Sun moves 1°/h in azimuth."""
    elevations = [3.0 if 90 <= i * 1.0 < 100 else 1.0 for i in range(360)]
    complete = [not (200 <= i < 210) for i in range(360)]           # one sector leaves the DEM
    hours = 13
    sun_az = [(80.0 + h) % 360 for h in range(hours)]                 # 80° .. 92° over 12 h
    geometry = {
        "siteID": "s", "observerHeightMeters": 2.0, "surfaceHeightMeters": 0.0,
        "sunMinimumDiscFraction": 0.5, "minimumClearanceDeg": 0.0,
        "horizon": {"azimuthStepDeg": 1.0, "maxDistanceMeters": 150000.0, "elevationsDeg": elevations, "complete": complete},
        "samples": {"start": "2026-11-20T00:00:00Z", "stepSeconds": 3600.0, "count": hours,
                    "sun": {"azimuthDeg": sun_az, "elevationDeg": [1.5] * hours, "angularRadiusDeg": [0.27] * hours},
                    "earth": {"azimuthDeg": [359.5, 0.5] + [1.0] * (hours - 2), "elevationDeg": [2.0] * hours,
                              "angularRadiusDeg": [0.95] * hours}},
    }
    visibility = {"siteID": "s", "coverage": [{"start": "2026-11-20T00:00:00Z", "end": "2026-11-20T12:00:00Z"}],
                  "sunlight": [{"start": "2026-11-20T00:00:00Z", "end": "2026-11-20T09:52:00Z"}],
                  "earthLineOfSight": [{"start": "2026-11-20T00:00:00Z", "end": "2026-11-20T12:00:00Z"}],
                  "events": [{"id": "e", "condition": "sunlight", "kind": "obstructionBegins", "time": "2026-11-20T09:52:00Z",
                              "summary": "test", "geometry": None}]}
    return {"geometry": [geometry], "visibility": [visibility]}


def test_disc_fraction_threshold_blocks_the_sun_below_half_the_disc():
    assert disc_fraction(1.0, 1.0, 0.27) == pytest.approx(0.5)
    assert disc_fraction(0.99, 1.0, 0.27) < 0.5            # centre just below the horizon: requirement fails
    assert disc_state(disc_fraction(1.30, 1.0, 0.27)) == "fullyVisible"
    assert disc_state(disc_fraction(1.10, 1.0, 0.27)) == "partiallyVisible"
    assert disc_state(disc_fraction(0.70, 1.0, 0.27)) == "obstructed"


def test_sun_crossing_the_wall_changes_state():
    scenario = handmade_scenario()
    before = reading(scenario, "s", "sunlight", t(20, 9))     # az 89°: horizon 1°, Sun 1.5° -> visible
    after = reading(scenario, "s", "sunlight", t(20, 11))     # az 91°: wall 3° -> obstructed
    assert before["discState"] == "fullyVisible" and before["clearanceDeg"] == pytest.approx(0.5)
    assert after["discState"] == "obstructed" and after["clearanceDeg"] == pytest.approx(-1.5)
    assert before["requirementState"] == "visible" and after["requirementState"] == "obstructed"


def test_unknown_is_never_success():
    scenario = handmade_scenario()
    outside = reading(scenario, "s", "sunlight", t(20, 12, 30))  # after the last sample and outside coverage
    assert outside["available"] is False and outside["requirementState"] == "unknown"
    assert interval_state(scenario["visibility"][0], "sunlight", t(21, 0)) == "unknown"


def test_incomplete_horizon_sector_is_unavailable():
    geometry = handmade_scenario()["geometry"][0]
    assert horizon_at(geometry, 205.0) is None
    assert horizon_at(geometry, 199.0) is None        # neighbour ray 200° is incomplete
    assert horizon_at(geometry, 198.5) == pytest.approx(1.0)


def test_azimuth_wraparound():
    geometry = handmade_scenario()["geometry"][0]
    geometry["horizon"]["elevationsDeg"][359] = 2.0
    geometry["horizon"]["elevationsDeg"][0] = 4.0
    assert horizon_at(geometry, 359.5) == pytest.approx(3.0)
    assert horizon_at(geometry, -0.5) == pytest.approx(3.0)
    earth = target_at(geometry, "earthLineOfSight", t(20, 0, 30))  # 359.5° -> 0.5° the short way
    assert earth["azimuthDeg"] == pytest.approx(0.0, abs=1e-9) or earth["azimuthDeg"] == pytest.approx(360.0)


def test_interpolation_stays_inside_the_samples():
    geometry = handmade_scenario()["geometry"][0]
    assert target_at(geometry, "sunlight", t(19, 23, 59)) is None
    assert target_at(geometry, "sunlight", t(20, 12)) is not None       # last sample exactly
    assert target_at(geometry, "sunlight", t(20, 12, 1)) is None
    assert target_at(geometry, "sunlight", t(20, 0, 30))["azimuthDeg"] == pytest.approx(80.5)


def test_obstruction_example():
    example = obstruction_example(handmade_scenario())
    assert example["siteID"] == "s" and example["event"]["time"] == "2026-11-20T09:52:00Z"
    states = [r["requirementState"] for r in example["readings"]]
    assert states == ["visible", "visible", "obstructed", "obstructed"]


def test_exported_geometry_is_schema_valid_and_reproduces_the_intervals(built):
    """Recomputing the flags from the exported geometry at every sample time matches the bisected
    intervals, except at samples adjacent to a transition (±1 step, where bisection moved the edge)."""
    _, _, scenario = built
    assert validate_scenario(scenario) == []
    assert {g["siteID"] for g in scenario["geometry"]} == {v["siteID"] for v in scenario["visibility"]}
    for g in scenario["geometry"]:
        samples = g["samples"]
        start, step = parse_utc(samples["start"]), dt.timedelta(seconds=samples["stepSeconds"])
        visibility = next(v for v in scenario["visibility"] if v["siteID"] == g["siteID"])
        for condition in ("sunlight", "earthLineOfSight"):
            edges = [parse_utc(r[k]) for r in visibility[condition] for k in ("start", "end")]
            mismatches = 0
            for i in range(samples["count"]):
                moment = start + i * step
                r = reading(scenario, g["siteID"], condition, moment)
                if r.get("discFraction") is None:
                    continue
                threshold = g["sunMinimumDiscFraction"] if condition == "sunlight" else 1e-12
                geometric = r["discFraction"] >= threshold if condition == "sunlight" else r["discFraction"] > threshold
                if geometric != (r["requirementState"] == "visible"):
                    assert any(abs((moment - e).total_seconds()) <= samples["stepSeconds"] for e in edges), (g["siteID"], condition, moment)
                    mismatches += 1
            assert mismatches <= len(edges)


def test_closest_approach_reports_the_lowest_clearance():
    scenario = handmade_scenario()
    [best] = closest_approach(scenario)
    assert best["clearanceDeg"] == pytest.approx(-1.5)   # Sun behind the 3° wall


def test_example_uses_an_ending_obstruction_when_none_begins():
    scenario = handmade_scenario()
    scenario["visibility"][0]["events"][0]["kind"] = "visibilityReturns"
    assert obstruction_example(scenario)["event"]["kind"] == "visibilityReturns"
