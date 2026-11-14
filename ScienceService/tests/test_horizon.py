"""Horizon masks on synthetic terrain with known answers."""
from __future__ import annotations

import math

import numpy as np

from lunavi_science.dem import (SPHERICAL_SOUTH_POLAR_STEREO, DemSampler, FunctionLayer, make_to_latlon, make_to_xy,
                                polar_stereographic_latlon, polar_stereographic_xy)
from lunavi_science.horizon import compute_horizon

R = 1_737_400.0


def flat(x, y):
    return np.zeros_like(x)


def test_flat_sphere_horizon_equals_geometric_dip():
    dip = math.degrees(math.acos(R / (R + 1000.0)))  # 1.944° for a 1 km observer height
    for lat, lon in [(-90.0, 0.0), (-89.5, 30.0), (-88.0, -100.0)]:
        mask = compute_horizon(DemSampler([FunctionLayer(flat)]), lat, lon, 1000.0, azimuth_step_deg=2.0)
        assert mask.complete.all()
        assert np.allclose(mask.elevations_deg, -dip, atol=0.01), (lat, lon, mask.elevations_deg.min(), mask.elevations_deg.max())


def test_ring_wall_matches_curvature_formula():
    def ring(x, y):
        rho = np.hypot(x, y)
        return np.where((rho > 20_000) & (rho < 21_000), 2_000.0, 0.0)

    mask = compute_horizon(DemSampler([FunctionLayer(ring)]), -90.0, 0.0, 2.0, azimuth_step_deg=5.0, near_step_m=10.0)
    theta = 20_000.0 / R
    r, r0 = R + 2_000.0, R + 2.0
    expected = math.degrees(math.atan2(r * math.cos(theta) - r0, r * math.sin(theta)))
    assert np.allclose(mask.elevations_deg, expected, atol=0.05)


def high_sector_centre(mask, margin_deg=0.5) -> float:
    """Circular mean azimuth of the sector within `margin_deg` of the highest horizon."""
    high = mask.azimuths_deg[mask.elevations_deg >= mask.elevations_deg.max() - margin_deg]
    angles = np.radians(high)
    return float(np.degrees(np.arctan2(np.sin(angles).mean(), np.cos(angles).mean())) % 360.0)


def test_azimuths_follow_the_ephemeris_convention_at_the_pole():
    # From the pole, azimuth 0 points to 0° longitude (+y on the map) and azimuth 90 to 90°E (+x).
    def east_wall(x, y):
        return np.where((x > 15_000) & (x < 16_000) & (np.abs(y) < 3_000), 3_000.0, 0.0)

    mask = compute_horizon(DemSampler([FunctionLayer(east_wall)]), -90.0, 0.0, 2.0, azimuth_step_deg=1.0)
    assert abs(high_sector_centre(mask) - 90.0) <= 1.0
    assert mask.at(270.0) < 0.0 < mask.at(90.0)


def test_off_pole_observer_sees_the_pole_due_south():
    def polar_massif(x, y):
        return np.where(np.hypot(x, y) < 3_000, 3_000.0, 0.0)

    mask = compute_horizon(DemSampler([FunctionLayer(polar_massif)]), -89.5, 0.0, 2.0, azimuth_step_deg=1.0)
    assert abs(high_sector_centre(mask) - 180.0) <= 1.0


def test_rays_leaving_the_dem_mark_the_sector_incomplete():
    def island(x, y):
        return np.where(np.hypot(x, y) < 100_000, 0.0, np.nan)

    mask = compute_horizon(DemSampler([FunctionLayer(island)]), -90.0, 0.0, 2.0, azimuth_step_deg=5.0, max_distance_m=150_000)
    assert not mask.complete.any()
    assert not mask.is_complete(np.array([0.0, 123.4])).any()


def test_layers_are_sampled_in_priority_order():
    near = FunctionLayer(lambda x, y: np.where(np.hypot(x, y) < 1_000, 5.0, np.nan), name="near")
    far = FunctionLayer(lambda x, y: np.full_like(x, 100.0), name="far")
    sampler = DemSampler([near, far])
    heights = sampler.sample_latlon(np.array([-90.0, -89.0]), np.array([0.0, 0.0]))
    assert heights.tolist() == [5.0, 100.0]


def test_spherical_formula_matches_proj():
    lat = np.array([-89.9, -88.5, -85.0, -80.5])
    lon = np.array([0.0, 45.0, -120.0, 179.0])
    x_formula, y_formula = polar_stereographic_xy(lat, lon)
    x_proj, y_proj = make_to_xy(SPHERICAL_SOUTH_POLAR_STEREO)(lat, lon)
    assert np.allclose(x_formula, x_proj, atol=1e-3) and np.allclose(y_formula, y_proj, atol=1e-3)
    lat_back, lon_back = make_to_latlon(SPHERICAL_SOUTH_POLAR_STEREO)(x_proj, y_proj)
    lat_f, lon_f = polar_stereographic_latlon(x_formula, y_formula)
    assert np.allclose(lat_back, lat, atol=1e-9) and np.allclose(lat_f, lat, atol=1e-9)
    assert np.allclose(np.mod(lon_back - lon + 180, 360) - 180, 0, atol=1e-9)
    assert np.allclose(np.mod(lon_f - lon + 180, 360) - 180, 0, atol=1e-9)
