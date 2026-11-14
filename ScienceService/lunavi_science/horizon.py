"""Terrain horizon masks from a lunar DEM, with lunar curvature.

For each azimuth a ray is marched along the great circle from the observer. A terrain point at
angular distance theta and radius r = R + h appears at elevation

    atan2(r cos(theta) - r0, r sin(theta))

from an observer at radius r0 = R + h0 + observer_height. The horizon is the maximum over the ray.
Near field is sampled every few metres, the far field geometrically out to `max_distance_m`
(curvature drop is ~2.9 km at 100 km and ~6.5 km at 150 km, comparable to south-pole relief).

Rays use the same local east/north basis as ephemeris.enu_basis, so terrain azimuths and
Sun/Earth azimuths share one convention (clockwise from local north), including at the pole.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import numpy as np

from .dem import LUNAR_RADIUS_M
from .ephemeris import enu_basis, site_vector_km


@dataclass
class HorizonMask:
    azimuths_deg: np.ndarray
    elevations_deg: np.ndarray
    complete: np.ndarray  # True where the ray stayed inside DEM coverage to max distance
    surface_height_m: float
    observer_height_m: float
    max_distance_m: float

    def at(self, azimuth_deg) -> np.ndarray:
        az = np.mod(np.asarray(azimuth_deg, dtype=float), 360.0)
        grid = np.concatenate([self.azimuths_deg, [self.azimuths_deg[0] + 360.0]])
        values = np.concatenate([self.elevations_deg, [self.elevations_deg[0]]])
        return np.interp(az, grid, values)

    def is_complete(self, azimuth_deg) -> np.ndarray:
        az = np.mod(np.asarray(azimuth_deg, dtype=float), 360.0)
        step = self.azimuths_deg[1] - self.azimuths_deg[0]
        lower = (np.floor(az / step).astype(int)) % len(self.azimuths_deg)
        upper = (lower + 1) % len(self.azimuths_deg)
        return self.complete[lower] & self.complete[upper]


def ray_points(lat_deg: float, lon_deg: float, azimuths_deg: np.ndarray, theta: np.ndarray):
    """Lat/lon (deg) of points at angular distances `theta` along each azimuth. Shapes (A, D)."""
    east, north, up = enu_basis(site_vector_km(lat_deg, lon_deg, 1.0))
    az = np.radians(np.asarray(azimuths_deg, dtype=float))[:, None, None]
    th = np.asarray(theta, dtype=float)[None, :, None]
    direction = np.cos(az) * north + np.sin(az) * east          # (A, 1, 3)
    points = np.cos(th) * up + np.sin(th) * direction           # (A, D, 3)
    lat = np.degrees(np.arcsin(np.clip(points[..., 2], -1.0, 1.0)))
    lon = np.degrees(np.arctan2(points[..., 1], points[..., 0]))
    return lat, lon


def ray_distances(near_step_m: float, max_distance_m: float, far_samples: int = 1500) -> np.ndarray:
    near_limit = min(2_000.0, max_distance_m)
    near = np.arange(near_step_m, near_limit, near_step_m)
    far = np.geomspace(near_limit, max_distance_m, far_samples) if max_distance_m > near_limit else np.array([])
    return np.unique(np.concatenate([near, far]))


def compute_horizon(sampler, lat_deg: float, lon_deg: float, observer_height_m: float,
                    azimuth_step_deg: float = 0.5, max_distance_m: float = 150_000.0, near_step_m: float = 10.0,
                    radius_m: float = LUNAR_RADIUS_M, surface_height_m: Optional[float] = None) -> HorizonMask:
    if surface_height_m is None:
        surface_height_m = float(sampler.sample_latlon(np.array([lat_deg]), np.array([lon_deg]))[0])
        if np.isnan(surface_height_m):
            raise ValueError(f"Observer {lat_deg:.4f}, {lon_deg:.4f} is outside DEM coverage")
    r0 = radius_m + surface_height_m + observer_height_m

    azimuths = np.arange(0.0, 360.0, azimuth_step_deg)
    distances = ray_distances(near_step_m, max_distance_m)
    theta = distances / radius_m
    lat, lon = ray_points(lat_deg, lon_deg, azimuths, theta)
    heights = sampler.sample_latlon(lat.ravel(), lon.ravel()).reshape(lat.shape)

    th = theta[None, :]
    r = radius_m + heights
    elevation = np.degrees(np.arctan2(r * np.cos(th) - r0, r * np.sin(th)))
    valid = ~np.isnan(heights)
    elevation = np.where(valid, elevation, -90.0)
    return HorizonMask(azimuths, elevation.max(axis=1), valid.all(axis=1), surface_height_m, observer_height_m, max_distance_m)
