"""Sun and Earth directions from a lunar surface site with NAIF SPICE.

Frame: MOON_ME (mean Earth / polar axis), the frame of the LOLA PGDA DEMs.
Use either the DE421 lunar set (moon_pa_de421_1900-2050.bpc + moon_080317.tf + moon_assoc_me.tf)
or the DE440 set (moon_pa_de440_200625.bpc + the current moon_de440_*.tf, whose MOON_ME is the
DE421-compatible MOON_ME_DE440_ME421). Record the choice in the scenario metadata.

Local frame: "up" is the radial direction of a spherical Moon (R = 1737.4 km), matching the
spherical-curvature horizon model in horizon.py. Azimuth is measured clockwise from local north.
Aberration correction 'LT+S' is applied at the Moon's centre; moving the observer to the surface
changes directions by far less than an arcsecond.
"""
from __future__ import annotations

import math
from typing import Iterable, Sequence

import numpy as np

MOON_RADIUS_KM = 1737.4
SUN_RADIUS_KM = 695_700.0
EARTH_RADIUS_KM = 6_371.0  # mean radius; Earth counts as visible if any part of its disc is above the horizon


def load_kernels(spice, paths: Iterable[str]) -> list[str]:
    loaded = []
    for path in paths:
        spice.furnsh(str(path))
        loaded.append(str(path))
    return loaded


def site_vector_km(lat_deg: float, lon_deg: float, radius_km: float) -> np.ndarray:
    lat, lon = math.radians(lat_deg), math.radians(lon_deg)
    return radius_km * np.array([math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat)])


def enu_basis(site: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    up = site / np.linalg.norm(site)
    east = np.cross(np.array([0.0, 0.0, 1.0]), up)
    if np.linalg.norm(east) < 1e-12:  # exactly at a pole: pick a deterministic east
        east = np.array([0.0, 1.0, 0.0])
    east /= np.linalg.norm(east)
    north = np.cross(up, east)
    return east, north, up


def target_azel(spice, target: str, ets: Sequence[float], site: np.ndarray, frame: str = "MOON_ME", abcorr: str = "LT+S"):
    """Returns (azimuth_deg, elevation_deg, distance_km) arrays for `target` seen from `site`."""
    positions, _ = spice.spkpos(target, list(ets), frame, abcorr, "MOON")
    positions = np.atleast_2d(np.asarray(positions, dtype=float))
    vectors = positions - site
    east, north, up = enu_basis(site)
    distance = np.linalg.norm(vectors, axis=1)
    elevation = np.degrees(np.arcsin(np.clip(vectors @ up / distance, -1.0, 1.0)))
    azimuth = np.degrees(np.arctan2(vectors @ east, vectors @ north)) % 360.0
    return azimuth, elevation, distance


def angular_radius_deg(physical_radius_km: float, distance_km):
    return np.degrees(np.arcsin(physical_radius_km / np.asarray(distance_km)))


def sub_point_latitude_deg(spice, target: str, et: float, frame: str = "MOON_ME") -> float:
    """Selenographic latitude of the sub-target point (spherical); at the south pole elevation = -this."""
    position, _ = spice.spkpos(target, et, frame, "LT+S", "MOON")
    position = np.asarray(position, dtype=float)
    return math.degrees(math.asin(position[2] / np.linalg.norm(position)))
