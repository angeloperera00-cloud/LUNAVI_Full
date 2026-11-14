"""Acceptance scenarios A–D evaluated on a real ComputedScenario file with the app's rules.

  python -m lunavi_science acceptance --scenario ../Lunavi/Resources/ComputedScenario.json

Uses intervals.py, which mirrors VisibilityEvaluator / RecoverySearchService in the app (the same
half-open intervals, precedence and recovery rule), so the printed results are what the app must show.
Nothing is assumed: if the requested site or dates are not in the file, the scenario says so.

A  Valid mission    — the requested plan (default: Connecting Ridge, 29 Nov 2026 15:00 UTC, 24 h).
B  Failed mission   — the same plan delayed by the scenario's delayHours: which requirement fails and when,
                      and the computed transition (event) that explains it.
C  Mission Rescue   — recovery options for the delayed plan (option A same site later, option B nearest site).
D  Missing data     — a window that runs 12 h past the end of the site's coverage: must be Unknown, not met.
"""
from __future__ import annotations

import datetime as dt
from typing import Optional

from . import intervals as iv
from .timeutil import iso, parse_utc

DEFAULT_SITE = "pgda78-site01"
DEFAULT_START = "2026-11-29T15:00:00Z"
DEFAULT_HOURS = 24


def _summary(e: iv.Evaluation) -> dict:
    def a(x: iv.Assessment) -> dict:
        return {"status": x.status, "firstFailure": iso(x.first_failure) if x.first_failure else None,
                "firstUnknown": iso(x.first_unknown) if x.first_unknown else None,
                "visibleH": round(x.visible_s / 3600, 3), "obstructedH": round(x.obstructed_s / 3600, 3),
                "unknownH": round(x.unknown_s / 3600, 3)}
    return {"site": e.site_id, "start": iso(e.window[0]), "end": iso(e.window[1]), "overall": e.overall,
            "sunlight": a(e.sunlight), "earthLineOfSight": a(e.earth)}


def run(scenario: dict, site_id: str = DEFAULT_SITE, start: str = DEFAULT_START, hours: float = DEFAULT_HOURS) -> dict:
    sites = {v["siteID"]: iv.site_data_from_json(v, parse_utc) for v in scenario["visibility"]}
    names = {s["id"]: s["name"] for s in scenario["sites"]}
    delay = float(scenario["mission"]["delayHours"])
    out: dict = {"schemaVersion": scenario.get("schemaVersion"), "period": scenario.get("period"),
                 "dataSource": scenario["metadata"]["source"], "scenarios": {}}

    data: Optional[iv.SiteData] = sites.get(site_id)
    if data is None:
        out["scenarios"]["A"] = {"result": "not available", "reason": f"site '{site_id}' has no data in this file"}
        return out
    t0 = parse_utc(start)

    a = iv.evaluate(data, site_id, t0, hours)
    out["scenarios"]["A"] = dict(_summary(a), siteName=names.get(site_id, site_id))

    delayed_start = t0 + dt.timedelta(hours=delay)
    b = iv.evaluate(data, site_id, delayed_start, hours)
    b_out = dict(_summary(b), delayHours=delay)
    failure = b.first_failure
    if failure:
        condition, moment = failure
        event = next((e for e in data.events if e["condition"] == condition and e["kind"] == "obstructionBegins"
                      and abs((parse_utc(e["time"]) - moment).total_seconds()) < 60), None)
        b_out["failedRequirement"] = condition
        b_out["obstructionStarts"] = iso(moment)
        b_out["explainingEvent"] = event["summary"] if event else None
        b_out["failureIsComputedTransition"] = event is not None
    out["scenarios"]["B"] = b_out

    stubs = [{"id": s["id"], "coordinate": s.get("coordinate"), "mapPosition": s.get("mapPosition")} for s in scenario["sites"]]
    order = iv.proximity_order(stubs, site_id, sites)
    options = iv.recovery_candidates(sites, order, site_id, delayed_start, hours) if b.overall != "met" else []
    out["scenarios"]["C"] = {
        "searched": b.overall != "met",
        "options": [{"kind": o["kind"], "site": o["siteId"], "siteName": names.get(o["siteId"], o["siteId"]),
                     "start": iso(o["start"]), "hours": o["hours"],
                     "verified": iv.evaluate(sites[o["siteId"]], o["siteId"], o["start"], o["hours"]).overall}
                    for o in options],
        "note": None if options or b.overall == "met" else "No option meets both requirements within the computed data.",
    }

    coverage_end = max(end for _, end in data.coverage) if data.coverage else None
    if coverage_end is not None:
        d = iv.evaluate(data, site_id, coverage_end - dt.timedelta(hours=12), 24)
        out["scenarios"]["D"] = dict(_summary(d), coverageEnd=iso(coverage_end),
                                     correctlyUnknown=d.overall != "met" and d.sunlight.unknown_s >= 12 * 3600 - 1
                                     and d.earth.unknown_s >= 12 * 3600 - 1)
    return out


def format_report(result: dict) -> str:
    lines = [f"Scenario file: schema {result['schemaVersion']}, source {result['dataSource']}, period {result['period']}"]
    s = result["scenarios"]
    if "B" not in s:
        return "\n".join(lines + [f"A: {s['A']}"])
    a, b, c = s["A"], s["B"], s["C"]
    lines.append(f"A  {a['siteName']} {a['start']} → {a['end']}: overall {a['overall']} "
                 f"(sun {a['sunlight']['status']}, earth {a['earthLineOfSight']['status']})")
    lines.append(f"B  delayed +{b['delayHours']:g} h {b['start']} → {b['end']}: overall {b['overall']}")
    if b.get("failedRequirement"):
        lines.append(f"   fails: {b['failedRequirement']} from {b['obstructionStarts']} "
                     f"({'computed transition' if b['failureIsComputedTransition'] else 'no matching event'})")
        if b["explainingEvent"]:
            lines.append(f"   {b['explainingEvent']}")
    if c["searched"]:
        for o in c["options"]:
            lines.append(f"C  option {o['kind']}: {o['siteName']} {o['start']} for {o['hours']:g} h → re-evaluated {o['verified']}")
        if c["note"]:
            lines.append(f"C  {c['note']}")
    else:
        lines.append("C  not needed: the delayed plan still meets both requirements")
    if "D" in s:
        d = s["D"]
        lines.append(f"D  {d['start']} → {d['end']} (coverage ends {d['coverageEnd']}): overall {d['overall']}, "
                     f"unknown {d['sunlight']['unknownH']} h → {'OK, reported as unknown' if d['correctlyUnknown'] else 'CHECK'}")
    return "\n".join(lines)
