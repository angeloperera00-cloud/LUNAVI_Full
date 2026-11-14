# LUNAVI scientific validation results

Generated 2026-11-14T15:53:30Z from `ComputedScenario.json`; period {'start': '2026-11-17T00:00:00Z', 'end': '2026-12-01T00:00:00Z', 'stepSeconds': 600.0, 'sampleCount': 2017}.
Observer 2.0 m; horizon rays every 0.5° to 150 km.

Sites: Connecting Ridge (-89.4527, -137.152253); Shackleton Rim (-89.762051, -157.074964); de Gerlache Rim (-88.668317, -68.375442)

## 1. Terrain horizon: app (ray marching) vs independent (all DEM cells)

| Site | Exported = recomputed (max Δ°) | Band | Rays | Mean Δ° | p95 abs Δ° | Max abs Δ° | Ray above cells >0.05° |
|---|---|---|---|---|---|---|---|
| pgda78-site01 | 5e-05 | nearFieldTile ≥1146 m, 0.5° | 720 | 0.0237 | 0.0579 | 0.1407 | 0 |
| pgda78-site01 | 5e-05 | allLayersFarField ≥4584 m, 2.0° | 180 | 0.0953 | 0.2585 | 0.3835 | 0 |
| pgda78-site01 | | horizon set by | {'<1146 m (not cross-checked)': 335, '1146 m – 4.6 km': 19, '≥4.6 km': 366, 'rays': 720} | | | | |
| pgda78-site04 | 5e-05 | nearFieldTile ≥1146 m, 0.5° | 720 | 0.0611 | 0.2096 | 0.2907 | 0 |
| pgda78-site04 | 5e-05 | allLayersFarField ≥4584 m, 2.0° | 180 | 0.097 | 0.2465 | 0.359 | 0 |
| pgda78-site04 | | horizon set by | {'<1146 m (not cross-checked)': 142, '1146 m – 4.6 km': 45, '≥4.6 km': 533, 'rays': 720} | | | | |
| pgda78-site11 | 5e-05 | nearFieldTile ≥1146 m, 0.5° | 720 | 0.0297 | 0.0797 | 0.1363 | 0 |
| pgda78-site11 | 5e-05 | allLayersFarField ≥4584 m, 2.0° | 180 | 0.0972 | 0.2691 | 0.3912 | 0 |
| pgda78-site11 | | horizon set by | {'<1146 m (not cross-checked)': 257, '1146 m – 4.6 km': 4, '≥4.6 km': 459, 'rays': 720} | | | | |

## 2. 18.6-year averages vs NASA PGDA product 69 (60 m/px)

| Site | Quantity | PGDA 69 centre (3×3 range) | LUNAVI h=0 m disc fraction | LUNAVI h=0 m centre above | LUNAVI h=2 m disc fraction |
|---|---|---|---|---|---|
| pgda78-site01 | sun | 0.6848 (0.4536–0.8642) | 0.5388 | 0.5382 | 0.8584 |
| pgda78-site01 | earth | 0.575 (0.5112–0.5817) | 0.5173 | 0.5173 | 0.5368 |
| pgda78-site04 | sun | 0.6624 (0.2051–0.7603) | 0.418 | 0.4187 | 0.8006 |
| pgda78-site04 | earth | 0.4522 (0.0–0.5021) | 0.3554 | 0.3559 | 0.456 |
| pgda78-site11 | sun | 0.7938 (0.3832–0.7938) | 0.545 | 0.5494 | 0.8274 |
| pgda78-site11 | earth | 0.614 (0.4976–0.614) | 0.4663 | 0.4663 | 0.5686 |

## 3. Visibility cases

| Site | Case | UTC | Az° | El° | Horizon app° | Horizon indep.° | Clearance app° | State app / indep. / stored | ΔHorizons az, el (°) | Conclusion |
|---|---|---|---|---|---|---|---|---|---|---|
| pgda78-site01 | Sun clearly visible | 2026-11-30T17:30:00Z | 60.5222 | 1.7411 | -2.6693 | -2.6441 | 4.4104 | visible / visible / visible | -0.0, 1e-05 | agree |
| pgda78-site01 | Sun closest to the criterion | 2026-11-20T13:20:00Z | 183.9994 | 0.9967 | -0.8715 | -1.7107 | 1.8681 | visible / visible / visible | -0.0, 0.0 | app consistent; horizon here is set 630 m from the site (< 1146 m), inside the zone the independent method cannot resolve — not cross-checked |
| pgda78-site01 | Sun blocked |  |  |  |  |  |  |  /  /  | ,  | no such instant in the computed period |
| pgda78-site01 | Earth clearly visible | 2026-11-23T18:30:00Z | 133.1925 | 5.8542 | -1.8985 | -1.8789 | 7.7527 | visible / visible / visible | -0.0, 0.0 | agree |
| pgda78-site01 | Earth closest to the criterion | 2026-11-30T20:40:00Z | 143.7559 | -1.8375 | -0.865 | -0.855 | -0.9726 | obstructed / obstructed / obstructed | -0.0, 4e-05 | agree |
| pgda78-site01 | Earth blocked | 2026-11-30T23:50:00Z | 143.8102 | -2.0415 | -0.8633 | -0.8546 | -1.1781 | obstructed / obstructed / obstructed | -0.0, 4e-05 | agree |
| pgda78-site01 | Missing data (1 h after the computed period) | 2026-12-01T01:00:00Z |  |  |  |  |  |  /  / unknown | ,  | unknown, as required |
| pgda78-site04 | Sun clearly visible | 2026-11-18T09:50:00Z | 229.9973 | 1.3968 | -2.4059 | -2.3986 | 3.8027 | visible / visible / visible | -0.0, -0.0 | agree |
| pgda78-site04 | Sun closest to the criterion | 2026-11-23T09:20:00Z | 169.5312 | 1.2946 | 0.7146 | -1.1631 | 0.58 | visible / visible / visible | -0.0, 1e-05 | app consistent; horizon here is set 570 m from the site (< 1146 m), inside the zone the independent method cannot resolve — not cross-checked |
| pgda78-site04 | Sun blocked |  |  |  |  |  |  |  /  /  | ,  | no such instant in the computed period |
| pgda78-site04 | Earth clearly visible | 2026-11-24T02:30:00Z | 153.6628 | 6.0398 | 0.4248 | -0.8748 | 5.615 | visible / visible / visible | -0.0, 1e-05 | app consistent; horizon here is set 510 m from the site (< 1146 m), inside the zone the independent method cannot resolve — not cross-checked |
| pgda78-site04 | Earth closest to the criterion | 2026-11-30T03:20:00Z | 163.2702 | -0.4824 | 0.5006 | -0.8175 | -0.9831 | obstructed / visible / obstructed | -0.0, 4e-05 | app consistent; horizon here is set 630 m from the site (< 1146 m), inside the zone the independent method cannot resolve — not cross-checked |
| pgda78-site04 | Earth blocked | 2026-11-30T23:50:00Z | 163.74 | -1.8282 | 0.4608 | -0.9458 | -2.2889 | obstructed / visible / obstructed | -0.0, 4e-05 | app consistent; horizon here is set 630 m from the site (< 1146 m), inside the zone the independent method cannot resolve — not cross-checked |
| pgda78-site04 | Missing data (1 h after the computed period) | 2026-12-01T01:00:00Z |  |  |  |  |  |  /  / unknown | ,  | unknown, as required |
| pgda78-site11 | Sun clearly visible | 2026-11-26T09:10:00Z | 44.5537 | 2.4551 | -2.411 | -2.4277 | 4.8662 | visible / visible / visible | -0.0, 1e-05 | app consistent; horizon here is set 180 m from the site (< 1146 m), inside the zone the independent method cannot resolve — not cross-checked |
| pgda78-site11 | Sun closest to the criterion | 2026-11-20T13:50:00Z | 114.997 | 0.9801 | -0.7483 | -0.7452 | 1.7284 | visible / visible / visible | -0.0, 0.0 | agree |
| pgda78-site11 | Sun blocked |  |  |  |  |  |  |  /  /  | ,  | no such instant in the computed period |
| pgda78-site11 | Earth clearly visible | 2026-11-24T02:20:00Z | 65.0831 | 6.816 | -0.796 | -0.7766 | 7.612 | visible / visible / visible | -0.0, 1e-05 | agree |
| pgda78-site11 | Earth closest to the criterion | 2026-11-30T23:50:00Z | 75.0161 | -1.2558 | -1.4172 | -1.4119 | 0.1614 | visible / visible / visible | -0.0, 4e-05 | agree |
| pgda78-site11 | Earth blocked |  |  |  |  |  |  |  /  /  | ,  | no such instant in the computed period |
| pgda78-site11 | Missing data (1 h after the computed period) | 2026-12-01T01:00:00Z |  |  |  |  |  |  /  / unknown | ,  | unknown, as required |

## 4. Mission decisions: app intervals vs independent 60 s recomputation

D: first earthLineOfSight obstruction in the data

| Scenario | Site, start, h | App: overall (sun, earth) | Independent: overall (sun, earth) | First obstruction app | Δ independent−app (s) | Agree |
|---|---|---|---|---|---|---|
| A | pgda78-site01, 2026-11-29T15:00:00Z, 24 | met (met, met) | met (met, met) | None | {'sunlight': None, 'earthLineOfSight': None} | True |
| B | pgda78-site04, 2026-11-29T15:00:00Z, 6 | met (met, met) | met (met, met) | None | {'sunlight': None, 'earthLineOfSight': None} | True |
| C | pgda78-site01, 2026-11-29T15:00:00Z, 48 | notMet (unknown, partial) | notMet (unknown, partial) | 2026-11-30T20:38:45Z | {'sunlight': None, 'earthLineOfSight': 15.0} | True |
| A+delay | pgda78-site01, 2026-11-29T21:00:00Z, 24 | notMet (met, partial) | notMet (met, partial) | 2026-11-30T20:38:45Z | {'sunlight': None, 'earthLineOfSight': 15.0} | True |
| D | pgda78-site01, 2026-11-30T17:38:45Z, 6 | notMet (met, partial) | notMet (met, partial) | 2026-11-30T20:38:45Z | {'sunlight': None, 'earthLineOfSight': 0.0} | True |

## 5. Mission Rescue vs brute force

```
{
  "delayedStart": "2026-11-29T21:00:00Z",
  "hours": 24,
  "proximityOrder": [
    "pgda78-site04",
    "pgda78-site11"
  ],
  "optionA": null,
  "bruteForceEarliestSameSite (1-min steps)": null,
  "optionA_matchesBruteForce": true,
  "optionB": "pgda78-site11",
  "allQualifyingSitesAtDelayedStart (nearest first)": [
    "pgda78-site11"
  ],
  "optionB_isNearestQualifying": true,
  "optionsReEvaluated": {
    "alternativeSite": "met"
  },
  "durationPreserved": true
}
```

## 6. Sensitivity

Baseline statuses: {'A': 'met', 'B': 'met', 'C': 'notMet', 'A+delay': 'notMet'}

| Variant | Max transition shift (min) | Median (min) | Unmatched transitions | Largest shift | Status changes |
|---|---|---|---|---|---|
| observer 1 m | 359.7 | 109.4 | 0 | pgda78-site04 earth obstructed 2026-11-30T03:17:49Z → 2026-11-29T21:18:08Z | none |
| observer 5 m | 323.8 | 257.2 | 0 | pgda78-site04 earth returns 2026-11-17T08:52:30Z → 2026-11-17T03:28:45Z | none |
| observer 10 m | 684.4 | 343.8 | 1 | pgda78-site04 earth obstructed 2026-11-30T03:17:49Z → 2026-11-30T14:42:12Z | none |
| azimuth step 0.25° | 8.4 | 3.4 | 0 | pgda78-site01 earth obstructed 2026-11-30T20:38:45Z → 2026-11-30T20:30:19Z | none |
| azimuth step 1° | 11.9 | 8.4 | 0 | pgda78-site01 earth obstructed 2026-11-30T20:38:45Z → 2026-11-30T20:50:38Z | none |
| search radius 100 km | 0.0 | 0.0 | 1 | pgda78-site04 earth returns 2026-11-17T08:52:30Z → 2026-11-17T08:52:30Z | {'C': 'notMet → unknown', 'A+delay': 'notMet → met'} |
| search radius 250 km | error: Read failed. See previous exception for details. | | | | |
| sampling 300 s | 0.0 | 0.0 | 0 | pgda78-site01 earth obstructed 2026-11-30T20:38:45Z → 2026-11-30T20:38:45Z | none |
| Sun: any part of disc | 0.0 | 0.0 | 0 | pgda78-site01 earth obstructed 2026-11-30T20:38:45Z → 2026-11-30T20:38:45Z | none |
| Sun: whole disc | 0.0 | 0.0 | 0 | pgda78-site01 earth obstructed 2026-11-30T20:38:45Z → 2026-11-30T20:38:45Z | none |
| clearance +0.1° | 95.3 | 93.8 | 0 | pgda78-site04 earth returns 2026-11-17T08:52:30Z → 2026-11-17T10:27:49Z | none |
