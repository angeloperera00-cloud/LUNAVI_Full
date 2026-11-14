# Computed date ranges

LUNAVI only evaluates dates for which the science pipeline actually computed results. It never repeats,
shifts or extrapolates one range into another. Each date range is a separate pipeline run, saved as a
separate `ComputedScenario*.json` file in `Lunavi/Resources/`.

## Generate a new range

From `ScienceService/`:

```sh
sh scripts/build_real_data.sh --start 2026-12-01T00:00:00Z --end 2026-12-15T00:00:00Z
```

This writes `Lunavi/Resources/ComputedScenario_20261201_20261215.json` and keeps any other range already
there. Options:

| Option | Meaning |
|---|---|
| `--start`, `--end` | Computation period, UTC. Both are required together. |
| `--step SECONDS` | Sample spacing (default from the config, normally 600 s). Transitions are still bisected to about ±30 s. |
| `--name NAME` | Output name; must start with `ComputedScenario`. |
| `--regenerate-config` | Rebuild `config/sites.json` from the template. Without it, an existing `config/sites.json` is kept, so edits you made there are never overwritten. |

Without `--start/--end`, the `period` in `config/sites.json` is used and the output is
`ComputedScenario.json` (the default range the app loads first).

## What is checked before anything is computed

`python -m lunavi_science check-coverage --config config/sites.json --start … --end …` prints the same
check on its own.

* **Planetary SPK** (e.g. `de421.bsp`): must contain the Sun, Earth–Moon barycentre, Earth and Moon over
  the *whole* period. DE421 covers 1899-07-29 to 2053-10-09.
* **Lunar binary PCK** (e.g. `moon_pa_de421_1900-2050.bpc`): must cover the lunar principal-axes frame
  over the whole period. This kernel ends in 2050, so it is the usual limit.
* **Leapseconds kernel**: has no end date, but only knows leap seconds announced before it was issued.
  Future dates are computed with the current TAI−UTC; this is recorded as a warning (≤ 1 s per
  unannounced leap second).
* **Frame kernels** (`.tf`): no time limit.
* **Terrain**: every site must have a surface height in at least one configured LOLA DEM layer.

A period partly outside any kernel is refused, not clamped. The scenario file records the result under
`coverage.kernels`, together with `period.stepSeconds` and `period.sampleCount`.

## In the app

* **Data & Method › Computed date ranges** lists every bundled range with its period and sampling, and
  switches between them. Switching resets the mission to that range's defaults; data from two ranges is
  never mixed.
* The landing-time editor only offers start times inside the computed coverage of the range in use.
* A plan whose window runs past the end of the data is reported as **Unknown** for the missing part —
  never as visible.
* The app rejects a scenario file whose coverage extends outside its declared computation period.
