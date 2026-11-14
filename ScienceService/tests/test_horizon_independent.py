"""Independent (all-cells) horizon vs the analytic sphere and vs the ray-marching horizon.py."""
from __future__ import annotations

import math

import numpy as np
import pytest

from lunavi_science.dem import SPHERICAL_SOUTH_POLAR_STEREO, DemLayer, DemSampler, LUNAR_RADIUS_M
from lunavi_science.horizon import compute_horizon
from lunavi_science.horizon_independent import compare, compute, fair_min_distance_m


def geotiff(path, fn, cell=200.0, half=170_000.0):
    import rasterio
    from rasterio.crs import CRS
    from rasterio.transform import from_origin

    n = int(2 * half / cell)
    xs = -half + (np.arange(n) + 0.5) * cell
    ys = half - (np.arange(n) + 0.5) * cell
    gx, gy = np.meshgrid(xs, ys)
    with rasterio.open(path, "w", driver="GTiff", height=n, width=n, count=1, dtype="float32",
                       crs=CRS.from_proj4(SPHERICAL_SOUTH_POLAR_STEREO), transform=from_origin(-half, half, cell, cell),
                       nodata=-9999.0) as dst:
        dst.write(fn(gx, gy).astype("float32"), 1)
    return DemLayer(str(path))


def test_smooth_sphere_gives_the_geometric_dip(tmp_path):
    layer = geotiff(tmp_path / "flat.tif", lambda x, y: np.zeros_like(x))
    ind = compute([layer], -89.9, 30.0, surface_height_m=0.0, observer_height_m=1000.0, azimuth_step_deg=2.0,
                  max_distance_m=120_000.0)
    dip = math.degrees(math.acos(LUNAR_RADIUS_M / (LUNAR_RADIUS_M + 1000.0)))
    assert np.nanmax(np.abs(ind.elevations_deg + dip)) < 0.01
    assert (ind.cell_counts > 0).all()


def test_agrees_with_ray_marching_on_rough_terrain(tmp_path):
    def heights(x, y):
        massif = 2_500.0 * np.exp(-(((x - 30_000.0) ** 2 + (y + 20_000.0) ** 2) / (2 * 8_000.0 ** 2)))
        ridge = 1_200.0 * np.exp(-((x + 0.5 * y + 45_000.0) ** 2) / (2 * 6_000.0 ** 2))
        return 300.0 * np.sin(x / 9_000.0) * np.cos(y / 11_000.0) + massif + ridge

    layer = geotiff(tmp_path / "rough.tif", heights)
    lat, lon = -89.85, 10.0
    d0 = fair_min_distance_m(200.0, 1.0)  # ≈ 22.9 km for the 200 m test grid
    ray = compute_horizon(DemSampler([layer]), lat, lon, observer_height_m=2.0, azimuth_step_deg=1.0,
                          max_distance_m=150_000.0, near_step_m=50.0, min_distance_m=d0)
    ind = compute([layer], lat, lon, ray.surface_height_m, 2.0, azimuth_step_deg=1.0, max_distance_m=150_000.0,
                  min_distance_m=d0)
    stats = compare(ray, ind)
    assert stats["rays"] == 360
    # Same terrain, different algorithm, where the comparison is fair (1° rays on a coarse 200 m grid):
    # measured p95 0.075°, max 0.099°. The ray horizon is never meaningfully above the cell maximum.
    assert stats["p95AbsDiffDeg"] < 0.1
    assert stats["maxAbsDiffDeg"] < 0.15
    assert stats["rayAboveIndependentBy>0.05deg"] == 0


def test_layer_priority_uses_the_first_layer_where_it_has_data(tmp_path):
    high = geotiff(tmp_path / "far.tif", lambda x, y: np.full_like(x, 5_000.0), cell=400.0)
    near = geotiff(tmp_path / "near.tif", lambda x, y: np.zeros_like(x), cell=200.0, half=170_000.0)
    # The near layer covers everything, so the 5 km "far" layer must be ignored entirely.
    ind = compute([near, high], -89.9, 30.0, 0.0, 1000.0, azimuth_step_deg=5.0, max_distance_m=100_000.0)
    assert np.nanmax(ind.elevations_deg) < 0
