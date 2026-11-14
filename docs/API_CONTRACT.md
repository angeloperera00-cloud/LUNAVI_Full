# LUNAVI science service — API v1

Base URL example: `http://127.0.0.1:8000`. JSON throughout.

## Conventions

- **Times.** ISO 8601 UTC with no fractional seconds, e.g. `2026-11-20T06:00:00Z`.
- **Intervals.** Half-open `[start, end)`, sent as `{"start": …, "end": …}`.
- **Authentication.** None. The service holds no secrets, and the iPad app must never embed any.
- **Scope.** The service serves results precomputed by `python -m lunavi_science build`. It does not compute visibility for new coordinates on demand. Requests it cannot answer from computed data return an error rather than an estimate.
- **Implementation.** Server: `ScienceService/lunavi_science/api.py`. Client: `Lunavi/Services/RemoteScienceService.swift`.

## Errors

Every error uses the same envelope:

```json
{ "error": { "code": "UNSUPPORTED_SITE", "message": "No computed visibility exists for 'demo-point-c'." } }
```

| HTTP | Code | When |
|---|---|---|
| 400 | `INVALID_DATE` | A time is not ISO 8601 UTC |
| 400 | `INVALID_TIME_INTERVAL` | `utcEnd` ≤ `utcStart`, or `durationHours` ≤ 0 |
| 400 | `INVALID_OBSERVER_HEIGHT` | `observerHeightM` outside 0–1000 m |
| 404 | `UNSUPPORTED_SITE` | Unknown site, or a site without computed data |
| 422 | `UNSUPPORTED_LOCATION` | Observer coordinates that are not the site's precomputed coordinates |
| 422 | `INVALID_REQUEST` | Malformed body or missing fields |

## Endpoints

### `GET /api/v1/health`

```json
{ "status": "ok", "version": "1.0.0", "scenarioId": "lunavi-computed-20261112T120000Z",
  "kernelsLoaded": false, "mode": "precomputed", "source": "computedBundled" }
```

`source` is the scenario's own data source. If the service is serving the simulated fixture, it reports `simulatedFixture`, and the app keeps the SIMULATED DEMO label.

### `GET /api/v1/scenario`

Returns the full `ComputedScenario.json`, the same schema as the app's `ComputedScenarioFile`:

| Key | Contents |
|---|---|
| `mission` | Default plan |
| `basemap` | Image resource name and georeferencing |
| `sites` | Site list |
| `metadata` | Source, criteria, assumptions, limitations, provenance and validation records |
| `visibility` | Per-site coverage, sunlight, Earth line-of-sight and events |
| `sensitivity` | Variants under alternative assumptions |
| `schemaVersion`, `generator`, `period` | Pipeline-only keys; the app ignores them |
| `sites[].surfaceHeightM` | Pipeline-only key; the app ignores it |

| `geometry` | Schema 2: per site, the horizon mask and sampled Sun and Earth directions (below). Optional; the simulated fixture has none |

The basemap image itself is **not** served. Bundle it in the app.

**`geometry[]` (schema 2)** holds the exact inputs of the visibility flags, for the same observer and in the same MOON_ME convention: azimuth clockwise from local north, elevation above the local horizontal.

```json
{ "siteID": "pgda78-site01", "observerHeightMeters": 2.0, "surfaceHeightMeters": 1803.4,
  "sunMinimumDiscFraction": 0.5, "minimumClearanceDeg": 0.0,
  "horizon": { "azimuthStepDeg": 0.5, "maxDistanceMeters": 150000.0,
               "elevationsDeg": [ … 720 values … ], "complete": [ … 720 booleans … ] },
  "samples": { "start": "2026-11-17T00:00:00Z", "stepSeconds": 600.0, "count": 2017,
               "sun":   { "azimuthDeg": [ … ], "elevationDeg": [ … ], "angularRadiusDeg": [ … ] },
               "earth": { "azimuthDeg": [ … ], "elevationDeg": [ … ], "angularRadiusDeg": [ … ] } } }
```

- Ray `i` points at azimuth `i × azimuthStepDeg`.
- `complete` is false where a ray left the DEM before `maxDistanceMeters`; the horizon there is unknown.
- Every sample array has `count` entries.
- Clients may interpolate between neighbouring samples only, never beyond the first or last sample.

### `GET /api/v1/sites` · `GET /api/v1/sites/{siteId}` · `GET /api/v1/datasets`

These return:
- the site list;
- one site;
- the scenario's id, source, provenance and validation records.

### `POST /api/v1/analysis/visibility`

Request (all keys of the app's `VisibilityRequest`):

```json
{
  "siteId": "pgda78-site01",
  "observerLatitudeDeg": null,
  "observerLongitudeDeg": null,
  "observerHeightM": 2.0,
  "utcStart": "2026-11-20T06:00:00Z",
  "utcEnd": "2026-11-21T06:00:00Z",
  "timeStepS": 600,
  "minimumClearanceDeg": 0.0,
  "model": "lunavi-horizon-v1",
  "datasetIds": []
}
```

Response (`VisibilityResponse`):

```json
{
  "scenarioId": "…", "siteId": "pgda78-site01",
  "utcStart": "2026-11-20T06:00:00Z", "utcEnd": "2026-11-21T06:00:00Z",
  "coverage": [{ "start": "…", "end": "…" }],
  "sunlight": [ … ], "earthLineOfSight": [ … ], "combined": [ … ],
  "firstFailure": { "condition": "sunlight", "time": "2026-11-21T08:00:00Z" },
  "events": [ { "id": "…", "condition": "sunlight", "kind": "obstructionBegins", "time": "…", "summary": "…",
                "geometry": { "targetAzimuthDeg": 0, "targetElevationDeg": 0, "horizonElevationDeg": 0, "clearanceDeg": 0 } } ],
  "provenance": [ … ], "assumptions": [ … ], "validation": [ … ],
  "warnings": [],
  "dataQuality": "complete"
}
```

**How the response is built**
- Intervals are clipped to the request window.
- `dataQuality` is one of:
  - `complete`: coverage spans the whole window;
  - `partial`: coverage spans part of the window;
  - `unavailable`: no coverage in the window.
- If the requested observer height or clearance differs from the precomputed assumptions, the response uses the precomputed values and says so in `warnings`.
- `geometry` is present only for computed data.

### `POST /api/v1/analysis/compare`

Request:

```json
{ "siteId": "…", "utcStart": "2026-11-20T06:00:00Z", "durationHours": 24, "delayHours": 6 }
```

The response holds `original` and `delayed` evaluations. Each evaluation contains:
- `siteId`, `utcStart`, `utcEnd`;
- `overall`: `met`, `notMet` or `unknown`;
- `sunlight` and `earthLineOfSight`: each with `status` (`met`, `partial`, `unavailable` or `unknown`), `firstFailure`, `firstUnknown`, and visible, obstructed and unknown seconds;
- `firstFailure`: `{ "condition", "time" }` or `null`.

### `POST /api/v1/analysis/recovery`

The request has the same shape as for compare; `utcStart` is the delayed start. The response holds `candidates`, a list of `{ "kind", "siteId", "evaluation" }`. The rules are the same as in the app:

- **`sameSiteLaterTime`:** the earliest start at or after `utcStart` at which both requirements hold for the whole window.
- **`alternativeSite`:** the nearest other site with data that meets both requirements at `utcStart`. "Nearest" is great-circle distance when both sites have coordinates, otherwise map distance.

The list is empty when the data supports no recovery.
