"""Shared fixtures.

SPICE tests need the NAIF DE421 lunar kernel set. Put the files in ScienceService/kernels/
(scripts/fetch_kernels.sh downloads them) or point LUNAVI_KERNEL_DIR at a directory holding them.
Tests that need kernels are skipped, not failed, when they are absent.
"""
from __future__ import annotations

import json
import os
import pathlib
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

APP_RESOURCES = ROOT.parent / "Lunavi" / "Resources"
REQUIRED_KERNELS = ["de421.bsp", "moon_pa_de421_1900-2050.bpc", "moon_080317.tf", "moon_assoc_me.tf"]


def kernel_dir() -> pathlib.Path:
    return pathlib.Path(os.environ.get("LUNAVI_KERNEL_DIR", ROOT / "kernels"))


def kernel_paths() -> list[str]:
    directory = kernel_dir()
    missing = [name for name in REQUIRED_KERNELS if not (directory / name).exists()]
    if missing:
        pytest.skip(f"SPICE kernels missing in {directory}: {', '.join(missing)} "
                    "(run scripts/fetch_kernels.sh or set LUNAVI_KERNEL_DIR)")
    paths = [str(directory / name) for name in REQUIRED_KERNELS]
    if (directory / "naif0012.tls").exists():
        paths.insert(0, str(directory / "naif0012.tls"))
    return paths


@pytest.fixture(scope="session")
def spice():
    import spiceypy

    paths = kernel_paths()
    spiceypy.kclear()
    for path in paths:
        spiceypy.furnsh(path)
    yield spiceypy
    spiceypy.kclear()


@pytest.fixture(scope="session")
def fixture_scenario() -> dict:
    """The app's simulated fixture (DemoMission/DemoSites/DemoVisibility.json) in ComputedScenario shape."""
    mission = json.loads((APP_RESOURCES / "DemoMission.json").read_text())
    sites = json.loads((APP_RESOURCES / "DemoSites.json").read_text())
    visibility = json.loads((APP_RESOURCES / "DemoVisibility.json").read_text())
    return {
        "mission": mission["mission"],
        "basemap": mission["basemap"],
        "sites": sites["sites"],
        "metadata": visibility["metadata"],
        "visibility": visibility["sites"],
        "sensitivity": visibility.get("sensitivity"),
    }
