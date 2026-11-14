"""Half-open UTC interval logic — a line-by-line port of the app's VisibilityEvaluator.

Rules (identical to Swift):
* Intervals are half-open [start, end).
* A requirement is met only if visibility covers the entire window without interruption.
* Outside coverage the state is unknown and never treated as visible.
* Precedence: known obstruction > unknown > met.
"""
from __future__ import annotations

import datetime as dt
import math
from dataclasses import dataclass, field
from typing import Optional

Interval = tuple[dt.datetime, dt.datetime]


def normalized(ranges: list[Interval]) -> list[Interval]:
    merged: list[list[dt.datetime]] = []
    for start, end in sorted((r for r in ranges if r[1] > r[0]), key=lambda r: r[0]):
        if merged and start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return [(a, b) for a, b in merged]


def intersect(first: list[Interval], second: list[Interval]) -> list[Interval]:
    a, b = normalized(first), normalized(second)
    i = j = 0
    out: list[Interval] = []
    while i < len(a) and j < len(b):
        lo, hi = max(a[i][0], b[j][0]), min(a[i][1], b[j][1])
        if lo < hi:
            out.append((lo, hi))
        if a[i][1] < b[j][1]:
            i += 1
        else:
            j += 1
    return out


def clip(ranges: list[Interval], window: Interval) -> list[Interval]:
    return intersect(ranges, [window])


def complement(ranges: list[Interval], window: Interval) -> list[Interval]:
    gaps: list[Interval] = []
    cursor = window[0]
    for start, end in clip(ranges, window):
        if start > cursor:
            gaps.append((cursor, start))
        cursor = max(cursor, end)
    if cursor < window[1]:
        gaps.append((cursor, window[1]))
    return gaps


def total(ranges: list[Interval]) -> float:
    return sum((b - a).total_seconds() for a, b in normalized(ranges))


@dataclass
class SiteData:
    site_id: str
    coverage: list[Interval]
    sunlight: list[Interval]
    earth: list[Interval]
    events: list[dict] = field(default_factory=list)

    def intervals(self, condition: str) -> list[Interval]:
        return self.sunlight if condition == "sunlight" else self.earth


@dataclass
class Assessment:
    condition: str
    status: str  # met | partial | unavailable | unknown
    first_failure: Optional[dt.datetime]
    first_unknown: Optional[dt.datetime]
    visible_s: float
    obstructed_s: float
    unknown_s: float


@dataclass
class Evaluation:
    site_id: str
    window: Interval
    sunlight: Assessment
    earth: Assessment
    overall: str  # met | notMet | unknown

    @property
    def first_failure(self) -> Optional[tuple[str, dt.datetime]]:
        failures = [(a.condition, a.first_failure) for a in (self.sunlight, self.earth) if a.first_failure]
        return min(failures, key=lambda f: f[1]) if failures else None


def assess(condition: str, data: Optional[SiteData], window: Interval) -> Assessment:
    if data is None:
        return Assessment(condition, "unknown", None, window[0], 0.0, 0.0, (window[1] - window[0]).total_seconds())
    covered = clip(data.coverage, window)
    visible = intersect(clip(data.intervals(condition), window), covered)
    obstructed = intersect(complement(visible, window), covered)
    unknown = complement(covered, window)
    v, o, u = total(visible), total(obstructed), total(unknown)
    if o > 0:
        status = "partial" if v > 0 else "unavailable"
    elif u > 0:
        status = "unknown"
    else:
        status = "met"
    return Assessment(condition, status, obstructed[0][0] if obstructed else None, unknown[0][0] if unknown else None, v, o, u)


def evaluate(data: Optional[SiteData], site_id: str, start: dt.datetime, hours: float) -> Evaluation:
    window = (start, start + dt.timedelta(hours=hours))
    sun = assess("sunlight", data, window)
    earth = assess("earthLineOfSight", data, window)
    statuses = {sun.status, earth.status}
    if statuses & {"partial", "unavailable"}:
        overall = "notMet"
    elif "unknown" in statuses:
        overall = "unknown"
    else:
        overall = "met"
    return Evaluation(site_id, window, sun, earth, overall)


def combined(data: SiteData) -> list[Interval]:
    return intersect(intersect(data.sunlight, data.earth), data.coverage)


def earliest_start(data: SiteData, not_before: dt.datetime, hours: float) -> Optional[dt.datetime]:
    need = dt.timedelta(hours=hours)
    for start, end in combined(data):
        if end <= not_before:
            continue
        candidate = max(start, not_before)
        if end - candidate >= need:
            return candidate
    return None


def recovery_candidates(sites: dict[str, SiteData], order: list[str], site_id: str, start: dt.datetime, hours: float) -> list[dict]:
    """Option A (same site, later start) and option B (first other site that meets both, in `order`)."""
    out: list[dict] = []
    data = sites.get(site_id)
    if data is not None:
        later = earliest_start(data, start, hours)
        if later is not None and later > start and evaluate(data, site_id, later, hours).overall == "met":
            out.append({"kind": "sameSiteLaterTime", "siteId": site_id, "start": later, "hours": hours})
    for other in order:
        if other == site_id or other not in sites:
            continue
        if evaluate(sites[other], other, start, hours).overall == "met":
            out.append({"kind": "alternativeSite", "siteId": other, "start": start, "hours": hours})
            break
    return out


LUNAR_RADIUS_KM = 1737.4


def great_circle_km(a: dict, b: dict) -> float:
    """Haversine distance between {'latitude','longitude'} dicts (same formula as SiteGeometry in Swift)."""
    lat1, lat2 = math.radians(a["latitude"]), math.radians(b["latitude"])
    d_lat = lat2 - lat1
    d_lon = math.radians(b["longitude"] - a["longitude"])
    h = math.sin(d_lat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(d_lon / 2) ** 2
    return 2 * LUNAR_RADIUS_KM * math.asin(min(1.0, math.sqrt(h)))


def proximity_order(sites: list[dict], base_id: str, with_data) -> list[str]:
    """Other sites with data, nearest first — mirrors SiteGeometry.proximity in the app."""
    base = next((s for s in sites if s["id"] == base_id), None)

    def key(other: dict) -> float:
        if base is None:
            return math.inf
        if base.get("coordinate") and other.get("coordinate"):
            return great_circle_km(base["coordinate"], other["coordinate"])
        if base.get("mapPosition") and other.get("mapPosition"):
            p, q = base["mapPosition"], other["mapPosition"]
            return math.hypot(p["x"] - q["x"], p["y"] - q["y"]) * 1000
        return math.inf

    return [s["id"] for s in sorted((s for s in sites if s["id"] != base_id and s["id"] in with_data), key=key)]


def site_data_from_json(entry: dict, parse) -> SiteData:
    def ranges(key: str) -> list[Interval]:
        return [(parse(r["start"]), parse(r["end"])) for r in entry.get(key, [])]
    return SiteData(entry["siteID"], ranges("coverage"), ranges("sunlight"), ranges("earthLineOfSight"), entry.get("events", []))
