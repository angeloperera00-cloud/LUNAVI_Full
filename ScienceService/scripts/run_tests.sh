#!/bin/sh
# Runs the science tests in the project's own virtual environment (ScienceService/.venv) with the
# project's kernels. Installs the declared requirements into .venv only — never globally.
#
#   cd ScienceService && sh scripts/run_tests.sh
set -eu
cd "$(dirname "$0")/.."
PY=""
for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
        PY="$candidate"; break
    fi
done
[ -n "$PY" ] || { echo "Python 3.10+ is required"; exit 1; }
[ -d .venv ] || "$PY" -m venv .venv
. .venv/bin/activate
pip install -q -r requirements.txt
python -c "import spiceypy, rasterio, pyproj, scipy; print('spiceypy', spiceypy.__version__, '| rasterio', rasterio.__version__, '| pyproj', __import__('pyproj').__version__)"
[ -f kernels/de421.bsp ] || sh scripts/fetch_kernels.sh
export LUNAVI_KERNEL_DIR="$(pwd)/kernels"
python -m pytest -q -rs "$@"
