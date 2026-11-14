#!/bin/sh
# Scientific validation of the bundled real dataset (needs internet for PGDA 69 and JPL Horizons).
#
#   cd ScienceService && sh scripts/validate_science.sh
#
# Writes docs/validation_results/validation_results.md (tables) and .json (all numbers).
# Takes roughly 10–30 minutes: it recomputes horizons, an 18.6-year average per site, and ten sensitivity runs.
set -eu
cd "$(dirname "$0")/.."
[ -d .venv ] || { echo "Run scripts/build_real_data.sh first (creates .venv and data)."; exit 1; }
. .venv/bin/activate
export GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR
export CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".TIF,.tif"
export GDAL_HTTP_MULTIRANGE=YES
export GDAL_HTTP_MERGE_CONSECUTIVE_RANGES=YES
python -m lunavi_science validate-science --config config/sites.json \
    --scenario ../Lunavi/Resources/ComputedScenario.json --out ../docs/validation_results "$@"
echo
echo "Results: docs/validation_results/validation_results.md"
