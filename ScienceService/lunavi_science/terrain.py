"""Terrain characteristics at a site from a LOLA DEM: elevation, local slope and roughness.

Method (per site, using the highest-priority DEM layer that resolves the analysis disc):
* Elevation: bilinear DEM height at the site (metres above the 1737.4 km reference sphere).
* Samples: DEM pixel centres within `radius_m` of the site, in the layer's projected coordinates.
  Heights are DEM values, never hillshade brightness.
* Slope: least-squares plane z = a·x + b·y + c through the samples; slope = atan(|∇z|·k), where k is the
  map's linear scale factor at the site (projected metres per ground metre), so the gradient is per
  ground metre. Near the pole k − 1 is tiny (≈ 2·10⁻⁵ at 89.5° S) but it is applied anyway.
* Roughness: root-mean-square of the residuals from that plane (metres), i.e. detrended height scatter
  at the DEM's resolution over the disc. Relief: max − min of the samples.
* Uncertainty: the statistical standard error of the fitted slope from the residuals. It does not
  include DEM errors or interpolation (PGDA product 78 pixels are largely interpolated between LOLA
  tracks), which is stated in the limitations.

This characterises terrain only. It is not a landing-hazard or safety assessment.
"""
from __future__ import annotations

import math
from typing import Optional

import numpy as np

MIN_SAMPLES = 9
MIN_VALID_FRACTION = 0.8
LIMITATIONS = [
    "Terrain characterization only — not a landing safety certification or hazard assessment.",
    "Computed from the LOLA DEM at its resolution; rocks, boulders and features smaller than about two pixels are not resolved.",
    "Many DEM pixels are interpolated between LOLA tracks; slope and roughness inherit that interpolation.",
    "The slope uncertainty is the statistical plane-fit error only; it does not include DEM error.",
]


def scale_factor(lat_deg: float, lon_deg: float, crs_wkt: Optional[str]) -> float:
    """Linear map scale factor at the site. Uses PROJ's factors for the layer CRS when available,
    otherwise the spherical polar stereographic formula k = 2 / (1 + |sin φ|) (true scale at the pole)."""
    if crs_wkt:
        try:
            from pyproj import CRS, Proj

            factors = Proj(CRS.from_user_input(crs_wkt)).get_factors(lon_deg, lat_deg)
            k = math.sqrt(float(factors.areal_scale))
            if math.isfinite(k) and k > 0:
                return k
        except Exception:
            pass
    return 2.0 / (1.0 + abs(math.sin(math.radians(lat_deg))))


def _sample_points(layer, x0: float, y0: float, radius_m: float):
    """Projected coordinates of the samples: pixel centres for raster layers, else a regular grid."""
    transform = getattr(layer, "transform", None)
    if transform is not None and getattr(layer, "data", None) is not None:
        inv = layer.inverse
        col0 = inv.a * x0 + inv.b * y0 + inv.c
        row0 = inv.d * x0 + inv.e * y0 + inv.f
        span = int(math.ceil(radius_m / layer.resolution_m)) + 1
        rows = np.arange(math.floor(row0) - span, math.floor(row0) + span + 1)
        cols = np.arange(math.floor(col0) - span, math.floor(col0) + span + 1)
        cc, rr = np.meshgrid(cols + 0.5, rows + 0.5)
        xs = transform.a * cc + transform.b * rr + transform.c
        ys = transform.d * cc + transform.e * rr + transform.f
    else:
        step = layer.resolution_m
        n = int(math.ceil(radius_m / step))
        offsets = np.arange(-n, n + 1) * step
        dx, dy = np.meshgrid(offsets, offsets)
        xs, ys = x0 + dx, y0 + dy
    inside = np.hypot(xs - x0, ys - y0) <= radius_m + 1e-9
    return xs[inside], ys[inside]


def characterize(layer, lat_deg: float, lon_deg: float, radius_m: float = 25.0) -> dict:
    """Terrain characteristics of one layer at one site; `available` is False with a reason when unsupported."""
    result = {"latitude": lat_deg, "longitude": lon_deg, "radiusM": float(radius_m),
              "resolutionM": float(layer.resolution_m), "source": layer.name}
    if layer.resolution_m > radius_m / 2:
        return dict(result, available=False,
                    reason=f"DEM resolution {layer.resolution_m:g} m is too coarse for a {radius_m:g} m analysis radius.")
    xy = layer.to_xy(np.array([lat_deg]), np.array([lon_deg]))
    x0, y0 = float(np.ravel(xy[0])[0]), float(np.ravel(xy[1])[0])
    elevation = float(np.ravel(layer.sample(np.array([x0]), np.array([y0])))[0])
    xs, ys = _sample_points(layer, x0, y0, radius_m)
    zs = np.asarray(layer.sample(xs, ys), dtype=float)
    valid = np.isfinite(zs)
    total = int(zs.size)
    count = int(valid.sum())
    valid_fraction = count / total if total else 0.0
    result.update(sampleCount=count, validFraction=round(valid_fraction, 4))
    if not math.isfinite(elevation) or count < MIN_SAMPLES or valid_fraction < MIN_VALID_FRACTION:
        return dict(result, available=False,
                    reason=f"Only {count} of {total} DEM samples within {radius_m:g} m have data (need ≥ {MIN_VALID_FRACTION:.0%}).")

    dx, dy, z = xs[valid] - x0, ys[valid] - y0, zs[valid]
    design = np.column_stack([dx, dy, np.ones_like(dx)])
    coeffs, *_ = np.linalg.lstsq(design, z, rcond=None)
    a, b, _ = coeffs
    residuals = z - design @ coeffs
    dof = max(count - 3, 1)
    sigma2 = float(residuals @ residuals) / dof
    cov = sigma2 * np.linalg.inv(design.T @ design)
    k = scale_factor(lat_deg, lon_deg, getattr(layer, "crs_wkt", None))
    gradient = math.hypot(a, b) * k
    slope = math.degrees(math.atan(gradient))
    # Standard error of |∇z| by first-order propagation, then of the slope angle.
    if gradient > 0:
        g_var = (a * a * cov[0, 0] + b * b * cov[1, 1] + 2 * a * b * cov[0, 1]) / (math.hypot(a, b) ** 2) * k * k
    else:
        g_var = (cov[0, 0] + cov[1, 1]) / 2 * k * k
    slope_se = math.degrees(math.sqrt(max(g_var, 0.0)) / (1 + gradient * gradient))
    return dict(result, available=True,
                elevationM=round(elevation, 2),
                slopeDeg=round(slope, 3),
                slopeUncertaintyDeg=round(slope_se, 3),
                roughnessM=round(float(np.sqrt(np.mean(residuals ** 2))), 3),
                reliefM=round(float(z.max() - z.min()), 2),
                scaleFactor=round(k, 8))


def site_terrain(layers: list, site: dict, radius_m: float = 25.0) -> dict:
    """First layer (priority order) that has data at the site and resolves the radius."""
    lat, lon = float(site["latitude"]), float(site["longitude"])
    reasons = []
    for layer in layers:
        centre = float(np.ravel(layer.sample_latlon(np.array([lat]), np.array([lon])))[0])
        if not math.isfinite(centre):
            continue
        result = characterize(layer, lat, lon, radius_m)
        if result["available"]:
            return dict(result, siteID=site["id"], limitations=LIMITATIONS,
                        method="Least-squares plane over DEM pixel centres within the radius; slope from the plane gradient (per ground metre), roughness = RMS residual.")
        reasons.append(result["reason"])
    return {"siteID": site["id"], "available": False, "radiusM": float(radius_m), "latitude": lat, "longitude": lon,
            "reason": "; ".join(reasons) or "No DEM layer has data at this site.", "limitations": LIMITATIONS}
