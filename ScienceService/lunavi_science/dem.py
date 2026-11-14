"""LOLA DEM access: windowed reads of (cloud-optimised) GeoTIFFs and bilinear sampling by lat/lon.

PGDA products 78 and 90 are south polar stereographic GeoTIFFs in metres (MOON_ME, DE421) with
heights in metres above the 1737.4 km reference sphere. Layers are sampled in priority order:
put the 5 m/pixel site tile (product 78) first and the regional DEM (product 90) second, so the
near field is high resolution and the distant horizon is still covered. Each layer converts
lat/lon with its own CRS, so layers do not need identical projection definitions.

Paths may be local files or URLs; rasterio reads COG windows over HTTP (/vsicurl/) without
downloading whole files.
"""
from __future__ import annotations

import math
from typing import Callable, Optional

import numpy as np

LUNAR_RADIUS_M = 1_737_400.0
SPHERICAL_SOUTH_POLAR_STEREO = "+proj=stere +lat_0=-90 +lon_0=0 +k=1 +x_0=0 +y_0=0 +R=1737400 +units=m +no_defs"


def polar_stereographic_xy(lat_deg, lon_deg, radius_m: float = LUNAR_RADIUS_M, lon0_deg: float = 0.0):
    """Spherical south polar stereographic, true scale at the pole (PROJ +proj=stere +lat_0=-90)."""
    lat = np.radians(np.asarray(lat_deg, dtype=float))
    lon = np.radians(np.asarray(lon_deg, dtype=float) - lon0_deg)
    rho = 2.0 * radius_m * np.tan(np.pi / 4.0 + lat / 2.0)
    return rho * np.sin(lon), rho * np.cos(lon)


def polar_stereographic_latlon(x, y, radius_m: float = LUNAR_RADIUS_M, lon0_deg: float = 0.0):
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    rho = np.hypot(x, y)
    lat = 2.0 * np.arctan(rho / (2.0 * radius_m)) - np.pi / 2.0
    lon = np.degrees(np.arctan2(x, y)) + lon0_deg
    return np.degrees(lat), np.mod(lon + 180.0, 360.0) - 180.0


def read_crs_wkt(path: str) -> Optional[str]:
    import rasterio

    with rasterio.open(path) as src:
        return src.crs.to_wkt() if src.crs else None


def make_to_xy(crs_wkt: Optional[str]) -> Callable:
    """lat/lon (deg, east-positive, planetocentric) -> projected x/y in the CRS (WKT or PROJ string).

    Uses the CRS's own geodetic CRS so PROJ treats both as the same (lunar) body.
    Falls back to the spherical south polar stereographic formula when no CRS is given.
    """
    if not crs_wkt:
        return lambda lat, lon: polar_stereographic_xy(lat, lon)
    from pyproj import CRS, Transformer

    crs = CRS.from_user_input(crs_wkt)
    transformer = Transformer.from_crs(crs.geodetic_crs, crs, always_xy=True)

    def to_xy(lat, lon):
        lon = np.mod(np.asarray(lon, dtype=float) + 180.0, 360.0) - 180.0
        x, y = transformer.transform(lon, np.asarray(lat, dtype=float))
        return np.asarray(x, dtype=float), np.asarray(y, dtype=float)

    return to_xy


def make_to_latlon(crs_wkt: Optional[str]) -> Callable:
    if not crs_wkt:
        return lambda x, y: polar_stereographic_latlon(x, y)
    from pyproj import CRS, Transformer

    crs = CRS.from_user_input(crs_wkt)
    transformer = Transformer.from_crs(crs, crs.geodetic_crs, always_xy=True)

    def to_latlon(x, y):
        lon, lat = transformer.transform(np.asarray(x, dtype=float), np.asarray(y, dtype=float))
        return np.asarray(lat, dtype=float), np.asarray(lon, dtype=float)

    return to_latlon


def crs_name(crs_wkt: Optional[str]) -> str:
    if not crs_wkt:
        return "Spherical south polar stereographic (R = 1737.4 km)"
    from pyproj import CRS

    crs = CRS.from_user_input(crs_wkt)
    if crs.name and crs.name.lower() != "unknown":
        return crs.name
    method = crs.coordinate_operation.method_name if crs.coordinate_operation else "Projected CRS"
    return f"{method}, sphere R = {crs.ellipsoid.semi_major_metre / 1000:.1f} km"


class DemLayer:
    """One raster band, read once into memory over the requested bounds at (about) the requested resolution."""

    def __init__(self, path: str, bounds_xy: Optional[tuple[float, float, float, float]] = None,
                 resolution_m: Optional[float] = None, name: Optional[str] = None, band: int = 1,
                 height_scale: float = 1.0):
        import rasterio
        from affine import Affine
        from rasterio.enums import Resampling
        from rasterio.windows import Window, from_bounds

        self.path = path
        self.name = name or path.rsplit("/", 1)[-1]
        with rasterio.open(path) as src:
            self.crs_wkt = src.crs.to_wkt() if src.crs else None
            native = abs(src.transform.a)
            full = Window(0, 0, src.width, src.height)
            if bounds_xy is not None:
                window = from_bounds(*bounds_xy, transform=src.transform)
                window = window.intersection(full).round_offsets().round_lengths()
            else:
                window = full
            factor = max(1, int(round((resolution_m or native) / native)))
            rows = max(1, int(window.height // factor))
            cols = max(1, int(window.width // factor))
            data = src.read(band, window=window, out_shape=(rows, cols), resampling=Resampling.average, masked=True)
            self.data = np.asarray(data.astype(np.float32).filled(np.nan)) * np.float32(height_scale)
            t = src.window_transform(window)
            sx, sy = window.width / cols, window.height / rows  # pixel size change from decimation
            self.transform = Affine(t.a * sx, t.b * sy, t.c, t.d * sx, t.e * sy, t.f)
            self.native_resolution_m = native
        self.resolution_m = abs(self.transform.a)
        self.inverse = ~self.transform
        self.to_xy = make_to_xy(self.crs_wkt)

    def sample(self, x, y) -> np.ndarray:
        """Bilinear sample at projected x/y; NaN outside the data (or next to missing pixels)."""
        from scipy.ndimage import map_coordinates

        x = np.asarray(x, dtype=float)
        y = np.asarray(y, dtype=float)
        inv = self.inverse
        col = inv.a * x + inv.b * y + inv.c
        row = inv.d * x + inv.e * y + inv.f
        return map_coordinates(self.data, [np.asarray(row) - 0.5, np.asarray(col) - 0.5], order=1,
                               mode="constant", cval=np.nan).astype(float)

    def sample_latlon(self, lat, lon) -> np.ndarray:
        x, y = self.to_xy(lat, lon)
        return self.sample(x, y)


class FunctionLayer:
    """A synthetic layer for tests: height = fn(x, y) in the spherical polar stereographic plane."""

    def __init__(self, fn: Callable, name: str = "synthetic", resolution_m: float = 100.0):
        self.fn = fn
        self.name = name
        self.resolution_m = resolution_m
        self.native_resolution_m = resolution_m
        self.crs_wkt = None
        self.to_xy = make_to_xy(None)

    def sample(self, x, y):
        return np.asarray(self.fn(np.asarray(x, dtype=float), np.asarray(y, dtype=float)), dtype=float)

    def sample_latlon(self, lat, lon):
        x, y = self.to_xy(lat, lon)
        return self.sample(x, y)


class DemSampler:
    """Samples layers in priority order by lat/lon; NaN where no layer has data."""

    def __init__(self, layers: list):
        self.layers = layers

    def sample_latlon(self, lat, lon) -> np.ndarray:
        lat = np.asarray(lat, dtype=float)
        lon = np.asarray(lon, dtype=float)
        result = np.full(lat.shape, np.nan)
        for layer in self.layers:
            missing = np.isnan(result)
            if not missing.any():
                break
            result[missing] = layer.sample_latlon(lat[missing], lon[missing])
        return result


def surface_height(sampler: DemSampler, lat_deg: float, lon_deg: float) -> float:
    value = float(sampler.sample_latlon(np.array([lat_deg]), np.array([lon_deg]))[0])
    if math.isnan(value):
        raise ValueError(f"Site {lat_deg:.4f}, {lon_deg:.4f} is outside DEM coverage")
    return value
