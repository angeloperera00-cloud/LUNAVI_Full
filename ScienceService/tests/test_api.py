"""The FastAPI service, served with the app's simulated fixture (labelled as such)."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from lunavi_science.api import create_app


@pytest.fixture(scope="module")
def client(fixture_scenario):
    return TestClient(create_app(fixture_scenario))


def plan(**overrides):
    body = {"siteId": "demo-point-a", "utcStart": "2026-11-20T06:00:00Z", "durationHours": 24, "delayHours": 6}
    body.update(overrides)
    return body


def test_health_reports_the_data_source(client):
    body = client.get("/api/v1/health").json()
    assert body["status"] == "ok"
    assert body["source"] == "simulatedFixture"
    assert body["kernelsLoaded"] is False


def test_scenario_and_sites(client, fixture_scenario):
    assert client.get("/api/v1/scenario").json()["mission"]["siteID"] == "demo-point-a"
    assert len(client.get("/api/v1/sites").json()["sites"]) == len(fixture_scenario["sites"])
    assert client.get("/api/v1/sites/ridge-site-b").json()["id"] == "ridge-site-b"


def test_unknown_site_uses_the_error_envelope(client):
    response = client.get("/api/v1/sites/nowhere")
    assert response.status_code == 404
    assert response.json() == {"error": {"code": "UNSUPPORTED_SITE", "message": "Unknown site 'nowhere'."}}


def test_site_without_data_is_not_guessed(client):
    response = client.post("/api/v1/analysis/compare", json=plan(siteId="demo-point-c"))
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "UNSUPPORTED_SITE"


def test_compare_reproduces_the_delay_failure(client):
    body = client.post("/api/v1/analysis/compare", json=plan()).json()
    assert body["original"]["overall"] == "met"
    assert body["delayed"]["overall"] == "notMet"
    assert body["delayed"]["firstFailure"] == {"condition": "sunlight", "time": "2026-11-21T08:00:00Z"}
    assert body["delayed"]["sunlight"]["obstructedSeconds"] == 4 * 3600


def test_recovery_returns_both_options(client):
    body = client.post("/api/v1/analysis/recovery", json=plan(utcStart="2026-11-20T12:00:00Z")).json()
    kinds = [(c["kind"], c["siteId"], c["evaluation"]["utcStart"]) for c in body["candidates"]]
    assert kinds == [("sameSiteLaterTime", "demo-point-a", "2026-11-25T12:00:00Z"),
                     ("alternativeSite", "ridge-site-b", "2026-11-20T12:00:00Z")]
    assert all(c["evaluation"]["overall"] == "met" for c in body["candidates"])


def test_visibility_window(client):
    body = client.post("/api/v1/analysis/visibility", json={
        "siteId": "demo-point-a", "utcStart": "2026-11-20T12:00:00Z", "utcEnd": "2026-11-21T12:00:00Z",
        "observerHeightM": 2.0, "timeStepS": 600, "minimumClearanceDeg": 0.0, "model": "lunavi-horizon-v1", "datasetIds": []}).json()
    assert body["sunlight"] == [{"start": "2026-11-20T12:00:00Z", "end": "2026-11-21T08:00:00Z"}]
    assert body["firstFailure"] == {"condition": "sunlight", "time": "2026-11-21T08:00:00Z"}
    assert body["dataQuality"] == "complete"
    assert [e["id"] for e in body["events"]] == ["a-sun-obstruction"]


@pytest.mark.parametrize("payload, code", [
    ({"utcStart": "20 Nov 2026"}, "INVALID_DATE"),
    ({"utcEnd": "2026-11-20T06:00:00Z"}, "INVALID_TIME_INTERVAL"),
    ({"observerHeightM": -5}, "INVALID_OBSERVER_HEIGHT"),
    # Illustrative demo sites have no coordinates, so a custom observer location is refused, not guessed.
    ({"observerLatitudeDeg": -89.0, "observerLongitudeDeg": 10.0}, "UNSUPPORTED_LOCATION"),
])
def test_visibility_rejects_bad_input(client, payload, code):
    body = {"siteId": "demo-point-a", "utcStart": "2026-11-20T06:00:00Z", "utcEnd": "2026-11-21T06:00:00Z"}
    body.update(payload)
    response = client.post("/api/v1/analysis/visibility", json=body)
    assert response.status_code == (422 if code == "UNSUPPORTED_LOCATION" else 400)
    assert response.json()["error"]["code"] == code


def test_malformed_body_is_a_typed_error(client):
    response = client.post("/api/v1/analysis/compare", json={"siteId": "demo-point-a"})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "INVALID_REQUEST"
