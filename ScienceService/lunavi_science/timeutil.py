"""UTC <-> SPICE ephemeris time (TDB seconds past J2000) and ISO 8601 helpers."""
from __future__ import annotations

import datetime as dt
import math

UTC = dt.timezone.utc
J2000_UTC_CALENDAR = dt.datetime(2000, 1, 1, 12, 0, 0, tzinfo=UTC)

# Constants of the NAIF leapseconds kernel (naif0012.tls) used by SPICE's DELTET model.
DELTA_T_A = 32.184
K = 1.657e-3
EB = 1.671e-2
M0 = 6.239996
M1 = 1.99096871e-7
# TAI - UTC. 37 s since 2017-01-01; no later leap second had been announced when this was written.
# Prefer loading naif0012.tls (or newer) so SPICE handles this itself.
TAI_MINUS_UTC = [(dt.datetime(2017, 1, 1, tzinfo=UTC), 37.0)]


def parse_utc(value: str) -> dt.datetime:
    """Parses 'YYYY-MM-DDTHH:MM:SSZ' (or with +00:00) into an aware UTC datetime."""
    text = value.strip().replace("Z", "+00:00")
    parsed = dt.datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def iso(moment: dt.datetime) -> str:
    """ISO 8601 UTC without fractional seconds (the format the iPad app decodes)."""
    return moment.astimezone(UTC).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")


def _tai_minus_utc(moment: dt.datetime) -> float:
    for start, value in reversed(TAI_MINUS_UTC):
        if moment >= start:
            return value
    raise ValueError("The built-in UTC->ET fallback only covers dates from 2017-01-01; load an LSK instead.")


def fallback_utc_to_et(moment: dt.datetime) -> float:
    """SPICE's DELTET model with the LSK constants above (agrees with str2et to well under 1 ms)."""
    utc_seconds = (moment.astimezone(UTC) - J2000_UTC_CALENDAR).total_seconds()
    et = utc_seconds + DELTA_T_A + _tai_minus_utc(moment)
    for _ in range(3):
        m = M0 + M1 * et
        e = m + EB * math.sin(m)
        et = utc_seconds + DELTA_T_A + _tai_minus_utc(moment) + K * math.sin(e)
    return et


def has_leapseconds_kernel(spice) -> bool:
    try:
        return spice.ktotal("TEXT") > 0 and spice.gdpool("DELTET/DELTA_T_A", 0, 1) is not None
    except Exception:
        return False


def utc_to_et(moment: dt.datetime, spice=None) -> float:
    """Uses SPICE str2et when a leapseconds kernel is loaded, otherwise the documented fallback."""
    if spice is not None and has_leapseconds_kernel(spice):
        return float(spice.str2et(iso(moment).replace("Z", "")))
    return fallback_utc_to_et(moment)


def time_grid(start: dt.datetime, end: dt.datetime, step_seconds: float) -> list[dt.datetime]:
    count = int(math.floor((end - start).total_seconds() / step_seconds))
    return [start + dt.timedelta(seconds=i * step_seconds) for i in range(count + 1)]
