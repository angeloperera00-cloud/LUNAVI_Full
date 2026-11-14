"""LUNAVI science service (FastAPI). Versioned JSON API, ISO 8601 UTC, typed error envelopes.

The service serves results computed by `python -m lunavi_science build`. It does not compute
visibility for arbitrary coordinates on demand: requests for sites without computed data return
UNSUPPORTED_SITE instead of a guess. No API key is required; never put secrets in the iPad app.

Run: python -m lunavi_science serve --scenario out/ComputedScenario.json --port 8000
"""
from __future__ import annotations

import datetime as dt
import json
from typing import Optional

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from . import __version__
from . import intervals as iv
from .timeutil import iso, parse_utc


class APIError(Exception):
    def __init__(self, status: int, code: str, message: str):
        self.status, self.code, self.message = status, code, message


class VisibilityRequest(BaseModel):
    siteId: str
    observerLatitudeDeg: Optional[float] = None
    observerLongitudeDeg: Optional[float] = None
    observerHeightM: float = 2.0
    utcStart: str
    utcEnd: str
    timeStepS: float = 600
    minimumClearanceDeg: float = 0.0
    model: str = "lunavi-horizon-v1"
    datasetIds: list[str] = []


class PlanRequest(BaseModel):
    siteId: str
    utcStart: str
    durationHours: int
    delayHours: int = 6


def create_app(scenario: dict) -> FastAPI:
    app = FastAPI(title="LUNAVI science service", version=__version__)
    sites = {s["id"]: s for s in scenario["sites"]}
    data = {v["siteID"]: iv.site_data_from_json(v, parse_utc) for v in scenario["visibility"]}
    visibility_json = {v["siteID"]: v for v in scenario["visibility"]}

    @app.exception_handler(APIError)
    async def api_error(_: Request, exc: APIError):
        return JSONResponse(status_code=exc.status, content={"error": {"code": exc.code, "message": exc.message}})

    @app.exception_handler(RequestValidationError)
    async def validation_error(_: Request, exc: RequestValidationError):
        return JSONResponse(status_code=422, content={"error": {"code": "INVALID_REQUEST", "message": str(exc.errors()[:3])}})

    def require_site(site_id: str) -> iv.SiteData:
        if site_id not in sites:
            raise APIError(404, "UNSUPPORTED_SITE", f"Unknown site '{site_id}'.")
        if site_id not in data:
            raise APIError(404, "UNSUPPORTED_SITE", f"No computed visibility exists for '{site_id}'.")
        return data[site_id]

    def parse_time(value: str, field: str) -> dt.datetime:
        try:
            return parse_utc(value)
        except ValueError:
            raise APIError(400, "INVALID_DATE", f"{field} must be ISO 8601 UTC, e.g. 2026-11-20T06:00:00Z.")

    def evaluation_json(e: iv.Evaluation) -> dict:
        def a(x: iv.Assessment) -> dict:
            return {"condition": x.condition, "status": x.status,
                    "firstFailure": iso(x.first_failure) if x.first_failure else None,
                    "firstUnknown": iso(x.first_unknown) if x.first_unknown else None,
                    "visibleSeconds": x.visible_s, "obstructedSeconds": x.obstructed_s, "unknownSeconds": x.unknown_s}
        failure = e.first_failure
        return {"siteId": e.site_id, "utcStart": iso(e.window[0]), "utcEnd": iso(e.window[1]), "overall": e.overall,
                "sunlight": a(e.sunlight), "earthLineOfSight": a(e.earth),
                "firstFailure": {"condition": failure[0], "time": iso(failure[1])} if failure else None}

    @app.get("/api/v1/health")
    def health():
        # The service serves precomputed results; it does not load SPICE kernels itself.
        return {"status": "ok", "version": __version__, "scenarioId": scenario["metadata"]["id"],
                "kernelsLoaded": False, "mode": "precomputed", "source": scenario["metadata"]["source"]}

    @app.get("/api/v1/scenario")
    def get_scenario():
        return scenario

    @app.get("/api/v1/sites")
    def list_sites():
        return {"sites": scenario["sites"]}

    @app.get("/api/v1/sites/{site_id}")
    def get_site(site_id: str):
        if site_id not in sites:
            raise APIError(404, "UNSUPPORTED_SITE", f"Unknown site '{site_id}'.")
        return sites[site_id]

    @app.get("/api/v1/datasets")
    def datasets():
        m = scenario["metadata"]
        return {"id": m["id"], "source": m["source"], "provenance": m["provenance"], "validation": m["validation"]}

    @app.post("/api/v1/analysis/visibility")
    def visibility(request: VisibilityRequest):
        site = require_site(request.siteId)
        start, end = parse_time(request.utcStart, "utcStart"), parse_time(request.utcEnd, "utcEnd")
        if end <= start:
            raise APIError(400, "INVALID_TIME_INTERVAL", "utcEnd must be after utcStart.")
        if request.observerHeightM < 0 or request.observerHeightM > 1000:
            raise APIError(400, "INVALID_OBSERVER_HEIGHT", "observerHeightM must be between 0 and 1000 m.")
        if request.observerLatitudeDeg is not None or request.observerLongitudeDeg is not None:
            coord = sites[request.siteId].get("coordinate")
            matches = (coord is not None and request.observerLatitudeDeg is not None and request.observerLongitudeDeg is not None
                       and abs(request.observerLatitudeDeg - coord["latitude"]) <= 1e-6
                       and abs(request.observerLongitudeDeg - coord["longitude"]) <= 1e-6)
            if not matches:
                raise APIError(422, "UNSUPPORTED_LOCATION",
                               "Only the precomputed site coordinates are supported; on-demand computation for other locations is not implemented.")
        meta = scenario["metadata"]
        warnings = []
        if abs(request.observerHeightM - (meta.get("observerHeightMeters") or 0)) > 1e-6 or abs(request.minimumClearanceDeg - (meta.get("minimumClearanceDeg") or 0)) > 1e-6:
            warnings.append("Requested observer height/clearance differ from the precomputed assumptions; results use the precomputed values.")
        window = (start, end)
        clip = lambda r: [{"start": iso(a), "end": iso(b)} for a, b in iv.clip(r, window)]
        evaluation = iv.evaluate(site, request.siteId, start, (end - start).total_seconds() / 3600)
        quality = "complete" if not iv.complement(site.coverage, window) else ("partial" if iv.clip(site.coverage, window) else "unavailable")
        failure = evaluation.first_failure
        return {
            "scenarioId": meta["id"], "siteId": request.siteId, "utcStart": iso(start), "utcEnd": iso(end),
            "coverage": clip(site.coverage), "sunlight": clip(site.sunlight), "earthLineOfSight": clip(site.earth),
            "combined": clip(iv.combined(site)),
            "firstFailure": {"condition": failure[0], "time": iso(failure[1])} if failure else None,
            "events": [e for e in visibility_json[request.siteId]["events"] if iso(start) <= e["time"] < iso(end)],
            "provenance": meta["provenance"], "assumptions": meta["assumptions"], "validation": meta["validation"],
            "warnings": warnings, "dataQuality": quality,
        }

    @app.post("/api/v1/analysis/compare")
    def compare(request: PlanRequest):
        site = require_site(request.siteId)
        start = parse_time(request.utcStart, "utcStart")
        if request.durationHours <= 0:
            raise APIError(400, "INVALID_TIME_INTERVAL", "durationHours must be positive.")
        original = iv.evaluate(site, request.siteId, start, request.durationHours)
        delayed = iv.evaluate(site, request.siteId, start + dt.timedelta(hours=request.delayHours), request.durationHours)
        return {"original": evaluation_json(original), "delayed": evaluation_json(delayed)}

    @app.post("/api/v1/analysis/recovery")
    def recovery(request: PlanRequest):
        require_site(request.siteId)
        start = parse_time(request.utcStart, "utcStart")
        if request.durationHours <= 0:
            raise APIError(400, "INVALID_TIME_INTERVAL", "durationHours must be positive.")
        order = iv.proximity_order(scenario["sites"], request.siteId, data)
        candidates = iv.recovery_candidates(data, order, request.siteId, start, request.durationHours)
        return {"candidates": [
            {"kind": c["kind"], "siteId": c["siteId"], "evaluation": evaluation_json(iv.evaluate(data[c["siteId"]], c["siteId"], c["start"], c["hours"]))}
            for c in candidates
        ]}

    return app


def load_app(scenario_path: str) -> FastAPI:
    with open(scenario_path) as f:
        return create_app(json.load(f))
