# LUNAVI — Scientific methodology and data provenance

What is computed, from which data, and what each number means. Validation status is in `VALIDATION.md`.

## Inputs (provenance)

| Input | Source | Used for |
|---|---|---|
| LOLA DEM, 5 m/pixel site tiles (Site01, Site04, Site11) | NASA GSFC PGDA product 78 | Near-field horizon, terrain characteristics, site coordinates (region files) |
| LOLA DEM, 20 m/pixel 80°S mosaic (`LDEM_80S_20MPP_ADJ.TIF`), read averaged to 80 m | NASA GSFC PGDA product 90 | Far-field horizon to 150 km |
| `de421.bsp` | NASA JPL NAIF | Sun, Earth, Moon positions |
| `moon_pa_de421_1900-2050.bpc`, `moon_080317.tf`, `moon_assoc_me.tf` | NASA JPL NAIF | Lunar orientation, MOON_ME frame |
| `naif0012.tls` | NASA JPL NAIF | UTC ↔ TDB |
| Independent checks | JPL Horizons API; Skyfield | Direction validation only |

Every scenario file records its kernels, DEM layers, resolutions, generation time and validation level in
`metadata.provenance` / `metadata.validation`, and (schema 3) the kernel coverage check in `coverage`.

## Computed quantities

1. **Site coordinates** — planetocentric latitude, east longitude in MOON_ME; centroid of the largest region above
   70 % illumination in each PGDA 78 region archive.
2. **Sun and Earth directions** — SPICE positions with LT+S correction, rotated into the local east-north-up
   frame of a sphere (R = 1737.4 km). Azimuth clockwise from local north; elevation above the local horizontal.
   Angular radius = asin(R_body / distance) (Sun 695,700 km; Earth 6,371 km).
3. **Terrain horizon** — for an observer 2 m above the DEM surface, rays every 0.5° of azimuth out to 150 km,
   including lunar curvature; the horizon is the highest elevation angle along each ray. Sectors where a ray
   leaves the DEM are marked incomplete; times when the Sun or Earth lies in such a sector are excluded from coverage.
4. **Visibility** — Sun: ≥ 50 % of the disc area above the horizon (the centre above it). Earth: any part of the disc
   above the horizon (PGDA product 69 criterion). Sampled every 600 s; each transition bisected to ±30 s.
5. **Intervals and evaluation** — half-open UTC intervals. A requirement is met only if visible for the whole
   window; precedence: known obstruction > unknown (no data) > met. The same rules run in Python (`intervals.py`)
   and Swift (`VisibilityEvaluator`).
6. **Mission Rescue** — option A: earliest later start at the same site with both requirements for the whole
   duration; option B: nearest other site meeting both at the delayed time. Only options that re-evaluate as met are shown.
7. **Shadow geometry (schema 2)** — horizon profile and sampled Sun/Earth azimuth, elevation and radius, so the app
   can show clearance (target elevation − terrain horizon) at any time, interpolating only between samples.
8. **Terrain characteristics (schema 3)** — on the highest-priority DEM layer that resolves the disc: elevation
   (bilinear), least-squares plane over pixel centres within 25 m, slope = atan(|∇z| · k) with the map scale
   factor k, roughness = RMS residual, relief, and the plane-fit standard error of the slope.

## Experimental, app-side

- **Solar power** — P = S × A × η × max(0, n̂·ŝ) × f_disc. S from 1361 W/m² at 1 AU scaled by the Sun's distance
  (from its exported angular radius); A, η, orientation are user assumptions; f_disc is the disc area above the
  terrain. Trapezoidal integration between samples; missing samples are excluded, never assumed sunlit.

## Dataset schema and coverage

| Schema | Adds |
|---|---|
| 1 | Sites, visibility intervals, events, metadata, sensitivity |
| 2 | `geometry`: horizon profile + Sun/Earth samples |
| 3 | `terrain`, `coverage` (kernel/DEM checks), `period.stepSeconds`, `period.sampleCount` |

The app decodes all three (missing parts show as unavailable). The bundled real dataset covers
**17 Nov – 1 Dec 2026** until regenerated; further ranges are added as separate files (see `DATE_RANGES.md`).
Nothing is extrapolated outside a computed period.
