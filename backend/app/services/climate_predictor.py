from functools import lru_cache
from pathlib import Path

import numpy as np
import pandas as pd
import skops.io as sio

MODEL_PATH = (
    Path(__file__).resolve().parents[3]
    / "artifacts"
    / "mars_models.skops"
)

REF_LAT = 18.4447
REF_LON = 77.4508
REF_ELEV = -2569.0

TARGETS = (
    "ground_temp_c",
    "air_temp_c",
    "wind_speed_ms",
    "wind_sin",
    "wind_cos",
    "pressure_pa",
    "solar_zenith_deg",
    "sunlit_fraction",
    "uv_irradiance",
    "total_solar_rad",
)

FEATURES = (
    "time_sin1",
    "time_cos1",
    "time_sin2",
    "time_cos2",
    "latitude",
    "longitude",
    "elevation_m",
)

ALLOWED_TYPES = {"sklearn.tree._tree.Tree"}


@lru_cache(maxsize=1)
def load_models():
    unknown = set(sio.get_untrusted_types(file=MODEL_PATH))

    if unknown != ALLOWED_TYPES:
        raise RuntimeError(
            f"Unexpected model types: {unknown}"
        )

    models = sio.load(
        MODEL_PATH,
        trusted=list(ALLOWED_TYPES),
    )

    if not isinstance(models, dict) or set(models) != set(TARGETS):
        raise RuntimeError("Climate model targets do not match")

    for model in models.values():
        if list(model.feature_names_in_) != list(FEATURES):
            raise RuntimeError("Climate model feature schema mismatch")

    return models


def build_features(minute, latitude, longitude, elevation):
    theta1 = 2 * np.pi * minute / 1440
    theta2 = 4 * np.pi * minute / 1440

    return pd.DataFrame([{
        "time_sin1": np.sin(theta1),
        "time_cos1": np.cos(theta1),
        "time_sin2": np.sin(theta2),
        "time_cos2": np.cos(theta2),
        "latitude": latitude,
        "longitude": longitude,
        "elevation_m": elevation,
    }])


def compass_direction(degrees):
    directions = [
        "N", "NNE", "NE", "ENE",
        "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW",
        "W", "WNW", "NW", "NNW",
    ]
    return directions[int((degrees + 11.25) / 22.5) % 16]


def _apply_climate_adjustments(predictions, latitude, elevation_m):
    """Apply elevation and latitude heuristic adjustments to raw predictions."""
    delta_elev = elevation_m - REF_ELEV
    predictions["pressure_pa"] *= np.exp(-delta_elev / 11100.0)
    lat_factor = np.cos(np.deg2rad(latitude)) / np.cos(np.deg2rad(REF_LAT))

    predictions["air_temp_c"] += -0.0015 * delta_elev + 4.0 * (lat_factor - 1)
    predictions["ground_temp_c"] += -0.0018 * delta_elev + 8.0 * (lat_factor - 1)
    predictions["solar_zenith_deg"] = float(
        np.clip(
            predictions["solar_zenith_deg"] + abs(latitude - REF_LAT) * 0.45,
            0,
            180,
        )
    )

    if predictions["solar_zenith_deg"] > 90:
        predictions["uv_irradiance"] = 0
        predictions["total_solar_rad"] = 0
        predictions["sunlit_fraction"] = 0
    else:
        predictions["uv_irradiance"] = max(
            0, predictions["uv_irradiance"] * lat_factor
        )
        predictions["total_solar_rad"] = max(
            0, predictions["total_solar_rad"] * lat_factor
        )


def _format_climate_response(
    predictions, latitude, longitude, ltst_time, elevation_m, model_count
):
    """Format adjusted climate predictions and safety alerts for API output."""
    solar_elevation = 90 - predictions["solar_zenith_deg"]
    wind_direction = (
        np.rad2deg(np.arctan2(predictions["wind_sin"], predictions["wind_cos"]))
        + 360
    ) % 360
    wind_speed = max(0, predictions["wind_speed_ms"])

    return {
        "inputs": {
            "latitude": round(latitude, 6),
            "longitude": round(longitude, 6),
            "ltst_time": ltst_time,
            "elevation_m": elevation_m,
        },
        "predictions": {
            "ground_temp_c": round(predictions["ground_temp_c"], 2),
            "air_temp_c": round(predictions["air_temp_c"], 2),
            "wind_speed_ms": round(wind_speed, 2),
            "wind_dir_deg": round(wind_direction, 1),
            "wind_compass": compass_direction(wind_direction),
            "pressure_pa": round(predictions["pressure_pa"], 2),
            "suit_delta_kpa": round((29600 - predictions["pressure_pa"]) / 1000, 2),
            "solar_zenith_deg": round(predictions["solar_zenith_deg"], 2),
            "solar_elevation_deg": round(solar_elevation, 2),
            "sunlit_percent": round(predictions["sunlit_fraction"] * 100, 1),
            "uv_irradiance": round(predictions["uv_irradiance"], 5),
            "total_solar_rad_wm2": round(predictions["total_solar_rad"], 2),
        },
        "safety_alerts": {
            "extreme_cold_alert": bool(
                predictions["ground_temp_c"] < -65
                or predictions["air_temp_c"] < -70
            ),
            "high_wind_dust_alert": bool(wind_speed > 10),
            "shadowed_region_alert": bool(
                solar_elevation <= 0 or predictions["sunlit_fraction"] < 0.5
            ),
            "elevated_uv_alert": bool(predictions["uv_irradiance"] > 0.02),
        },
        "model_metadata": {
            "model_type": "RandomForestRegressor",
            "model_count": model_count,
            "inference_method": "reference_location_with_heuristic_adjustments",
            "validated_for_eva_safety": False,
            "disclaimer": (
                "Experimental climate estimates. "
                "Not validated for astronaut safety decisions."
            ),
        },
    }


def predict_climate(latitude, longitude, ltst_time, elevation_m):
    """Predict Mars surface climate and EVA alerts for a site and LTST."""
    hour, minute = map(int, ltst_time.split(":"))
    minute_of_sol = hour * 60 + minute

    # Match the teammate's notebook: model inference uses
    # reference-location features, followed by heuristic corrections.
    features = build_features(minute_of_sol, REF_LAT, REF_LON, REF_ELEV)
    models = load_models()
    predictions = {
        target: float(models[target].predict(features)[0])
        for target in TARGETS
    }
    _apply_climate_adjustments(predictions, latitude, elevation_m)
    return _format_climate_response(
        predictions, latitude, longitude, ltst_time, elevation_m, len(models)
    )
