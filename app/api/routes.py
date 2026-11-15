from pydantic import BaseModel, Field
from app.schemas.routes import Point

import json
from functools import lru_cache
from pathlib import Path

import numpy as np
from fastapi import HTTPException
from app.schemas.routes import MountSharpRouteRequest

from fastapi import APIRouter
from typing import Literal

from app.schemas.routes import RouteRequest
from app.services.astar import plan_astar

router = APIRouter(
    prefix="/api/v1/routes",
    tags=["Routes"],
)


@router.post("/plan")
def plan_route(request: RouteRequest):
    result = plan_astar(
        start=(request.start.x, request.start.y),
        goal=(request.goal.x, request.goal.y),
        elevation=request.elevation,
        obstacles=request.obstacles,
        risk=request.risk,
        cell_size_m=request.cell_size_m,
        max_slope_deg=request.max_slope_deg,
        slope_weight=request.slope_weight,
        risk_weight=request.risk_weight,
    )

    result["terrain_source"] = "client_supplied_grid"
    result["validated_for_eva_safety"] = False

    return result


DATA_DIR = Path(__file__).resolve().parents[2] / "data" / "mount_sharp"


@lru_cache(maxsize=1)
def load_mount_sharp():
    elevation = np.load(
        DATA_DIR / "mount_sharp_elevation.npy",
        allow_pickle=False,
    )
    obstacles = np.load(
        DATA_DIR / "mount_sharp_obstacles.npy",
        allow_pickle=False,
    )

    with open(DATA_DIR / "mount_sharp_metadata.json") as f:
        metadata = json.load(f)

    if elevation.ndim != 2 or elevation.shape != obstacles.shape:
        raise ValueError("Invalid terrain grid dimensions")
    if not np.isfinite(elevation).all():
        raise ValueError("Elevation grid contains invalid values")
    if obstacles.dtype != np.bool_:
        raise ValueError("Obstacle mask must be boolean")

    cell_size = float(metadata["elevation_grid"]["cell_size_m"])
    if not np.isfinite(cell_size) or cell_size <= 0:
        raise ValueError("Invalid cell size")

    return elevation.tolist(), obstacles.tolist(), metadata, cell_size


@router.post("/mount-sharp")
def plan_mount_sharp_route(request: MountSharpRouteRequest):
    try:
        elevation, obstacles, metadata, cell_size = load_mount_sharp()
    except (OSError, ValueError, KeyError) as exc:
        raise HTTPException(
            status_code=503,
            detail="Mount Sharp terrain data unavailable or invalid",
        ) from exc

    height, width = len(elevation), len(elevation[0])

    for point in (request.start, request.goal):
        if point.x >= width or point.y >= height:
            raise HTTPException(
                status_code=422,
                detail="Start or goal outside terrain grid",
            )
        if obstacles[point.y][point.x]:
            raise HTTPException(
                status_code=422,
                detail="Start or goal blocked",
            )

    result = plan_astar(
        start=(request.start.x, request.start.y),
        goal=(request.goal.x, request.goal.y),
        elevation=elevation,
        obstacles=obstacles,
        cell_size_m=cell_size,
        max_slope_deg=request.max_slope_deg,
        slope_weight=request.slope_weight,
        risk_weight=request.risk_weight,
    )

    result.update({
        "terrain_source": "NASA-derived Mount Sharp DEM",
        "study_region": metadata["study_region"],
        "grid_width": width,
        "grid_height": height,
        "cell_size_m": cell_size,
        "grid_affine_transform": metadata[
            "elevation_grid"
        ]["affine_transform"],
        "map_affine_transform": metadata[
            "map_imagery"
        ]["affine_transform"],
        "validated_for_eva_safety": False,
        "limitations": metadata["limitations"],
    })

    return result


from app.services.eva_local import plan_eva_route


class EvaLocalRequest(BaseModel):
    start: Point
    goal: Point
    risk_weight: float = Field(default=20.0, ge=0, le=100)
    algorithm: Literal["astar", "theta_star"] = "astar"
    site: Literal["mount_sharp", "jezero"] = "mount_sharp"

@router.post("/eva-local")
def plan_eva_local_route(request: EvaLocalRequest):
    if request.start == request.goal:
        raise HTTPException(
            status_code=422,
            detail="Start and goal must differ",
        )

    for point in (request.start, request.goal):
        if point.x >= 100 or point.y >= 100:
            raise HTTPException(
                status_code=422,
                detail="Coordinates must be within the 100x100 EVA grid",
            )

    try:
        return plan_eva_route(
            start=(request.start.x, request.start.y),
            goal=(request.goal.x, request.goal.y),
            risk_weight=request.risk_weight,
            algorithm=request.algorithm,
            site=request.site,
        )
    except (OSError, ValueError, ImportError) as exc:
        raise HTTPException(
            status_code=503,
            detail="EVA local terrain imagery unavailable or invalid",
        ) from exc
