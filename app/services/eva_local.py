from functools import lru_cache
from pathlib import Path
import json
from PIL import Image

import numpy as np

from app.services.astar import plan_astar
from app.services.theta_star import plan_theta_star
from app.services.safety import validate_route_safety

BASE_DATA_DIR = Path(__file__).resolve().parents[2] / "data"
DATA_DIR = BASE_DATA_DIR / "mount_sharp"
JEZERO_DIR = BASE_DATA_DIR / "jezero"

CROP_X = 700
CROP_Y = 700
SIZE = 100
CELL_SIZE_M = 5.0


@lru_cache(maxsize=2)
def load_eva_terrain(site='mount_sharp'):
    if site == "mount_sharp":
        import rasterio
        from rasterio.windows import Window
        with rasterio.open(DATA_DIR / "mount_sharp_map.tif") as src:
            window = Window(CROP_X, CROP_Y, SIZE, SIZE)
            image = src.read(1, window=window)
            transform = list(src.window_transform(window))[:6]
        cell_width_m = CELL_SIZE_M
        cell_height_m = CELL_SIZE_M
        crop_origin = {"x": CROP_X, "y": CROP_Y}

    elif site == "jezero":
        image = np.asarray(Image.open(JEZERO_DIR / "jezero_tile.png"))
        metadata = json.loads(
            (JEZERO_DIR / "jezero_metadata.json").read_text()
        )
        cell_width_m = float(metadata["cell_width_m"])
        cell_height_m = float(metadata["cell_height_m"])
        transform = None
        crop_origin = metadata["source_window"]

    else:
        raise ValueError("Unsupported EVA site")

    if image.shape != (SIZE, SIZE):
        raise ValueError("Invalid EVA crop dimensions")

    valid = image != 0

    if not valid.any():
        raise ValueError("EVA crop contains no valid imagery")

    values = image[valid].astype(np.float32)

    # Experimental image-derived hazard indicators.
    # Darkness and local contrast are not verified physical obstacles.
    low_threshold = np.percentile(values, 12)

    padded = np.pad(
        image.astype(np.float32),
        1,
        mode="edge",
    )

    local_mean = np.zeros_like(image, dtype=np.float32)

    for dy in range(3):
        for dx in range(3):
            local_mean += padded[
                dy:dy + SIZE,
                dx:dx + SIZE,
            ]

    local_mean /= 9.0

    contrast = np.abs(image.astype(np.float32) - local_mean)

    contrast_threshold = np.percentile(
        contrast[valid],
        92,
    )

    candidate_hazards = (
        (image <= low_threshold)
        | (contrast >= contrast_threshold)
    ) & valid

    # Invalid pixels are blocked.
    obstacles = ~valid

    # Candidate hazards contribute risk rather than being
    # automatically classified as impassable.
    risk = candidate_hazards.astype(np.float32)

    # No genuine 5 m DEM is available.
    # Flat placeholder is used only to disable slope inference.
    elevation_placeholder = np.zeros(
        (SIZE, SIZE),
        dtype=np.float32,
    )

    return {
        "image": image,
        "obstacles": obstacles,
        "risk": risk,
        "elevation": elevation_placeholder,
        "transform": transform,
        "cell_width_m": cell_width_m,
        "cell_height_m": cell_height_m,
        "crop_origin": crop_origin,
        "candidate_hazards": int(candidate_hazards.sum()),
    }


def plan_eva_route(start, goal, risk_weight=20.0, algorithm="astar", site="mount_sharp"):
    terrain = load_eva_terrain(site)

    if algorithm not in ("astar", "theta_star"):
        raise ValueError("Unsupported routing algorithm")

    planner = plan_theta_star if algorithm == "theta_star" else plan_astar

    result = planner(
        start=start,
        goal=goal,
        elevation=terrain["elevation"].tolist(),
        obstacles=terrain["obstacles"].tolist(),
        risk=terrain["risk"].tolist(),
        cell_size_m=terrain["cell_width_m"],
        cell_height_m=terrain["cell_height_m"],
        max_slope_deg=89.0,
        slope_weight=0.0,
        risk_weight=risk_weight,
    )

    result.update({
        "mode": "hyperlocal_eva_experimental",
        "grid_width": SIZE,
        "grid_height": SIZE,
        "cell_size_m": terrain["cell_width_m"],
        "cell_width_m": terrain["cell_width_m"],
        "cell_height_m": terrain["cell_height_m"],
        "site": site,
        "crop_origin_pixels": terrain["crop_origin"],
        "map_affine_transform": terrain["transform"],
        "candidate_hazard_cells": terrain["candidate_hazards"],
        "hazard_source": "experimental_image_heuristics",
        "slope_assessment_available": False,
        "validated_for_eva_safety": False,
        "limitations": [
            "Candidate hazards are inferred from image darkness and local contrast.",
            "Shadows and illumination differences may cause false positives.",
            "No high-resolution elevation model is available.",
            "Route is experimental and not validated for astronaut use.",
        ],
    })

    safety = validate_route_safety(
        route_result=result,
        obstacles=terrain["obstacles"].tolist(),
        cell_width_m=terrain["cell_width_m"],
        cell_height_m=terrain["cell_height_m"],
    )

    result["safety"] = safety

    result["algorithm"] = algorithm

    return result
