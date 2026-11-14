"""Scientific validation suite for a LUNAVI scenario.

  python -m lunavi_science validate-science --config config/sites.json \
      --scenario ../Lunavi/Resources/ComputedScenario.json --out ../docs/validation_results

Sections (each records exactly what it compared; nothing here is assumed):

1. horizon     Ray-marched horizon (horizon.py, what the app uses) vs an independent all-cells horizon
               (horizon_independent.py), compared where the comparison is fair; plus a check that the
               horizon exported in the scenario equals a fresh recomputation.
2. pgda69      18.6-year average solar illumination and Earth visibility at each site from LUNAVI's
               horizon + SPICE, vs NASA GSFC PGDA product 69 (independent processing of LOLA data).
               A statistical comparison of averages — not a timestamp-level validation.
3. cases       Representative instants per site (Sun/Earth clear, near the horizon, blocked, no data):
               SPICE azimuth/elevation, both horizons, clearances, predicted states, optionally JPL
               Horizons azimuth/elevation at the same instant.
4. decisions   Mission windows recomputed independently (SPICE every 60 s, separately coded criteria)
               vs the app's interval evaluation.
5. rescue      Mission Rescue options vs a brute-force minute-by-minute search.
6. sensitivity Re-runs with perturbed observer height, azimuth step, search radius, sampling step and
               thresholds; reports transition shifts and any pass/fail changes.
"""
from __future__ import annotations

import dataclasses
import datetime as dt
import json
import math
import os
from typing import Optional

import numpy as np

from . import intervals as iv
from .dem import DemSampler, make_to_xy
from .ephemeris import EARTH_RADIUS_KM, SUN_RADIUS_KM, angular_radius_deg, load_kernels, site_vector_km, target_azel
from .horizon import compute_horizon, ray_distances, ray_points
from .horizon_independent import compare, compute as independent_horizon, fair_min_distance_m
from .dem import LUNAR_RADIUS_M
from .scenario import _load_layers, compute_site, settings_from_config
from .timeutil import iso, parse_utc, time_grid, utc_to_et
from .visibility import disc_fraction_visible

PGDA69_SUN = "https://pgda.gsfc.nasa.gov/data/MoonIllumination/AVGVISIB_85S_060M_201608.TIF"
PGDA69_EARTH = "https://pgda.gsfc.nasa.gov/data/MoonIllumination/AVGVISIB_85S_060M_201608_EARTH.TIF"
NUTATION_YEARS = 18.6


# ---------------------------------------------------------------------------------------------- context

@dataclasses.dataclass
class Context:
    cfg: dict
    settings: object
    layers: list
    sampler: DemSampler
    sites: list
    times: list
    ets: list
    scenario: dict
    resolve: object = None


def load_context(config_path: str, scenario_path: str, spice) -> Context:
    with open(config_path) as f:
        cfg = json.load(f)
    base = os.path.dirname(os.path.abspath(config_path))

    def resolve(p: str) -> str:
        return p if (p.startswith("/vsi") or "://" in p or os.path.isabs(p)) else os.path.join(base, p)

    with open(scenario_path) as f:
        scenario = json.load(f)
    # Validate the period the scenario was actually computed for.
    if scenario.get("period"):
        cfg = dict(cfg, period=dict(cfg.get("period", {}), start=scenario["period"]["start"], end=scenario["period"]["end"],
                                    stepSeconds=scenario["period"].get("stepSeconds", cfg.get("period", {}).get("stepSeconds", 600))))
    s = settings_from_config(cfg)
    load_kernels(spice, [resolve(k) for k in cfg["kernels"]])
    layers = _load_layers(cfg, resolve, cfg["sites"])
    times = time_grid(s.start, s.end, s.step_s)
    ets = [utc_to_et(t, spice) for t in times]
    return Context(cfg, s, layers, DemSampler(layers), cfg["sites"], times, ets, scenario, resolve)


def _scenario_sites(ctx) -> tuple[str, str]:
    """Connecting Ridge and Shackleton Rim when present; otherwise the scenario's first two sites."""
    ids = [x["id"] for x in ctx.sites]
    primary = "pgda78-site01" if "pgda78-site01" in ids else ids[0]
    secondary = "pgda78-site04" if "pgda78-site04" in ids else ids[min(1, len(ids) - 1)]
    return primary, secondary


def _scenario_list(ctx) -> list:
    p, q = _scenario_sites(ctx)
    t = ctx.scenario["mission"]["start"] if p != "pgda78-site01" else "2026-11-29T15:00:00Z"
    delayed = iso(parse_utc(t) + dt.timedelta(hours=float(ctx.scenario["mission"]["delayHours"])))
    return [("A", p, t, 24), ("B", q, t, 6), ("C", p, t, 48), ("A+delay", p, delayed, 24)]


def _site_position_km(site: dict, surface_m: float, observer_m: float) -> np.ndarray:
    return site_vector_km(float(site["latitude"]), float(site["longitude"]), (LUNAR_RADIUS_M + surface_m + observer_m) / 1000.0)


def _r(x, n=4):
    return None if x is None or (isinstance(x, float) and not math.isfinite(x)) else round(float(x), n)


# ---------------------------------------------------------------------------------------------- 1. horizon

def _ray_argmax_distances(ctx: Context, site: dict, mask) -> np.ndarray:
    """Distance (m) at which each ray's horizon maximum occurs (pipeline method)."""
    s = ctx.settings
    distances = ray_distances(s.near_step_m, s.max_distance_m)
    theta = distances / LUNAR_RADIUS_M
    lat, lon = ray_points(float(site["latitude"]), float(site["longitude"]), mask.azimuths_deg, theta)
    h = ctx.sampler.sample_latlon(lat.ravel(), lon.ravel()).reshape(lat.shape)
    r0 = LUNAR_RADIUS_M + mask.surface_height_m + mask.observer_height_m
    r = LUNAR_RADIUS_M + h
    el = np.degrees(np.arctan2(r * np.cos(theta)[None, :] - r0, r * np.sin(theta)[None, :]))
    el = np.where(np.isnan(h), -90.0, el)
    return distances[np.argmax(el, axis=1)]


def horizon_section(ctx: Context) -> dict:
    s = ctx.settings
    near_layer, far_step = ctx.layers[0], 2.0
    out = {"method": "ray-marching (app) vs all-cells wedge maximum (independent), compared beyond D0 = 2·cell/step",
           "sites": {}}
    exported = {g["siteID"]: g for g in ctx.scenario.get("geometry", [])}
    for site in ctx.sites:
        lat, lon = float(site["latitude"]), float(site["longitude"])
        mask = compute_horizon(ctx.sampler, lat, lon, s.observer_height_m, s.azimuth_step_deg, s.max_distance_m, s.near_step_m)
        entry: dict = {"surfaceHeightM": _r(mask.surface_height_m, 2)}

        g = exported.get(site["id"])
        if g:
            stored = np.asarray(g["horizon"]["elevationsDeg"], dtype=float)
            if len(stored) == len(mask.elevations_deg):
                entry["exportedVsRecomputedMaxAbsDeg"] = _r(np.nanmax(np.abs(stored - mask.elevations_deg)), 5)

        # Which distance band sets each ray's horizon.
        where = _ray_argmax_distances(ctx, site, mask)
        tile_layer = next((L for L in ctx.layers if np.isfinite(L.sample_latlon(np.array([lat]), np.array([lon]))[0])), near_layer)
        d0_near = fair_min_distance_m(tile_layer.resolution_m, s.azimuth_step_deg)
        far_layer = ctx.layers[-1]
        d0_far = fair_min_distance_m(far_layer.resolution_m, far_step)
        entry["horizonSetBy"] = {
            f"<{d0_near:.0f} m (not cross-checked)": int((where < d0_near).sum()),
            f"{d0_near:.0f} m – {d0_far / 1000:.1f} km": int(((where >= d0_near) & (where < d0_far)).sum()),
            f"≥{d0_far / 1000:.1f} km": int((where >= d0_far).sum()),
            "rays": int(len(where)),
        }

        # (a) Near field on the site tile at the app's azimuth step.
        near_ray = compute_horizon(DemSampler([tile_layer]), lat, lon, s.observer_height_m, s.azimuth_step_deg, s.max_distance_m,
                                   s.near_step_m, surface_height_m=mask.surface_height_m, min_distance_m=d0_near)
        near_ray.complete = np.ones_like(near_ray.complete)  # the tile ends inside the radius by design
        near_ind = independent_horizon([tile_layer], lat, lon, mask.surface_height_m, s.observer_height_m,
                                       s.azimuth_step_deg, s.max_distance_m, min_distance_m=d0_near)
        entry["nearFieldTile"] = dict(compare(near_ray, near_ind), azimuthStepDeg=s.azimuth_step_deg,
                                      fromDistanceM=round(d0_near), layer=tile_layer.name, cellM=_r(tile_layer.resolution_m, 1))

        # (b) All layers beyond the far-field fair distance, at a 2° step.
        far_ray = compute_horizon(ctx.sampler, lat, lon, s.observer_height_m, far_step, s.max_distance_m, s.near_step_m,
                                  surface_height_m=mask.surface_height_m, min_distance_m=d0_far)
        far_ind = independent_horizon(ctx.layers, lat, lon, mask.surface_height_m, s.observer_height_m, far_step,
                                      s.max_distance_m, min_distance_m=d0_far)
        entry["allLayersFarField"] = dict(compare(far_ray, far_ind), azimuthStepDeg=far_step, fromDistanceM=round(d0_far))
        out["sites"][site["id"]] = entry
    return out


# ---------------------------------------------------------------------------------------------- 2. PGDA 69

def _read_pgda(path: str, lat: float, lon: float, half: int = 1) -> dict:
    import rasterio
    from rasterio.windows import Window

    with rasterio.open(path) as src:
        x, y = make_to_xy(src.crs.to_wkt() if src.crs else None)(np.array([lat]), np.array([lon]))
        row, col = src.index(float(x[0]), float(y[0]))
        window = Window(col - half, row - half, 2 * half + 1, 2 * half + 1)
        raw = src.read(1, window=window, masked=True).astype(float).filled(np.nan)
        scale = (src.scales or [1.0])[0] or 1.0
        offset = (src.offsets or [0.0])[0] or 0.0
        values = raw * scale + offset
        res = abs(src.transform.a)
    unit_scale = 0.01 if np.nanmax(values) > 1.5 else 1.0  # percent → fraction
    v = values * unit_scale
    return {"centre": _r(v[half, half]), "min3x3": _r(np.nanmin(v)), "max3x3": _r(np.nanmax(v)),
            "rawCentre": _r(values[half, half]), "scaleApplied": scale, "offsetApplied": offset,
            "interpretedAsPercent": unit_scale == 0.01, "pixelM": _r(res, 1)}


def long_term_average(spice, ctx: Context, site: dict, observer_m: float, start: dt.datetime, years: float = NUTATION_YEARS,
                      step_hours: float = 1.0) -> dict:
    s = ctx.settings
    lat, lon = float(site["latitude"]), float(site["longitude"])
    mask = compute_horizon(ctx.sampler, lat, lon, observer_m, s.azimuth_step_deg, s.max_distance_m, s.near_step_m)
    position = _site_position_km(site, mask.surface_height_m, observer_m)
    n = int(years * 365.25 * 24 / step_hours)
    et0 = utc_to_et(start, spice)
    ets = et0 + np.arange(n) * step_hours * 3600.0
    out = {"observerHeightM": observer_m, "samples": n, "start": iso(start), "years": years}
    for name, target, radius_km in (("sun", "SUN", SUN_RADIUS_KM), ("earth", "EARTH", EARTH_RADIUS_KM)):
        az, el, distance = target_azel(spice, target, list(ets), position)
        radius = angular_radius_deg(radius_km, distance)
        complete = mask.is_complete(az)
        horizon = mask.at(az)
        fraction = disc_fraction_visible(el, horizon, radius)
        out[name] = {
            "meanDiscFraction": _r(np.mean(fraction[complete])),
            "fractionCentreAbove": _r(np.mean((el > horizon)[complete])),
            "fractionAnyPartAbove": _r(np.mean((el + radius > horizon)[complete])),
            "unknownShare": _r(1 - complete.mean()),
        }
    return out


def pgda69_section(spice, ctx: Context, sun_path: str = PGDA69_SUN, earth_path: str = PGDA69_EARTH,
                   start: Optional[dt.datetime] = None, step_hours: float = 1.0) -> dict:
    start = start or dt.datetime(2017, 1, 1, tzinfo=dt.timezone.utc)  # full 18.6-yr cycle to mid-2035; inside DE421 and the 2050 PCK
    out = {"reference": {"sun": sun_path, "earth": earth_path,
                         "note": "PGDA 69: hourly samples over one 18.6-year nutation cycle, LOLA DEM, 60 m/px; "
                                 "observer height and exact epoch are not stated on the product page."},
           "sites": {}}
    for site in ctx.sites:
        lat, lon = float(site["latitude"]), float(site["longitude"])
        entry: dict = {}
        for label, path in (("sun", sun_path), ("earth", earth_path)):
            try:
                entry[f"pgda69_{label}"] = _read_pgda(path, lat, lon)
            except Exception as error:  # network or file problems are reported, never replaced by a value
                entry[f"pgda69_{label}"] = {"error": str(error)}
        for h in (0.0, ctx.settings.observer_height_m):
            entry[f"lunavi_h{h:g}m"] = long_term_average(spice, ctx, site, h, start, step_hours=step_hours)
        out["sites"][site["id"]] = entry
    return out


# ---------------------------------------------------------------------------------------------- 3. cases

def _state(condition: str, el: float, horizon: float, radius: float, s) -> tuple[str, float]:
    if condition == "sunlight":
        f = float(disc_fraction_visible(el - s.min_clearance_deg, horizon, radius))
        return ("visible" if f >= s.sun_min_fraction else "obstructed"), f
    return ("visible" if el - s.min_clearance_deg + radius > horizon else "obstructed"), float(el + radius > horizon)


def cases_section(spice, ctx: Context, use_horizons: bool = True) -> dict:
    s = ctx.settings
    vis = {v["siteID"]: iv.site_data_from_json(v, parse_utc) for v in ctx.scenario["visibility"]}
    geo = {g["siteID"]: g for g in ctx.scenario.get("geometry", [])}
    out = {"sites": {}}
    for site in ctx.sites:
        sid = site["id"]
        lat, lon = float(site["latitude"]), float(site["longitude"])
        g = geo.get(sid)
        if not g:
            out["sites"][sid] = {"error": "scenario has no geometry for this site"}
            continue
        mask = compute_horizon(ctx.sampler, lat, lon, s.observer_height_m, s.azimuth_step_deg, s.max_distance_m, s.near_step_m)
        tile = next((L for L in ctx.layers if np.isfinite(L.sample_latlon(np.array([lat]), np.array([lon]))[0])), ctx.layers[0])
        d0 = fair_min_distance_m(tile.resolution_m, s.azimuth_step_deg)
        # Independent horizon from terrain beyond D0 (where the all-cells method is fair). If the app's horizon
        # in a direction is set closer than D0, the two can legitimately differ; such rows are flagged.
        ind = independent_horizon(ctx.layers, lat, lon, mask.surface_height_m, s.observer_height_m, s.azimuth_step_deg,
                                  s.max_distance_m, min_distance_m=d0)
        position = _site_position_km(site, mask.surface_height_m, s.observer_height_m)
        set_at = _ray_argmax_distances(ctx, site, mask)
        start = parse_utc(g["samples"]["start"])
        step = float(g["samples"]["stepSeconds"])
        picks = []
        for condition, key in (("sunlight", "sun"), ("earthLineOfSight", "earth")):
            tr = g["samples"][key]
            # The last sample is the period end itself; coverage is half-open, so it is (correctly) unknown. Skip it.
            az, el, rad = (np.asarray(tr[k], dtype=float)[:-1] for k in ("azimuthDeg", "elevationDeg", "angularRadiusDeg"))
            clearance = el - mask.at(az)
            edge = clearance - (0.0 if condition == "sunlight" else -rad)  # distance to the criterion line
            label = "Sun" if condition == "sunlight" else "Earth"
            picks.append((f"{label} clearly visible", condition, int(np.argmax(clearance))))
            picks.append((f"{label} closest to the criterion", condition, int(np.argmin(np.abs(edge)))))
            blocked = np.where(edge < 0)[0]
            picks.append((f"{label} blocked", condition, int(blocked[np.argmin(edge[blocked])]) if blocked.size else None))
        rows = []
        for title, condition, index in picks:
            if index is None:
                rows.append({"case": title, "result": "no such instant in the computed period"})
                continue
            moment = start + dt.timedelta(seconds=index * step)
            target = "SUN" if condition == "sunlight" else "EARTH"
            az, el, distance = target_azel(spice, target, [utc_to_et(moment, spice)], position)
            radius = float(angular_radius_deg(SUN_RADIUS_KM if target == "SUN" else EARTH_RADIUS_KM, distance)[0])
            az, el = float(az[0]), float(el[0])
            h_app, h_ind = float(np.ravel(mask.at(az))[0]), float(np.ravel(ind.at(az))[0])
            state_app, _ = _state(condition, el, h_app, radius, s)
            state_ind, _ = _state(condition, el, h_ind, radius, s)
            row = {"case": title, "condition": condition, "utc": iso(moment), "azimuthDeg": _r(az), "elevationDeg": _r(el),
                   "angularRadiusDeg": _r(radius), "horizonAppDeg": _r(h_app), "horizonIndependentDeg": _r(h_ind),
                   "clearanceAppDeg": _r(el - h_app), "clearanceIndependentDeg": _r(el - h_ind),
                   "stateApp": state_app, "stateIndependentHorizon": state_ind,
                   "stateStoredIntervals": _interval_state(vis[sid], condition, moment),
                   "horizonsDeltaAzDeg": None, "horizonsDeltaElDeg": None}
            if use_horizons:
                try:
                    from .horizons_check import query_azel
                    rows_h = query_azel(lat, lon, (mask.surface_height_m + s.observer_height_m) / 1000.0, target,
                                        moment, moment + dt.timedelta(minutes=1), "1m")
                    if rows_h:
                        _, h_az, h_el = rows_h[0]
                        row["horizonsDeltaAzDeg"] = _r(((az - h_az + 180) % 360) - 180, 5)
                        row["horizonsDeltaElDeg"] = _r(el - h_el, 5)
                except Exception as error:
                    row["horizonsError"] = str(error)[:160]
            ray = int(round(az / s.azimuth_step_deg)) % len(set_at)
            row["horizonSetAtDistanceM"] = round(float(set_at[ray]))
            if state_app != row["stateStoredIntervals"]:
                row["conclusion"] = "DIFFER: app geometry vs stored intervals — inspect"
            elif set_at[ray] < d0:
                row["conclusion"] = (f"app consistent; horizon here is set {set_at[ray]:.0f} m from the site (< {d0:.0f} m), "
                                     "inside the zone the independent method cannot resolve — not cross-checked")
            elif state_app == state_ind:
                row["conclusion"] = "agree"
            else:
                row["conclusion"] = "DIFFER: independent horizon changes the state — near-threshold, inspect"
            rows.append(row)
        # Missing data: one hour after the computed period.
        after = ctx.settings.end + dt.timedelta(hours=1)
        rows.append({"case": "Missing data (1 h after the computed period)", "utc": iso(after),
                     "stateStoredIntervals": _interval_state(vis[sid], "sunlight", after),
                     "conclusion": "unknown, as required" if _interval_state(vis[sid], "sunlight", after) == "unknown" else "ERROR"})
        out["sites"][sid] = {"latitude": lat, "longitude": lon, "surfaceHeightM": _r(mask.surface_height_m, 2), "cases": rows}
    return out


def _interval_state(data: iv.SiteData, condition: str, moment: dt.datetime) -> str:
    if not any(a <= moment < b for a, b in data.coverage):
        return "unknown"
    return "visible" if any(a <= moment < b for a, b in data.intervals(condition)) else "obstructed"


# ---------------------------------------------------------------------------------------------- 4. decisions

def _independent_window(spice, ctx: Context, site: dict, start: dt.datetime, hours: float, mask, step_s: float = 60.0) -> dict:
    """Status recomputed from SPICE every `step_s` with separately coded criteria (no intervals)."""
    s = ctx.settings
    period_end = ctx.settings.end
    n = int(hours * 3600 / step_s)
    times = [start + dt.timedelta(seconds=i * step_s) for i in range(n)]
    position = _site_position_km(site, mask.surface_height_m, s.observer_height_m)
    known = np.array([ctx.settings.start <= t < period_end for t in times])
    result = {}
    for condition, target, radius_km in (("sunlight", "SUN", SUN_RADIUS_KM), ("earthLineOfSight", "EARTH", EARTH_RADIUS_KM)):
        az, el, distance = target_azel(spice, target, [utc_to_et(t, spice) for t in times], position)
        radius = angular_radius_deg(radius_km, distance)
        horizon = mask.at(az)
        complete = mask.is_complete(az)
        if condition == "sunlight":
            ok = disc_fraction_visible(el - s.min_clearance_deg, horizon, radius) >= s.sun_min_fraction
        else:
            ok = el - s.min_clearance_deg + radius > horizon
        known_c = known & complete
        blocked = known_c & ~ok
        unknown = ~known_c
        if blocked.any():
            status = "partial" if (known_c & ok).any() else "unavailable"
        elif unknown.any():
            status = "unknown"
        else:
            status = "met"
        first_block = times[int(np.argmax(blocked))] if blocked.any() else None
        result[condition] = {"status": status, "firstObstruction": iso(first_block) if first_block else None,
                             "obstructedH": _r(blocked.sum() * step_s / 3600, 3), "unknownH": _r(unknown.sum() * step_s / 3600, 3)}
    statuses = {result[c]["status"] for c in result}
    result["overall"] = "notMet" if statuses & {"partial", "unavailable"} else ("unknown" if "unknown" in statuses else "met")
    return result


def decisions_section(spice, ctx: Context) -> dict:
    s = ctx.settings
    vis = {v["siteID"]: iv.site_data_from_json(v, parse_utc) for v in ctx.scenario["visibility"]}
    by_id = {x["id"]: x for x in ctx.sites}
    scenarios = _scenario_list(ctx)
    # D: the first genuine obstruction in the data (any site, Sun first), as a 6 h window around its start.
    d_case = None
    for condition in ("sunlight", "earthLineOfSight"):
        for sid, data in vis.items():
            cov = [(a, b) for a, b in data.coverage]
            vis_c = data.intervals(condition)
            for a, b in cov:
                gaps = iv.complement(iv.clip(vis_c, (a, b)), (a, b))
                if gaps:
                    g0 = gaps[0][0]
                    d_case = ("D", sid, iso(max(a, g0 - dt.timedelta(hours=3))), 6, condition)
                    break
            if d_case:
                break
        if d_case:
            break
    if d_case:
        scenarios.append(d_case[:4])
    out = {"scenarios": {}, "D_source": f"first {d_case[4]} obstruction in the data" if d_case else "no obstruction in the data"}
    masks = {}
    for key, sid, start, hours in scenarios:
        if sid not in by_id or sid not in vis:
            out["scenarios"][key] = {"error": f"site {sid} not in this scenario"}
            continue
        site = by_id[sid]
        if sid not in masks:
            masks[sid] = compute_horizon(ctx.sampler, float(site["latitude"]), float(site["longitude"]), s.observer_height_m,
                                         s.azimuth_step_deg, s.max_distance_m, s.near_step_m)
        t0 = parse_utc(start)
        app = iv.evaluate(vis[sid], sid, t0, hours)
        ind = _independent_window(spice, ctx, site, t0, hours, masks[sid])

        def first(x):
            return iso(x.first_failure) if x.first_failure else None
        app_d = {"overall": app.overall,
                 "sunlight": {"status": app.sunlight.status, "firstObstruction": first(app.sunlight), "unknownH": _r(app.sunlight.unknown_s / 3600, 3),
                              "obstructedH": _r(app.sunlight.obstructed_s / 3600, 3)},
                 "earthLineOfSight": {"status": app.earth.status, "firstObstruction": first(app.earth), "unknownH": _r(app.earth.unknown_s / 3600, 3),
                                      "obstructedH": _r(app.earth.obstructed_s / 3600, 3)}}
        diffs = {}
        for c in ("sunlight", "earthLineOfSight"):
            a, b = app_d[c]["firstObstruction"], ind[c]["firstObstruction"]
            diffs[c] = None if not (a and b) else _r((parse_utc(b) - parse_utc(a)).total_seconds(), 0)
        out["scenarios"][key] = {"site": sid, "start": start, "hours": hours, "app": app_d, "independent60s": ind,
                                 "statusAgrees": app_d["overall"] == ind["overall"]
                                 and all(app_d[c]["status"] == ind[c]["status"] for c in ("sunlight", "earthLineOfSight")),
                                 "firstObstructionDiffS (independent − app, 60 s grid)": diffs}
    return out


# ---------------------------------------------------------------------------------------------- 5. rescue

def rescue_section(ctx: Context, hours: float = 24) -> dict:
    _, site_id, start, _ = _scenario_list(ctx)[0]
    vis = {v["siteID"]: iv.site_data_from_json(v, parse_utc) for v in ctx.scenario["visibility"]}
    delay = float(ctx.scenario["mission"]["delayHours"])
    base = parse_utc(start) + dt.timedelta(hours=delay)
    stubs = [{"id": x["id"], "coordinate": x.get("coordinate")} for x in ctx.scenario["sites"]]
    order = iv.proximity_order(stubs, site_id, vis)
    options = iv.recovery_candidates(vis, order, site_id, base, hours)
    # Brute force: every minute from the delayed start to the end of coverage, same site.
    data = vis[site_id]
    end = max(b for _, b in data.coverage)
    t, earliest = base, None
    while t + dt.timedelta(hours=hours) <= end:
        if iv.evaluate(data, site_id, t, hours).overall == "met":
            earliest = t
            break
        t += dt.timedelta(minutes=1)
    qualifying = [sid for sid in order if iv.evaluate(vis[sid], sid, base, hours).overall == "met"]
    opt_a = next((o for o in options if o["kind"] == "sameSiteLaterTime"), None)
    opt_b = next((o for o in options if o["kind"] == "alternativeSite"), None)
    return {
        "delayedStart": iso(base), "hours": hours, "proximityOrder": order,
        "optionA": iso(opt_a["start"]) if opt_a else None,
        "bruteForceEarliestSameSite (1-min steps)": iso(earliest) if earliest else None,
        "optionA_matchesBruteForce": (opt_a is None and earliest is None) or (opt_a is not None and earliest is not None
                                                                             and abs((opt_a["start"] - earliest).total_seconds()) < 60),
        "optionB": opt_b["siteId"] if opt_b else None,
        "allQualifyingSitesAtDelayedStart (nearest first)": qualifying,
        "optionB_isNearestQualifying": (opt_b["siteId"] if opt_b else None) == (qualifying[0] if qualifying else None),
        "optionsReEvaluated": {o["kind"]: iv.evaluate(vis[o["siteId"]], o["siteId"], o["start"], o["hours"]).overall for o in options},
        "durationPreserved": all(o["hours"] == hours for o in options),
    }


# ---------------------------------------------------------------------------------------------- 6. sensitivity

def _transitions(ranges: list) -> list:
    return sorted([a for a, _ in ranges] + [b for _, b in ranges])


def sensitivity_section(spice, ctx: Context, variants: Optional[list] = None) -> dict:
    s0 = ctx.settings
    variants = variants or [
        ("observer 1 m", {"observer_height_m": 1.0}), ("observer 5 m", {"observer_height_m": 5.0}),
        ("observer 10 m", {"observer_height_m": 10.0}),
        ("azimuth step 0.25°", {"azimuth_step_deg": 0.25}), ("azimuth step 1°", {"azimuth_step_deg": 1.0}),
        ("search radius 100 km", {"max_distance_m": 100_000.0}),
        ("search radius 250 km", {"max_distance_m": 250_000.0}),
        ("sampling 300 s", {"step_s": 300.0}),
        ("Sun: any part of disc", {"sun_min_fraction": 0.0}), ("Sun: whole disc", {"sun_min_fraction": 1.0}),
        ("clearance +0.1°", {"min_clearance_deg": 0.1}),
    ]
    scen = _scenario_list(ctx)

    def sampler_for(settings):
        """Reload the far-field layer with a larger window when the search radius exceeds the configured padding."""
        pads = [float(L.get("boundsPaddingM") or 0) for L in ctx.cfg["dem"]["layers"]]
        if not pads or settings.max_distance_m + 10_000 <= max(pads):
            return ctx.sampler
        layers_cfg = [dict(L, boundsPaddingM=settings.max_distance_m + 10_000) if L.get("boundsPaddingM") else L
                      for L in ctx.cfg["dem"]["layers"]]
        cfg2 = dict(ctx.cfg, dem=dict(ctx.cfg["dem"], layers=layers_cfg))
        return DemSampler(_load_layers(cfg2, ctx.resolve, ctx.sites))

    def run(settings) -> dict:
        times = time_grid(settings.start, settings.end, settings.step_s)
        ets = [utc_to_et(t, spice) for t in times]
        sampler = sampler_for(settings)
        comps = {site["id"]: compute_site(spice, sampler, site, settings, times, ets) for site in ctx.sites}
        data = {k: iv.SiteData(k, c.coverage, c.sunlight, c.earth) for k, c in comps.items()}
        return {"comps": comps, "data": data}

    base = run(s0)
    out = {"baseline": {}, "variants": {}}
    for key, sid, start, hours in scen:
        if sid in base["data"]:
            out["baseline"][key] = iv.evaluate(base["data"][sid], sid, parse_utc(start), hours).overall
    for label, change in variants:
        settings = dataclasses.replace(s0, **change)
        try:
            res = run(settings)
        except Exception as error:
            out["variants"][label] = {"error": str(error)[:200]}
            continue
        shifts, unmatched, largest = [], 0, None
        for sid, comp in res["comps"].items():
            b = base["comps"][sid]
            for attr in ("sunlight", "earth"):
                for edge in (0, 1):  # 0 = visibility returns (interval start), 1 = obstruction begins (interval end)
                    base_t = sorted(r[edge] for r in getattr(b, attr))
                    var_t = sorted(r[edge] for r in getattr(comp, attr))
                    for t in base_t:
                        if t in (s0.start, s0.end):
                            continue  # period boundaries are not transitions
                        cand = [x for x in var_t if x not in (settings.start, settings.end)]
                        nearest = min(cand, key=lambda x: abs((x - t).total_seconds())) if cand else None
                        if nearest is None or abs((nearest - t).total_seconds()) > 12 * 3600:
                            unmatched += 1
                            continue
                        shift = (nearest - t).total_seconds() / 60.0
                        shifts.append(abs(shift))
                        if largest is None or abs(shift) > abs(largest["shiftMin"]):
                            largest = {"site": sid, "condition": attr, "kind": "returns" if edge == 0 else "obstructed",
                                       "baseline": iso(t), "variant": iso(nearest), "shiftMin": _r(shift, 1)}
        statuses = {key: iv.evaluate(res["data"][sid], sid, parse_utc(start), hours).overall
                    for key, sid, start, hours in scen if sid in res["data"]}
        out["variants"][label] = {
            "maxTransitionShiftMin": _r(max(shifts), 1) if shifts else 0.0,
            "medianTransitionShiftMin": _r(float(np.median(shifts)), 1) if shifts else 0.0,
            "transitionsWithoutCounterpart": unmatched,
            "largestShift": largest,
            "scenarioStatus": statuses,
            "statusChanges": {k: f"{out['baseline'][k]} → {v}" for k, v in statuses.items() if out["baseline"].get(k) != v},
        }
    return out


# ---------------------------------------------------------------------------------------------- report

def run_all(config: str, scenario: str, out_dir: str, spice=None, sections: Optional[list] = None,
            use_network: bool = True, pgda_step_hours: float = 1.0) -> dict:
    if spice is None:
        import spiceypy as spice
    ctx = load_context(config, scenario, spice)
    sections = sections or ["horizon", "pgda69", "cases", "decisions", "rescue", "sensitivity"]
    result: dict = {"generatedAt": iso(dt.datetime.now(dt.timezone.utc)), "scenario": os.path.basename(scenario),
                    "period": ctx.scenario.get("period"), "kernels": ctx.cfg["kernels"],
                    "layers": [{"name": L.name, "resolutionM": _r(L.resolution_m, 1)} for L in ctx.layers],
                    "observerHeightM": ctx.settings.observer_height_m, "azimuthStepDeg": ctx.settings.azimuth_step_deg,
                    "maxDistanceM": ctx.settings.max_distance_m,
                    "sites": [{"id": x["id"], "name": x.get("name"), "latitude": x["latitude"], "longitude": x["longitude"],
                               "coordinateSource": x.get("coordinateSource")} for x in ctx.sites]}
    for name in sections:
        print(f"[validate-science] {name} …", flush=True)
        if name == "horizon":
            result["horizon"] = horizon_section(ctx)
        elif name == "pgda69":
            result["pgda69"] = pgda69_section(spice, ctx, step_hours=pgda_step_hours) if use_network else {"skipped": "network disabled"}
        elif name == "cases":
            result["cases"] = cases_section(spice, ctx, use_horizons=use_network)
        elif name == "decisions":
            result["decisions"] = decisions_section(spice, ctx)
        elif name == "rescue":
            result["rescue"] = rescue_section(ctx)
        elif name == "sensitivity":
            result["sensitivity"] = sensitivity_section(spice, ctx)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "validation_results.json"), "w") as f:
        json.dump(result, f, indent=2, default=str)
    with open(os.path.join(out_dir, "validation_results.md"), "w") as f:
        f.write(format_markdown(result))
    return result


def format_markdown(r: dict) -> str:
    L = [f"# LUNAVI scientific validation results", "",
         f"Generated {r['generatedAt']} from `{r['scenario']}`; period {r.get('period')}.",
         f"Observer {r['observerHeightM']} m; horizon rays every {r['azimuthStepDeg']}° to {r['maxDistanceM'] / 1000:g} km.",
         "", "Sites: " + "; ".join(f"{s['name']} ({s['latitude']}, {s['longitude']})" for s in r["sites"]), ""]
    if "horizon" in r:
        L += ["## 1. Terrain horizon: app (ray marching) vs independent (all DEM cells)", "",
              "| Site | Exported = recomputed (max Δ°) | Band | Rays | Mean Δ° | p95 abs Δ° | Max abs Δ° | Ray above cells >0.05° |",
              "|---|---|---|---|---|---|---|---|"]
        for sid, e in r["horizon"]["sites"].items():
            for band in ("nearFieldTile", "allLayersFarField"):
                c = e[band]
                L.append(f"| {sid} | {e.get('exportedVsRecomputedMaxAbsDeg')} | {band} ≥{c['fromDistanceM']} m, {c['azimuthStepDeg']}° | {c.get('rays')} | "
                         f"{c.get('meanDiffDeg')} | {c.get('p95AbsDiffDeg')} | {c.get('maxAbsDiffDeg')} | {c.get('rayAboveIndependentBy>0.05deg')} |")
            L.append(f"| {sid} | | horizon set by | {e['horizonSetBy']} | | | | |")
        L.append("")
    if "pgda69" in r and "sites" in r["pgda69"]:
        L += ["## 2. 18.6-year averages vs NASA PGDA product 69 (60 m/px)", "",
              "| Site | Quantity | PGDA 69 centre (3×3 range) | LUNAVI h=0 m disc fraction | LUNAVI h=0 m centre above | LUNAVI h=2 m disc fraction |",
              "|---|---|---|---|---|---|"]
        for sid, e in r["pgda69"]["sites"].items():
            for q in ("sun", "earth"):
                p = e.get(f"pgda69_{q}", {})
                ref = p.get("error") or f"{p.get('centre')} ({p.get('min3x3')}–{p.get('max3x3')})"
                h0 = next((v for k, v in e.items() if k.startswith("lunavi_h0")), {}).get(q, {})
                h2 = next((v for k, v in e.items() if k.startswith("lunavi_h") and not k.startswith("lunavi_h0m")), {}).get(q, {})
                L.append(f"| {sid} | {q} | {ref} | {h0.get('meanDiscFraction')} | {h0.get('fractionCentreAbove')} | {h2.get('meanDiscFraction')} |")
        L.append("")
    if "cases" in r:
        L += ["## 3. Visibility cases", "",
              "| Site | Case | UTC | Az° | El° | Horizon app° | Horizon indep.° | Clearance app° | State app / indep. / stored | ΔHorizons az, el (°) | Conclusion |",
              "|---|---|---|---|---|---|---|---|---|---|---|"]
        for sid, e in r["cases"]["sites"].items():
            for c in e.get("cases", []):
                L.append(f"| {sid} | {c['case']} | {c.get('utc', '')} | {c.get('azimuthDeg', '')} | {c.get('elevationDeg', '')} | "
                         f"{c.get('horizonAppDeg', '')} | {c.get('horizonIndependentDeg', '')} | {c.get('clearanceAppDeg', '')} | "
                         f"{c.get('stateApp', '')} / {c.get('stateIndependentHorizon', '')} / {c.get('stateStoredIntervals', '')} | "
                         f"{c.get('horizonsDeltaAzDeg', '')}, {c.get('horizonsDeltaElDeg', '')} | {c.get('conclusion', c.get('result', ''))} |")
        L.append("")
    if "decisions" in r:
        L += ["## 4. Mission decisions: app intervals vs independent 60 s recomputation", "", f"D: {r['decisions']['D_source']}", "",
              "| Scenario | Site, start, h | App: overall (sun, earth) | Independent: overall (sun, earth) | First obstruction app | Δ independent−app (s) | Agree |",
              "|---|---|---|---|---|---|---|"]
        for k, e in r["decisions"]["scenarios"].items():
            if "error" in e:
                L.append(f"| {k} | {e['error']} | | | | | |")
                continue
            a, i = e["app"], e["independent60s"]
            fo = a["sunlight"]["firstObstruction"] or a["earthLineOfSight"]["firstObstruction"]
            L.append(f"| {k} | {e['site']}, {e['start']}, {e['hours']} | {a['overall']} ({a['sunlight']['status']}, {a['earthLineOfSight']['status']}) | "
                     f"{i['overall']} ({i['sunlight']['status']}, {i['earthLineOfSight']['status']}) | {fo} | "
                     f"{e['firstObstructionDiffS (independent − app, 60 s grid)']} | {e['statusAgrees']} |")
        L.append("")
    if "rescue" in r:
        L += ["## 5. Mission Rescue vs brute force", "", "```", json.dumps(r["rescue"], indent=2, default=str), "```", ""]
    if "sensitivity" in r:
        L += ["## 6. Sensitivity", "", f"Baseline statuses: {r['sensitivity']['baseline']}", "",
              "| Variant | Max transition shift (min) | Median (min) | Unmatched transitions | Largest shift | Status changes |", "|---|---|---|---|---|---|"]
        for k, v in r["sensitivity"]["variants"].items():
            if "error" in v:
                L.append(f"| {k} | error: {v['error']} | | | | |")
                continue
            g = v.get("largestShift") or {}
            detail = f"{g.get('site')} {g.get('condition')} {g.get('kind')} {g.get('baseline')} → {g.get('variant')}" if g else ""
            L.append(f"| {k} | {v['maxTransitionShiftMin']} | {v['medianTransitionShiftMin']} | {v['transitionsWithoutCounterpart']} | {detail} | "
                     f"{v['statusChanges'] or 'none'} |")
        L.append("")
    return "\n".join(L)
