# LUNAVI — Validation report

Status as of 14 Nov 2026. Each item says **where it ran**. Nothing here is NASA-certified, and nothing below is a landing-safety or operational result.

## 1. Automated tests that were actually executed

| Suite | Where | Result |
|---|---|---|
| Python pipeline (`ScienceService/tests`, 71 tests) | Linux build environment, Python 3.13, NAIF DE421 lunar kernels | **71 passed** |
| Swift unit tests (`LunaviTests`, 39 tests) | Developer Mac, Xcode, iPad Pro 13-inch (M5) simulator, 14 Nov 10:42 | **39 passed** (screenshot of the test navigator) |
| Swift UI test (`DemoFlowUITests`) | Same Mac and simulator | **Failed** at an unidentified step; re-run pending with step-labelled assertions |
| Site-comparison tests (`SiteComparisonTests`, 5 tests), added after the run above | — | **Not yet run** |

## 2. Independently validated calculations

| Calculation | Reference | Result |
|---|---|---|
| Sun and Earth azimuth/elevation from a lunar surface site (SPICE, MOON_ME, LT+S) | **Skyfield**: an independent ephemeris implementation reading the same DE421 kernels, with its own frame and aberration code. 3 sites × 5 epochs × 2 targets | Max difference < 0.001° (measured 0.00003°) — `test_ephemeris.py` |
| Same, for the three computed sites over 17 Nov – 1 Dec 2026 | **JPL Horizons API**, topocentric observer on the Moon (`coord@301`); 342 samples | Max \|Δelevation\| and \|Δazimuth\| below 0.0001° (tolerance 0.05°): **passed**. Run on the developer Mac, 14 Nov 2026 09:37 UTC, and recorded in `ComputedScenario.json` |
| UTC → TDB conversion without a leapseconds kernel | Skyfield TDB | Within 0.02 ms |
| Topocentric Earth-up window at the pole | Regression of the validated geometry | 17 Nov 16:40 – 29 Nov 23:40 UTC (centre), ±30 min |

What these checks cover: **directions to the Sun and Earth only**. They do not validate the terrain horizon.

## 3. Verified by analytic tests (implementation correctness, not field validation)

- **Horizon on a smooth sphere:** equals the geometric dip, 1.944° for a 1 km observer, within 0.01°.
- **Ring wall:** matches the curvature formula `atan2(r cosθ − r0, r sinθ)` within 0.05°.
- **Azimuth convention:** identical for terrain rays and Sun/Earth directions, at the pole and off it (`test_horizon.py`).
- **Exported shadow geometry:** recomputing the visibility flags from it reproduces the bisected intervals at every sample, except samples next to a transition (`test_shadow.py`).
- **Interval rules shared by Python and Swift:**
  - half-open windows;
  - unknown is never success;
  - a known obstruction outranks unknown;
  - recovery search is pure interval arithmetic.
- **Spherical stereographic formula:** matches PROJ to 1 mm.
- **Hillshade:** lit from the correct direction.

## 4. Simplified approximations (stated in the app's Data & Method)

| Approximation | Effect |
|---|---|
| Local vertical = radial direction of a 1737.4 km sphere | Negligible for elevation at these sites |
| Sun disc fraction computed against a straight horizon segment | Small error when the horizon curves sharply within ±0.27° of azimuth |
| Horizon rays every 0.5° azimuth to 150 km, interpolated in between | Narrow peaks can be under-resolved |
| Visibility sampled every 600 s, transitions bisected | Transition times ±30 s |
| Shadow panel interpolates linearly between 600 s samples | Display only; requirement states come from the bisected intervals |
| DEM heights read as metres above 1737.4 km; far field averaged to 80 m | Horizon angle accuracy limited by DEM resolution; about 90 % of PGDA 78 pixels are interpolated |

## 5. Not yet validated

- **Terrain horizon / illumination against PGDA product 69** (long-term average Sun and Earth visibility). No comparison has been run, and the `horizon` validation record stays "not validated".
- **Site coordinates.** These are the centroid of the largest region above 70 % illumination in each PGDA 78 archive. That choice is documented but not independently reviewed.
- **The real-data results themselves.** For example, "Sun never blocked at the three sites in 17 Nov – 1 Dec 2026" follows from the validated directions and the unvalidated horizon.

## 6. Unsupported — not modelled, never claimed

- Radio links, antenna pointing, DSN scheduling. Earth line of sight is geometric only.
- Power generation, thermal limits, landing hazards, slopes, rocks.
- Any time-dependent shadow map: the map image is static shaded relief.
- Dates outside the computed period. These show as Unknown, never as visible.

## Reproduce

```sh
cd ScienceService
LUNAVI_KERNEL_DIR=kernels .venv/bin/python -m pytest                                        # section 1, 2, 3
.venv/bin/python -m lunavi_science horizons-check --scenario out/ComputedScenario.json --kernels kernels/*   # section 2
.venv/bin/python -m lunavi_science shadow --scenario ../Lunavi/Resources/ComputedScenario.json             # shadow readings
```
Swift: open `Lunavi.xcodeproj` and press ⌘U.
