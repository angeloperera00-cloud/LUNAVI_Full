"""Checks a ComputedScenario dict against the app's Codable models (Swift decoding is strict)."""
from __future__ import annotations

import re

ISO = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
SOURCES = {"simulatedFixture", "computedBundled", "computedLive", "imported"}
LEVELS = {"notApplicable", "notValidated", "ephemerisChecked", "horizonCompared", "validatedAgainstReference"}
KINDS = {"illustrativeDemo", "publishedCatalog", "computed"}
CONDITIONS = {"sunlight", "earthLineOfSight"}
EVENT_KINDS = {"obstructionBegins", "visibilityReturns"}


def validate_scenario(s: dict) -> list[str]:
    errors: list[str] = []

    def need(obj, key, types, where, nullable=False):
        if not isinstance(obj, dict) or key not in obj:
            errors.append(f"{where}: missing '{key}'")
            return None
        value = obj[key]
        if value is None and nullable:
            return None
        if not isinstance(value, types) or (isinstance(value, bool) and bool not in (types if isinstance(types, tuple) else (types,))):
            errors.append(f"{where}.{key}: expected {types}, got {type(value).__name__}")
            return None
        return value

    def date(obj, key, where, nullable=False):
        value = need(obj, key, str, where, nullable)
        if value is not None and not ISO.match(value):
            errors.append(f"{where}.{key}: '{value}' is not YYYY-MM-DDTHH:MM:SSZ")
        return value

    def ranges(obj, key, where):
        items = need(obj, key, list, where) or []
        for i, r in enumerate(items):
            a, b = date(r, "start", f"{where}.{key}[{i}]"), date(r, "end", f"{where}.{key}[{i}]")
            if a and b and b <= a:
                errors.append(f"{where}.{key}[{i}]: end must be after start")

    mission = need(s, "mission", dict, "scenario") or {}
    for key, t in [("missionName", str), ("siteID", str), ("durationHours", int), ("delayHours", int), ("durationOptions", list)]:
        need(mission, key, t, "mission")
    date(mission, "start", "mission")

    basemap = need(s, "basemap", dict, "scenario") or {}
    for key, t in [("imageResource", str), ("imageExtension", str), ("isIllustrative", bool), ("title", str), ("attribution", str), ("pixelWidth", int), ("pixelHeight", int)]:
        need(basemap, key, t, "basemap")
    need(basemap, "metersPerPixel", (int, float), "basemap", nullable=True)
    need(basemap, "projection", str, "basemap", nullable=True)

    site_ids = set()
    for i, site in enumerate(need(s, "sites", list, "scenario") or []):
        where = f"sites[{i}]"
        for key, t in [("id", str), ("name", str), ("shortName", str), ("regionLabel", str), ("hasTerrainData", bool), ("terrainDataNote", str), ("sourceNote", str)]:
            need(site, key, t, where)
        if need(site, "kind", str, where) not in KINDS:
            errors.append(f"{where}.kind: invalid")
        position = need(site, "mapPosition", dict, where, nullable=True)
        if position is not None:
            need(position, "x", (int, float), f"{where}.mapPosition")
            need(position, "y", (int, float), f"{where}.mapPosition")
        coordinate = need(site, "coordinate", dict, where, nullable=True)
        if coordinate is not None:
            need(coordinate, "latitude", (int, float), f"{where}.coordinate")
            need(coordinate, "longitude", (int, float), f"{where}.coordinate")
            need(coordinate, "source", str, f"{where}.coordinate")
        site_ids.add(site.get("id"))
    if mission.get("siteID") not in site_ids:
        errors.append("mission.siteID is not in sites")

    metadata = need(s, "metadata", dict, "scenario") or {}
    for key, t in [("id", str), ("title", str), ("sunCriterion", str), ("earthCriterion", str), ("referenceFrame", str), ("ephemeris", str), ("assumptions", list), ("limitations", list), ("provenance", list), ("validation", list), ("disclaimer", str)]:
        need(metadata, key, t, "metadata")
    if metadata.get("source") not in SOURCES:
        errors.append("metadata.source: invalid")
    date(metadata, "generatedAt", "metadata", nullable=True)
    for key in ("timeStepSeconds", "observerHeightMeters", "minimumClearanceDeg"):
        need(metadata, key, (int, float), "metadata", nullable=True)
    for i, p in enumerate(metadata.get("provenance", [])):
        for key in ("id", "role", "name", "provider", "version", "resolution", "coordinateSystem", "status"):
            need(p, key, str, f"metadata.provenance[{i}]")
        need(p, "link", str, f"metadata.provenance[{i}]", nullable=True)
    for i, v in enumerate(metadata.get("validation", [])):
        for key in ("id", "component", "detail"):
            need(v, key, str, f"metadata.validation[{i}]")
        if v.get("level") not in LEVELS:
            errors.append(f"metadata.validation[{i}].level: invalid")

    for i, v in enumerate(need(s, "visibility", list, "scenario") or []):
        where = f"visibility[{i}]"
        if need(v, "siteID", str, where) not in site_ids:
            errors.append(f"{where}.siteID: unknown site")
        for key in ("coverage", "sunlight", "earthLineOfSight"):
            ranges(v, key, where)
        for j, e in enumerate(need(v, "events", list, where) or []):
            w = f"{where}.events[{j}]"
            need(e, "id", str, w)
            need(e, "summary", str, w)
            date(e, "time", w)
            if e.get("condition") not in CONDITIONS:
                errors.append(f"{w}.condition: invalid")
            if e.get("kind") not in EVENT_KINDS:
                errors.append(f"{w}.kind: invalid")
            g = need(e, "geometry", dict, w, nullable=True)
            if g is not None:
                for key in ("targetAzimuthDeg", "targetElevationDeg", "horizonElevationDeg", "clearanceDeg"):
                    need(g, key, (int, float), f"{w}.geometry")

    for i, v in enumerate(s.get("sensitivity") or []):
        where = f"sensitivity[{i}]"
        for key, t in [("id", str), ("label", str), ("siteID", str), ("observerHeightMeters", (int, float)), ("minimumClearanceDeg", (int, float)), ("timeStepSeconds", (int, float))]:
            need(v, key, t, where)
        for key in ("coverage", "sunlight", "earthLineOfSight"):
            ranges(v, key, where)
    for i, g in enumerate(s.get("geometry") or []):
        where = f"geometry[{i}]"
        if need(g, "siteID", str, where) not in site_ids:
            errors.append(f"{where}.siteID: unknown site")
        for key in ("observerHeightMeters", "surfaceHeightMeters", "sunMinimumDiscFraction", "minimumClearanceDeg"):
            need(g, key, (int, float), where)
        h = need(g, "horizon", dict, where) or {}
        need(h, "azimuthStepDeg", (int, float), f"{where}.horizon")
        need(h, "maxDistanceMeters", (int, float), f"{where}.horizon")
        elevations = need(h, "elevationsDeg", list, f"{where}.horizon") or []
        complete = need(h, "complete", list, f"{where}.horizon") or []
        step = h.get("azimuthStepDeg") or 0
        if step and len(elevations) != round(360 / step):
            errors.append(f"{where}.horizon: expected {round(360 / step)} elevations, got {len(elevations)}")
        if len(complete) != len(elevations):
            errors.append(f"{where}.horizon: 'complete' and 'elevationsDeg' lengths differ")
        smp = need(g, "samples", dict, where) or {}
        date(smp, "start", f"{where}.samples")
        need(smp, "stepSeconds", (int, float), f"{where}.samples")
        count = need(smp, "count", int, f"{where}.samples") or 0
        for target in ("sun", "earth"):
            track = need(smp, target, dict, f"{where}.samples") or {}
            for key in ("azimuthDeg", "elevationDeg", "angularRadiusDeg"):
                values = need(track, key, list, f"{where}.samples.{target}") or []
                if len(values) != count:
                    errors.append(f"{where}.samples.{target}.{key}: expected {count} values, got {len(values)}")
    return errors
