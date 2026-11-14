from __future__ import annotations

import datetime as dt

import numpy as np

from lunavi_science.basemap import hillshade
from lunavi_science.timeutil import UTC, iso, time_grid
from lunavi_science.visibility import disc_fraction_visible, earth_visible, intervals_from_samples, sun_visible

SUN_RADIUS = 0.27
EARTH_RADIUS = 0.95


def test_disc_fraction_limits():
    assert np.isclose(disc_fraction_visible(1.0, 1.0, SUN_RADIUS), 0.5)
    assert np.isclose(disc_fraction_visible(1.0 + SUN_RADIUS, 1.0, SUN_RADIUS), 1.0)
    assert np.isclose(disc_fraction_visible(1.0 - SUN_RADIUS, 1.0, SUN_RADIUS), 0.0)
    fractions = disc_fraction_visible(np.linspace(0.5, 1.5, 50), 1.0, SUN_RADIUS)
    assert np.all(np.diff(fractions) >= 0)


def test_sun_needs_half_the_disc_by_default():
    assert sun_visible(1.0, 1.0, SUN_RADIUS)
    assert not sun_visible(0.999, 1.0, SUN_RADIUS)
    assert sun_visible(0.9, 1.0, SUN_RADIUS, min_fraction=0.0)   # limb still above
    assert not sun_visible(1.1, 1.0, SUN_RADIUS, clearance_deg=0.2)


def test_earth_counts_when_any_part_clears_the_horizon():
    assert earth_visible(-0.5, 0.0, EARTH_RADIUS)
    assert not earth_visible(-0.96, 0.0, EARTH_RADIUS)
    assert not earth_visible(0.5, 0.0, EARTH_RADIUS, clearance_deg=1.6)


def test_intervals_are_half_open_and_bisected_to_whole_seconds():
    start = dt.datetime(2026, 11, 20, tzinfo=UTC)
    off = start + dt.timedelta(hours=3, minutes=17, seconds=41)
    on = start + dt.timedelta(hours=7, minutes=2, seconds=5)
    end = start + dt.timedelta(hours=10)

    def state(moment):
        return moment < off or moment >= on

    times = time_grid(start, end, 600)
    result = intervals_from_samples(times, [state(m) for m in times], state)
    assert len(result) == 2
    (a0, a1), (b0, b1) = result
    assert a0 == start and b1 == times[-1]
    assert abs((a1 - off).total_seconds()) <= 31 and a1 >= off
    assert abs((b0 - on).total_seconds()) <= 31 and b0 >= on
    assert all(m.microsecond == 0 for m in (a1, b0))
    assert iso(a1).endswith("Z")


def test_never_visible_and_always_visible():
    start = dt.datetime(2026, 11, 20, tzinfo=UTC)
    times = time_grid(start, start + dt.timedelta(hours=2), 600)
    assert intervals_from_samples(times, [False] * len(times)) == []
    assert intervals_from_samples(times, [True] * len(times)) == [(times[0], times[-1])]


def test_hillshade_lights_slopes_facing_the_light():
    cell = 10.0
    y, x = np.mgrid[0:50, 0:50]
    facing_northwest = (x - (50 - y)) * cell * 0.3   # rises toward the south-east, faces north-west
    facing_southeast = -facing_northwest
    lit = hillshade(facing_northwest, cell, azimuth_deg=315.0)
    shaded = hillshade(facing_southeast, cell, azimuth_deg=315.0)
    assert lit[25, 25] > shaded[25, 25] + 0.3
