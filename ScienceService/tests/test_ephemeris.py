"""Ephemeris geometry, checked against an independent implementation (Skyfield)."""
from __future__ import annotations

import datetime as dt

import numpy as np
import pytest

from conftest import kernel_dir
from lunavi_science.ephemeris import EARTH_RADIUS_KM, angular_radius_deg, site_vector_km, target_azel
from lunavi_science.timeutil import UTC, fallback_utc_to_et, time_grid, utc_to_et

EPOCHS = [dt.datetime(2026, 11, d, h, tzinfo=UTC) for d, h in [(18, 0), (20, 6), (21, 8), (25, 12), (29, 18)]]
SITES = [(-89.5, 30.0), (-89.9, -120.0), (-85.0, 0.0)]


def test_utc_to_et_fallback_matches_skyfield_tdb():
    skyfield = pytest.importorskip("skyfield.api")
    ts = skyfield.load.timescale(builtin=True)
    for moment in EPOCHS:
        t = ts.from_datetime(moment)
        et = (t.whole - 2451545.0) * 86400.0 + t.tdb_fraction * 86400.0
        assert abs(fallback_utc_to_et(moment) - et) < 2e-3  # seconds


def test_utc_to_et_uses_spice_when_a_leapseconds_kernel_is_loaded(spice):
    moment = EPOCHS[1]
    if (kernel_dir() / "naif0012.tls").exists():
        assert abs(utc_to_et(moment, spice) - float(spice.str2et("2026-11-20T06:00:00"))) < 1e-6
    assert abs(utc_to_et(moment, spice) - fallback_utc_to_et(moment)) < 2e-3


def test_sun_and_earth_directions_match_skyfield(spice):
    api = pytest.importorskip("skyfield.api")
    from skyfield.planetarylib import PlanetaryConstants

    directory = kernel_dir()
    ts = api.load.timescale(builtin=True)
    eph = api.load_file(str(directory / "de421.bsp"))
    pc = PlanetaryConstants()
    with open(directory / "moon_080317.tf", "rb") as f:
        pc.read_text(f)
    bpc = open(directory / "moon_pa_de421_1900-2050.bpc", "rb")  # read lazily; keep open for the test
    pc.read_binary(bpc)
    pc.variables["BODY301_RADII"] = [1737.4, 1737.4, 1737.4]
    frame = pc.build_frame_named("MOON_ME_DE421")

    worst = 0.0
    for lat, lon in SITES:
        place = eph["moon"] + pc.build_latlon_degrees(frame, lat, lon)
        site = site_vector_km(lat, lon, 1737.4)
        for moment in EPOCHS:
            t = ts.from_datetime(moment)
            for name, body in (("SUN", eph["sun"]), ("EARTH", eph["earth"])):
                alt, az, _ = place.at(t).observe(body).apparent().altaz()
                a, e, _ = target_azel(spice, name, [fallback_utc_to_et(moment)], site)
                d_az = (az.degrees - a[0] + 180.0) % 360.0 - 180.0
                worst = max(worst, abs(alt.degrees - e[0]), abs(d_az) * np.cos(np.radians(e[0])))
    bpc.close()
    assert worst < 0.001, worst  # degrees


def test_earth_up_window_at_the_pole_regression(spice):
    """Topocentric Earth centre above the pole's flat horizon: 17 Nov ~16:40 to 29 Nov ~23:40 UTC (10-min grid)."""
    times = time_grid(dt.datetime(2026, 11, 10, tzinfo=UTC), dt.datetime(2026, 12, 10, tzinfo=UTC), 600)
    _, el, dist = target_azel(spice, "EARTH", [fallback_utc_to_et(m) for m in times], site_vector_km(-90.0, 0.0, 1737.4))
    up = el > 0
    rises = [times[i + 1] for i in range(len(times) - 1) if not up[i] and up[i + 1]]
    sets = [times[i + 1] for i in range(len(times) - 1) if up[i] and not up[i + 1]]
    assert abs((rises[0] - dt.datetime(2026, 11, 17, 16, 40, tzinfo=UTC)).total_seconds()) <= 1800
    assert abs((sets[0] - dt.datetime(2026, 11, 29, 23, 40, tzinfo=UTC)).total_seconds()) <= 1800
    assert 6.0 < el.max() < 6.5
    radius = angular_radius_deg(EARTH_RADIUS_KM, dist)  # 0.90°–1.03° over the lunar orbit
    assert np.all((radius > 0.85) & (radius < 1.05))
