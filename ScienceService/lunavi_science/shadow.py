"""Shadow analysis readings from an exported scenario (schema 2 "geometry" blocks).

Mirrors the app's ShadowAnalysisService so results can be reproduced from the command line:

    python -m lunavi_science shadow --scenario ../Lunavi/Resources/ComputedScenario.json
    python -m lunavi_science shadow --scenario ... --site pgda78-site01 --time 2026-11-29T15:00:00Z

Rules (identical in Swift):
* Target directions are linearly interpolated only *between* two exported samples; outside the
  sampled period the reading is unavailable. Azimuth interpolation takes the short way round 360°.
* The terrain horizon at an azimuth is interpolated between the two neighbouring horizon rays with
  360° wraparound, and is unavailable if either ray left the DEM before the maximum distance.
* Disc fraction is the visible fraction of the target's disc above (horizon + minimum clearance).
* The requirement state (visible / obstructed / unknown) always comes from the exported intervals,
  which were bisected to ±30 s, never from the interpolated geometry.
"""
from __future__ import annotations

import datetime as dt
import math
from typing import Optional

from .timeutil import iso, parse_utc

TARGET_KEYS = {"sunlight": "sun", "earthLineOfSight": "earth"}


def disc_fraction(elevation: float, horizon: float, radius: float, clearance: float = 0.0) -> float:
    if radius <= 0:
        return 1.0 if elevation >= horizon + clearance else 0.0
    d = max(-1.0, min(1.0, (elevation - (horizon + clearance)) / radius))
    return (math.acos(-d) + d * math.sqrt(1.0 - d * d)) / math.pi


def disc_state(fraction: float) -> str:
    if fraction >= 0.999:
        return "fullyVisible"
    if fraction <= 0.001:
        return "obstructed"
    return "partiallyVisible"


def horizon_at(geometry: dict, azimuth: float) -> Optional[float]:
    h = geometry["horizon"]
    step, values, complete = h["azimuthStepDeg"], h["elevationsDeg"], h["complete"]
    n = len(values)
    position = (azimuth % 360.0) / step
    lower = int(math.floor(position)) % n
    upper = (lower + 1) % n
    if not (complete[lower] and complete[upper]):
        return None
    t = position - math.floor(position)
    return values[lower] + (values[upper] - values[lower]) * t


def target_at(geometry: dict, target: str, moment: dt.datetime) -> Optional[dict]:
    samples = geometry["samples"]
    start, step, count = parse_utc(samples["start"]), samples["stepSeconds"], samples["count"]
    offset = (moment - start).total_seconds() / step
    if offset < 0 or offset > count - 1:
        return None
    i = min(int(math.floor(offset)), count - 2) if count > 1 else 0
    t = offset - i
    track = samples[TARGET_KEYS[target]]
    if count == 1:
        return {"azimuthDeg": track["azimuthDeg"][0], "elevationDeg": track["elevationDeg"][0], "angularRadiusDeg": track["angularRadiusDeg"][0]}
    a0, a1 = track["azimuthDeg"][i], track["azimuthDeg"][i + 1]
    delta = (a1 - a0 + 180.0) % 360.0 - 180.0
    lerp = lambda key: track[key][i] + (track[key][i + 1] - track[key][i]) * t
    return {"azimuthDeg": (a0 + delta * t) % 360.0, "elevationDeg": lerp("elevationDeg"), "angularRadiusDeg": lerp("angularRadiusDeg")}


def interval_state(visibility: dict, condition: str, moment: dt.datetime) -> str:
    inside = lambda ranges: any(parse_utc(r["start"]) <= moment < parse_utc(r["end"]) for r in ranges)
    if not inside(visibility["coverage"]):
        return "unknown"
    return "visible" if inside(visibility[condition]) else "obstructed"


def reading(scenario: dict, site_id: str, condition: str, moment: dt.datetime) -> dict:
    geometry = next((g for g in scenario.get("geometry") or [] if g["siteID"] == site_id), None)
    visibility = next((v for v in scenario["visibility"] if v["siteID"] == site_id), None)
    out = {"siteID": site_id, "condition": condition, "time": iso(moment),
           "requirementState": interval_state(visibility, condition, moment) if visibility else "unknown"}
    if geometry is None:
        return {**out, "available": False, "reason": "No exported geometry for this site."}
    direction = target_at(geometry, condition, moment)
    if direction is None:
        return {**out, "available": False, "reason": "Time is outside the sampled period."}
    horizon = horizon_at(geometry, direction["azimuthDeg"])
    out.update(available=True, **direction, aboveIdealHorizon=direction["elevationDeg"] > 0.0)
    if horizon is None:
        return {**out, "terrainHorizonDeg": None, "reason": "Horizon sector not fully covered by the DEM."}
    clearance = direction["elevationDeg"] - horizon
    fraction = disc_fraction(direction["elevationDeg"], horizon, direction["angularRadiusDeg"], geometry["minimumClearanceDeg"])
    return {**out, "terrainHorizonDeg": horizon, "clearanceDeg": clearance, "discFraction": fraction, "discState": disc_state(fraction)}


def obstruction_example(scenario: dict) -> Optional[dict]:
    """The first computed sunlight transition at a site with geometry, with readings around it.

    Prefers an obstruction that begins; otherwise uses one that ends (the Sun emerging from terrain).
    """
    with_geometry = {g["siteID"] for g in scenario.get("geometry") or []}
    for kind in ("obstructionBegins", "visibilityReturns"):
        for entry in scenario["visibility"]:
            if entry["siteID"] not in with_geometry:
                continue
            for event in entry["events"]:
                if event["condition"] != "sunlight" or event["kind"] != kind:
                    continue
                moment = parse_utc(event["time"])
                times = [moment - dt.timedelta(hours=1), moment - dt.timedelta(seconds=60), moment, moment + dt.timedelta(hours=1)]
                return {"siteID": entry["siteID"], "event": event,
                        "readings": [reading(scenario, entry["siteID"], "sunlight", t) for t in times]}
    return None


def closest_approach(scenario: dict) -> list[dict]:
    """Per site, the sample where the Sun comes closest to the terrain (lowest clearance)."""
    out = []
    for g in scenario.get("geometry") or []:
        samples = g["samples"]
        start, step = parse_utc(samples["start"]), samples["stepSeconds"]
        best = None
        for i in range(samples["count"]):
            moment = start + dt.timedelta(seconds=i * step)
            r = reading(scenario, g["siteID"], "sunlight", moment)
            if r.get("clearanceDeg") is not None and (best is None or r["clearanceDeg"] < best["clearanceDeg"]):
                best = r
        if best:
            out.append(best)
    return out


def format_reading(r: dict) -> str:
    if not r.get("available"):
        return f"{r['time']}  requirement={r['requirementState']:<10}  geometry unavailable: {r['reason']}"
    if r.get("terrainHorizonDeg") is None:
        return (f"{r['time']}  az {r['azimuthDeg']:7.3f}°  el {r['elevationDeg']:+.3f}°  horizon unavailable  "
                f"requirement={r['requirementState']}")
    return (f"{r['time']}  az {r['azimuthDeg']:7.3f}°  el {r['elevationDeg']:+.3f}°  horizon {r['terrainHorizonDeg']:+.3f}°  "
            f"clearance {r['clearanceDeg']:+.3f}°  disc {r['discFraction'] * 100:5.1f}% ({r['discState']})  "
            f"requirement={r['requirementState']}")
