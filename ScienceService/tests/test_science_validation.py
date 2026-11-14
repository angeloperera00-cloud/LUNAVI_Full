"""validate-science on the synthetic pipeline (real DE421 geometry, synthetic terrain, synthetic PGDA stand-in)."""
from __future__ import annotations

import json

import numpy as np

from lunavi_science.dem import SPHERICAL_SOUTH_POLAR_STEREO
from lunavi_science.science_validation import format_markdown, load_context, pgda69_section, run_all
from test_pipeline_synthetic import built  # noqa: F401  (shared module-scoped fixture)


def _fake_pgda(path, value_percent):
    import rasterio
    from rasterio.crs import CRS
    from rasterio.transform import from_origin

    with rasterio.open(path, "w", driver="GTiff", height=400, width=400, count=1, dtype="int16",
                       crs=CRS.from_proj4(SPHERICAL_SOUTH_POLAR_STEREO), transform=from_origin(-12_000, 12_000, 60, 60)) as dst:
        dst.write(np.full((400, 400), value_percent, dtype="int16"), 1)


def test_full_suite_runs_and_is_consistent(built, spice, tmp_path):  # noqa: F811
    work, _, _ = built
    out = tmp_path / "results"
    result = run_all(str(work / "config.json"), str(work / "out" / "ComputedScenario.json"), str(out), spice=spice,
                     sections=["horizon", "cases", "decisions", "rescue"], use_network=False)
    assert (out / "validation_results.md").exists() and json.loads((out / "validation_results.json").read_text())

    for sid, e in result["horizon"]["sites"].items():
        assert e["exportedVsRecomputedMaxAbsDeg"] <= 1e-4          # the app's exported horizon is the pipeline's
        assert e["allLayersFarField"]["rayAboveIndependentBy>0.05deg"] == 0
        assert e["allLayersFarField"]["p95AbsDiffDeg"] < 0.2   # 2° wedges include peaks between rays

    for sid, e in result["cases"]["sites"].items():
        missing = e["cases"][-1]
        assert missing["stateStoredIntervals"] == "unknown"
        for c in e["cases"][:-1]:
            if "stateApp" in c and abs(c["clearanceAppDeg"]) > 0.3:   # away from the threshold, all three must agree
                assert c["stateApp"] == c["stateStoredIntervals"], c

    for key, e in result["decisions"]["scenarios"].items():
        assert e["statusAgrees"], (key, e)
        for d in e["firstObstructionDiffS (independent − app, 60 s grid)"].values():
            assert d is None or abs(d) <= 90  # app bisects to ±30 s; the check samples every 60 s

    rescue = result["rescue"]
    assert rescue["optionA_matchesBruteForce"] and rescue["optionB_isNearestQualifying"] and rescue["durationPreserved"]
    assert all(v == "met" for v in rescue["optionsReEvaluated"].values())
    assert "## 1. Terrain horizon" in format_markdown(result)


def test_pgda_comparison_reads_scaled_reference_and_averages(built, spice, tmp_path):  # noqa: F811
    work, _, _ = built
    sun, earth = tmp_path / "sun.tif", tmp_path / "earth.tif"
    _fake_pgda(sun, 37)
    _fake_pgda(earth, 55)
    ctx = load_context(str(work / "config.json"), str(work / "out" / "ComputedScenario.json"), spice)
    result = pgda69_section(spice, ctx, str(sun), str(earth), step_hours=24 * 7)
    e = result["sites"]["synthetic-a"]
    assert e["pgda69_sun"]["centre"] == 0.37 and e["pgda69_sun"]["interpretedAsPercent"]
    assert e["pgda69_earth"]["centre"] == 0.55
    lunavi = e["lunavi_h0m"]
    assert 0.0 <= lunavi["sun"]["meanDiscFraction"] <= 1.0
    assert lunavi["sun"]["fractionCentreAbove"] <= lunavi["sun"]["fractionAnyPartAbove"]
    assert lunavi["samples"] > 900


def test_sensitivity_identity_and_finer_sampling(built, spice):  # noqa: F811
    from lunavi_science.science_validation import sensitivity_section
    work, _, _ = built
    ctx = load_context(str(work / "config.json"), str(work / "out" / "ComputedScenario.json"), spice)
    result = sensitivity_section(spice, ctx, variants=[("identity", {"observer_height_m": ctx.settings.observer_height_m}),
                                                       ("sampling 900 s", {"step_s": 900.0})])
    identity = result["variants"]["identity"]
    assert identity["maxTransitionShiftMin"] == 0.0 and identity["statusChanges"] == {}
    assert result["variants"]["sampling 900 s"]["maxTransitionShiftMin"] <= 1.0  # bisection makes sampling nearly irrelevant


def test_disc_fraction_equals_numerically_integrated_area():
    """Section 5: the circular-segment formula is the visible AREA fraction of the disc."""
    from lunavi_science.visibility import disc_fraction_visible
    y = np.linspace(-1, 1, 400_001)
    width = 2 * np.sqrt(1 - y ** 2)
    for d in (-1.0, -0.7, -0.3, 0.0, 0.25, 0.6, 0.95, 1.0):
        # Centre at d radii above the horizon line: visible where y > -d.
        numeric = getattr(np, "trapezoid", getattr(np, "trapz", None))(np.where(y > -d, width, 0.0), y) / np.pi
        assert abs(float(disc_fraction_visible(d, 0.0, 1.0)) - numeric) < 1e-5, d
