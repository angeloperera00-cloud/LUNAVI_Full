"""The Python interval logic must give the same answers as the app's Swift tests on the same fixture."""
from __future__ import annotations

import datetime as dt

import pytest

from lunavi_science import intervals as iv
from lunavi_science.timeutil import UTC, parse_utc


def t(day: int, hour: int, minute: int = 0) -> dt.datetime:
    return dt.datetime(2026, 11, day, hour, minute, tzinfo=UTC)


@pytest.fixture(scope="module")
def sites(fixture_scenario):
    return {entry["siteID"]: iv.site_data_from_json(entry, parse_utc) for entry in fixture_scenario["visibility"]}


def order_for(fixture_scenario, sites, site_id):
    return iv.proximity_order(fixture_scenario["sites"], site_id, sites)


def test_original_plan_meets_both(sites):
    evaluation = iv.evaluate(sites["demo-point-a"], "demo-point-a", t(20, 6), 24)
    assert evaluation.overall == "met"
    assert evaluation.first_failure is None


def test_delayed_plan_fails_sunlight_at_21_nov_0800(sites):
    evaluation = iv.evaluate(sites["demo-point-a"], "demo-point-a", t(20, 12), 24)
    assert evaluation.overall == "notMet"
    assert evaluation.first_failure == ("sunlight", t(21, 8))
    assert evaluation.sunlight.status == "partial"
    assert evaluation.sunlight.obstructed_s == 4 * 3600
    assert evaluation.sunlight.visible_s == 20 * 3600
    assert evaluation.earth.status == "met"


@pytest.mark.parametrize("hours", [6, 12])
def test_short_plans_absorb_the_delay(sites, hours):
    assert iv.evaluate(sites["demo-point-a"], "demo-point-a", t(20, 12), hours).overall == "met"


def test_48_hour_original_already_fails(sites):
    assert iv.evaluate(sites["demo-point-a"], "demo-point-a", t(20, 6), 48).overall == "notMet"


def test_recovery_options_match_the_app(fixture_scenario, sites):
    candidates = iv.recovery_candidates(sites, order_for(fixture_scenario, sites, "demo-point-a"), "demo-point-a", t(20, 12), 24)
    assert [c["kind"] for c in candidates] == ["sameSiteLaterTime", "alternativeSite"]
    assert candidates[0]["start"] == t(25, 12)
    assert candidates[0]["start"] - t(20, 12) == dt.timedelta(days=5)
    assert candidates[1]["siteId"] == "ridge-site-b"
    assert candidates[1]["start"] == t(20, 12)


def test_no_recovery_for_48_hours(fixture_scenario, sites):
    assert iv.recovery_candidates(sites, order_for(fixture_scenario, sites, "demo-point-a"), "demo-point-a", t(20, 12), 48) == []


def test_site_without_data_is_unknown_not_met(sites):
    evaluation = iv.evaluate(None, "demo-point-c", t(20, 6), 24)
    assert evaluation.overall == "unknown"
    assert evaluation.sunlight.unknown_s == 24 * 3600


def test_known_obstruction_takes_precedence_over_unknown():
    data = iv.SiteData("x", coverage=[(t(20, 0), t(21, 0))], sunlight=[(t(20, 0), t(20, 12))], earth=[(t(20, 0), t(21, 0))])
    evaluation = iv.evaluate(data, "x", t(20, 6), 24)  # obstructed from 12:00, unknown from 21 Nov 00:00
    assert evaluation.sunlight.status == "partial"
    assert evaluation.earth.status == "unknown"
    assert evaluation.overall == "notMet"


def test_half_open_end_is_met_and_one_minute_gap_is_not():
    window_end = t(21, 6)
    data = iv.SiteData("x", coverage=[(t(20, 0), t(22, 0))], sunlight=[(t(20, 6), window_end)], earth=[(t(20, 0), t(22, 0))])
    assert iv.evaluate(data, "x", t(20, 6), 24).overall == "met"
    gap = iv.SiteData("x", coverage=data.coverage, sunlight=[(t(20, 6), t(20, 18)), (t(20, 18, 1), t(22, 0))], earth=data.earth)
    evaluation = iv.evaluate(gap, "x", t(20, 6), 24)
    assert evaluation.overall == "notMet"
    assert evaluation.first_failure == ("sunlight", t(20, 18))


def test_earliest_start_uses_interval_arithmetic():
    data = iv.SiteData("x", coverage=[(t(19, 0), t(28, 0))], sunlight=[(t(19, 0), t(21, 8)), (t(25, 12), t(27, 0))],
                       earth=[(t(19, 0), t(28, 0))])
    assert iv.earliest_start(data, t(20, 12), 24) == t(25, 12)
    assert iv.earliest_start(data, t(19, 0), 24) == t(19, 0)
    assert iv.earliest_start(data, t(26, 12), 24) is None
