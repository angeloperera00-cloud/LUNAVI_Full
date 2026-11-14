# LUNAVI science pipeline

This pipeline computes **geometric Sun and Earth visibility** at lunar south-pole sites from two public NASA sources:
- LOLA elevation models from the NASA GSFC Planetary Geodynamics Data Archive (PGDA).
- NAIF SPICE ephemerides.

It writes `ComputedScenario.json` and a LOLA-derived basemap. Bundle those in the app, or serve them through a small FastAPI service. Results are geometric line-of-sight only: no power, thermal, radio-link or landing-safety modelling.

```
config (sites + DEM paths + kernels)
   │
   ├─ SPICE: Sun/Earth position in MOON_ME, LT+S, seen from the site  ──┐
   ├─ LOLA DEMs: horizon mask per site (0.5° rays to 150 km, curvature) ─┤
   │                                                                     ▼
   │                     sampled visibility (600 s) → transitions bisected to ±30 s
   │                     coverage = times when the target's horizon sector is fully inside the DEMs
   ▼
ComputedScenario.json + computed_south_pole_basemap.jpg  →  Lunavi/Resources/  (or `serve`)
```

## Quick start: one command

```sh
sh scripts/build_real_data.sh            # streams the 2.6 GB far-field DEM
sh scripts/build_real_data.sh --download-far-field
```

This runs steps 1–5 below automatically for Site01, Site04 and Site11. Coordinates come from NASA's region shapefiles via `make-config` (see step 3), and the results are copied into `Lunavi/Resources/`.

## Install

Requires Python 3.11+.

```sh
cd ScienceService
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
```

## 1. SPICE kernels

```sh
sh scripts/fetch_kernels.sh     # into ScienceService/kernels/
```

This downloads the DE421 lunar set from NAIF `generic_kernels`:
- `naif0012.tls`
- `de421.bsp`
- `moon_pa_de421_1900-2050.bpc`
- `moon_080317.tf`
- `moon_assoc_me.tf`

The frame is **MOON_ME**, the frame of the LOLA DEMs. To use DE440 instead, load `de440s.bsp`, `moon_pa_de440_200625.bpc` and the current `moon_de440_*.tf`. That frame kernel's `MOON_ME` is NAIF's DE421-compatible mean-Earth frame. Record your choice in `ephemerisLabel`.

## 2. LOLA elevation data

Download into `ScienceService/data/`, or point the config at `/vsicurl/https://…` URLs. All files are cloud-optimised GeoTIFFs, so rasterio reads only the windows it needs.

| Role | Product | Files |
|---|---|---|
| Near field | [PGDA product 78](https://pgda.gsfc.nasa.gov/products/78): 5 m/pixel, about 16 × 16 km around each site | `SiteXX_final_adj_5mpp_surf.tif`; `SiteXX_ROIs.tgz` (region shapefiles) |
| Far field | [PGDA product 90](https://pgda.gsfc.nasa.gov/products/90): 80–90°S at 20 m/pixel (other scales available) | `LDEM_80S_20MPP_ADJ.TIF`; optional `LDEM_80S_20MPP_ADJ_HILL.TIF` hillshade |

Both products use south polar stereographic X/Y in metres, in the MOON_ME frame of DE421. The far-field layer is needed because terrain up to ~150 km away sets the polar horizon. Lunar curvature drops terrain by about 2.9 km at 100 km, which is comparable to south-pole relief.

## 3. Configure

```sh
cp config/sites.example.json config/sites.json
```

Or generate it from downloaded PGDA product 78 files (`data/SiteXX_final_adj_5mpp_surf.tif` and `data/SiteXX_ROIs.tgz`):

```sh
python -m lunavi_science make-config --data data --out config/sites.json --sites Site01 Site04 Site11
```

`make-config` uses the centroid of each site's largest region in its NASA shapefile, prints every region it found, and records the chosen one in `coordinateSource`. Edit the coordinates if you want a specific point inside a region.

To write the config by hand, fill in:
- **Site coordinates** (`latitude`, `longitude`, `coordinateSource`). Take them from a citable source, for example:
  - the ROI shapefiles in `SiteXX_ROIs.tgz`;
  - the Wueller et al. (2026) `Landing_Sites` shapefile (CC BY 4.0).

  The builder refuses a site without all three fields. Never estimate coordinates from an image.
- **DEM paths and versions.**
- **`period`.** UTC start, end and sampling step. Earth is above the south pole's horizon roughly 17–30 Nov 2026, so the template uses 17 Nov – 1 Dec.
- **`model`.** Observer height (2 m), clearance (0°), Sun disc fraction (0.5), ray length, azimuth step, and the sensitivity variants.
- **`mission`.** Duration, delay and duration options shown in the app.

## 4. Build

```sh
python -m lunavi_science build --config config/sites.json --out out
```

**Outputs in `out/`**
- `ComputedScenario.json`
- `computed_south_pole_basemap.jpg`

**What the build does for each site**
1. Computes the horizon mask.
2. Samples the Sun and Earth directions.
3. Bisects each visibility transition.
4. Records events with the computed azimuth, elevation, horizon and clearance at each transition.
5. Recomputes sensitivity variants at the default plan's site.

**Default plan.** The app's default plan is chosen automatically: the first whole-hour start where the plan meets both requirements, the +6 h copy fails, and the app's recovery search finds an option. If none exists, the scenario says so in its assumptions.

**Validation.** Every output is checked against the app's schema before it is written.

**Use it in the app**

```sh
cp out/ComputedScenario.json out/computed_south_pole_basemap.jpg ../Lunavi/Resources/
```

## 5. Check the ephemeris against JPL Horizons (optional)

```sh
python -m lunavi_science horizons-check --scenario out/ComputedScenario.json --kernels kernels/*
```

**What it does**
1. Requests apparent azimuth and elevation (quantity 4) of the Sun and Earth from each site through the [Horizons API](https://ssd-api.jpl.nasa.gov/doc/horizons.html). Requests use `CENTER='coord@301'`, `COORD_TYPE='GEODETIC'` and `SITE_COORD='E-lon,lat,alt_km'`.
2. Compares the results with SPICE and writes an `ephemeris` validation record into the scenario.
3. Exits 0 when the worst elevation difference is within `--tolerance-deg` (default 0.05°).

The default tolerance allows for any difference between Horizons' lunar body-fixed model and MOON_ME. Tighten it once you've confirmed which frame Horizons uses.

**Before relying on it**
- The API page documents `coord` with `SITE_COORD` but not the `@301` body suffix. Confirm that syntax in the Horizons manual if the request is rejected.
- This check covers directions only, not the terrain horizon.

## 6. Serve (optional)

```sh
python -m lunavi_science serve --scenario out/ComputedScenario.json --port 8000
```

Start the app with the launch argument `-scienceServiceURL http://127.0.0.1:8000`. The service serves the precomputed scenario and evaluates plans with the same interval rules as the app. It refuses sites or coordinates it has no computed data for, rather than guessing. See `../docs/API_CONTRACT.md`.

## Shadow analysis data (schema 2)

`build` also writes a `geometry` block per site: the horizon mask and the Sun and Earth directions at every sample. These are the same numbers the visibility flags were computed from. The app's Lunar Shadow Analysis panel reads them.

To print a reproducible example (the first computed sunlight transition with readings around it, or the closest approach if there is none):

```sh
python -m lunavi_science shadow --scenario out/ComputedScenario.json
python -m lunavi_science shadow --scenario out/ComputedScenario.json --site pgda78-site01 --time 2026-11-29T15:00:00Z
```

`test_shadow.py` recomputes the flags from the exported geometry at every sample and checks they match the bisected intervals, apart from samples next to a transition.

## Other commands

```sh
python -m lunavi_science validate --scenario out/ComputedScenario.json   # schema check against the app's Codable models
```

## Tests

```sh
LUNAVI_KERNEL_DIR=kernels python -m pytest
```

**Coverage**

| Test file | What it checks |
|---|---|
| `test_intervals.py` | Interval logic against the app's own fixture: the same answers as the Swift tests |
| `test_horizon.py` | Horizons on analytic terrain: flat-sphere dip, a ring wall against the curvature formula, the azimuth convention at and off the pole, incomplete sectors, layer priority, PROJ against the spherical formula |
| `test_visibility.py` | Disc criteria, bisection, half-open intervals, hillshade orientation |
| `test_ephemeris.py` | SPICE directions against **Skyfield**, an independent implementation reading the same DE421 kernels (agreement < 0.001°); UTC→TDB against Skyfield |
| `test_pipeline_synthetic.py` | A full build on a synthetic GeoTIFF. Checks schema; full coverage; events on the horizon; sensitivity monotonicity (a higher observer sees more, a clearance sees less); basemap georeferencing; refusal of uncited sites |
| `test_api.py`, `test_schema.py` | Endpoints, error envelopes, and the schema validator against the app's fixture |

SPICE tests are skipped, not failed, when the kernels are missing.

The synthetic DEM in the tests is invented terrain, used only to exercise the pipeline. It is never bundled.

## Method notes

- **Frames.** Directions are computed in MOON_ME with `spkpos(target, et, "MOON_ME", "LT+S", "MOON")`, minus the site vector. Local up is the radial direction of a 1737.4 km sphere; azimuth runs clockwise from local north. Rays and target azimuths share one east/north basis, so the conventions agree even at the pole.
- **Horizon.** For each azimuth, the horizon is the maximum of `atan2(r cosθ − r0, r sinθ)` along the great-circle ray. Here `r = R + h(θ)` and `r0 = R + h_site + observer_height`. Rays are sampled every 10 m to 2 km, then geometrically spaced to 150 km.
- **Sun.** Visible when at least 50 % of the disc is above the horizon plus clearance, equivalent to the Sun's centre being above it. The disc fraction uses a straight-horizon approximation.
- **Earth.** Visible when any part of the disc is above the horizon plus clearance, the PGDA product 69 criterion. Earth's angular radius from the lunar surface is about 0.89–1.03°.
- **Coverage.** Times when the target's azimuth falls in a sector whose ray left the DEMs before 150 km are excluded. The app shows them as unknown.
- **Time.** UTC→TDB uses the loaded leapseconds kernel. Without one, a built-in implementation of the same formula is used (TAI−UTC = 37 s); it is valid only for dates from 2017 until the next leap second.

## Limitations

- DEM resolution and interpolation limit horizon accuracy; about 90 % of PGDA product 78 pixels are interpolated (Barker et al., 2021).
- Transition times are accurate to about ±30 s plus model error, and are displayed to the minute.
- There is no automated comparison with PGDA product 69 yet. The `horizon` validation record stays "not validated" until one is done.
