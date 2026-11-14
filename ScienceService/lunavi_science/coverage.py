"""Checks that a requested computation period is supported by every input before anything is computed.

* SPICE: every binary SPK must provide the Sun, Earth, Earth-Moon barycentre and Moon over the whole
  period, and the lunar binary PCK must cover the MOON_PA frame over the period. Text kernels (FK,
  text PCK, LSK) have no time span; the LSK only knows leap seconds announced before it was issued,
  which is reported as a warning (it shifts UTC-TDB by at most one second per unannounced leap second).
* Terrain: every site must lie inside the DEM layers (a NaN surface height means no data).

Nothing is extrapolated: a period outside kernel coverage is refused, not clamped.
"""
from __future__ import annotations

import datetime as dt
import math
import os
from dataclasses import dataclass, field

from .timeutil import iso, utc_to_et

# NAIF IDs needed for Sun and Earth directions as seen from the Moon.
REQUIRED_SPK_BODIES = {10: "Sun", 3: "Earth-Moon barycentre", 399: "Earth", 301: "Moon"}
# Frame class IDs of the lunar principal-axes orientation in the binary PCKs LUNAVI supports.
LUNAR_PCK_FRAMES = {31006: "MOON_PA_DE421", 31008: "MOON_PA_DE440"}
# Last leap second known to naif0012.tls (TAI-UTC = 37 s from this instant).
LAST_KNOWN_LEAP_SECOND = dt.datetime(2017, 1, 1, tzinfo=dt.timezone.utc)


@dataclass
class KernelCoverage:
    file: str
    kind: str
    covers_period: bool
    spans: dict = field(default_factory=dict)  # name -> (start ISO, end ISO) of the covering interval, or None

    def to_json(self) -> dict:
        return {"file": self.file, "kind": self.kind, "coversPeriod": self.covers_period,
                "spans": {name: (None if span is None else {"start": span[0], "end": span[1]}) for name, span in self.spans.items()}}


@dataclass
class CoverageReport:
    start: dt.datetime
    end: dt.datetime
    kernels: list = field(default_factory=list)
    errors: list = field(default_factory=list)
    warnings: list = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors

    def to_json(self) -> dict:
        return {"start": iso(self.start), "end": iso(self.end), "ok": self.ok,
                "kernels": [k.to_json() for k in self.kernels], "errors": self.errors, "warnings": self.warnings}


def _window_intervals(spice, window) -> list[tuple[float, float]]:
    return [tuple(spice.wnfetd(window, i)) for i in range(spice.wncard(window))]


def _et_to_iso(spice, et: float) -> str:
    try:
        return spice.et2utc(et, "ISOC", 0) + "Z"
    except Exception:  # no LSK loaded
        return f"ET {et:.0f}"


def _covering(intervals: list, start_et: float, end_et: float):
    return next(((a, b) for a, b in intervals if a <= start_et and b >= end_et), None)


def check_kernel_coverage(spice, kernel_paths: list, start: dt.datetime, end: dt.datetime) -> CoverageReport:
    """Coverage of every binary kernel against [start, end]. Kernels must already be loaded (for the LSK)."""
    report = CoverageReport(start=start, end=end)
    if end <= start:
        report.errors.append("The period end must be after its start.")
        return report
    try:
        start_et, end_et = utc_to_et(start, spice), utc_to_et(end, spice)
    except ValueError as error:  # no LSK and a date the built-in UTC table does not cover
        report.errors.append(f"UTC cannot be converted to ephemeris time for this period: {error}")
        return report
    bodies_covered = {body: False for body in REQUIRED_SPK_BODIES}
    lunar_frame_covered = False
    has_spk = has_pck = has_lsk = False

    for path in kernel_paths:
        name = os.path.basename(path)
        try:
            _, kind = spice.getfat(path)
        except Exception as error:  # unreadable file
            report.errors.append(f"{name}: cannot be read ({error}).")
            continue
        kind = kind.strip().upper()
        if kind == "SPK":
            has_spk = True
            ids = spice.spkobj(path)
            present = {ids[i] for i in range(spice.card(ids))}
            spans, covers = {}, True
            for body, label in REQUIRED_SPK_BODIES.items():
                if body not in present:
                    continue
                intervals = _window_intervals(spice, spice.spkcov(path, body))
                hit = _covering(intervals, start_et, end_et)
                spans[label] = None if hit is None else (_et_to_iso(spice, hit[0]), _et_to_iso(spice, hit[1]))
                if hit is None:
                    covers = False
                    span = ", ".join(f"{_et_to_iso(spice, a)} – {_et_to_iso(spice, b)}" for a, b in intervals)
                    report.errors.append(f"{name}: {label} (NAIF {body}) is only covered {span}, not the whole requested period.")
                else:
                    bodies_covered[body] = True
            report.kernels.append(KernelCoverage(name, "SPK", covers, spans))
        elif kind == "PCK" and path.lower().endswith(".bpc"):
            has_pck = True
            frames = spice.cell_int(100)
            spice.pckfrm(path, frames)
            spans, covers = {}, True
            for i in range(spice.card(frames)):
                frame = frames[i]
                label = LUNAR_PCK_FRAMES.get(frame, f"frame {frame}")
                window = spice.cell_double(2000)
                spice.pckcov(path, frame, window)
                hit = _covering(_window_intervals(spice, window), start_et, end_et)
                spans[label] = None if hit is None else (_et_to_iso(spice, hit[0]), _et_to_iso(spice, hit[1]))
                if hit is None:
                    covers = False
                    report.errors.append(f"{name}: {label} orientation does not cover the whole requested period.")
                elif frame in LUNAR_PCK_FRAMES:
                    lunar_frame_covered = True
            report.kernels.append(KernelCoverage(name, "binary PCK", covers, spans))
        else:
            if kind == "LSK":
                has_lsk = True
            report.kernels.append(KernelCoverage(name, kind, True, {}))

    if not has_spk:
        report.errors.append("No planetary SPK (e.g. de421.bsp) is loaded: Sun and Earth positions are unavailable.")
    for body, ok in bodies_covered.items():
        if has_spk and not ok and not any(REQUIRED_SPK_BODIES[body] in e for e in report.errors):
            report.errors.append(f"No loaded SPK provides {REQUIRED_SPK_BODIES[body]} (NAIF {body}).")
    if not has_pck:
        report.errors.append("No lunar binary PCK (e.g. moon_pa_de421_1900-2050.bpc) is loaded: the MOON_ME frame is unavailable.")
    elif not lunar_frame_covered and not any("orientation" in e for e in report.errors):
        report.errors.append("No loaded binary PCK provides the lunar principal-axes frame (MOON_PA).")
    if end > LAST_KNOWN_LEAP_SECOND:
        report.warnings.append(
            "UTC to TDB after 2017-01-01 assumes no leap second beyond those in the leapseconds kernel; "
            "an unannounced leap second would shift times by 1 s." if has_lsk else
            "No leapseconds kernel loaded: UTC to TDB uses the built-in TAI-UTC = 37 s.")
    return report


def check_terrain(sampler, sites: list) -> list[str]:
    """Errors for sites whose surface height is not available in any DEM layer."""
    import numpy as np

    errors = []
    for site in sites:
        lat, lon = float(site["latitude"]), float(site["longitude"])
        value = float(sampler.sample_latlon(np.array([lat]), np.array([lon]))[0])
        if math.isnan(value):
            errors.append(f"Site '{site.get('id')}' ({lat:.5f}, {lon:.5f}) is outside every DEM layer: no LOLA terrain data.")
    return errors
