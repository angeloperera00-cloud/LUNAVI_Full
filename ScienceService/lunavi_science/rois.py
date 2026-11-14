"""Site coordinates from the region-of-interest (ROI) files published with PGDA product 78.

Each `SiteXX_ROIs.tgz` holds the regions studied at that site. Published archives contain GMT
vector text files (`SiteXX_ROIs.gmt`); ESRI shapefiles are also accepted. The coordinate system of a
GMT file is read from its `@J` header when present. Otherwise each plausible reading (the site
tile's projected CRS, lon/lat, lat/lon) is tried, and only a reading that puts the region inside the
site's own 5 m LOLA tile is accepted. A site's coordinate is the centroid of its largest region; the
chosen region is recorded in `coordinateSource` so the coordinate traces back to the NASA file.
"""
from __future__ import annotations

import os
import re
import tarfile
from dataclasses import dataclass
from typing import Optional

import numpy as np

from .dem import make_to_latlon, make_to_xy, read_crs_wkt

PGDA78 = "https://pgda.gsfc.nasa.gov/products/78"


@dataclass
class RoiFeature:
    source: str                      # file the feature came from
    name: str
    vertices: np.ndarray             # (N, 2) raw coordinates as stored in the file
    crs: Optional[str] = None        # declared CRS (WKT or PROJ string) if the file states one


def extract(archive: str, dest: str) -> list[str]:
    """Extracts the regular files of an ROI archive (flattened, path-safe) and returns their paths."""
    os.makedirs(dest, exist_ok=True)
    written = []
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            if member.isdir():
                continue
            name = os.path.basename(member.name.replace("\\", "/"))
            if not name or name.startswith("._"):      # skip macOS resource forks
                continue
            try:
                stream = tar.extractfile(member)       # None for entries without data
            except KeyError:                           # link to a file that is not in the archive
                print(f"    note: {os.path.basename(archive)}: '{name}' links to '{member.linkname}', which the archive does not contain")
                continue
            if stream is None:
                continue
            target = os.path.join(dest, name)
            with open(target, "wb") as out:
                out.write(stream.read())
            written.append(target)
    return sorted(written)


# ---------------------------------------------------------------- readers

def read_gmt(path: str) -> list[RoiFeature]:
    """GMT multi-segment text: segments start with '>', coordinates are the first two numbers per line.

    Understands OGR's GMT dialect (`# @VGMT1.0`, `# @Jp"<proj4>"`, `# @Jw"<wkt>"`, `# @N` field
    names, `# @D` values) and plain GMT files (`> -L"label"` or `> label`).
    """
    crs = None
    field_names: list[str] = []
    features: list[RoiFeature] = []
    current: list[tuple[float, float]] = []
    label = ""

    def flush():
        nonlocal current, label
        if current:
            features.append(RoiFeature(path, label or f"{os.path.basename(path)} #{len(features) + 1}",
                                       np.asarray(current, dtype=float), crs))
        current, label = [], ""

    with open(path, errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith("#"):
                for key, value in re.findall(r'@([A-Za-z])([^@]*)', line):
                    value = value.strip()
                    if key == "J" and value[:1] in "pw" and len(value) > 1:
                        crs = value[1:].strip().strip('"').replace('\\"', '"')
                    elif key == "N":
                        field_names = value.split("|")
                    elif key == "D":
                        values = [v.strip().strip('"') for v in value.split("|")]
                        named = dict(zip([n.lower() for n in field_names], values))
                        label = named.get("name") or named.get("id") or next((v for v in values if v), label)
                continue
            if line.startswith(">"):
                flush()
                quoted = re.search(r'-L"([^"]*)"', line) or re.search(r"-L(\S+)", line)
                rest = line[1:].strip()
                label = quoted.group(1) if quoted else (rest if rest and not rest.startswith("-") else "")
                continue
            numbers = re.findall(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?", line)
            if len(numbers) >= 2:
                current.append((float(numbers[0]), float(numbers[1])))
    flush()
    return features


def read_shapefile(path: str) -> list[RoiFeature]:
    import shapefile

    reader = shapefile.Reader(path)
    fields = [f[0] for f in reader.fields[1:]]
    prj = os.path.splitext(path)[0] + ".prj"
    crs = open(prj).read() if os.path.exists(prj) else None
    out = []
    for index, shape_record in enumerate(reader.iterShapeRecords()):
        shape, record = shape_record.shape, shape_record.record
        if not shape.points:
            continue
        named = {k.lower(): str(v).strip() for k, v in zip(fields, record)}
        label = named.get("name") or named.get("id") or next((str(v).strip() for v in record if str(v).strip()), "")
        points = np.asarray(shape.points, dtype=float)[:, :2]
        parts = list(shape.parts) + [len(points)]
        rings = [points[parts[i]:parts[i + 1]] for i in range(len(parts) - 1)]
        out.append(RoiFeature(path, label or f"{os.path.basename(path)} #{index + 1}", max(rings, key=len), crs))
    return out


def read_features(paths: list[str]) -> list[RoiFeature]:
    features = []
    for path in paths:
        lower = path.lower()
        if lower.endswith(".gmt"):
            features += read_gmt(path)
        elif lower.endswith(".shp"):
            features += read_shapefile(path)
    return features


# ---------------------------------------------------------------- geometry

def ring_centroid(points: np.ndarray) -> tuple[float, float, float]:
    """(cx, cy, area) of a polygon ring; the mean point and zero area for points and lines."""
    if len(points) >= 3:
        x, y = points[:, 0], points[:, 1]
        cross = x * np.roll(y, -1) - np.roll(x, -1) * y
        area = cross.sum() / 2.0
        if abs(area) > 1e-9:
            cx = ((x + np.roll(x, -1)) * cross).sum() / (6.0 * area)
            cy = ((y + np.roll(y, -1)) * cross).sum() / (6.0 * area)
            return float(cx), float(cy), float(abs(area))
    return float(points[:, 0].mean()), float(points[:, 1].mean()), 0.0


def _tile_bounds(tile_path: str) -> tuple[float, float, float, float]:
    import rasterio

    with rasterio.open(tile_path) as src:
        b = src.bounds
        return b.left, b.bottom, b.right, b.top


def _readings(feature: RoiFeature, tile_crs: Optional[str]):
    """Plausible interpretations of the raw vertices, each converted to the tile's projected x/y."""
    raw = feature.vertices
    to_tile = make_to_xy(tile_crs)
    if feature.crs:
        try:
            lat, lon = make_to_latlon(feature.crs)(raw[:, 0], raw[:, 1])
            yield f"declared CRS", np.column_stack(to_tile(lat, lon))
        except Exception:
            pass
    # Values that fit degree ranges are read as degrees first: as metres they would describe a
    # region a few hundred metres from the exact pole, which no PGDA 78 site is.
    if np.all(np.abs(raw[:, 0]) <= 360) and np.all(np.abs(raw[:, 1]) <= 90):
        yield "longitude/latitude", np.column_stack(to_tile(raw[:, 1], raw[:, 0]))
    if np.all(np.abs(raw[:, 0]) <= 90) and np.all(np.abs(raw[:, 1]) <= 360):
        yield "latitude/longitude", np.column_stack(to_tile(raw[:, 0], raw[:, 1]))
    yield "site tile CRS (projected metres)", raw


def tile_centre(site_id: str, tile_path: str, tile_crs, bounds, reason: str) -> dict:
    """Fallback: the centre of the site's 5 m LOLA tile, which PGDA 78 builds around each studied site."""
    left, bottom, right, top = bounds
    lat, lon = make_to_latlon(tile_crs)(np.array([(left + right) / 2]), np.array([(bottom + top) / 2]))
    width_km, height_km = (right - left) / 1000, (top - bottom) / 1000
    print(f"    note: {site_id}: {reason}; using the centre of {os.path.basename(tile_path)} instead")
    return {
        "latitude": round(float(lat[0]), 6),
        "longitude": round(float(lon[0]), 6),
        "coordinateSource": (f"centre of the {width_km:.0f} x {height_km:.0f} km {site_id} LOLA DEM tile "
                             f"({os.path.basename(tile_path)}), NASA GSFC PGDA product 78 ({PGDA78})"),
        "features": [],
    }


def site_coordinate(site_id: str, archive: str, workdir: str, tile_path: str) -> dict:
    """Returns {latitude, longitude, coordinateSource, features} for one PGDA 78 site."""
    files = extract(archive, os.path.join(workdir, site_id)) if os.path.exists(archive) else []
    features = read_features(files)
    tile_crs = read_crs_wkt(tile_path)
    left, bottom, right, top = _tile_bounds(tile_path)
    inside = lambda x, y: left <= x <= right and bottom <= y <= top
    if not features:
        return tile_centre(site_id, tile_path, tile_crs, (left, bottom, right, top),
                           f"no readable regions in {os.path.basename(archive)}")

    accepted = []
    for feature in features:
        for reading, xy in _readings(feature, tile_crs):
            cx, cy, area = ring_centroid(xy)
            if inside(cx, cy):
                accepted.append((feature, reading, cx, cy, area))
                break
    if not accepted:
        return tile_centre(site_id, tile_path, tile_crs, (left, bottom, right, top),
                           f"no region in {os.path.basename(archive)} falls inside the site tile")
    feature, reading, cx, cy, area = max(accepted, key=lambda a: a[4])
    lat, lon = make_to_latlon(tile_crs)(np.array([cx]), np.array([cy]))
    what = f"centroid of the largest region '{feature.name}'" if area > 0 else f"region '{feature.name}'"
    return {
        "latitude": round(float(lat[0]), 6),
        "longitude": round(float(lon[0]), 6),
        "coordinateSource": f"{what} in {os.path.basename(archive)} ({reading}), NASA GSFC PGDA product 78 ({PGDA78})",
        "features": [{"name": f.name, "kind": "polygon" if a > 0 else "point/line", "areaKm2": round(a / 1e6, 3),
                      "reading": r} for f, r, _, _, a in accepted],
    }


def make_config(template_path: str, data_dir: str, out_path: str, far_field: str, sites: list[str]) -> dict:
    """Writes a ready-to-build config from downloaded PGDA 78 tiles + ROI archives."""
    import json

    with open(template_path) as f:
        cfg = json.load(f)
    config_dir = os.path.dirname(os.path.abspath(out_path))
    rel = lambda p: p if p.startswith("/vsi") or "://" in p else os.path.relpath(os.path.abspath(p), config_dir)
    template_sites = {s["id"]: s for s in cfg["sites"]}
    layers, site_entries = [], []
    for code in sites:  # e.g. "Site01"
        tile = os.path.join(data_dir, f"{code}_final_adj_5mpp_surf.tif")
        archive = os.path.join(data_dir, f"{code}_ROIs.tgz")
        coord = site_coordinate(code, archive, os.path.join(data_dir, "rois"), tile)
        site_id = f"pgda78-{code.lower()}"
        base = template_sites.get(site_id, {"id": site_id, "name": code, "shortName": code})
        entry = {k: v for k, v in base.items() if k not in ("latitude", "longitude", "coordinateSource")}
        entry.update(latitude=coord["latitude"], longitude=coord["longitude"], coordinateSource=coord["coordinateSource"])
        site_entries.append(entry)
        layers.append({"name": f"PGDA product 78 {code} LDEM (5 m/pixel)", "path": rel(tile),
                       "version": "as downloaded", "link": PGDA78})
        print(f"{code}: {coord['latitude']:.5f}, {coord['longitude']:.5f}  <- {coord['coordinateSource']}")
        for feature in coord["features"]:
            print(f"    region: {feature['name']} ({feature['kind']}, {feature['areaKm2']} km², {feature['reading']})")
    far = next((layer for layer in cfg["dem"]["layers"] if "product 90" in layer["name"]), None) or {}
    layers.append({**far, "name": "PGDA product 90 LDEM_80S_20MPP_ADJ (20 m/pixel)", "path": rel(far_field),
                   "version": far.get("version") or "as published", "link": "https://pgda.gsfc.nasa.gov/products/90",
                   "boundsPaddingM": far.get("boundsPaddingM", 160000), "resolutionM": far.get("resolutionM", 80)})
    cfg["dem"]["layers"] = layers
    cfg["sites"] = site_entries
    cfg.pop("_readme", None)
    with open(out_path, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    return cfg
