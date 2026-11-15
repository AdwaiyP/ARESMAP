"""Mars Date & Time calculations following NASA Mars24 / Allison & McEwen (2000)."""

from __future__ import annotations

from datetime import datetime, timezone
import math
from typing import Any

# Allison & McEwen (2000) planetary perturbation terms: (amplitude_deg, period_days, phase_deg)
_PERTURBERS: tuple[tuple[float, float, float], ...] = (
    (0.0071, 2.2353, 49.409),
    (0.0057, 2.7543, 168.173),
    (0.0039, 1.1177, 191.837),
    (0.0037, 15.7866, 21.736),
    (0.0021, 2.1354, 15.704),
    (0.0020, 2.4694, 95.528),
    (0.0018, 32.8493, 49.095),
)

_SOL_DAYS = 1.0274912517
_TROPICAL_SOLS_PER_MY = 668.5991
# Clancy et al. (2000): Mars Year 1 began at Ls = 0 deg on 1955-04-11 11:20 UTC (JD_TT ~ 2435208.972)
_MSD_MY1_START = (2435208.9722 - 2451545.0 - 4.5) / _SOL_DAYS + 44796.0 - 0.0009626
_AU_LIGHT_SEC = 499.004783836


def _format_hms(hours: float) -> str:
    """Format fractional hours [0, 24) as HH:MM:SS."""
    total_sec = int(round((hours % 24.0) * 3600.0)) % 86400
    hh, rem = divmod(total_sec, 3600)
    mm, ss = divmod(rem, 60)
    return f"{hh:02d}:{mm:02d}:{ss:02d}"


def _solar_longitude_and_eot(delta_t_j2000: float) -> tuple[float, float]:
    """Return (Ls_deg, equation_of_time_hours) at days since J2000 TT.

    Implements the analytical Mars ephemeris from Allison & McEwen (2000),
    *Planetary and Space Science* 48(2-3), Eqs. 16-20:
    - Mean anomaly M and fictitious mean sun alpha_FMS advance linearly from J2000.
    - True anomaly equation-of-center (v - M) uses a 5-harmonic Fourier series
      in M plus 7 planetary perturbation cosines (Jupiter, Earth, Venus, etc.).
    - Areocentric solar longitude Ls = alpha_FMS + (v - M).
    - Equation of Time (EOT) converts mean solar time (LMST) to true solar time
      (LTST) using the obliquity-induced 2*Ls/4*Ls/6*Ls terms minus (v - M).
    """
    m_deg = (19.3871 + 0.52402073 * delta_t_j2000) % 360.0
    alpha_fms = (270.3871 + 0.524038496 * delta_t_j2000) % 360.0
    pbs = sum(
        amp * math.cos(math.radians(0.985626 * delta_t_j2000 / tau + phi))
        for amp, tau, phi in _PERTURBERS
    )
    m_rad = math.radians(m_deg)
    v_minus_m = (
        (10.691 + 3.0e-7 * delta_t_j2000) * math.sin(m_rad)
        + 0.623 * math.sin(2.0 * m_rad)
        + 0.050 * math.sin(3.0 * m_rad)
        + 0.005 * math.sin(4.0 * m_rad)
        + 0.0005 * math.sin(5.0 * m_rad)
        + pbs
    )
    ls_deg = (alpha_fms + v_minus_m) % 360.0
    ls_rad = math.radians(ls_deg)
    eot_deg = (
        2.861 * math.sin(2.0 * ls_rad)
        - 0.071 * math.sin(4.0 * ls_rad)
        + 0.002 * math.sin(6.0 * ls_rad)
        - v_minus_m
    )
    return ls_deg, eot_deg / 15.0


def _compute_owlt_sec(delta_t_j2000: float) -> int:
    """Estimate Earth-Mars one-way light time in seconds using J2000 Keplerian elements.

    Uses standard J2000 mean orbital elements (Standish / JPL) for Earth and Mars
    to solve heliocentric Cartesian positions (x, y, z in AU), then multiplies
    Euclidean separation by the IAU light-time constant (499.004783836 s/AU).
    """
    # Earth orbital elements (J2000)
    m_e = math.radians((357.5291 + 0.98560028 * delta_t_j2000) % 360.0)
    l_e = math.radians((100.4664 + 0.98564736 * delta_t_j2000) % 360.0)
    e_e = 0.0167086
    r_e = 1.00014 - 0.01671 * math.cos(m_e) - 0.00014 * math.cos(2.0 * m_e)
    lon_e = l_e + (2.0 * e_e * math.sin(m_e)) + (1.25 * e_e * e_e * math.sin(2.0 * m_e))
    xe, ye = r_e * math.cos(lon_e), r_e * math.sin(lon_e)

    # Mars orbital elements (J2000)
    m_m = math.radians((19.3871 + 0.52402073 * delta_t_j2000) % 360.0)
    l_m = math.radians((355.4330 + 0.52403295 * delta_t_j2000) % 360.0)
    e_m = 0.0934006
    a_m = 1.523679
    v_m = m_m + (2.0 * e_m - 0.25 * e_m**3) * math.sin(m_m) + 1.25 * e_m**2 * math.sin(2.0 * m_m)
    r_m = a_m * (1.0 - e_m**2) / (1.0 + e_m * math.cos(v_m))
    lon_m = l_m + (v_m - m_m)
    inc_m = math.radians(1.850)
    node_m = math.radians(49.558)
    xm = r_m * (math.cos(node_m) * math.cos(lon_m - node_m) - math.sin(node_m) * math.sin(lon_m - node_m) * math.cos(inc_m))
    ym = r_m * (math.sin(node_m) * math.cos(lon_m - node_m) + math.cos(node_m) * math.sin(lon_m - node_m) * math.cos(inc_m))
    zm = r_m * math.sin(lon_m - node_m) * math.sin(inc_m)

    dist_au = math.sqrt((xm - xe) ** 2 + (ym - ye) ** 2 + zm**2)
    return int(round(dist_au * _AU_LIGHT_SEC))


def _mars_season(ls_deg: float) -> tuple[str, str]:
    """Return (full_season, short_north_season) for a given solar longitude."""
    if ls_deg < 90.0:
        return "N. Spring / S. Autumn", "N. Spring"
    if ls_deg < 180.0:
        return "N. Summer / S. Winter", "N. Summer"
    if ls_deg < 270.0:
        return "N. Autumn / S. Spring", "N. Autumn"
    return "N. Winter / S. Summer", "N. Winter"


def compute_mars_time(lon: float | None = None, utc_time: datetime | None = None) -> dict[str, Any]:
    """Compute live Mars Date & Time telemetry (MSD, MTC, MY, Ls, season, LMST/LTST, OWLT)."""
    if utc_time is None:
        now = datetime.now(timezone.utc)
    elif utc_time.tzinfo is None:
        now = utc_time.replace(tzinfo=timezone.utc)
    else:
        now = utc_time.astimezone(timezone.utc)

    jd_utc = 2440587.5 + now.timestamp() / 86400.0
    jd_tt = jd_utc + 69.184 / 86400.0
    delta_t_j2000 = jd_tt - 2451545.0

    msd = (delta_t_j2000 - 4.5) / _SOL_DAYS + 44796.0 - 0.0009626
    mtc_hours = (msd % 1.0) * 24.0
    ls_deg, eot_hours = _solar_longitude_and_eot(delta_t_j2000)

    # Mars Year aligned to Ls = 0 deg crossings
    raw_years = (msd - _MSD_MY1_START) / _TROPICAL_SOLS_PER_MY
    mars_year = 1 + int(math.floor(raw_years))
    frac_mean = raw_years % 1.0
    frac_ls = ls_deg / 360.0
    if frac_mean > 0.75 and frac_ls < 0.25:
        mars_year += 1
    elif frac_mean < 0.25 and frac_ls > 0.75:
        mars_year -= 1

    # Estimate sol within current Mars Year using exact Ls = 0 crossing
    est_start_dt = delta_t_j2000 - (ls_deg / 0.524038496)
    for _ in range(3):
        ls_check, _ = _solar_longitude_and_eot(est_start_dt)
        err = ((ls_check + 180.0) % 360.0) - 180.0
        est_start_dt -= err / 0.524038496
    sol_of_year = max(0.0, (delta_t_j2000 - est_start_dt) / _SOL_DAYS)

    season_full, season_short = _mars_season(ls_deg)
    mars_month = min(12, int(ls_deg // 30.0) + 1)

    owlt_sec = _compute_owlt_sec(delta_t_j2000)
    owlt_m, owlt_s = divmod(owlt_sec, 60)

    payload: dict[str, Any] = {
        "earth_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "mars_sol_date": round(msd, 3),
        "mtc": _format_hms(mtc_hours),
        "mars_year": mars_year,
        "solar_longitude_deg": round(ls_deg, 2),
        "mars_month": mars_month,
        "mars_season": season_full,
        "mars_season_short": season_short,
        "sol_of_year": round(sol_of_year, 1),
        "equation_of_time_min": round(eot_hours * 60.0, 2),
        "owlt_sec": owlt_sec,
        "owlt_formatted": f"{owlt_m}m {owlt_s:02d}s",
        "owlt_range_sec": [180, 1340],
    }

    if lon is not None:
        lmst_hours = (mtc_hours + lon / 15.0) % 24.0
        ltst_hours = (lmst_hours + eot_hours) % 24.0
        payload["local_lon_deg"] = round(lon, 4)
        payload["lmst"] = _format_hms(lmst_hours)
        payload["ltst"] = _format_hms(ltst_hours)

    return payload
