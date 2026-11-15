from app.api.maps import router as jezero_maps_router
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.map_data import router as map_router
from app.api.routes import router as routes_router
from app.db import get_db

try:
    from app.api.climate import router as climate_router
except ImportError:
    climate_router = None

FRONTEND_DIR = Path(__file__).resolve().parents[1] / "frontend"

app = FastAPI(
    title="ARES - Astronaut Route & Exploration System",
    description="Mars EVA planning and exploration API",
    version="0.2.0",
)

app.add_middleware(GZipMiddleware, minimum_size=1024)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

if climate_router is not None:
    app.include_router(climate_router)
app.include_router(routes_router)
app.include_router(map_router)
app.include_router(jezero_maps_router)


@app.get("/api/v1/health")
def health():
    return {
        "status": "ok",
        "service": "ARES",
    }


@app.get("/api/v1/mission")
def get_mission():
    return {
        "name": "ARES",
        "study_region": "Mount Sharp, Gale Crater",
        "status": "active",
        "data_status": "mongodb_connected",
    }


@app.get("/api/v1/layers")
def get_layers():
    try:
        db = get_db()
        docs = list(db["map_layers"].find({"body": "mars"}, {"_id": 0, "layer_id": 1, "category": 1, "region": 1}))
        return {"layers": [{**d, "status": "active"} for d in docs]}
    except Exception:
        return {
            "layers": [
                {"id": "optical", "status": "pending"},
                {"id": "topography", "status": "pending"},
                {"id": "science", "status": "pending"},
                {"id": "environment", "status": "pending"},
            ]
        }


if FRONTEND_DIR.exists():
    app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")
