# LUNAVI — Scientific validation report

Status 14 Nov 2026. Every number below was **measured**; where each ran is stated. Nothing here is
NASA-certified, operational, or a landing-safety result. "Internally verified" = checked by tests or a second
implementation of our own; "independently validated" = compared with an external reference (JPL Horizons,
NASA PGDA 69). Raw results: `docs/validation_results/validation_results.{md,json}` (run 2026-11-14 15:53 UTC
on the developer Mac with the bundled real dataset). Reproduce: `cd ScienceService && sh scripts/validate_science.sh`.

## Classification

| Scientific feature | Classification | Evidence |
|---|---|---|
| Sun/Earth azimuth & elevation (SPICE) | **Independently validated** | JPL Horizons: \|Δ\| < 0.0001° over 342 samples (Nov) and 2,166 samples (Dec–Feb); 18 per-case instants Δel ≤ 0.00004° (0.14″); Skyfield < 0.001° |
| UTC → TDB, kernel coverage | **Independently validated** | naif0012 LSK; Skyfield TDB < 0.02 ms; periods outside DE421 / the 2050 lunar PCK are refused |
| Terrain-horizon algorithm | **Internally verified** | Exported = recomputed (5×10⁻⁵°); independent all-cells method agrees, max 0.14–0.29° (near field), app never above the cells |
| Terrain horizon vs real terrain | **Not yet validated** | PGDA 69 comparison inconclusive (§3); 20–47 % of directions set by terrain < 1.15 km, not cross-checked |
| Visibility criteria (disc fraction, Earth any-part) | **Internally verified** | Formula = numerically integrated disc area (< 10⁻⁵) |
| Mission decisions (met / not met / unknown) | **Internally verified** | 5 scenarios recomputed independently (SPICE every 60 s): all agree, obstruction times within 15 s |
| Mission Rescue | **Internally verified** | Minute-by-minute brute force agrees (option A none, option B de Gerlache Rim) |
| Missing-data handling | **Internally verified** | After the period: Unknown at every site; windows past the data report the missing hours |
| Terrain slope / roughness | **Internally verified, approximate** | Synthetic planes exact (±0.001°); not compared with a published slope product |
| Solar power estimate | **Approximate / experimental** | Matches an independent Python computation < 10⁻⁶; physics simplified, user-assumed panel |
| Radio links, landing hazards, thermal, battery | **Unsupported** | Not modelled; never claimed |

## 1. Inputs

| Input | Version / resolution |
|---|---|
| NASA GSFC PGDA 78 site DEMs Site01, Site04, Site11 | 5 m/pixel (`SiteXX_final_adj_5mpp_surf.tif`) |
| NASA GSFC PGDA 90 `LDEM_80S_20MPP_ADJ.TIF` | 20 m/pixel, read averaged to 80 m |
| NAIF kernels | `naif0012.tls`, `de421.bsp`, `moon_pa_de421_1900-2050.bpc`, `moon_080317.tf`, `moon_assoc_me.tf` |
| Sites (centroid of largest > 70 % illumination region, PGDA 78 ROI files) | Connecting Ridge −89.4527, −137.1523; Shackleton Rim −89.7621, −157.0750; de Gerlache Rim −88.6683, −68.3754 |
| Model | Observer 2 m above DEM; rays every 0.5° to 150 km with curvature; Sun ≥ 50 % of disc; Earth any part; 600 s sampling, transitions bisected ±30 s |
| Computed ranges | 17 Nov – 1 Dec 2026 (2,017 samples); 1 Dec 2026 – 1 Mar 2027 (12,961 samples) |

## 2. Terrain horizon: app vs an independent implementation

The app's horizon (ray marching, bilinear DEM samples) was compared with a separately written method that takes
**every DEM cell** in 3-D and keeps the highest per azimuth wedge (`horizon_independent.py`). A wedge is a fair
reference only where it is ≥ 2 cells wide: beyond 1,146 m on the 5 m tiles (0.5° step) and beyond 4.6 km for all
layers (2° step). Δ = independent − app (positive is expected: a wedge contains peaks beside the ray).

| Site | Band | Mean Δ | p95 \|Δ\| | Max \|Δ\| | App above cells by > 0.05° |
|---|---|---|---|---|---|
| Connecting Ridge | 5 m tile, ≥ 1,146 m | +0.024° | 0.058° | 0.141° | 0 of 720 |
| | all layers, ≥ 4.6 km, 2° | +0.095° | 0.259° | 0.384° | 0 of 180 |
| Shackleton Rim | 5 m tile | +0.061° | 0.210° | 0.291° | 0 |
| | all layers | +0.097° | 0.247° | 0.359° | 0 |
| de Gerlache Rim | 5 m tile | +0.030° | 0.080° | 0.136° | 0 |
| | all layers | +0.097° | 0.269° | 0.391° | 0 |

Horizon set closer than 1,146 m (not cross-checkable): Connecting Ridge 335 / 720 rays (47 %), Shackleton Rim 142
(20 %), de Gerlache Rim 257 (36 %). The exported horizon equals a fresh recomputation to 5×10⁻⁵° at all sites.

## 3. 18.6-year averages vs NASA PGDA product 69 (60 m/px)

PGDA 69 (`AVGVISIB_85S_060M_201608[_EARTH].TIF`, https://pgda.gsfc.nasa.gov/products/69) averages hourly samples
over one 18.6-year nutation cycle; its observer height and epoch are not stated. LUNAVI: hourly SPICE directions
2017-01-01 + 18.6 years (163,047 samples) against LUNAVI's horizon, mean visible disc fraction.

| Site | | PGDA 69 centre (3×3 range) | LUNAVI h = 0 m | LUNAVI h = 2 m |
|---|---|---|---|---|
| Connecting Ridge | Sun | 0.685 (0.454–0.864) | 0.539 | 0.858 |
| | Earth | 0.575 (0.511–0.582) | 0.517 | 0.537 |
| Shackleton Rim | Sun | 0.662 (0.205–0.760) | 0.418 | 0.801 |
| | Earth | 0.452 (0.000–0.502) | 0.355 | 0.456 |
| de Gerlache Rim | Sun | 0.794 (0.383–0.794) | 0.545 | 0.827 |
| | Earth | 0.614 (0.498–0.614) | 0.466 | 0.569 |

**Conclusion: not validated.** Earth averages mostly fall within PGDA 69's 3×3 range. Sun averages bracket PGDA 69
(lower at 0 m, higher at 2 m) and the 2 m values exceed the 3×3 maximum at two of three sites. The sites lie on
steep illumination gradients at 60 m scale, and the result depends strongly on observer height and on terrain
within ~1 km resolved by the 5 m DEM but smoothed at 60 m. A like-for-like comparison would need the 60 m DEM
and PGDA 69's observer height.

## 4. Visibility cases (real data, SPICE recomputed exactly; Horizons at the same instant)

All app states equal the stored intervals; Horizons Δaz ≈ 0.0°, Δel ≤ 0.00004° in every row. The Sun is never
blocked at any site in 17 Nov – 1 Dec 2026 (smallest Sun clearance: Shackleton Rim +0.58°, 23 Nov 09:20).

| Site | Case | UTC | Az | El | Horizon app / indep. | Clearance | States app / indep. / stored |
|---|---|---|---|---|---|---|---|
| Connecting Ridge | Earth closest to criterion | 30 Nov 20:40 | 143.76° | −1.84° | −0.865° / −0.855° (set at 134 km) | −0.97° | obstructed ×3 |
| Connecting Ridge | Earth clearly visible | 23 Nov 18:30 | 133.19° | +5.85° | −1.899° / −1.879° | +7.75° | visible ×3 |
| de Gerlache Rim | Earth closest to criterion | 30 Nov 23:50 | 75.02° | −1.26° | −1.417° / −1.412° | +0.16° | visible ×3 |
| Shackleton Rim | Earth closest to criterion | 30 Nov 03:20 | 163.27° | −0.48° | +0.501° / −0.818° | −0.98° | obstructed / visible / obstructed |
| Shackleton Rim | Sun closest to criterion | 23 Nov 09:20 | 169.53° | +1.29° | +0.715° / −1.163° | +0.58° | visible ×3 |

At Shackleton Rim the app's horizon in the Earth/Sun directions is set by terrain **510–630 m** from the site
(+0.4° to +0.7°), inside the zone the independent method cannot resolve. These rows are consistent but **not
cross-checked**; the independent value excludes that near terrain by design.

## 5. Mission decisions (real data): app vs independent 60 s recomputation

| Scenario | App | Independent | First obstruction | Δ (s) |
|---|---|---|---|---|
| A Connecting Ridge, 29 Nov 15:00, 24 h | met | met | — | — |
| B Shackleton Rim, 29 Nov 15:00, 6 h | met | met | — | — |
| C Connecting Ridge, 29 Nov 15:00, 48 h | not met (Sun unknown 15 h, Earth partial) | same | Earth 30 Nov 20:38:45 | 15 |
| A + 6 h delay | not met (Earth partial, 0.35 h) | same | Earth 30 Nov 20:38:45 | 15 |
| D first Earth obstruction, 6 h | not met | same | 30 Nov 20:38:45 | 0 |

## 6. Mission Rescue (delayed start 29 Nov 21:00, 24 h)

Option A (same site later): none in the computed data; brute force over every minute to the end of coverage
agrees. Option B: de Gerlache Rim, the only qualifying site (nearest-first order: Shackleton Rim fails, de Gerlache
Rim meets both); re-evaluated as met; duration preserved.

## 7. Sensitivity (all sites, full period)

| Variant | Max transition shift | Scenario status changes |
|---|---|---|
| Observer 1 m / 5 m / 10 m | 360 / 324 / 684 min (Shackleton Rim Earth) | none |
| Azimuth step 0.25° / 1° | 8.4 / 11.9 min | none |
| Sampling 300 s | 0 | none |
| Sun threshold any part / whole disc | 0 | none |
| Clearance +0.1° | 95 min | none |
| Search radius 100 km | — | **A + delay: not met → met; C: not met → unknown** |
| Search radius 250 km | blocked (remote DEM read failed) | — |

Findings: (1) Scenario A and B results are robust to every tested variant. (2) The Mission Rescue failure
(Earth at Connecting Ridge, 30 Nov 20:38:45) is caused by terrain **~134 km** away; with a 100 km radius it
disappears. Terrain beyond 150 km is not modelled and could not be tested (250 km run failed). (3) Earth transitions
at Shackleton Rim move by hours with observer height because they are controlled by terrain ~0.6 km away.

## 8. Terrain characteristics (real data, 25 m disc on the 5 m DEM; plane-fit uncertainty only)

| Site | Elevation | Slope | Roughness (RMS) | Relief |
|---|---|---|---|---|
| Connecting Ridge | 1,956.4 m | 1.40° ± 0.05° | 0.10 m | 1.2 m |
| Shackleton Rim | 1,729.3 m | 3.69° ± 0.33° | 0.64 m | 4.0 m |
| de Gerlache Rim | 1,814.2 m | 0.94° ± 0.09° | 0.16 m | 1.2 m |

Characterisation of the DEM only — not a landing-safety certification.

## 9. Automated tests

| Suite | Result |
|---|---|
| Python, 105 tests (`sh scripts/run_tests.sh`, developer Mac and Linux) | 105 passed (104 confirmed on the Mac before the last two tests were added) |
| Swift unit tests, 97 | passed on the Mac (iPad Pro 13-inch M5 simulator, iPadOS 27.0) |
| Swift UI test (Mission Rescue journey) | passed once (15:31); later runs fail at Step 7 (Explain button not tappable by the test runner); diagnosis in progress |

## 10. Defects found during validation

| Defect | Where | Fixed |
|---|---|---|
| Wedge comparison unfair near the observer | validation tool | Fair-distance rule D0 = 2·cell/step |
| Horizons per-case query passed "10"/"399" instead of "SUN"/"EARTH" | validation tool | Yes, regression test |
| Period-end instant (unknown by design) picked as a case | validation tool | Yes, regression test |
| Transition matching mixed rises and sets | validation tool | Yes |

No error was found in LUNAVI's scientific code.

## 11. Why results do not mean more than they say

- **Earth line of sight ≠ communication**: geometry only; no antenna, link budget, ground station or DSN scheduling.
- **Sunlight ≠ usable power**: the experimental estimate covers irradiance, panel geometry and terrain shadowing only.
- **Slope/roughness ≠ landing safety**: 5 m DEM over 25 m; rocks and small craters are not resolved.
