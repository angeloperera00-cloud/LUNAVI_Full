#!/bin/sh
# One command: real NASA data -> computed LUNAVI scenario installed in the app.
#
#   cd ScienceService && sh scripts/build_real_data.sh
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
for arg in "$@"; do
    case "$arg" in
        --download-far-field) FAR_FIELD="data/LDEM_80S_20MPP_ADJ.TIF" ;;
        *) echo "unknown option: $arg"; exit 2 ;;
    esac
done

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

# 4. Coordinates from the NASA region shapefiles
python -m lunavi_science make-config --data data --out config/sites.json --far-field "$FAR_FIELD" --sites $SITES

# 5. Build
python -m lunavi_science build --config config/sites.json --out out

# 6. Ephemeris check against JPL Horizons (does not stop the script if it fails)
if ! python -m lunavi_science horizons-check --scenario out/ComputedScenario.json --kernels kernels/*; then
    echo "Note: the Horizons check did not pass or could not run; the scenario stays marked 'not validated'."
fi

# 7. Install into the app
cp out/ComputedScenario.json out/computed_south_pole_basemap.jpg ../Lunavi/Resources/
echo
echo "Done. Real computed data installed in Lunavi/Resources/. Rebuild the app in Xcode (Product > Clean Build Folder, then Run)."
