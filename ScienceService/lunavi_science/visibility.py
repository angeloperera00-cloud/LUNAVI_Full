"""Visibility criteria and conversion of sampled states into timestamped intervals.

Criteria (also written into the scenario metadata):
* Sun: visible when at least `sun_min_fraction` of the solar disc is above the modeled horizon
  plus the clearance angle. The default 0.5 is equivalent to the Sun's centre being above it.
* Earth: visible when any part of the disc is above the modeled horizon plus clearance
  (the criterion used by PGDA product 69). Geometric line of sight only — not a radio link.
"""
from __future__ import annotations

import datetime as dt
from typing import Callable, Optional

import numpy as np


def disc_fraction_visible(elevation_deg, horizon_deg, radius_deg):
    """Fraction of a disc above a locally straight horizon line."""
    d = np.clip((np.asarray(elevation_deg) - np.asarray(horizon_deg)) / np.asarray(radius_deg), -1.0, 1.0)
    return (np.arccos(-d) + d * np.sqrt(1.0 - d * d)) / np.pi


def sun_visible(elevation_deg, horizon_deg, radius_deg, min_fraction: float = 0.5, clearance_deg: float = 0.0):
    fraction = disc_fraction_visible(np.asarray(elevation_deg) - clearance_deg, horizon_deg, radius_deg)
    return fraction > 0.0 if min_fraction <= 0.0 else fraction >= min_fraction


def earth_visible(elevation_deg, horizon_deg, radius_deg, clearance_deg: float = 0.0):
    return np.asarray(elevation_deg) - clearance_deg + np.asarray(radius_deg) > np.asarray(horizon_deg)


def intervals_from_samples(times: list[dt.datetime], flags, refine: Optional[Callable[[dt.datetime], bool]] = None,
                           tolerance_s: float = 30.0) -> list[tuple[dt.datetime, dt.datetime]]:
    """Turns sampled booleans into half-open intervals [start, end), bisecting each transition.

    The first sample opens an interval if visible; the last sample time closes an open interval
    (it is the end of the computed period, i.e. the coverage end).
    """
    flags = [bool(f) for f in flags]
    if not times:
        return []

    def transition(a: dt.datetime, b: dt.datetime, state_a: bool) -> dt.datetime:
        if refine is None:
            return b
        lo, hi = a, b
        while (hi - lo).total_seconds() > tolerance_s:
            mid = lo + (hi - lo) / 2
            if refine(mid) == state_a:
                lo = mid
            else:
                hi = mid
        if hi.microsecond:  # round up to a whole second for clean ISO 8601 output
            hi = hi.replace(microsecond=0) + dt.timedelta(seconds=1)
        return hi

    out: list[tuple[dt.datetime, dt.datetime]] = []
    start = times[0] if flags[0] else None
    for i in range(len(times) - 1):
        if flags[i] != flags[i + 1]:
            t = transition(times[i], times[i + 1], flags[i])
            if flags[i]:
                out.append((start, t))
                start = None
            else:
                start = t
    if start is not None and times[-1] > start:
        out.append((start, times[-1]))
    return out
