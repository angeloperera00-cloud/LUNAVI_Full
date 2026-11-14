"""Acceptance scenarios on a hand-made scenario with known answers (test input, not lunar data)."""
from __future__ import annotations

from lunavi_science.acceptance import format_report, run


def r(a, b):
    return {"start": a, "end": b}


SCENARIO = {
    "schemaVersion": 3, "period": {"start": "2026-11-17T00:00:00Z", "end": "2026-12-01T00:00:00Z"},
    "mission": {"delayHours": 6},
    "metadata": {"source": "computedBundled"},
    "sites": [{"id": "s1", "name": "Site One", "coordinate": {"latitude": -89.4, "longitude": -137.0}},
              {"id": "s2", "name": "Site Two", "coordinate": {"latitude": -89.7, "longitude": -157.0}}],
    "visibility": [
        {"siteID": "s1", "coverage": [r("2026-11-17T00:00:00Z", "2026-12-01T00:00:00Z")],
         "sunlight": [r("2026-11-17T00:00:00Z", "2026-12-01T00:00:00Z")],
         "earthLineOfSight": [r("2026-11-17T00:00:00Z", "2026-11-30T19:00:00Z")],
         "events": [{"condition": "earthLineOfSight", "kind": "obstructionBegins", "time": "2026-11-30T19:00:00Z",
                     "summary": "Computed: the Earth drops below the modeled terrain horizon."}]},
        {"siteID": "s2", "coverage": [r("2026-11-17T00:00:00Z", "2026-12-01T00:00:00Z")],
         "sunlight": [r("2026-11-17T00:00:00Z", "2026-12-01T00:00:00Z")],
         "earthLineOfSight": [r("2026-11-17T00:00:00Z", "2026-12-01T00:00:00Z")], "events": []},
    ],
}


def test_scenarios_a_to_d():
    result = run(SCENARIO, "s1", "2026-11-29T15:00:00Z", 24)
    s = result["scenarios"]
    assert s["A"]["overall"] == "met"
    assert s["B"]["overall"] == "notMet"
    assert s["B"]["failedRequirement"] == "earthLineOfSight"
    assert s["B"]["obstructionStarts"] == "2026-11-30T19:00:00Z"
    assert s["B"]["failureIsComputedTransition"] is True
    assert [o["kind"] for o in s["C"]["options"]] == ["alternativeSite"]  # s1 never regains Earth in the data
    assert s["C"]["options"][0]["site"] == "s2" and s["C"]["options"][0]["verified"] == "met"
    assert s["D"]["overall"] == "notMet"  # Earth already obstructed before the data ends
    assert s["D"]["correctlyUnknown"] is True
    assert "OK, reported as unknown" in format_report(result)


def test_missing_site_is_reported_not_invented():
    result = run(SCENARIO, "nowhere")
    assert result["scenarios"]["A"]["result"] == "not available"


def test_no_recovery_is_reported_honestly():
    scenario = dict(SCENARIO, visibility=[SCENARIO["visibility"][0]])
    result = run(scenario, "s1", "2026-11-29T15:00:00Z", 24)
    assert result["scenarios"]["C"]["options"] == []
    assert "No option" in result["scenarios"]["C"]["note"]
