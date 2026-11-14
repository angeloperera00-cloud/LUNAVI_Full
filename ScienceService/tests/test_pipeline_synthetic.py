"""End-to-end build on a synthetic DEM (real DE421 geometry, invented terrain).

The terrain and site coordinates here are synthetic test inputs, not lunar data. The test checks that
the pipeline runs, that its output matches the app's schema, and that physical relations hold.
"""
from __future__ import annotations

import json
import math

import numpy as np
import pytest

from conftest import kernel_paths
from lunavi_science import intervals as iv
from lunavi_science.dem import SPHERICAL_SOUTH_POLAR_STEREO, polar_stereographic_xy
from lunavi_science.ephemeris import EARTH_RADIUS_KM
from lunavi_science.scenario import build, find_demo_case, settings_from_config
from lunavi_science.schema import validate_scenario
from lunavi_science.timeutil import parse_utc

SITES = [
    {"id": "synthetic-a", "name": "Synthetic Site A", "latitude": -89.85, "longitude": 10.0},
    {"id": "synthetic-b", "name": "Synthetic Site B", "latitude": -89.75, "longitude": 120.0},
]


def synthetic_heights(x, y):
    massif = 2_500.0 * np.exp(-(((x - 30_000.0) ** 2 + (y + 20_000.0) ** 2) / (2 * 8_000.0 ** 2)))
    ridge = 1_200.0 * np.exp(-((x + 0.5 * y + 45_000.0) ** 2) / (2 * 6_000.0 ** 2))
    return 300.0 * np.sin(x / 9_000.0) * np.cos(y / 11_000.0) + massif + ridge


@pytest.fixture(scope="module")
def built(tmp_path_factory, spice):
    import rasterio
    from rasterio.crs import CRS
    from rasterio.transform import from_origin

    work = tmp_path_factory.mktemp("pipeline")
    cell, half = 200.0, 180_000.0
    n = int(2 * half / cell)
    xs = -half + (np.arange(n) + 0.5) * cell
    ys = half - (np.arange(n) + 0.5) * cell
    gx, gy = np.meshgrid(xs, ys)
    with rasterio.open(work / "synthetic_dem.tif", "w", driver="GTiff", height=n, width=n, count=1, dtype="float32",
                       crs=CRS.from_proj4(SPHERICAL_SOUTH_POLAR_STEREO), transform=from_origin(-half, half, cell, cell),
                       nodata=-9999.0) as dst:
        dst.write(synthetic_heights(gx, gy).astype("float32"), 1)

    config = {
        "missionName": "Synthetic pipeline test",
        "ephemerisLabel": "NAIF DE421 + MOON_ME (test)",
        "kernels": kernel_paths(),
        "dem": {"layers": [{"name": "synthetic DEM", "path": str(work / "synthetic_dem.tif"), "boundsPaddingM": 170_000}]},
        "basemap": {"sizePx": 256, "marginM": 8_000},
        "period": {"start": "2026-11-17T00:00:00Z", "end": "2026-11-30T00:00:00Z", "stepSeconds": 1800},
        "model": {"observerHeightM": 2.0, "azimuthStepDeg": 1.0, "nearStepM": 50.0, "maxDistanceM": 150_000,
                  "sensitivityObserverHeightsM": [10.0], "sensitivityClearancesDeg": [0.5]},
        "mission": {"durationHours": 24, "delayHours": 6, "durationOptions": [6, 12, 24, 48]},
        "sites": [dict(site, coordinateSource="synthetic test input") for site in SITES],
    }
    (work / "config.json").write_text(json.dumps(config))
    scenario = build(str(work / "config.json"), str(work / "out"), spice=spice)
    return work, config, scenario


def ranges(entries):
    return [(parse_utc(r["start"]), parse_utc(r["end"])) for r in entries]


def total_hours(entries):
    return sum((b - a).total_seconds() for a, b in ranges(entries)) / 3600


def test_output_matches_the_app_schema(built):
    work, _, scenario = built
    assert validate_scenario(scenario) == []
    on_disk = json.loads((work / "out" / "ComputedScenario.json").read_text())
    assert on_disk["metadata"]["source"] == "computedBundled"
    assert {v["level"] for v in on_disk["metadata"]["validation"]} == {"notValidated"}
    assert all(site["kind"] == "computed" and site["coordinate"]["source"] for site in on_disk["sites"])


def test_coverage_is_complete_inside_the_dem(built):
    _, config, scenario = built
    period = (parse_utc(config["period"]["start"]), parse_utc(config["period"]["end"]))
    for entry in scenario["visibility"]:
        assert ranges(entry["coverage"]) == [period]
        for key in ("sunlight", "earthLineOfSight"):
            for a, b in ranges(entry[key]):
                assert period[0] <= a < b <= period[1]


def test_terrain_only_removes_visibility_compared_with_a_flat_moon(built, spice):
    """Earth can only be visible when its disc is above the flat-horizon geometry (plus dip), never more."""
    from lunavi_science.ephemeris import site_vector_km, target_azel, angular_radius_deg
    from lunavi_science.timeutil import utc_to_et

    _, _, scenario = built
    for entry, site in zip(scenario["visibility"], SITES):
        for a, b in ranges(entry["earthLineOfSight"]):
            mid = a + (b - a) / 2
            _, el, dist = target_azel(spice, "EARTH", [utc_to_et(mid, spice)], site_vector_km(site["latitude"], site["longitude"], 1737.4))
            dip = math.degrees(math.acos(1737.4 / (1737.4 + 4.0)))  # generous: < 4 km of local relief
            assert el[0] + angular_radius_deg(EARTH_RADIUS_KM, dist)[0] > -dip


def test_events_sit_on_the_horizon(built, spice):
    """At a bisected transition the Sun's centre (50 % criterion) or Earth's limb (any-part criterion) is on the horizon."""
    from lunavi_science.ephemeris import angular_radius_deg, site_vector_km, target_azel
    from lunavi_science.timeutil import utc_to_et

    _, _, scenario = built
    count = 0
    for entry, site in zip(scenario["visibility"], SITES):
        position = site_vector_km(site["latitude"], site["longitude"], 1737.4)
        for event in entry["events"]:
            count += 1
            clearance = event["geometry"]["clearanceDeg"]
            if event["condition"] == "sunlight":
                assert abs(clearance) < 0.05, event
            else:
                _, _, dist = target_azel(spice, "EARTH", [utc_to_et(parse_utc(event["time"]), spice)], position)
                assert abs(clearance + angular_radius_deg(EARTH_RADIUS_KM, dist)[0]) < 0.05, event
            assert event["summary"].startswith("Computed:")
    assert count, "the synthetic massif should create at least one transition"


def test_sensitivity_variants_move_in_the_physical_direction(built):
    _, _, scenario = built
    variants = {v["label"]: v for v in scenario["sensitivity"]}
    assert set(variants) == {"Baseline", "Observer height 10 m", "Minimum clearance 0.5°"}
    base = variants["Baseline"]
    for key in ("sunlight", "earthLineOfSight"):
        assert total_hours(variants["Observer height 10 m"][key]) >= total_hours(base[key]) - 0.02
        assert total_hours(variants["Minimum clearance 0.5°"][key]) <= total_hours(base[key]) + 0.02


def test_default_plan_follows_the_app_rules(built):
    _, config, scenario = built
    mission = scenario["mission"]
    data = {v["siteID"]: iv.site_data_from_json(v, parse_utc) for v in scenario["visibility"]}
    if any("chosen automatically" in a for a in scenario["metadata"]["assumptions"]):
        start = parse_utc(mission["start"])
        site = mission["siteID"]
        assert iv.evaluate(data[site], site, start, mission["durationHours"]).overall == "met"
        delayed = start + (parse_utc("2026-01-01T06:00:00Z") - parse_utc("2026-01-01T00:00:00Z"))
        assert iv.evaluate(data[site], site, delayed, mission["durationHours"]).overall == "notMet"
        order = iv.proximity_order(scenario["sites"], site, data)
        assert iv.recovery_candidates(data, order, site, delayed, mission["durationHours"])
    else:
        assert any("No delay-failure case" in a for a in scenario["metadata"]["assumptions"])
    assert settings_from_config(config).delay_h == mission["delayHours"] == 6


def test_basemap_is_georeferenced(built):
    work, _, scenario = built
    basemap = scenario["basemap"]
    assert (work / "out" / f"{basemap['imageResource']}.jpg").exists()
    assert basemap["isIllustrative"] is False and basemap["metersPerPixel"] > 0
    for site, entry in zip(SITES, scenario["sites"]):
        u, v = entry["mapPosition"]["x"], entry["mapPosition"]["y"]
        assert 0 < u < 1 and 0 < v < 1
    # Pin positions agree with the projection: the vector between sites matches in metres.
    (xa, ya), (xb, yb) = (polar_stereographic_xy(s["latitude"], s["longitude"]) for s in SITES)
    pa, pb = scenario["sites"][0]["mapPosition"], scenario["sites"][1]["mapPosition"]
    side = basemap["metersPerPixel"] * basemap["pixelWidth"]
    assert abs((pb["x"] - pa["x"]) * side - (xb - xa)) < 5.0
    assert abs(-(pb["y"] - pa["y"]) * side - (yb - ya)) < 5.0


def test_missing_coordinates_are_refused(tmp_path, spice):
    config = {"kernels": [], "dem": {"layers": []}, "period": {"start": "2026-11-17T00:00:00Z", "end": "2026-11-18T00:00:00Z"},
              "sites": [{"id": "x", "name": "X", "latitude": None, "longitude": 10.0, "coordinateSource": None}]}
    (tmp_path / "c.json").write_text(json.dumps(config))
    with pytest.raises(ValueError, match="citable source"):
        build(str(tmp_path / "c.json"), str(tmp_path / "out"), spice=spice)


def test_find_demo_case_returns_none_without_a_failure():
    assert find_demo_case([], settings_from_config({"period": {"start": "2026-11-17T00:00:00Z", "end": "2026-11-18T00:00:00Z"}})) is None


def test_find_demo_case_on_the_app_fixture_intervals(fixture_scenario):
    """With the fixture's intervals as input, the search picks the first whole hour where +6 h fails and a rescue exists."""
    from lunavi_science.horizon import HorizonMask
    from lunavi_science.scenario import SiteComputation

    computations = []
    for entry in fixture_scenario["visibility"]:
        data = iv.site_data_from_json(entry, parse_utc)
        site = {"id": data.site_id, "latitude": -89.5, "longitude": 0.0 if data.site_id == "demo-point-a" else 5.0}
        computations.append(SiteComputation(site, HorizonMask(np.zeros(1), np.zeros(1), np.ones(1, bool), 0, 2, 0),
                                            data.coverage, data.sunlight, data.earth, data.events))
    settings = settings_from_config({"period": {"start": "2026-11-19T00:00:00Z", "end": "2026-11-28T00:00:00Z"}})
    assert find_demo_case(computations, settings) == ("demo-point-a", parse_utc("2026-11-20T03:00:00Z"))
