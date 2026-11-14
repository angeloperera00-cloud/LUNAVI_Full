"""Period validation against the real NAIF kernels and the DEM, before anything is computed."""
from __future__ import annotations

import json

import numpy as np
import pytest

from conftest import kernel_paths
from lunavi_science.coverage import check_kernel_coverage, check_terrain
from lunavi_science.dem import DemSampler, FunctionLayer
from lunavi_science.scenario import apply_period_override, build
from lunavi_science.timeutil import parse_utc, time_grid


def test_supported_period_passes(spice):
    report = check_kernel_coverage(spice, kernel_paths(), parse_utc("2026-11-17T00:00:00Z"), parse_utc("2026-12-01T00:00:00Z"))
    assert report.ok, report.errors
    kinds = {k.kind for k in report.kernels}
    assert {"SPK", "binary PCK"} <= kinds
    spk = next(k for k in report.kernels if k.kind == "SPK")
    assert set(spk.spans) == {"Sun", "Earth-Moon barycentre", "Earth", "Moon"}
    assert report.to_json()["ok"] is True


def test_period_beyond_lunar_orientation_kernel_is_refused(spice):
    # moon_pa_de421_1900-2050.bpc ends in 2050; de421.bsp itself runs to 2053.
    report = check_kernel_coverage(spice, kernel_paths(), parse_utc("2051-01-01T00:00:00Z"), parse_utc("2051-01-15T00:00:00Z"))
    assert not report.ok
    assert any("moon_pa_de421" in e for e in report.errors)
    assert not any("de421.bsp" in e for e in report.errors)


def test_period_partly_outside_coverage_is_refused(spice):
    # Starts inside, ends outside: no false success at the boundary.
    report = check_kernel_coverage(spice, kernel_paths(), parse_utc("2050-12-20T00:00:00Z"), parse_utc("2051-01-10T00:00:00Z"))
    assert not report.ok


def test_dates_before_every_kernel_are_refused(spice):
    report = check_kernel_coverage(spice, kernel_paths(), parse_utc("1890-01-01T00:00:00Z"), parse_utc("1890-01-02T00:00:00Z"))
    assert not report.ok
    # With a leapseconds kernel the SPK and PCK spans are reported; without one, the UTC conversion itself is refused.
    assert any("de421.bsp" in e or "ephemeris time" in e for e in report.errors)


def test_reversed_period_is_refused(spice):
    report = check_kernel_coverage(spice, kernel_paths(), parse_utc("2026-12-02T00:00:00Z"), parse_utc("2026-12-01T00:00:00Z"))
    assert not report.ok


def test_missing_astronomical_data_is_refused(spice):
    without_spk = [p for p in kernel_paths() if not p.endswith(".bsp")]
    report = check_kernel_coverage(spice, without_spk, parse_utc("2026-11-17T00:00:00Z"), parse_utc("2026-11-18T00:00:00Z"))
    assert any("No planetary SPK" in e for e in report.errors)
    without_pck = [p for p in kernel_paths() if not p.endswith(".bpc")]
    report = check_kernel_coverage(spice, without_pck, parse_utc("2026-11-17T00:00:00Z"), parse_utc("2026-11-18T00:00:00Z"))
    assert any("binary PCK" in e for e in report.errors)


def test_missing_terrain_is_reported():
    inside = FunctionLayer(lambda x, y: np.where(np.hypot(x, y) < 50_000, 100.0, np.nan))
    sampler = DemSampler([inside])
    sites = [{"id": "near-pole", "latitude": -89.9, "longitude": 0.0},
             {"id": "far-away", "latitude": -80.0, "longitude": 0.0}]
    errors = check_terrain(sampler, sites)
    assert len(errors) == 1 and "far-away" in errors[0]


def test_period_override_is_parsed_and_validated():
    cfg = {"period": {"start": "2026-11-17T00:00:00Z", "end": "2026-12-01T00:00:00Z", "stepSeconds": 600}}
    out = apply_period_override(cfg, "2026-12-01T00:00:00+00:00", "2026-12-15T00:00:00Z", 300)
    assert out["period"] == {"start": "2026-12-01T00:00:00Z", "end": "2026-12-15T00:00:00Z", "stepSeconds": 300.0}
    assert cfg["period"]["start"] == "2026-11-17T00:00:00Z"  # the original config is not modified
    with pytest.raises(ValueError):
        apply_period_override(cfg, "not a date")
    with pytest.raises(ValueError):
        apply_period_override(cfg, step_seconds=0)


def test_build_refuses_unsupported_period_before_computing(spice, tmp_path):
    config = {
        "kernels": kernel_paths(),
        "dem": {"layers": [{"name": "never read", "path": str(tmp_path / "missing.tif")}]},
        "period": {"start": "2051-01-01T00:00:00Z", "end": "2051-01-02T00:00:00Z", "stepSeconds": 600},
        "sites": [{"id": "s", "name": "S", "latitude": -89.9, "longitude": 0.0, "coordinateSource": "test"}],
    }
    path = tmp_path / "config.json"
    path.write_text(json.dumps(config))
    with pytest.raises(ValueError, match="not supported by the loaded SPICE kernels"):
        build(str(path), str(tmp_path / "out"), spice=spice)
    assert not (tmp_path / "out").exists()


def test_output_name_must_keep_the_discovery_prefix(tmp_path):
    with pytest.raises(ValueError, match="ComputedScenario"):
        build(str(tmp_path / "unused.json"), str(tmp_path), spice=object(), output_name="December")


def test_sample_count_matches_the_grid():
    start, end = parse_utc("2026-12-01T00:00:00Z"), parse_utc("2026-12-02T00:00:00Z")
    grid = time_grid(start, end, 600)
    assert len(grid) == 145 and grid[0] == start and grid[-1] == end
    uneven = time_grid(start, parse_utc("2026-12-01T00:25:00Z"), 600)
    assert uneven[-1] == parse_utc("2026-12-01T00:20:00Z")  # the grid never runs past the requested end
