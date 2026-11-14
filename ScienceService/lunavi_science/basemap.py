"""Georeferenced basemap for the app: LOLA-derived shaded relief around the sites.

The image is square and north-up in the projected CRS (row 0 = maximum y; for south polar
stereographic, +y points toward 0° longitude, the Earth-facing side). Site positions are returned
as normalised (x, y) image coordinates so the app never needs projection math.
"""
from __future__ import annotations

import numpy as np

from .dem import crs_name, make_to_latlon, make_to_xy


def hillshade(heights: np.ndarray, cell_m: float, azimuth_deg: float = 315.0, altitude_deg: float = 30.0) -> np.ndarray:
    """Standard (ESRI-style) hillshade of a north-up grid whose rows increase southward."""
    filled = np.where(np.isnan(heights), np.nanmean(heights), heights)
    dz_drow, dz_dcol = np.gradient(filled, cell_m)  # dz_drow: change toward the image bottom (south)
    slope = np.arctan(np.hypot(dz_dcol, dz_drow))
    aspect = np.arctan2(dz_drow, -dz_dcol)
    sun_azimuth = np.radians(360.0 - azimuth_deg + 90.0)
    zenith = np.radians(90.0 - altitude_deg)
    shade = np.cos(zenith) * np.cos(slope) + np.sin(zenith) * np.sin(slope) * np.cos(sun_azimuth - aspect)
    return np.clip(shade, 0.0, 1.0)


def render_basemap(sampler, sites_latlon: list, out_path: str, crs_wkt=None, size_px: int = 2048,
                   margin_m: float = 12_000.0, hillshade_layer=None, layer_names=None):
    from PIL import Image

    to_xy, to_latlon = make_to_xy(crs_wkt), make_to_latlon(crs_wkt)
    xs, ys = to_xy(np.array([p[0] for p in sites_latlon]), np.array([p[1] for p in sites_latlon]))
    cx, cy = (xs.min() + xs.max()) / 2.0, (ys.min() + ys.max()) / 2.0
    half = max(xs.max() - xs.min(), ys.max() - ys.min()) / 2.0 + margin_m
    xmin, xmax, ymin, ymax = cx - half, cx + half, cy - half, cy + half
    cell = (xmax - xmin) / size_px

    gx = xmin + (np.arange(size_px) + 0.5) * cell
    gy = ymax - (np.arange(size_px) + 0.5) * cell
    grid_x, grid_y = np.meshgrid(gx, gy)
    lat, lon = to_latlon(grid_x.ravel(), grid_y.ravel())

    if hillshade_layer is not None:
        values = hillshade_layer.sample_latlon(lat, lon).reshape(grid_x.shape)
        lo, hi = np.nanpercentile(values, [1, 99])
        image = np.clip((values - lo) / max(hi - lo, 1e-9), 0.0, 1.0)
        title = "LOLA hillshade"
    else:
        heights = sampler.sample_latlon(lat, lon).reshape(grid_x.shape)
        shade = hillshade(heights, cell)
        lo, hi = np.percentile(shade, [2, 98])
        image = np.clip((shade - lo) / max(hi - lo, 1e-9), 0.0, 1.0)  # contrast stretch for display only
        title = "LOLA-derived shaded relief"
    image = np.nan_to_num(image, nan=0.0) ** 0.9
    Image.fromarray((image * 255).astype(np.uint8), mode="L").save(out_path, quality=86, optimize=True)

    positions = [((x - xmin) / (xmax - xmin), (ymax - y) / (ymax - ymin)) for x, y in zip(xs, ys)]
    manifest = {
        "imageResource": out_path.replace("\\", "/").rsplit("/", 1)[-1].rsplit(".", 1)[0],
        "imageExtension": "jpg",
        "isIllustrative": False,
        "title": title,
        "attribution": "Shaded relief derived from NASA LRO LOLA elevation data (NASA GSFC PGDA): " + ", ".join(layer_names or []) + ".",
        "pixelWidth": size_px,
        "pixelHeight": size_px,
        "metersPerPixel": round(float(cell), 4),
        "projection": f"{crs_name(crs_wkt)}; x {xmin:.0f}..{xmax:.0f} m, y {ymin:.0f}..{ymax:.0f} m",
    }
    return manifest, positions
