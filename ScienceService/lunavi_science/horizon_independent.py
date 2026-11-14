"""An independent terrain-horizon implementation, for cross-checking `horizon.py`.

`horizon.py` marches rays: it samples the DEM bilinearly at points along each azimuth line and takes
the highest elevation angle. This module does not march rays. It takes **every DEM cell** within the
search radius, places the cell centre on the sphere in 3-D (radius R + height), computes the exact
vector from the observer, and converts it to azimuth/elevation in the local east-north-up frame.
The horizon in the wedge A ± step/2 is the highest cell centre in it.

A wedge is only a fair reference where it is at least ~2 cells wide, i.e. beyond
D0 = 2·cell / step(rad) (≈ 570 m for 5 m cells at 0.5°). Closer in, a narrow wedge contains few or no
cell centres while a ray's bilinear samples draw on cells beside it. The comparison is therefore made
on terrain beyond D0 (both methods restricted to it), and the share of rays whose full horizon is set
closer than D0 is reported separately.

Different algorithm, same input data and conventions (DEM layers in priority order, R = 1737.4 km,
observer = surface + height, azimuth clockwise from north in `ephemeris.enu_basis`). Differences
between the two therefore measure algorithmic error (ray sampling, interpolation, wedge vs line),
not DEM error. Expected bias: a wedge of width `bin_width` contains terrain beside the ray, so this
horizon is ≥ the ray horizon except where bilinear interpolation exceeds the cell values.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from .dem import LUNAR_RADIUS_M, make_to_latlon
from .ephemeris import enu_basis


@dataclass
class IndependentHorizon:
    azimuths_deg: np.ndarray       # bin centres
    elevations_deg: np.ndarray     # NaN where no cell fell in the bin
    cell_counts: np.ndarray
    bin_width_deg: float
    observer_radius_m: float

    def at(self, azimuth_deg) -> np.ndarray:
        """Linear interpolation between bin centres (same scheme as HorizonMask.at)."""
        az = np.mod(np.asarray(azimuth_deg, dtype=float), 360.0)
        grid = np.concatenate([self.azimuths_deg, [self.azimuths_deg[0] + 360.0]])
        values = np.concatenate([self.elevations_deg, [self.elevations_deg[0]]])
        return np.interp(az, grid, values)


def _unit(lat_deg, lon_deg) -> np.ndarray:
    lat, lon = np.radians(lat_deg), np.radians(lon_deg)
    return np.stack([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)], axis=-1)


def _covered_by(layer, lat, lon) -> np.ndarray:
    """True where `layer` has a finite value at the nearest pixel (used for layer priority)."""
    x, y = layer.to_xy(lat, lon)
    inv = layer.inverse
    col = np.floor(inv.a * x + inv.b * y + inv.c).astype(np.int64)
    row = np.floor(inv.d * x + inv.e * y + inv.f).astype(np.int64)
    rows, cols = layer.data.shape
    inside = (row >= 0) & (row < rows) & (col >= 0) & (col < cols)
    out = np.zeros(lat.shape, dtype=bool)
    out[inside] = np.isfinite(layer.data[row[inside], col[inside]])
    return out


def compute(layers: list, lat_deg: float, lon_deg: float, surface_height_m: float, observer_height_m: float,
            azimuth_step_deg: float = 0.5, max_distance_m: float = 150_000.0, min_distance_m: float = 1.0,
            radius_m: float = LUNAR_RADIUS_M, chunk_rows: int = 256) -> IndependentHorizon:
    """Brute-force horizon over all cells of raster layers (objects with data/transform/inverse/to_xy/crs_wkt)."""
    n_bins = int(round(360.0 / azimuth_step_deg))
    best = np.full(n_bins, -90.0)
    counts = np.zeros(n_bins, dtype=np.int64)
    site = _unit(lat_deg, lon_deg)
    east, north, up = enu_basis(site)
    r0 = radius_m + surface_height_m + observer_height_m
    observer = r0 * site
    cos_max = math.cos(max_distance_m / radius_m)
    cos_min = math.cos(min_distance_m / radius_m)

    for index, layer in enumerate(layers):
        higher = layers[:index]
        to_latlon = make_to_latlon(layer.crs_wkt)
        t = layer.transform
        n_rows, n_cols = layer.data.shape
        cols = np.arange(n_cols) + 0.5
        for start in range(0, n_rows, chunk_rows):
            rows = np.arange(start, min(start + chunk_rows, n_rows)) + 0.5
            cc, rr = np.meshgrid(cols, rows)
            heights = layer.data[start:start + len(rows), :].astype(float)
            finite = np.isfinite(heights)
            if not finite.any():
                continue
            xs = t.a * cc + t.b * rr + t.c
            ys = t.d * cc + t.e * rr + t.f
            lat, lon = to_latlon(xs[finite], ys[finite])
            z = heights[finite]
            units = _unit(lat, lon)
            cosang = units @ site
            keep = (cosang >= cos_max) & (cosang <= cos_min)
            if not keep.any():
                continue
            lat, lon, z, units = lat[keep], lon[keep], z[keep], units[keep]
            if higher:
                covered = np.zeros(len(z), dtype=bool)
                for h in higher:
                    covered |= _covered_by(h, lat, lon)
                lat, lon, z, units = lat[~covered], lon[~covered], z[~covered], units[~covered]
                if len(z) == 0:
                    continue
            vectors = (radius_m + z)[:, None] * units - observer
            dist = np.linalg.norm(vectors, axis=1)
            elevation = np.degrees(np.arcsin(np.clip(vectors @ up / dist, -1.0, 1.0)))
            azimuth = np.degrees(np.arctan2(vectors @ east, vectors @ north)) % 360.0
            bins = np.round(azimuth / azimuth_step_deg).astype(np.int64) % n_bins
            np.maximum.at(best, bins, elevation)
            np.add.at(counts, bins, 1)

    elevations = np.where(counts > 0, best, np.nan)
    return IndependentHorizon(np.arange(n_bins) * azimuth_step_deg, elevations, counts, azimuth_step_deg, r0)


def fair_min_distance_m(cell_m: float, azimuth_step_deg: float) -> float:
    return 2.0 * cell_m / math.radians(azimuth_step_deg)


def compare(ray_mask, independent: IndependentHorizon) -> dict:
    """Statistics of (independent − ray) over rays that are complete in both."""
    ray_az = ray_mask.azimuths_deg
    ind = independent.at(ray_az) if len(independent.azimuths_deg) != len(ray_az) else independent.elevations_deg
    ok = ray_mask.complete & np.isfinite(ind)
    d = ind[ok] - ray_mask.elevations_deg[ok]
    if d.size == 0:
        return {"rays": 0}
    worst = int(np.argmax(np.abs(d)))
    return {
        "rays": int(d.size),
        "meanDiffDeg": round(float(d.mean()), 4),
        "medianDiffDeg": round(float(np.median(d)), 4),
        "p95AbsDiffDeg": round(float(np.percentile(np.abs(d), 95)), 4),
        "maxAbsDiffDeg": round(float(np.abs(d).max()), 4),
        "worstAzimuthDeg": float(ray_az[ok][worst]),
        "rayAboveIndependentBy>0.05deg": int((d < -0.05).sum()),
        "independentAboveRayBy>0.1deg": int((d > 0.1).sum()),
    }
