"""Command line: build | horizons-check | validate | serve.

  python -m lunavi_science make-config --data data --out config/sites.json
  python -m lunavi_science build --config config/sites.json --out out/
  python -m lunavi_science horizons-check --scenario out/ComputedScenario.json --kernels <files...>
  python -m lunavi_science validate --scenario out/ComputedScenario.json
  python -m lunavi_science serve --scenario out/ComputedScenario.json --port 8000
"""
from __future__ import annotations

import argparse
import json
import sys


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="lunavi_science")
    sub = parser.add_subparsers(dest="command", required=True)

    build = sub.add_parser("build", help="compute visibility and write ComputedScenario.json + basemap")
    build.add_argument("--config", required=True)
    build.add_argument("--out", default="out")
    build.add_argument("--start", help="override period.start (ISO 8601 UTC)")
    build.add_argument("--end", help="override period.end (ISO 8601 UTC)")
    build.add_argument("--step", type=float, help="override period.stepSeconds")
    build.add_argument("--name", default="ComputedScenario",
                       help="output file name without .json; must start with ComputedScenario")

    cov = sub.add_parser("check-coverage", help="check a period against the SPICE kernels and DEM before building")
    cov.add_argument("--config", required=True)
    cov.add_argument("--start")
    cov.add_argument("--end")

    check = sub.add_parser("horizons-check", help="compare SPICE az/el with JPL Horizons and record the result")
    check.add_argument("--scenario", required=True)
    check.add_argument("--kernels", nargs="+", required=True)
    check.add_argument("--tolerance-deg", type=float, default=0.05)
    check.add_argument("--step", default="6h")

    make = sub.add_parser("make-config", help="write config/sites.json from downloaded PGDA 78 tiles + ROI archives")
    make.add_argument("--data", default="data")
    make.add_argument("--template", default="config/sites.example.json")
    make.add_argument("--out", default="config/sites.json")
    make.add_argument("--far-field", default="/vsicurl/https://pgda.gsfc.nasa.gov/data/LOLA_20mpp/LDEM_80S_20MPP_ADJ.TIF")
    make.add_argument("--sites", nargs="+", default=["Site01", "Site04", "Site11"])

    shadow = sub.add_parser("shadow", help="print shadow-analysis readings (reproducible example)")
    shadow.add_argument("--scenario", required=True)
    shadow.add_argument("--site")
    shadow.add_argument("--time", help="ISO 8601 UTC, e.g. 2026-11-29T15:00:00Z")
    shadow.add_argument("--condition", default="sunlight", choices=["sunlight", "earthLineOfSight"])

    acc = sub.add_parser("acceptance", help="evaluate acceptance scenarios A–D on a scenario file with the app's rules")
    acc.add_argument("--scenario", required=True)
    acc.add_argument("--site", default="pgda78-site01")
    acc.add_argument("--start", default="2026-11-29T15:00:00Z")
    acc.add_argument("--hours", type=float, default=24)
    acc.add_argument("--json", action="store_true")

    validate = sub.add_parser("validate", help="check a scenario file against the app schema")
    validate.add_argument("--scenario", required=True)

    serve = sub.add_parser("serve", help="run the FastAPI science service")
    serve.add_argument("--scenario", required=True)
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8000)

    args = parser.parse_args(argv)

    if args.command == "build":
        from .scenario import build as build_scenario
        try:
            scenario = build_scenario(args.config, args.out, start=args.start, end=args.end,
                                      step_seconds=args.step, output_name=args.name)
        except (ValueError, FileNotFoundError) as error:
            print(f"error: {error}", file=sys.stderr)
            return 2
        mission, period = scenario["mission"], scenario["period"]
        print(f"Wrote {args.out}/{args.name}.json — computed {period['start']} to {period['end']} "
              f"({period['sampleCount']} samples); default plan {mission['siteID']} at {mission['start']} for {mission['durationHours']} h")
        return 0

    if args.command == "check-coverage":
        import os
        import spiceypy as spice
        from .coverage import check_kernel_coverage
        from .ephemeris import load_kernels
        from .scenario import apply_period_override, settings_from_config
        with open(args.config) as f:
            cfg = apply_period_override(json.load(f), args.start, args.end)
        base = os.path.dirname(os.path.abspath(args.config))
        paths = [k if os.path.isabs(k) else os.path.join(base, k) for k in cfg["kernels"]]
        s = settings_from_config(cfg)
        report = check_kernel_coverage(spice, load_kernels(spice, paths), s.start, s.end)
        print(json.dumps(report.to_json(), indent=2))
        return 0 if report.ok else 1

    if args.command == "make-config":
        from .rois import make_config
        try:
            make_config(args.template, args.data, args.out, args.far_field, args.sites)
        except (ValueError, FileNotFoundError) as error:
            print(f"error: {error}", file=sys.stderr)
            return 2
        print(f"Wrote {args.out}")
        return 0

    if args.command == "horizons-check":
        import spiceypy as spice
        from .ephemeris import load_kernels
        from .horizons_check import run
        load_kernels(spice, args.kernels)
        result = run(spice, args.scenario, args.tolerance_deg, args.step)
        print(json.dumps(result["record"], indent=2))
        return 0 if result["record"]["level"] == "ephemerisChecked" else 1

    if args.command == "shadow":
        from .shadow import format_reading, obstruction_example, reading
        from .timeutil import parse_utc
        with open(args.scenario) as f:
            scenario = json.load(f)
        if not scenario.get("geometry"):
            print("error: this scenario has no geometry (schema 2). Rebuild it with 'build'.", file=sys.stderr)
            return 2
        if args.site and args.time:
            print(format_reading(reading(scenario, args.site, args.condition, parse_utc(args.time))))
            return 0
        example = obstruction_example(scenario)
        if example is None:
            from .shadow import closest_approach
            print("No computed sunlight transition in this scenario's period: the Sun stays above the modeled terrain")
            print("at every site. Closest approach to obstruction per site:")
            for r in closest_approach(scenario):
                print(f"  {r['siteID']}: " + format_reading(r))
            print("To find an obstruction, add sites or widen 'period' in config/sites.json and rebuild.")
            return 0
        event = example["event"]
        what = "begins" if event["kind"] == "obstructionBegins" else "ends (Sun emerges)"
        print(f"Sunlight obstruction at {example['siteID']} {what} at {event['time']}")
        print(f"  {event['summary']}")
        for r in example["readings"]:
            print("  " + format_reading(r))
        return 0

    if args.command == "acceptance":
        from .acceptance import format_report, run
        with open(args.scenario) as f:
            result = run(json.load(f), args.site, args.start, args.hours)
        print(json.dumps(result, indent=2) if args.json else format_report(result))
        return 0

    if args.command == "validate":
        from .schema import validate_scenario
        with open(args.scenario) as f:
            errors = validate_scenario(json.load(f))
        print("\n".join(errors) if errors else "Scenario matches the app schema.")
        return 1 if errors else 0

    if args.command == "serve":
        import uvicorn
        from .api import load_app
        uvicorn.run(load_app(args.scenario), host=args.host, port=args.port)
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
