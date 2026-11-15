"""Mars surface ionizing radiation & space-weather assessment (MSL RAD + DONKI)."""

from datetime import datetime, timedelta, timezone
import math
import time
import urllib.request
import json

_REF_ELEV_M = -4500.0
_SCALE_HEIGHT_M = 11100.0
_REF_COLUMN_G_CM2 = 21.4
_REF_GCR_MSV_DAY = 0.67
_DONKI_CACHE = {"ts": 0.0, "events": [], "source": "msl_rad_baseline"}
_DONKI_TTL_SEC = 600.0


def _fetch_donki_sep_events():
    """Fetch recent NASA DONKI SEP events with a short timeout and 10m cache."""
    now = time.monotonic()
    if now - _DONKI_CACHE["ts"] < _DONKI_TTL_SEC:
        return _DONKI_CACHE["events"], _DONKI_CACHE["source"]

    end_dt = datetime.now(timezone.utc)
    start_dt = end_dt - timedelta(days=3)
    url = (
        "https://api.kauai.ccmc.gsfc.nasa.gov/DONKI/SEP"
        f"?startDate={start_dt:%Y-%m-%d}&endDate={end_dt:%Y-%m-%d}"
    )
    try:
        with urllib.request.urlopen(url, timeout=2.5) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        events = payload if isinstance(payload, list) else []
        source = "nasa_donki_live+msl_rad"
    except Exception:
        events = []
        source = "msl_rad_baseline"

    _DONKI_CACHE.update({"ts": now, "events": events, "source": source})
    return events, source


def _determine_radiation_safety(total_usv_hr, sep_active):
    """Classify EVA radiation safety state and return crew recommendations."""
    if sep_active or total_usv_hr >= 120.0:
        return (
            "HAZARD",
            [
                "Solar Energetic Particle (SEP) / high-dose condition active.",
                "Abort exposed EVA and shelter inside habitat or regolith-shielded rover.",
            ],
        )
    if total_usv_hr >= 45.0:
        return (
            "CAUTION",
            [
                "Thin atmospheric column increases GCR exposure at high elevation.",
                "Limit continuous surface EVA duration and log cumulative suit dosimetry.",
            ],
        )
    return (
        "NOMINAL",
        [
            "Nominal Galactic Cosmic Ray (GCR) background; no active SEP storm.",
            "Standard EVA dosimeter monitoring applies.",
        ],
    )


def assess_surface_radiation(latitude, longitude, elevation_m=-4500.0):
    """Estimate Mars surface GCR/SEP dose rate and EVA safety state."""
    lat = float(latitude)
    lon = float(longitude)
    elev = float(elevation_m)
    column_g_cm2 = _REF_COLUMN_G_CM2 * math.exp(
        -(elev - _REF_ELEV_M) / _SCALE_HEIGHT_M
    )
    shield_factor = max(0.70, min(2.35, _REF_COLUMN_G_CM2 / max(column_g_cm2, 1.0)))

    # Southern Highlands crustal magnetic anomaly (Terra Sirenum / Terra Cimmeria)
    # spans roughly lat [-65, -20], lon [140..180] or [-180..-120]
    in_crustal_anomaly = (-65.0 <= lat <= -20.0) and (lon >= 140.0 or lon <= -120.0)
    mag_factor = 0.88 if in_crustal_anomaly else 1.0

    # High-latitude polar regions have slightly higher solar/cosmic particle access
    polar_factor = 1.0 + 0.08 * max(0.0, (abs(lat) - 55.0) / 35.0)

    gcr_msv_day = _REF_GCR_MSV_DAY * (0.7 + 0.3 * shield_factor) * mag_factor * polar_factor
    gcr_usv_hr = (gcr_msv_day * 1000.0) / 24.0

    events, source = _fetch_donki_sep_events()
    sep_active = len(events) > 0
    sep_usv_hr = 95.0 * shield_factor * mag_factor * polar_factor if sep_active else 0.0
    total_usv_hr = gcr_usv_hr + sep_usv_hr
    eva_4h_msv = (total_usv_hr * 4.0) / 1000.0
    safety_state, recommendations = _determine_radiation_safety(
        total_usv_hr, sep_active
    )

    return {
        "status": "ok",
        "location": {
            "latitude": round(float(latitude), 6),
            "longitude": round(float(longitude), 6),
            "elevation_m": round(elev, 1),
        },
        "radiation": {
            "gcr_dose_msv_day": round(gcr_msv_day, 3),
            "total_dose_rate_usv_hr": round(total_usv_hr, 2),
            "eva_4h_dose_msv": round(eva_4h_msv, 4),
            "column_depth_g_cm2": round(column_g_cm2, 2),
            "sep_alert_level": "ACTIVE_SEP" if sep_active else "QUIET",
            "recent_sep_events": len(events),
            "safety_state": safety_state,
            "recommendations": recommendations,
        },
        "source": source,
        "disclaimer": (
            "Advisory Mars surface radiation estimate calibrated to MSL RAD "
            "(~0.67 mSv/day at Gale Crater) and NASA DONKI SEP feed."
        ),
    }
