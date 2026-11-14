#!/bin/sh
# One command: real NASA data -> computed LUNAVI scenario installed in the app.
#
#   cd ScienceService && sh scripts/build_real_data.sh
#
# Another date range (kept alongside the existing one; the app lists both in Data & Method):
#
#   sh scripts/build_real_data.sh --start 2026-12-01T00:00:00Z --end 2026-12-15T00:00:00Z
#
# Options:
#   --start ISO --end ISO   computation period (UTC). Without them, period in config/sites.json is used.
#   --step SECONDS          sample spacing (default: config, normally 600)
#   --name NAME             output name (must start with ComputedScenario). Default: ComputedScenario,
#                           or ComputedScenario_YYYYMMDD_YYYYMMDD when --start/--end are given.
#   --regenerate-config     rewrite config/sites.json from the template (otherwise an existing one is kept,
#                           so periods or settings you edited there are never overwritten)
#   --download-far-field    download the 2.6 GB regional DEM instead of streaming it
#
# The period is checked against every SPICE kernel and the DEM before anything is computed;
# unsupported dates stop the build with an explanation. See docs/DATE_RANGES.md.
#
# 1. Python environment   2. NAIF SPICE kernels (~19 MB)
# 3. PGDA product 78 site tiles + region shapefiles (Site01, Site04, Site11)
# 4. Site coordinates from those NASA shapefiles -> config/sites.json
# 5. Visibility build. The 80°S regional DEM (PGDA product 90, 2.6 GB) is streamed:
#    only the area around the sites is read. Use --download-far-field to download it instead.
# 6. Optional JPL Horizons check   7. Copy results into Lunavi/Resources/
set -eu
cd "$(dirname "$0")/.."

FAR_FIELD="/vsicurl/https://pgda.gsfc.nasa.gov/data/LOLA_20mpp/LDEM_80S_20MPP_ADJ.TIF"
SITES="Site01 Site04 Site11"
START=""; END=""; STEP=""; NAME=""; REGENERATE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --download-far-field) FAR_FIELD="data/LDEM_80S_20MPP_ADJ.TIF" ;;
        --start) START="$2"; shift ;;
        --end) END="$2"; shift ;;
        --step) STEP="$2"; shift ;;
        --name) NAME="$2"; shift ;;
        --regenerate-config) REGENERATE=1 ;;
        *) echo "unknown option: $1"; exit 2 ;;
    esac
    shift
done
if { [ -n "$START" ] && [ -z "$END" ]; } || { [ -z "$START" ] && [ -n "$END" ]; }; then
    echo "Give both --start and --end (UTC, e.g. 2026-12-01T00:00:00Z)."; exit 2
fi
if [ -z "$NAME" ]; then
    if [ -n "$START" ]; then
        NAME="ComputedScenario_$(echo "$START" | cut -c1-10 | tr -d '-')_$(echo "$END" | cut -c1-10 | tr -d '-')"
    else
        NAME="ComputedScenario"
    fi
fi
case "$NAME" in
    ComputedScenario*) ;;
    *) echo "--name must start with ComputedScenario"; exit 2 ;;
esac

# 1. Python 3.10+
PY=""
for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
        PY="$candidate"; break
    fi
done
[ -n "$PY" ] || { echo "Python 3.10+ is required (e.g. brew install python@3.12)"; exit 1; }
[ -d .venv ] || "$PY" -m venv .venv
. .venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt

# 2. Kernels
sh scripts/fetch_kernels.sh

# 3. PGDA product 78 data
mkdir -p data
fetch() {  # url dest
    if [ -s "$2" ]; then echo "have $(basename "$2")"; return; fi
    echo "downloading $(basename "$2")"
    curl -fL --retry 3 -o "$2.part" "$1"
    mv "$2.part" "$2"
}
for site in $SITES; do
    fetch "https://pgda.gsfc.nasa.gov/data/LOLA_5mpp/$site/${site}_final_adj_5mpp_surf.tif" "data/${site}_final_adj_5mpp_surf.tif"
    fetch "https://pgda.gsfc.nasa.gov/data/LOLA_5mpp/$site/${site}_ROIs.tgz" "data/${site}_ROIs.tgz"
done
if [ "$FAR_FIELD" = "data/LDEM_80S_20MPP_ADJ.TIF" ]; then
    fetch "https://pgda.gsfc.nasa.gov/data/LOLA_20mpp/LDEM_80S_20MPP_ADJ.TIF" "data/LDEM_80S_20MPP_ADJ.TIF"
    FAR_FIELD="$(pwd)/data/LDEM_80S_20MPP_ADJ.TIF"
fi

# Faster remote reads of cloud-optimised GeoTIFFs
export GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR
export CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".TIF,.tif"
export GDAL_HTTP_MULTIRANGE=YES
export GDAL_HTTP_MERGE_CONSECUTIVE_RANGES=YES

# 4. Coordinates from the NASA region shapefiles (an existing config/sites.json is kept)
if [ ! -f config/sites.json ] || [ "$REGENERATE" = 1 ]; then
    python -m lunavi_science make-config --data data --out config/sites.json --far-field "$FAR_FIELD" --sites $SITES
else
    echo "Keeping existing config/sites.json (use --regenerate-config to rebuild it from the template)."
fi

# 5. Check the period against the kernels, then build
PERIOD_ARGS=""
[ -n "$START" ] && PERIOD_ARGS="--start $START --end $END"
[ -n "$STEP" ] && PERIOD_ARGS="$PERIOD_ARGS --step $STEP"
# shellcheck disable=SC2086
python -m lunavi_science check-coverage --config config/sites.json ${START:+--start $START --end $END} >/dev/null || {
    python -m lunavi_science check-coverage --config config/sites.json ${START:+--start $START --end $END}
    echo "The requested period is not covered by the SPICE kernels; nothing was computed."; exit 1; }
# shellcheck disable=SC2086
python -m lunavi_science build --config config/sites.json --out out --name "$NAME" $PERIOD_ARGS

# 6. Ephemeris check against JPL Horizons (does not stop the script if it fails)
if ! python -m lunavi_science horizons-check --scenario "out/$NAME.json" --kernels kernels/*; then
    echo "Note: the Horizons check did not pass or could not run; the scenario stays marked 'not validated'."
fi

# 7. Validate against the app schema, print the acceptance scenarios, then install into the app
#    (other ComputedScenario*.json files already there are kept; the app copy is identical to out/)
python -m lunavi_science validate --scenario "out/$NAME.json" || { echo "Scenario failed validation; not installed."; exit 1; }
python -m lunavi_science acceptance --scenario "out/$NAME.json" || true
cp "out/$NAME.json" out/computed_south_pole_basemap.jpg ../Lunavi/Resources/
cmp -s "out/$NAME.json" "../Lunavi/Resources/$NAME.json" && echo "App copy matches out/$NAME.json"
echo
echo "Done. Installed Lunavi/Resources/$NAME.json. Rebuild the app in Xcode (Product > Clean Build Folder, then Run)."
echo "Bundled computed ranges:"; ls ../Lunavi/Resources/ComputedScenario*.json
