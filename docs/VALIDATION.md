# LUNAVI — Validation report

Status as of 14 Nov 2026. Each item says **where it ran**. Nothing here is NASA-certified, operational, or a
landing-safety result. "Tested" means automated tests of the implementation; "validated" means compared
with an independent reference. They are kept separate on purpose.

## 1. Automated tests

### Python (`ScienceService/tests`, 97 tests)

| Environment | Result |
|---|---|
| Linux, Python 3.13, spiceypy (CSPICE N0067), NAIF DE421 lunar kernels | **97 passed** |
| Same, but `spiceypy` not installed (reproduces the earlier external run: 72/73 passed, 21 *errors*) | **76 passed, 21 skipped**, each skip saying "spiceypy is not installed…". The 21 were environment errors, not code failures |

Run in the project's own environment: `sh ScienceService/scripts/run_tests.sh` (creates/uses `.venv`, installs
`requirements.txt` there only, fetches the kernels, prints skip reasons).

New since the previous report: kernel/DEM coverage checks (11), terrain characteristics (10 synthetic + 1 on the
raster code path of a GeoTIFF), period/coverage metadata (1), acceptance scenarios (3).

### Swift (`LunaviTests`, 96 tests; `LunaviUITests`, 1 test)

| Run | Result |
|---|---|
| Developer Mac, 14 Nov 10:42, 39 tests (before P1–P3) | 39 passed |
| Developer Mac, 14 Nov ~12:18, after P1–P3 | Build succeeded; 1 reported failure: `EarthWindowsTests.windowEndsAfterPeriod`. Cause: wrong test data (the test window did not end after the test period). Test corrected; **re-run pending** |
| `RealDataAcceptanceTests` (7 tests, scenarios A–E on the bundled real data) | **Not run yet.** They run only when `ComputedScenario.json` is bundled, and the schema-3 terrain test needs the rebuilt file |
| `DemoFlowUITests` | **Failure step still unidentified.** Every identifier and label it checks exists in the source; the step-labelled message from a Mac run is needed |

Swift code is **not** compiled in the Linux build environment (no Swift toolchain). It is checked there with a
Swift syntax parser (tree-sitter-swift; 0 errors in all files, and it also accepts all 68 original files),
which does not type-check.

## 2. Independently validated calculations

| Calculation | Reference | Result |
|---|---|---|
| Sun/Earth azimuth and elevation from a lunar surface site (SPICE, MOON_ME, LT+S) | **Skyfield** reading the same DE421 kernels, with its own frame and aberration code; 3 sites × 5 epochs × 2 targets | Max difference < 0.001° (measured 0.00003°) — `test_ephemeris.py` |
| Same, for the three computed sites, 17 Nov – 1 Dec 2026 | **JPL Horizons API**, topocentric observer on the Moon (`coord@301`), 342 samples | \|Δ\| < 0.0001° (tolerance 0.05°): **passed** on the developer Mac, 14 Nov 2026 09:37 UTC; recorded in `ComputedScenario.json` |
| UTC → TDB without a leapseconds kernel | Skyfield TDB | Within 0.02 ms |
| Kernel time coverage | The kernels' own coverage windows (SPICE `spkcov`, `pckcov`) | DE421 SPK: 1899-07-29 – 2053-10-09; `moon_pa_de421_1900-2050.bpc`: to 2050-12-31. Periods outside are refused |
| Solar-power estimator (Swift) | An independent Python implementation of the same formula on real DE421 Sun samples | Agreement < 10⁻⁶ relative (Swift test `matchesPythonReference`; pending a Mac run) |

These cover **directions to the Sun and Earth** and the estimator's arithmetic. They do **not** validate the
terrain horizon.

## 3. Verified by analytic or synthetic tests (implementation correctness, not field validation)

- Horizon on a smooth sphere equals the geometric dip (1.944° for a 1 km observer, ±0.01°); ring-wall formula ±0.05°.
- Azimuth convention identical for terrain rays and Sun/Earth (at and off the pole).
- Exported shadow geometry reproduces the bisected intervals at every sample except next to transitions.
- Interval rules shared by Python and Swift: half-open; unknown never success; obstruction outranks unknown;
  exact-boundary cases; recovery search by interval arithmetic.
- Earth windows: coverage edges never reported as transitions; next window unknown when a data gap intervenes.
- Terrain: flat surface → 0° and 0 m; planes with known gradients → exact slope (±0.001°); sinusoid roughness
  bounded by its amplitude; missing samples → unavailable; site coordinate maps to the right DEM point;
  on a 200 m GeoTIFF the fitted slope matches the analytic gradient within 0.5°.
- Solar power: zero/full/half-disc illumination, grazing incidence, invalid inputs, missing geometry,
  inverse-square irradiance, trapezoidal integration with off-grid window edges.
- PDF report: values equal the store; UTC preserved; unknowns stay unknown; long content paginates without
  losing the last row; limitations included.

## 4. Simplified approximations

| Approximation | Effect |
|---|---|
| Local vertical = radial direction of a 1737.4 km sphere | Negligible at these sites |
| Sun disc fraction against a straight horizon segment | Small error where the horizon curves sharply within ±0.27° of azimuth |
| Horizon rays every 0.5° to 150 km, interpolated between | Narrow peaks can be under-resolved |
| 600 s sampling, transitions bisected | Transition times ±30 s |
| Exported angular radii rounded to 0.0001° | ≈ 0.04 % in the solar-irradiance estimate |
| Terrain plane fit over a 25 m disc on the 5 m DEM | Features below ~10 m are not resolved |

## 5. Not validated (explicitly unverified)

- **Terrain horizon / illumination against PGDA product 69** — not run; the `horizon` validation record stays "not validated". Consequently every real-data *visibility interval* is derived from validated directions and an **unvalidated** horizon.
- **Site coordinates** (centroid of the largest > 70 % illumination region in each PGDA 78 archive) — documented, not independently reviewed.
- **Terrain slope/roughness on the real PGDA 78 tiles** — computed with tested code, but not compared with a published slope product.
- **Solar power** — physics simplified; no comparison with any spacecraft or published lunar power study.

## 6. Why some results do not mean what they might seem to

- **Earth line of sight ≠ communication.** It is geometry only: Earth's disc above the modeled terrain. A link also needs antenna pointing, transmitter power, ground-station visibility and scheduling (e.g. DSN), none of which is modelled.
- **Sunlight ≠ usable electrical power.** Visibility says the Sun is above the terrain. Usable power also depends on panel area, efficiency, orientation, temperature, dust, degradation and battery state — the experimental estimate covers only the first three, as user assumptions.
- **Slope/roughness ≠ landing safety.** They describe the DEM surface at 5 m resolution over a 25 m disc. Landing hazards (rocks, small craters, lander tolerances) need a spacecraft-specific hazard model and much finer data.

## Reproduce

```sh
cd ScienceService
sh scripts/run_tests.sh                                                             # section 1 (Python)
.venv/bin/python -m lunavi_science horizons-check --scenario out/ComputedScenario.json --kernels kernels/*
.venv/bin/python -m lunavi_science acceptance --scenario ../Lunavi/Resources/ComputedScenario.json
.venv/bin/python -m lunavi_science check-coverage --config config/sites.json --start 2026-12-01T00:00:00Z --end 2026-12-15T00:00:00Z
```
Swift: open `Lunavi.xcodeproj`, ⌘U.
