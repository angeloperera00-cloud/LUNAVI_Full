"""Builds ComputedScenario.json (and a basemap) for the LUNAVI app from real NASA inputs.

Inputs (see config/sites.example.json):
* SPICE kernels (LSK, PCK, planetary SPK, lunar binary PCK + frame kernel)
* LOLA DEM layers (PGDA 78 near field first, PGDA 90 far field second)
* Site coordinates from a citable source (never guessed)

Outputs in --out:
* ComputedScenario.json — same schema as the app's ComputedScenarioFile
* computed_south_pole_basemap.jpg — LOLA-derived shaded relief (or a cropped hillshade product)
Copy both into Lunavi/Resources/; the app then uses them instead of the simulated fixture.
"""
from __future__ import annotations

import datetime as dt
import json
import os
from dataclasses import dataclass, field
from typing import Optional

import numpy as np

from . import SCHEMA_VERSION, __version__
from . import intervals as iv
from .basemap import render_basemap
from .coverage import check_kernel_coverage, check_terrain
from .terrain import site_terrain
from .dem import LUNAR_RADIUS_M, DemLayer, DemSampler, crs_name, make_to_xy, read_crs_wkt
from .ephemeris import EARTH_RADIUS_KM, SUN_RADIUS_KM, angular_radius_deg, load_kernels, site_vector_km, target_azel
from .horizon import HorizonMask, compute_horizon
from .schema import validate_scenario
from .timeutil import has_leapseconds_kernel, iso, parse_utc, time_grid, utc_to_et
from .visibility import earth_visible, intervals_from_samples, sun_visible

TARGETS = {"sunlight": "SUN", "earthLineOfSight": "EARTH"}
RADII = {"sunlight": SUN_RADIUS_KM, "earthLineOfSight": EARTH_RADIUS_KM}
BASEMAP_NAME = "computed_south_pole_basemap"


@dataclass
class Settings:
    start: dt.datetime
    end: dt.datetime
    step_s: float
    observer_height_m: float = 2.0
    min_clearance_deg: float = 0.0
    sun_min_fraction: float = 0.5
    max_distance_m: float = 150_000.0
    azimuth_step_deg: float = 0.5
    near_step_m: float = 10.0
    duration_h: int = 24
    delay_h: int = 6
    duration_options: list = field(default_factory=lambda: [6, 12, 24, 48])
    sensitivity_heights: list = field(default_factory=lambda: [10.0])
    sensitivity_clearances: list = field(default_factory=lambda: [0.5])
    terrain_radius_m: float = 25.0


def settings_from_config(cfg: dict) -> Settings:
    period, model, mission = cfg["period"], cfg.get("model", {}), cfg.get("mission", {})
    return Settings(
        start=parse_utc(period["start"]),
        end=parse_utc(period["end"]),
        step_s=float(period.get("stepSeconds", 600)),
        observer_height_m=float(model.get("observerHeightM", 2.0)),
        min_clearance_deg=float(model.get("minimumClearanceDeg", 0.0)),
        sun_min_fraction=float(model.get("sunMinFraction", 0.5)),
        max_distance_m=float(model.get("maxDistanceM", 150_000.0)),
        azimuth_step_deg=float(model.get("azimuthStepDeg", 0.5)),
        near_step_m=float(model.get("nearStepM", 10.0)),
        duration_h=int(mission.get("durationHours", 24)),
        delay_h=int(mission.get("delayHours", 6)),
        duration_options=[int(v) for v in mission.get("durationOptions", [6, 12, 24, 48])],
        sensitivity_heights=[float(v) for v in model.get("sensitivityObserverHeightsM", [10.0])],
        sensitivity_clearances=[float(v) for v in model.get("sensitivityClearancesDeg", [0.5])],
        terrain_radius_m=float(model.get("terrainRadiusM", 25.0)),
    )


@dataclass
class SiteComputation:
    config: dict
    horizon: HorizonMask
    coverage: list
    sunlight: list
    earth: list
    events: list
    samples: dict = field(default_factory=dict)  # condition -> {"az","el","radius"} on the sampling grid

    @property
    def site_id(self) -> str:
        return self.config["id"]

    def site_data(self) -> iv.SiteData:
        return iv.SiteData(self.site_id, self.coverage, self.sunlight, self.earth, self.events)


def compute_site(spice, sampler, site: dict, s: Settings, times: list, ets: list,
                 observer_height_m: Optional[float] = None, clearance_deg: Optional[float] = None,
                 horizon: Optional[HorizonMask] = None) -> SiteComputation:
    lat, lon = float(site["latitude"]), float(site["longitude"])
    height = s.observer_height_m if observer_height_m is None else observer_height_m
    clearance = s.min_clearance_deg if clearance_deg is None else clearance_deg
    if horizon is None:
        horizon = compute_horizon(sampler, lat, lon, height, s.azimuth_step_deg, s.max_distance_m, s.near_step_m)
    radius_km = (LUNAR_RADIUS_M + horizon.surface_height_m + height) / 1000.0
    position = site_vector_km(lat, lon, radius_km)

    def visible(condition: str, az, el, distance):
        radius = angular_radius_deg(RADII[condition], distance)
        if condition == "sunlight":
            return sun_visible(el, horizon.at(az), radius, s.sun_min_fraction, clearance)
        return earth_visible(el, horizon.at(az), radius, clearance)

    def state_at(condition: str, moment: dt.datetime) -> bool:
        az, el, distance = target_azel(spice, TARGETS[condition], [utc_to_et(moment, spice)], position)
        return bool(visible(condition, az, el, distance)[0])

    def geometry(condition: str, moment: dt.datetime) -> dict:
        az, el, _ = target_azel(spice, TARGETS[condition], [utc_to_et(moment, spice)], position)
        hz = float(horizon.at(az)[0])
        return {"targetAzimuthDeg": round(float(az[0]), 4), "targetElevationDeg": round(float(el[0]), 4),
                "horizonElevationDeg": round(hz, 4), "clearanceDeg": round(float(el[0]) - hz, 4)}

    results, samples, complete = {}, {}, np.ones(len(times), dtype=bool)
    for condition, target in TARGETS.items():
        az, el, distance = target_azel(spice, target, ets, position)
        samples[condition] = {"az": az, "el": el, "radius": angular_radius_deg(RADII[condition], distance)}
        complete &= horizon.is_complete(az)
        flags = visible(condition, az, el, distance)
        results[condition] = intervals_from_samples(times, flags, lambda moment, c=condition: state_at(c, moment))
    coverage = intervals_from_samples(times, complete)

    events = []
    for condition, ranges in results.items():
        label = "Sun" if condition == "sunlight" else "Earth"
        for start, end in ranges:
            for kind, moment in (("visibilityReturns", start), ("obstructionBegins", end)):
                if moment <= times[0] or moment >= times[-1]:
                    continue  # period boundaries are not physical transitions
                g = geometry(condition, moment)
                verb = "rises above" if kind == "visibilityReturns" else "drops below"
                events.append({
                    "id": f"{site['id']}-{condition}-{kind}-{iso(moment)}",
                    "condition": condition,
                    "kind": kind,
                    "time": iso(moment),
                    "summary": (f"Computed: the {label} {verb} the modeled terrain horizon at azimuth "
                                f"{g['targetAzimuthDeg']:.1f}° (horizon {g['horizonElevationDeg']:.2f}°, "
                                f"{label} elevation {g['targetElevationDeg']:.2f}°)."),
                    "geometry": g,
                })
    events.sort(key=lambda e: e["time"])
    return SiteComputation(site, horizon, coverage, results["sunlight"], results["earthLineOfSight"], events, samples)


def geometry_json(c: SiteComputation, s: Settings, times: list) -> dict:
    """Exports the exact inputs of the visibility flags: the horizon mask and the sampled target directions.

    Same observer (site, DEM surface + observer height), same MOON_ME azimuth convention (clockwise from
    local north) and same sampling grid as the intervals, so the app can show *why* a state holds.
    """
    r = lambda values, n=4: [round(float(v), n) for v in values]
    step = (times[1] - times[0]).total_seconds() if len(times) > 1 else s.step_s
    return {
        "siteID": c.site_id,
        "observerHeightMeters": float(c.horizon.observer_height_m),
        "surfaceHeightMeters": round(float(c.horizon.surface_height_m), 2),
        "sunMinimumDiscFraction": s.sun_min_fraction,
        "minimumClearanceDeg": s.min_clearance_deg,
        "horizon": {
            "azimuthStepDeg": float(c.horizon.azimuths_deg[1] - c.horizon.azimuths_deg[0]),
            "maxDistanceMeters": float(c.horizon.max_distance_m),
            "elevationsDeg": r(c.horizon.elevations_deg),
            "complete": [bool(v) for v in c.horizon.complete],
        },
        "samples": {
            "start": iso(times[0]),
            "stepSeconds": step,
            "count": len(times),
            "sun": {"azimuthDeg": r(c.samples["sunlight"]["az"]), "elevationDeg": r(c.samples["sunlight"]["el"]),
                    "angularRadiusDeg": r(c.samples["sunlight"]["radius"], 5)},
            "earth": {"azimuthDeg": r(c.samples["earthLineOfSight"]["az"]), "elevationDeg": r(c.samples["earthLineOfSight"]["el"]),
                      "angularRadiusDeg": r(c.samples["earthLineOfSight"]["radius"], 5)},
        },
    }


def _site_stub(c: SiteComputation) -> dict:
    return {"id": c.site_id, "coordinate": {"latitude": c.config["latitude"], "longitude": c.config["longitude"]}}


def find_demo_case(computations: list, s: Settings) -> Optional[tuple]:
    """First (site, whole-hour start) where the plan meets both requirements, the +delay copy fails,
    and the app's recovery search (same rules) finds at least one option."""
    sites = {c.site_id: c.site_data() for c in computations}
    stubs = [_site_stub(c) for c in computations]
    step = dt.timedelta(hours=1)
    for c in computations:
        order = iv.proximity_order(stubs, c.site_id, sites)
        for cov_start, cov_end in c.coverage:
            start = cov_start.replace(minute=0, second=0, microsecond=0)
            if start < cov_start:
                start += step
            while start + dt.timedelta(hours=s.duration_h + s.delay_h) <= cov_end:
                if iv.evaluate(sites[c.site_id], c.site_id, start, s.duration_h).overall == "met":
                    delayed_start = start + dt.timedelta(hours=s.delay_h)
                    delayed = iv.evaluate(sites[c.site_id], c.site_id, delayed_start, s.duration_h)
                    if delayed.overall == "notMet" and iv.recovery_candidates(sites, order, c.site_id, delayed_start, s.duration_h):
                        return c.site_id, start
                start += step
    return None


def _ranges(ranges: list) -> list:
    return [{"start": iso(a), "end": iso(b)} for a, b in ranges]


def _load_layers(cfg: dict, resolve, sites: list) -> list:
    lats = np.array([float(x["latitude"]) for x in sites])
    lons = np.array([float(x["longitude"]) for x in sites])
    layers = []
    for layer_cfg in cfg["dem"]["layers"]:
        if not layer_cfg.get("path"):
            raise ValueError(f"DEM layer '{layer_cfg.get('name', '?')}' has no path; see config/sites.example.json.")
        path = resolve(layer_cfg["path"])
        bounds = None
        if layer_cfg.get("boundsPaddingM") is not None:
            xs, ys = make_to_xy(read_crs_wkt(path))(lats, lons)
            pad = float(layer_cfg["boundsPaddingM"])
            bounds = (float(xs.min()) - pad, float(ys.min()) - pad, float(xs.max()) + pad, float(ys.max()) + pad)
        layers.append(DemLayer(path, bounds_xy=bounds, resolution_m=layer_cfg.get("resolutionM"),
                               name=layer_cfg.get("name"), band=int(layer_cfg.get("band", 1))))
    return layers


def apply_period_override(cfg: dict, start: Optional[str] = None, end: Optional[str] = None,
                          step_seconds: Optional[float] = None) -> dict:
    """Returns a copy of cfg with the requested period. Values are parsed (and so validated) here."""
    period = dict(cfg.get("period", {}))
    if start is not None:
        period["start"] = iso(parse_utc(start))
    if end is not None:
        period["end"] = iso(parse_utc(end))
    if step_seconds is not None:
        if step_seconds <= 0:
            raise ValueError("period step must be positive")
        period["stepSeconds"] = float(step_seconds)
    return dict(cfg, period=period)


def build(config_path: str, out_dir: str, spice=None, start: Optional[str] = None, end: Optional[str] = None,
          step_seconds: Optional[float] = None, output_name: str = "ComputedScenario") -> dict:
    """Computes a scenario for the configured (or overridden) period and writes <output_name>.json."""
    if spice is None:
        import spiceypy as spice
    if not output_name.startswith("ComputedScenario") or "/" in output_name:
        raise ValueError("output name must start with 'ComputedScenario' (the app discovers files by that prefix)")
    with open(config_path) as f:
        cfg = apply_period_override(json.load(f), start, end, step_seconds)
    base = os.path.dirname(os.path.abspath(config_path))

    def resolve(p: str) -> str:
        return p if (p.startswith("/vsi") or "://" in p or os.path.isabs(p)) else os.path.join(base, p)

    s = settings_from_config(cfg)
    for site in cfg["sites"]:
        if site.get("latitude") is None or site.get("longitude") is None or not site.get("coordinateSource"):
            raise ValueError(f"Site '{site.get('id')}' needs latitude, longitude and coordinateSource from a citable source.")
    if s.end <= s.start:
        raise ValueError("period.end must be after period.start")
    if not cfg.get("dem", {}).get("layers"):
        raise ValueError("Configure at least one DEM layer under dem.layers.")

    kernels = load_kernels(spice, [resolve(k) for k in cfg["kernels"]])
    lsk = has_leapseconds_kernel(spice)
    kernel_coverage = check_kernel_coverage(spice, kernels, s.start, s.end)
    if not kernel_coverage.ok:
        raise ValueError("The requested period is not supported by the loaded SPICE kernels:\n"
                         + "\n".join(kernel_coverage.errors))

    layer_cfgs = cfg["dem"]["layers"]
    layers = _load_layers(cfg, resolve, cfg["sites"])
    sampler = DemSampler(layers)
    terrain_errors = check_terrain(sampler, cfg["sites"])
    if terrain_errors:
        raise ValueError("Terrain data is missing:\n" + "\n".join(terrain_errors))

    times = time_grid(s.start, s.end, s.step_s)
    ets = [utc_to_et(t, spice) for t in times]

    computations = [compute_site(spice, sampler, site, s, times, ets) for site in cfg["sites"]]
    case = find_demo_case(computations, s)
    if case:
        demo_site, demo_start = case
        demo_note = ("Default plan chosen automatically: the first whole-hour start where the plan meets both "
                     "requirements, the +delay copy fails, and a recovery option exists.")
    else:
        first = computations[0]
        demo_site = first.site_id
        demo_start = first.coverage[0][0] if first.coverage else s.start
        demo_note = "No delay-failure case exists in this period; the default plan starts at the beginning of coverage."

    demo = next(c for c in computations if c.site_id == demo_site)
    baseline = (s.observer_height_m, s.min_clearance_deg)
    variants = [baseline]
    for v in [(h, s.min_clearance_deg) for h in s.sensitivity_heights] + [(s.observer_height_m, c) for c in s.sensitivity_clearances]:
        if v not in variants:
            variants.append(v)
    sensitivity = []
    for height, clearance in variants:
        if (height, clearance) == baseline:
            result, label = demo, "Baseline"
        else:
            reuse = demo.horizon if height == s.observer_height_m else None
            result = compute_site(spice, sampler, demo.config, s, times, ets, observer_height_m=height,
                                  clearance_deg=clearance, horizon=reuse)
            label = f"Observer height {height:g} m" if height != s.observer_height_m else f"Minimum clearance {clearance:g}°"
        sensitivity.append({
            "id": f"{demo_site}-h{height:g}-c{clearance:g}", "label": label, "siteID": demo_site,
            "observerHeightMeters": height, "minimumClearanceDeg": clearance, "timeStepSeconds": s.step_s,
            "coverage": _ranges(result.coverage), "sunlight": _ranges(result.sunlight), "earthLineOfSight": _ranges(result.earth),
        })

    os.makedirs(out_dir, exist_ok=True)
    basemap_cfg = cfg.get("basemap", {})
    basemap_crs = next((layer.crs_wkt for layer in reversed(layers) if layer.crs_wkt), None)
    hillshade_layer = None
    if basemap_cfg.get("hillshadePath"):
        hillshade_layer = DemLayer(resolve(basemap_cfg["hillshadePath"]), name="hillshade", band=int(basemap_cfg.get("hillshadeBand", 1)),
                                   resolution_m=basemap_cfg.get("hillshadeResolutionM"))
    basemap, positions = render_basemap(
        sampler, [(c.config["latitude"], c.config["longitude"]) for c in computations],
        os.path.join(out_dir, BASEMAP_NAME + ".jpg"), crs_wkt=basemap_crs,
        size_px=int(basemap_cfg.get("sizePx", 2048)), margin_m=float(basemap_cfg.get("marginM", 12_000)),
        hillshade_layer=hillshade_layer, layer_names=[layer.name for layer in layers])

    layer_names = ", ".join(layer.name for layer in layers)
    sites_json = []
    for c, (u, v) in zip(computations, positions):
        site = c.config
        sites_json.append({
            "id": site["id"], "name": site["name"], "shortName": site.get("shortName", site["name"]),
            "kind": "computed", "regionLabel": site.get("regionLabel", "Lunar South Pole"),
            "mapPosition": {"x": round(float(u), 5), "y": round(float(v), 5)},
            "coordinate": {"latitude": site["latitude"], "longitude": site["longitude"], "source": site["coordinateSource"]},
            "hasTerrainData": True,
            "terrainDataNote": (f"Horizon computed to {s.max_distance_m / 1000:g} km from: {layer_names}. "
                                f"DEM surface height {c.horizon.surface_height_m:.1f} m; observer {s.observer_height_m:g} m above it."),
            "sourceNote": site.get("sourceNote", site["coordinateSource"]),
            "surfaceHeightM": round(float(c.horizon.surface_height_m), 2),
        })

    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    provenance = [
        {"id": f"dem-{i}", "role": "Elevation (near field)" if i == 0 and len(layers) > 1 else "Elevation",
         "name": layer.name, "provider": "NASA GSFC Planetary Geodynamics Data Archive (LOLA)",
         "version": layer_cfgs[i].get("version", "See product page"),
         "resolution": f"{layer.resolution_m:.0f} m/pixel as read (native {layer.native_resolution_m:.0f} m)",
         "coordinateSystem": crs_name(layer.crs_wkt), "status": "Used to compute horizons",
         "link": layer_cfgs[i].get("link")}
        for i, layer in enumerate(layers)
    ] + [
        {"id": "spice", "role": "Sun and Earth geometry", "name": cfg.get("ephemerisLabel", "NAIF SPICE kernels"),
         "provider": "NASA JPL NAIF", "version": ", ".join(os.path.basename(k) for k in kernels),
         "resolution": f"{s.step_s:g} s sampling; transitions bisected to ±30 s", "coordinateSystem": "MOON_ME",
         "status": "Used to compute directions", "link": "https://naif.jpl.nasa.gov/naif/data_generic.html"},
        {"id": "basemap", "role": "Terrain imagery", "name": basemap["title"], "provider": "Rendered by the LUNAVI pipeline from the elevation data above",
         "version": iso(now), "resolution": f"{basemap['metersPerPixel']:.1f} m/pixel", "coordinateSystem": crs_name(basemap_crs),
         "status": "Bundled", "link": None},
    ]
    clearance_text = f" plus {s.min_clearance_deg:g}° clearance" if s.min_clearance_deg else ""
    metadata = {
        "id": f"lunavi-computed-{now.strftime('%Y%m%dT%H%M%SZ')}",
        "title": f"{cfg.get('missionName', 'LUNAVI analysis')} — computed visibility",
        "source": "computedBundled",
        "generatedAt": iso(now),
        "timeStepSeconds": s.step_s,
        "observerHeightMeters": s.observer_height_m,
        "minimumClearanceDeg": s.min_clearance_deg,
        "sunCriterion": (f"At least {s.sun_min_fraction:.0%} of the solar disc above the modeled terrain horizon{clearance_text}"
                         + (" (50 % = the Sun's centre above it)." if abs(s.sun_min_fraction - 0.5) < 1e-9 else ".")),
        "earthCriterion": f"Any part of Earth's disc above the modeled terrain horizon{clearance_text} (the PGDA product 69 criterion). Geometric line of sight only — not a radio-link prediction.",
        "referenceFrame": "MOON_ME (mean Earth / polar axis), the frame of the LOLA PGDA DEMs; spherical local vertical, R = 1737.4 km",
        "ephemeris": cfg.get("ephemerisLabel", "See provenance"),
        "assumptions": [
            f"Observer {s.observer_height_m:g} m above the DEM surface; horizon from rays every {s.azimuth_step_deg:g}° out to {s.max_distance_m / 1000:g} km, including lunar curvature.",
            "DEM heights are metres above the 1737.4 km reference sphere (the LOLA LDEM convention).",
            "Sun and Earth directions use LT+S aberration correction at the Moon's centre.",
            "Times when the target lies in a horizon sector without complete DEM coverage are excluded from coverage (shown as unknown).",
            "UTC to TDB through the loaded leapseconds kernel." if lsk else "UTC to TDB through the leapseconds-kernel formula with TAI-UTC = 37 s (no LSK loaded).",
            demo_note,
        ],
        "limitations": [
            "Horizon accuracy is limited by DEM resolution and interpolation (about 90 % of PGDA product 78 pixels are interpolated).",
            "Transition times are bisected to about ±30 s and displayed to the minute.",
            "Visibility is geometric only: no thermal, radio-link or landing-safety modelling. The app's solar power estimate is experimental and its terrain values are characterization only, not a hazard assessment.",
        ],
        "provenance": provenance,
        "validation": [
            {"id": "ephemeris", "component": "Ephemeris (Sun/Earth directions)", "level": "notValidated",
             "detail": "Not yet compared with JPL Horizons. Run: python -m lunavi_science horizons-check."},
            {"id": "horizon", "component": "Terrain horizon", "level": "notValidated",
             "detail": "Not yet compared with PGDA product 69 average Sun and Earth visibility."},
        ],
        "disclaimer": "Computed geometric visibility — not independently validated. Not a NASA product and not an operational planning result.",
    }
    scenario = {
        "schemaVersion": SCHEMA_VERSION,
        "generator": f"lunavi_science {__version__}",
        "period": {"start": iso(times[0]), "end": iso(times[-1]), "stepSeconds": s.step_s, "sampleCount": len(times)},
        "coverage": {
            "requestedStart": iso(s.start), "requestedEnd": iso(s.end),
            "computedStart": iso(times[0]), "computedEnd": iso(times[-1]),
            "stepSeconds": s.step_s, "sampleCount": len(times),
            "kernels": kernel_coverage.to_json(),
            "terrain": "Every site has LOLA surface data in at least one configured DEM layer.",
        },
        "mission": {"missionName": cfg.get("missionName", "LUNAVI South Pole Analysis"), "siteID": demo_site, "start": iso(demo_start),
                    "durationHours": s.duration_h, "delayHours": s.delay_h, "durationOptions": s.duration_options},
        "basemap": basemap,
        "sites": sites_json,
        "metadata": metadata,
        "visibility": [{"siteID": c.site_id, "coverage": _ranges(c.coverage), "sunlight": _ranges(c.sunlight),
                        "earthLineOfSight": _ranges(c.earth), "events": c.events} for c in computations],
        "sensitivity": sensitivity,
        "geometry": [geometry_json(c, s, times) for c in computations],
        "terrain": [site_terrain(layers, c.config, s.terrain_radius_m) for c in computations],
    }
    errors = validate_scenario(scenario)
    if errors:
        raise ValueError("Scenario failed schema validation:\n" + "\n".join(errors))
    with open(os.path.join(out_dir, output_name + ".json"), "w") as f:
        json.dump(scenario, f, indent=2, ensure_ascii=False)
    return scenario
