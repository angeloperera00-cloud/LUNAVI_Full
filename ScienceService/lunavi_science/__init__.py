"""LUNAVI science pipeline.

Computes geometric Sun and Earth visibility at lunar south-pole sites from NASA LOLA elevation
data (PGDA products 78/90) and NAIF SPICE ephemerides, writes ComputedScenario.json for the
LUNAVI iPad app, cross-checks geometry against JPL Horizons, and serves results through a
small FastAPI service.

Results are geometric visibility only. They do not predict power, radio-link quality or
landing safety, and are not operational flight products.
"""

__version__ = "1.1.0"
# 2: adds per-site "geometry" (horizon profile + sampled Sun/Earth directions) for shadow analysis.
SCHEMA_VERSION = 2
