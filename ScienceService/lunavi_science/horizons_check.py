"""Independent ephemeris check against the JPL Horizons API (https://ssd-api.jpl.nasa.gov/doc/horizons.html).

For each computed site, requests apparent azimuth/elevation (observer quantity 4) of the Sun (10) and
Earth (399) from a topocentric site on the Moon and compares them with SPICE values at the same UTC
instants. This validates ephemeris geometry only — not the terrain horizon.

Notes:
* The site is given as CENTER='coord@301' with SITE_COORD 'E-lon,lat,alt_km' (COORD_TYPE=GEODETIC).
  The API page documents 'coord' + SITE_COORD; confirm the '@301' body suffix in the Horizons manual
  if the request is rejected.
* Input errors may return HTTP 200 with an 'error' field; this module checks for it.
* Requests are sent one at a time.
"""
from __future__ import annotations

import datetime as dt
import json
import ssl
import time
import urllib.parse
import urllib.request

import numpy as np

from .ephemeris import site_vector_km, target_azel
from .timeutil import UTC, iso, parse_utc, utc_to_et

API = "https://ssd.jpl.nasa.gov/api/horizons.api"
TARGET_IDS = {"SUN": "10", "EARTH": "399"}


def _quote(value: str) -> str:
    return f"'{value}'"


def _ssl_context() -> ssl.SSLContext:
    """Uses the operating system's certificate store (macOS Keychain) when `truststore` is installed.

    Networks that inspect HTTPS (university or company proxies, some antivirus tools) add their own
    certificate, which the Keychain trusts but Python's bundled list does not.
    """
    try:
        import truststore
        return truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    except ImportError:
        return ssl.create_default_context()


def query_azel(lat_deg: float, lon_deg: float, alt_km: float, target: str, start: dt.datetime, stop: dt.datetime, step: str = "6h"):
    params = {
        "format": "json",
        "COMMAND": _quote(TARGET_IDS[target]),
        "OBJ_DATA": _quote("NO"),
        "MAKE_EPHEM": _quote("YES"),
        "EPHEM_TYPE": _quote("OBSERVER"),
        "CENTER": _quote("coord@301"),
        "COORD_TYPE": _quote("GEODETIC"),
        "SITE_COORD": _quote(f"{lon_deg % 360:.6f},{lat_deg:.6f},{alt_km:.6f}"),
        "START_TIME": _quote(start.strftime("%Y-%m-%d %H:%M")),
        "STOP_TIME": _quote(stop.strftime("%Y-%m-%d %H:%M")),
        "STEP_SIZE": _quote(step),
        "QUANTITIES": _quote("4"),
        "ANG_FORMAT": _quote("DEG"),
        "CSV_FORMAT": _quote("YES"),
        "EXTRA_PREC": _quote("YES"),
        "TIME_TYPE": _quote("UT"),
    }
    url = API + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=60, context=_ssl_context()) as response:
        payload = json.load(response)
    if "error" in payload:
        raise RuntimeError(f"Horizons error: {payload['error']}")
    return parse_observer_csv(payload.get("result", ""))


def _parse_horizons_time(text: str) -> dt.datetime:
    for fmt in ("%Y-%b-%d %H:%M", "%Y-%b-%d %H:%M:%S", "%Y-%b-%d %H:%M:%S.%f"):
        try:
            return dt.datetime.strptime(text.strip(), fmt).replace(tzinfo=UTC)
        except ValueError:
            continue
    raise RuntimeError(f"Unrecognised Horizons time '{text}'")


def parse_observer_csv(result: str) -> list[tuple[dt.datetime, float, float]]:
    if "$$SOE" not in result:
        raise RuntimeError("Horizons result has no ephemeris table ($$SOE missing)")
    rows = []
    for line in result.split("$$SOE", 1)[1].split("$$EOE", 1)[0].strip().splitlines():
        fields = [f.strip() for f in line.split(",")]
        moment = _parse_horizons_time(fields[0])
        numbers = []
        for f in fields[1:]:
            try:
                numbers.append(float(f))
            except ValueError:
                continue
        if len(numbers) >= 2:
            rows.append((moment, numbers[0], numbers[1]))
    return rows


def compare_site(spice, site: dict, surface_height_m: float, observer_height_m: float, start: dt.datetime, stop: dt.datetime, step: str = "6h") -> dict:
    radius_km = 1737.4 + (surface_height_m + observer_height_m) / 1000.0
    position = site_vector_km(site["latitude"], site["longitude"], radius_km)
    report = {}
    for target in ("SUN", "EARTH"):
        rows = query_azel(site["latitude"], site["longitude"], (surface_height_m + observer_height_m) / 1000.0, target, start, stop, step)
        ets = [utc_to_et(t, spice) for t, _, _ in rows]
        az, el, _ = target_azel(spice, target, ets, position)
        d_az = (np.array([r[1] for r in rows]) - az + 180.0) % 360.0 - 180.0
        d_el = np.array([r[2] for r in rows]) - el
        report[target] = {"samples": len(rows), "maxAbsAzimuthDeg": float(np.max(np.abs(d_az))), "maxAbsElevationDeg": float(np.max(np.abs(d_el)))}
        time.sleep(1.0)
    return report


def run(spice, scenario_path: str, tolerance_deg: float = 0.05, step: str = "6h") -> dict:
    """Compares every computed site and records an 'ephemeris' ValidationRecord in the scenario file.

    The default tolerance (0.05°) allows for differences between Horizons' lunar body-fixed model and
    MOON_ME; tighten it once the frame used by Horizons for 'coord@301' is confirmed.
    """
    with open(scenario_path) as f:
        scenario = json.load(f)
    observer = scenario["metadata"].get("observerHeightMeters") or 0.0
    start, stop = parse_utc(scenario["period"]["start"]), parse_utc(scenario["period"]["end"])
    results = {}
    for site in scenario["sites"]:
        if not site.get("coordinate") or site.get("kind") != "computed":
            continue
        coord = {"latitude": site["coordinate"]["latitude"], "longitude": site["coordinate"]["longitude"]}
        results[site["id"]] = compare_site(spice, coord, float(site.get("surfaceHeightM", 0.0)), observer, start, stop, step)
    if not results:
        raise RuntimeError("No computed sites with coordinates to check.")

    worst_el = max(r[t]["maxAbsElevationDeg"] for r in results.values() for t in r)
    worst_az = max(r[t]["maxAbsAzimuthDeg"] for r in results.values() for t in r)
    samples = sum(r[t]["samples"] for r in results.values() for t in r)
    passed = worst_el <= tolerance_deg
    record = {
        "id": "ephemeris",
        "component": "Ephemeris (Sun/Earth directions)",
        "level": "ephemerisChecked" if passed else "notValidated",
        "detail": (f"JPL Horizons comparison on {iso(dt.datetime.now(UTC))}: max |Δelevation| {worst_el:.4f}°, "
                   f"max |Δazimuth| {worst_az:.4f}° over {samples} samples; tolerance {tolerance_deg}° "
                   f"({'passed' if passed else 'not met'}). Checks directions only, not the terrain horizon."),
    }
    scenario["metadata"]["validation"] = [v for v in scenario["metadata"]["validation"] if v.get("id") != "ephemeris"] + [record]
    with open(scenario_path, "w") as f:
        json.dump(scenario, f, indent=2, ensure_ascii=False)
    return {"sites": results, "record": record}
