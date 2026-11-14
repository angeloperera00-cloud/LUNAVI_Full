"""LUNAVI science pipeline.

Computes geometric Sun and Earth visibility at lunar south-pole sites from NASA LOLA elevation
data (PGDA products 78/90) and NAIF SPICE ephemerides, writes ComputedScenario.json for the
LUNAVI iPad app, cross-checks geometry against JPL Horizons, and serves results through a
small FastAPI service.

Visibility results are geometric only. They do not predict radio-link quality or landing safety,
and are not operational flight products. Terrain values (schema 3) characterise the DEM surface;
they are not a hazard assessment.
"""

__version__ = "1.2.0"
# 2: adds per-site "geometry" (horizon profile + sampled Sun/Earth directions) for shadow analysis.
# 3: adds "terrain" (elevation, slope, roughness per site), "coverage" (kernel/DEM checks) and
#    period.stepSeconds / period.sampleCount.
SCHEMA_VERSION = 3
