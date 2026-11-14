"""Terrain characteristics on synthetic surfaces with known answers (not lunar data)."""
from __future__ import annotations

import math

import numpy as np
import pytest

from lunavi_science.dem import FunctionLayer, polar_stereographic_xy
from lunavi_science.terrain import characterize, scale_factor, site_terrain

LAT, LON = -89.5, 45.0


def layer(fn, resolution=5.0):
    return FunctionLayer(fn, resolution_m=resolution)


def test_flat_terrain():
    r = characterize(layer(lambda x, y: np.full_like(x, 1234.5)), LAT, LON, 25.0)
    assert r["available"]
    assert r["elevationM"] == pytest.approx(1234.5)
    assert r["slopeDeg"] == pytest.approx(0.0, abs=1e-6)
    assert r["roughnessM"] == pytest.approx(0.0, abs=1e-6)
    assert r["reliefM"] == pytest.approx(0.0, abs=1e-6)


@pytest.mark.parametrize("gx,gy", [(0.1, 0.0), (0.0, -0.25), (0.3, 0.4)])
def test_known_planar_slope(gx, gy):
    r = characterize(layer(lambda x, y: 100.0 + gx * x + gy * y), LAT, LON, 25.0)
    k = scale_factor(LAT, LON, None)
    expected = math.degrees(math.atan(math.hypot(gx, gy) * k))
    assert r["slopeDeg"] == pytest.approx(expected, abs=1e-3)
    assert r["roughnessM"] == pytest.approx(0.0, abs=1e-6)
    assert r["slopeUncertaintyDeg"] == pytest.approx(0.0, abs=1e-6)


def test_roughness_of_a_sinusoid_on_a_slope():
    amplitude, wavelength = 0.8, 10.0  # 2 samples per wavelength at 5 m, sampled at crests and troughs
    r = characterize(layer(lambda x, y: 0.05 * x + amplitude * np.cos(2 * np.pi * x / wavelength)), LAT, LON, 40.0)
    assert r["available"]
    assert 0.3 < r["roughnessM"] <= amplitude + 1e-6
    assert r["reliefM"] == pytest.approx(2 * amplitude + 0.05 * 80, rel=0.25)
    assert r["slopeUncertaintyDeg"] > 0


def test_missing_samples_make_the_result_unavailable():
    half = layer(lambda x, y: np.where(x > polar_stereographic_xy(LAT, LON)[0], 10.0, np.nan))
    r = characterize(half, LAT, LON, 25.0)
    assert r["available"] is False
    assert "have data" in r["reason"]


def test_coarse_layers_are_not_used():
    r = characterize(layer(lambda x, y: x * 0, resolution=80.0), LAT, LON, 25.0)
    assert r["available"] is False and "too coarse" in r["reason"]


def test_coordinate_transformation_samples_the_site():
    x0, y0 = polar_stereographic_xy(LAT, LON)
    r = characterize(layer(lambda x, y: 0.01 * (x - x0) + 0.02 * (y - y0) + 500.0), LAT, LON, 25.0)
    assert r["elevationM"] == pytest.approx(500.0, abs=1e-6)  # the site maps to (x0, y0)


def test_scale_factor_is_one_at_the_pole_and_tiny_nearby():
    assert scale_factor(-90.0, 0.0, None) == pytest.approx(1.0)
    assert scale_factor(-89.5, 0.0, None) - 1 == pytest.approx(1.9e-5, rel=0.05)


def test_site_terrain_uses_the_first_layer_with_data():
    coarse_everywhere = layer(lambda x, y: x * 0 + 7.0, resolution=80.0)
    fine_nowhere = layer(lambda x, y: x * np.nan)
    fine = layer(lambda x, y: x * 0 + 3.0)
    site = {"id": "s", "latitude": LAT, "longitude": LON}
    assert site_terrain([fine_nowhere, fine, coarse_everywhere], site)["elevationM"] == pytest.approx(3.0)
    missing = site_terrain([coarse_everywhere], site)
    assert missing["available"] is False and missing["siteID"] == "s"
    assert any("not a landing safety" in line for line in missing["limitations"])
