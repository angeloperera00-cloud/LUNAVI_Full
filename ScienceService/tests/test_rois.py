"""Site coordinates from PGDA 78 region archives (synthetic archives in the published formats)."""
from __future__ import annotations

import io
import json
import os
import tarfile
from pathlib import Path

import numpy as np
import pytest

from lunavi_science.dem import SPHERICAL_SOUTH_POLAR_STEREO, polar_stereographic_latlon
from lunavi_science.rois import extract, make_config, read_gmt, site_coordinate


def write_tile(path, cx, cy, half=8_000.0, cell=100.0):
    import rasterio
    from rasterio.crs import CRS
    from rasterio.transform import from_origin

    n = int(2 * half / cell)
    with rasterio.open(path, "w", driver="GTiff", height=n, width=n, count=1, dtype="float32",
                       crs=CRS.from_proj4(SPHERICAL_SOUTH_POLAR_STEREO),
                       transform=from_origin(cx - half, cy + half, cell, cell)) as dst:
        dst.write(np.zeros((1, n, n), dtype="float32"))
    return str(path)


def tgz(path, files: dict, hardlink: str | None = None):
    """files: arcname -> text. hardlink: arcname of an extra hard-link entry to the first file."""
    with tarfile.open(path, "w:gz") as tar:
        first = None
        for name, text in files.items():
            data = text.encode()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
            first = first or name
        if hardlink:
            link = tarfile.TarInfo(hardlink)
            link.type = tarfile.LNKTYPE
            link.linkname = first
            tar.addfile(link)
    return str(path)


def square(cx, cy, half):
    return [(cx - half, cy - half), (cx - half, cy + half), (cx + half, cy + half), (cx + half, cy - half), (cx - half, cy - half)]


def gmt_text(polygons, header="# @VGMT1.0 @GPOLYGON\n# @NNAME\n# @Tstring\n# FEATURE_DATA\n"):
    out = header
    for name, ring in polygons:
        out += f"> \n# @D{name}\n" + "".join(f"{x} {y}\n" for x, y in ring)
    return out


def test_ogr_gmt_in_projected_metres(tmp_path):
    tile = write_tile(tmp_path / "Site01_final_adj_5mpp_surf.tif", 0.0, 9_000.0)
    archive = tgz(tmp_path / "Site01_ROIs.tgz", {"Site01_ROIs.gmt": gmt_text([("small", square(2_000, 10_000, 200)),
                                                                            ("main region", square(-1_000, 8_500, 1_500))])})
    coord = site_coordinate("Site01", archive, str(tmp_path / "work"), tile)
    lat, lon = polar_stereographic_latlon(np.array([-1_000.0]), np.array([8_500.0]))
    assert abs(coord["latitude"] - lat[0]) < 1e-5 and abs(coord["longitude"] - lon[0]) < 1e-5
    assert "main region" in coord["coordinateSource"] and "PGDA product 78" in coord["coordinateSource"]
    assert "projected" in coord["coordinateSource"]


def test_plain_gmt_in_longitude_latitude_with_hard_link_entry(tmp_path):
    centre = (3_000.0, -6_000.0)
    tile = write_tile(tmp_path / "tile.tif", *centre)
    lat, lon = polar_stereographic_latlon(np.array([centre[0]]), np.array([centre[1]]))
    ring = [(lon[0] + dlon, lat[0] + dlat) for dlon, dlat in [(-0.5, -0.02), (-0.5, 0.02), (0.5, 0.02), (0.5, -0.02), (-0.5, -0.02)]]
    text = '> -L"ridge ROI"\n' + "".join(f"{a:.8f} {b:.8f}\n" for a, b in ring)
    archive = tgz(tmp_path / "Site04_ROIs.tgz", {"Site04/Site04_ROIs.gmt": text}, hardlink="Site04_ROIs.gmt")
    coord = site_coordinate("Site04", archive, str(tmp_path / "work"), tile)
    assert abs(coord["latitude"] - lat[0]) < 0.01 and abs(((coord["longitude"] - lon[0]) + 180) % 360 - 180) < 0.6
    assert "ridge ROI" in coord["coordinateSource"] and "longitude/latitude" in coord["coordinateSource"]


def test_declared_proj_header_is_used(tmp_path):
    tile = write_tile(tmp_path / "tile.tif", 5_000.0, 5_000.0)
    header = f'# @VGMT1.0 @GPOLYGON @Jp"{SPHERICAL_SOUTH_POLAR_STEREO}"\n# @NNAME\n# FEATURE_DATA\n'
    archive = tgz(tmp_path / "a.tgz", {"x.gmt": gmt_text([("R1", square(5_200, 4_800, 500))], header)})
    coord = site_coordinate("SiteX", archive, str(tmp_path / "work"), tile)
    assert "declared CRS" in coord["coordinateSource"] and "R1" in coord["coordinateSource"]


def test_regions_outside_the_tile_fall_back_to_the_tile_centre(tmp_path):
    tile = write_tile(tmp_path / "tile.tif", 0.0, 9_000.0)
    archive = tgz(tmp_path / "a.tgz", {"x.gmt": gmt_text([("far away", square(90_000, 90_000, 500))])})
    coord = site_coordinate("SiteX", archive, str(tmp_path / "work"), tile)
    lat, lon = polar_stereographic_latlon(np.array([0.0]), np.array([9_000.0]))
    assert abs(coord["latitude"] - lat[0]) < 1e-5 and "centre of the 16 x 16 km" in coord["coordinateSource"]


def test_archive_with_only_a_dangling_link_uses_the_tile_centre(tmp_path):
    """The published Site01_ROIs.tgz holds only a link to a file that is not in the archive."""
    tile = write_tile(tmp_path / "Site01_final_adj_5mpp_surf.tif", 2_000.0, 7_000.0)
    archive = tmp_path / "Site01_ROIs.tgz"
    with tarfile.open(archive, "w:gz") as tar:
        link = tarfile.TarInfo("Site01_ROIs.gmt")
        link.type = tarfile.SYMTYPE
        link.linkname = "Site01_final_adj_5mpp_01_regionProps_avgillGT070.gmt"
        tar.addfile(link)
    coord = site_coordinate("Site01", str(archive), str(tmp_path / "work"), tile)
    lat, lon = polar_stereographic_latlon(np.array([2_000.0]), np.array([7_000.0]))
    assert abs(coord["latitude"] - lat[0]) < 1e-5 and abs(coord["longitude"] - lon[0]) < 1e-5
    assert "Site01_final_adj_5mpp_surf.tif" in coord["coordinateSource"]


def test_path_traversal_entries_are_flattened(tmp_path):
    archive = tgz(tmp_path / "a.tgz", {"../../escape.gmt": "> \n1 2\n3 4\n"})
    files = extract(archive, str(tmp_path / "out"))
    assert files == [str(tmp_path / "out" / "escape.gmt")]
    assert not (tmp_path / "escape.gmt").exists()


def test_gmt_reader_labels():
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".gmt", delete=False) as f:
        f.write('> -L"A"\n0 0\n1 0\n1 1\n> B\n5 5\n6 5\n6 6\n')
    features = read_gmt(f.name)
    os.unlink(f.name)
    assert [x.name for x in features] == ["A", "B"] and len(features[0].vertices) == 3


def test_make_config_writes_a_buildable_config(tmp_path):
    data = tmp_path / "data"
    data.mkdir()
    for code, centre in [("Site01", (-3_000, 8_000)), ("Site11", (6_000, 2_000))]:
        write_tile(data / f"{code}_final_adj_5mpp_surf.tif", *centre)
        tgz(data / f"{code}_ROIs.tgz", {f"{code}_ROIs.gmt": gmt_text([("region", square(*centre, 1_000))])})
    template = Path(__file__).resolve().parents[1] / "config" / "sites.example.json"
    out = tmp_path / "config" / "sites.json"
    out.parent.mkdir()
    cfg = make_config(str(template), str(data), str(out), "/vsicurl/https://example.invalid/LDEM.TIF", ["Site01", "Site11"])
    assert json.loads(out.read_text()) == cfg
    assert [s["id"] for s in cfg["sites"]] == ["pgda78-site01", "pgda78-site11"]
    assert cfg["sites"][0]["name"] == "Connecting Ridge"
    assert all(s["latitude"] < -89 and s["coordinateSource"] for s in cfg["sites"])
    assert [layer["path"] for layer in cfg["dem"]["layers"]] == [
        "../data/Site01_final_adj_5mpp_surf.tif", "../data/Site11_final_adj_5mpp_surf.tif", "/vsicurl/https://example.invalid/LDEM.TIF"]
