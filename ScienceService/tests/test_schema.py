"""The schema validator mirrors the app's Codable models; the app's own fixture must pass it."""
from __future__ import annotations

import copy
import json

from lunavi_science.__main__ import main
from lunavi_science.schema import validate_scenario


def test_app_fixture_passes(fixture_scenario):
    assert validate_scenario(fixture_scenario) == []


def test_errors_are_reported(fixture_scenario):
    broken = copy.deepcopy(fixture_scenario)
    broken["mission"]["start"] = "2026-11-20T06:00:00.500Z"
    broken["mission"]["siteID"] = "nowhere"
    broken["visibility"][0]["sunlight"][0]["end"] = broken["visibility"][0]["sunlight"][0]["start"]
    del broken["metadata"]["disclaimer"]
    broken["metadata"]["source"] = "verified"
    errors = "\n".join(validate_scenario(broken))
    for fragment in ("mission.start", "mission.siteID", "end must be after start", "disclaimer", "metadata.source"):
        assert fragment in errors


def test_cli_validate(tmp_path, fixture_scenario, capsys):
    path = tmp_path / "scenario.json"
    path.write_text(json.dumps(fixture_scenario))
    assert main(["validate", "--scenario", str(path)]) == 0
    assert "matches" in capsys.readouterr().out
