# LUNAVI — Lunar Mission Navigator

LUNAVI is a native iPadOS app for exploring lunar south-pole surface-operation windows. Pick a site and a UTC start, and it checks two requirements across the whole window: **sunlight** and **direct Earth line of sight**. Its signature flow is **Mission Rescue**: when a plan is delayed, LUNAVI shows which requirement fails, when and why, then searches for a later start at the same site or an alternative site that meets both requirements again.

Built for the NASA Space Apps Challenge 2026. LUNAVI uses public NASA data products. It is **not** a NASA product and is not affiliated with, approved or endorsed by NASA, JPL or GSFC.

---

## What's in this repository

| Path | What it is |
|---|---|
| `Lunavi.xcodeproj` | Xcode project (Xcode 16+ synchronized folders). Scheme **Lunavi** |
| `Lunavi/` | The app: SwiftUI, Swift 6 language mode, iPadOS 18.0+ |
| `LunaviTests/` | Unit tests (Swift Testing): evaluator, delay simulation, recovery search, store state |
| `LunaviUITests/` | One XCUITest journey through the full Mission Rescue flow; saves 3 screenshots as attachments |
| `ScienceService/` | Python pipeline: LOLA DEM horizons + NAIF SPICE geometry → `ComputedScenario.json`; optional FastAPI service |
| `Tools/generate_illustrative_assets.py` | Regenerates the app icon and the illustrative terrain image (deterministic) |
| `docs/API_CONTRACT.md` | Science service API v1 |
| `ATTRIBUTION.md` | Data sources, citations and credits |

---

## Run the app

Requirements: a Mac with **Xcode 16 or later** and an iPad Simulator runtime (iPadOS 18+).

1. Open `Lunavi.xcodeproj`, choose the **Lunavi** scheme and any iPad simulator, then press Run.
   Simulator builds need no signing team. For a physical iPad, set your team under *Signing & Capabilities*.
2. The app opens in landscape on the simulated demo scenario, fully offline.

### Run the tests from the command line

```sh
# Pick an available iPad simulator
xcrun simctl list devices available | grep -i ipad

# Unit + UI tests (replace the device name with one from the list)
xcodebuild test \
  -project Lunavi.xcodeproj -scheme Lunavi \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  -resultBundlePath build/Lunavi.xcresult

# Export the three screenshots captured by the UI test
xcrun xcresulttool export attachments --path build/Lunavi.xcresult --output-path Screenshots
```

The UI test saves `01-original-mission-plan`, `02-delay-impact` and `03-mission-rescue`. It runs with `-uiTesting`, which disables animations and always uses the simulated fixture, so the scripted journey stays the same even after you bundle computed data.

---

## The 30-second demo

1. **Original plan.** Demo Point A, 20 NOV 2026 06:00 UTC, 24 h. Both requirements are met.
2. **Simulate +6h Delay.** The delayed window fails: sunlight is interrupted from 21 NOV 2026 08:00 UTC (4 h of the window affected). Earth line of sight still holds.
3. **Explain This Change.** What changed, which requirement fails, when it begins, why, and how reliable the conclusion is.
4. **Find Recovery Options.**
   - **A:** same site, later start: 25 NOV 2026 12:00 UTC.
   - **B:** Ridge Site B at the delayed start, 20 NOV 2026 12:00 UTC.
5. **Preview** an option on the map and timeline, then **Apply to Demo Plan**.
6. **Reset Demo** restores the original plan.

Other durations behave differently, by design: at 6 h and 12 h the delay is absorbed; at 48 h the original plan already fails and no recovery exists within the data.

---

## Lunar Shadow Analysis

Open it from **Shadow Analysis** in the toolbar, or from the delay-impact card when a delayed plan fails. It explains *why* a site has, or lacks, sunlight and Earth line of sight at one instant:

- **Readings for the Sun and Earth:**
  - azimuth and elevation;
  - the terrain horizon at that azimuth;
  - clearance above the terrain;
  - how much of the disc is above it (fully visible, partially visible or obstructed);
  - whether the target is above the *ideal* smooth-Moon horizon. This separates terrain obstruction from the target actually setting.
- **360° horizon profile** (Swift Charts): the modeled terrain from LOLA, with the Sun and Earth plotted at their computed positions. The window can be centred on the Sun or shown as 0°–360°.
- **To-scale close-up** looking toward the Sun: the terrain silhouette drawn over the solar disc.
- **Time control.** It moves the mission timeline cursor, so the map, timeline and panel always show the same instant. Values are interpolated only between computed samples; outside them the panel shows **Data Unavailable**.
- **Mission Rescue:**
  - says whether the failure is a terrain obstruction and when it begins and ends;
  - compares each recovery option by its lowest clearance over its whole window.

Requirement badges always come from the computed visibility intervals. The angles explain them.

The simulated demo has no terrain geometry, so the panel shows Data Unavailable there and invents no angles. Real geometry needs a scenario built with pipeline schema 2. Rebuild it with `sh scripts/build_real_data.sh`.

Reproducible example (prints the first computed sunlight transition, or the closest approach if the Sun never touches the terrain in the period):
```sh
cd ScienceService && .venv/bin/python -m lunavi_science shadow --scenario ../Lunavi/Resources/ComputedScenario.json
```

---

## Data modes, and what is real

Each session uses exactly one data source, shown as a badge in the toolbar. Sources are never mixed.

| Badge | Source | When |
|---|---|---|
| **SIMULATED DEMO** | Hand-authored fixture (`DemoMission.json`, `DemoSites.json`, `DemoVisibility.json`) on procedurally generated terrain | Default |
| **COMPUTED** | `ComputedScenario.json` from the science pipeline, bundled in the app | When that file is in `Lunavi/Resources/` |
| **LIVE SERVICE** | The same data, served by the FastAPI service | Launch argument `-scienceServiceURL` |

In simulated mode:
- Site names are generic ("Demo Point A") and map positions are illustrative, not lunar coordinates.
- The terrain image is generated (`Tools/generate_illustrative_assets.py`). It is not NASA imagery, is not to scale, and has no scale bar.
- No angles are shown, because nothing is computed. Real sites named in PGDA product 78 appear in the site list as catalogue entries only, with no analysis.

A fixture served by the live service keeps its SIMULATED label.

---

## Use real NASA data

One command on your Mac (Python 3.10+; roughly 150 MB of downloads, plus streamed reads of the large DEM):

```sh
cd ScienceService
sh scripts/build_real_data.sh
```

It:
1. Sets up Python and downloads the NAIF SPICE kernels.
2. Downloads the 5 m/pixel LOLA tiles and region shapefiles for **Site01 (Connecting Ridge), Site04 (Shackleton Rim) and Site11 (de Gerlache Rim)** from PGDA product 78.
3. Takes each site's coordinate from NASA's own region shapefile (the centroid of its largest region) and records the source.
4. Streams the 80°S regional LOLA DEM (PGDA product 90) for the far horizon. Add `--download-far-field` to download the 2.6 GB file instead.
5. Computes sunlight and Earth line-of-sight for 17 Nov – 1 Dec 2026, checks the geometry against JPL Horizons, and copies `ComputedScenario.json` and `computed_south_pole_basemap.jpg` into `Lunavi/Resources/`.

Then in Xcode: **Product ▸ Clean Build Folder**, and Run. The app now opens on real data:
- the badge reads **COMPUTED**;
- the map is real LOLA terrain with a scale bar, and pins sit at the real site positions;
- Explain This Change shows the computed Sun or Earth azimuth, elevation and horizon at the failure time.

The default plan is picked automatically from the computed windows (a start where +6 h fails and a recovery exists). To go back to the simulated demo, delete those two files from `Lunavi/Resources/`. The UI test always uses the simulated demo.

Manual steps and options are in [`ScienceService/README.md`](ScienceService/README.md).

**Live service (optional):**
1. Run `python -m lunavi_science serve --scenario out/ComputedScenario.json`.
2. Add `-scienceServiceURL http://127.0.0.1:8000` under *Edit Scheme → Run → Arguments*. The simulator can reach the Mac's localhost.
3. Keep the basemap image bundled in the app.

---

## Scientific method (summary)

- **Interval semantics.** UTC intervals are half-open, `[start, end)`. A requirement is met only when visibility covers the **entire** window without interruption; total hours never count as success. Outside a site's data coverage the state is **unknown**, never assumed visible. Precedence is known obstruction > unknown > met.
- **Sun:** at least 50 % of the solar disc above the modeled terrain horizon, i.e. the Sun's centre above it.
- **Earth:** any part of Earth's disc above the horizon, the PGDA product 69 criterion. This is geometric line of sight only, not a radio-link prediction.
- **Horizons.** Rays every 0.5° to 150 km, with curvature, for an observer 2 m above the DEM surface. Sensitivity variants recompute the windows for a 10 m observer and a 0.5° clearance.
- **Recovery search.** Pure interval arithmetic with no time stepping, using exactly the same rules as the evaluation:
  - **A:** the earliest start at or after the delayed start at the same site.
  - **B:** the nearest other site with data that meets both requirements at the delayed start.

The full method, criteria, assumptions, limitations, provenance and validation status are in the app under **Data & Method**.

---

## Verification status

Full details, with where each check ran, are in [`docs/VALIDATION.md`](docs/VALIDATION.md); the method and data
provenance are in [`docs/METHODOLOGY.md`](docs/METHODOLOGY.md).

| Check | Status |
|---|---|
| Python pipeline tests (97) | **Passed** (Linux, Python 3.13, DE421 kernels). Without `spiceypy` installed, 21 are skipped with a reason. Run `sh ScienceService/scripts/run_tests.sh` |
| SPICE Sun/Earth directions vs Skyfield and vs JPL Horizons | **Validated**: < 0.001° and < 0.0001° |
| Pipeline on real LOLA DEMs (17 Nov – 1 Dec 2026) | **Run** on the developer Mac; bundled as `ComputedScenario.json`. Rebuild for schema 3 (terrain) |
| Swift build and unit tests | Built on the developer Mac; one test-data error found and fixed; re-run pending |
| Swift UI test | Failure step still to be identified |
| Terrain horizon vs PGDA product 69 | **Not validated** |

---

## Implemented / not implemented

**Implemented**
- Mission workspace: map, site pins, inspector, visibility timeline, Mission Rescue (delay → impact → explanation → recovery options → preview → apply → reset).
- Lunar Shadow Analysis (Sun/Earth geometry, 360° terrain horizon, clearances at the timeline's inspection time).
- Site Comparison (same UTC window for every site; preview vs Use for Plan).
- Earth Visibility Windows (windows, obstructions, no-data stretches, next window; select to focus the timeline).
- Mission Report: multi-page PDF built from the app's state, with preview, share and save.
- Beginner tutorial (12 steps; opens once on first launch; Help reopens it).
- Computed date ranges: kernel and DEM coverage checks; several bundled ranges; start times limited to computed coverage.
- Experimental Solar Power Estimate and Terrain Characteristics (elevation, slope, roughness).

**Not implemented**
- On-demand computation for arbitrary coordinates (the service refuses rather than guessing).
- Comparison with PGDA product 69; landing-hazard modelling; radio-link modelling; light appearance.

---

## Limitations

- Earth line of sight is geometric only — not a radio link. Sunlight visibility is not usable power; the power figure is an experimental estimate from user assumptions. Slope and roughness characterise the DEM; they do not certify landing safety.
- Horizon accuracy is limited by DEM resolution and interpolation (about 90 % of PGDA product 78 pixels are interpolated); the terrain horizon is not independently validated.
- Results exist only for computed periods; outside them the app shows Unknown. Not a NASA product; not for operational planning.

---

## License

Original LUNAVI code and assets: Apache License 2.0 (`LICENSE`). Third-party data keep their own terms; see `ATTRIBUTION.md`.
