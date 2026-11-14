#!/bin/sh
# Downloads the NAIF generic kernels used by the LUNAVI pipeline (DE421 lunar set) into ScienceService/kernels.
# Source: NASA JPL NAIF generic_kernels. Older files are sometimes moved to "a_old_versions",
# so every known location is tried in turn. About 19 MB in total.
set -eu

NAIF="https://naif.jpl.nasa.gov/pub/naif/generic_kernels"
DEST="$(cd "$(dirname "$0")/.." && pwd)/kernels"
mkdir -p "$DEST"

fetch() {  # name url...
    name="$1"; shift
    if [ -s "$DEST/$name" ]; then echo "have $name"; return 0; fi
    for url in "$@"; do
        echo "fetching $name from $url"
        if curl -fsSL --retry 2 -o "$DEST/$name.part" "$url"; then
            mv "$DEST/$name.part" "$DEST/$name"
            return 0
        fi
    done
    rm -f "$DEST/$name.part"
    echo "error: could not download $name. Download it from $NAIF and put it in $DEST" >&2
    exit 1
}

fetch naif0012.tls \
    "$NAIF/lsk/naif0012.tls" \
    "$NAIF/lsk/a_old_versions/naif0012.tls"
fetch de421.bsp \
    "$NAIF/spk/planets/a_old_versions/de421.bsp" \
    "$NAIF/spk/planets/de421.bsp" \
    "https://ssd.jpl.nasa.gov/ftp/eph/planets/bsp/de421.bsp"
fetch moon_pa_de421_1900-2050.bpc \
    "$NAIF/pck/moon_pa_de421_1900-2050.bpc" \
    "$NAIF/pck/a_old_versions/moon_pa_de421_1900-2050.bpc"
fetch moon_080317.tf \
    "$NAIF/fk/satellites/moon_080317.tf" \
    "$NAIF/fk/satellites/a_old_versions/moon_080317.tf"
fetch moon_assoc_me.tf \
    "$NAIF/fk/satellites/moon_assoc_me.tf" \
    "$NAIF/fk/satellites/a_old_versions/moon_assoc_me.tf"
echo "Kernels are in $DEST"
