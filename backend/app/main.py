from collections import defaultdict, deque
import os
from pathlib import Path
import time

from fastapi import FastAPI, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.api.map_data import get_mars_time, router as map_router
from app.api.maps import router as maps_router
from app.api.routes import router as routes_router
from app.db import get_db

try:
    from app.api.climate import router as climate_router
except ImportError:
    climate_router = None

FRONTEND_DIR = Path(__file__).resolve().parents[2] / "frontend"

app = FastAPI(
    title="ARES - Astronaut Route & Exploration System",
    description="Mars EVA planning and exploration API",
    version="0.2.0",
)

_cors_raw = os.getenv("ARES_CORS_ORIGINS", "*").strip()
_cors_origins = ["*"] if _cors_raw == "*" else [o.strip() for o in _cors_raw.split(",") if o.strip()]

app.add_middleware(GZipMiddleware, minimum_size=1024)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

_RATE_LIMIT_RPM = int(os.getenv("ARES_RATE_LIMIT_RPM", "300"))
_ARES_API_KEY = os.getenv("ARES_API_KEY", "").strip()
_ip_windows: dict[str, deque[float]] = defaultdict(deque)


@app.middleware("http")
async def gateway_security_and_rate_limit(request: Request, call_next):
    path = request.url.path
    if path.startswith("/api/") and path != "/api/v1/health":
        # Optional API key protection for mutating mission-data endpoints
        if _ARES_API_KEY and request.method in ("POST", "PUT", "PATCH", "DELETE"):
            if path.startswith("/api/v1/map/waypoints") or path.startswith("/api/v1/map/features"):
                auth_hdr = request.headers.get("authorization", "")
                bearer = auth_hdr[7:].strip() if auth_hdr.lower().startswith("bearer ") else ""
                api_key = request.headers.get("x-api-key", "").strip() or bearer
                if api_key != _ARES_API_KEY:
                    return JSONResponse({"detail": "Unauthorized: invalid or missing API key"}, status_code=401)

        # Sliding-window per-IP rate limiting (high enough for 5x5 Street View bursts)
        if _RATE_LIMIT_RPM > 0:
            fwd = request.headers.get("x-forwarded-for", "").split(",")[0].strip()
            client_ip = fwd or (request.client.host if request.client else "unknown")
            now = time.monotonic()
            win = _ip_windows[client_ip]
            while win and now - win[0] > 60.0:
                win.popleft()
            if len(win) >= _RATE_LIMIT_RPM:
                return JSONResponse(
                    {"detail": "Rate limit exceeded; retry shortly"},
                    status_code=429,
                    headers={"Retry-After": "10"},
                )
            win.append(now)

    resp = await call_next(request)
    resp.headers.setdefault("X-Content-Type-Options", "nosniff")
    resp.headers.setdefault("X-Frame-Options", "SAMEORIGIN")
    resp.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
    return resp

if climate_router is not None:
    app.include_router(climate_router)
app.include_router(routes_router)
app.include_router(map_router)
app.include_router(maps_router)


@app.get("/api/v1/health")
def health():
    return {
        "status": "ok",
        "service": "ARES",
    }


@app.get("/api/v1/time", tags=["Time"])
def get_time(
    lon: float = Query(137.4417, ge=-180.0, le=180.0, description="East longitude in degrees for LMST/LTST (default: Gale Crater)"),
    utc: str | None = Query(None, description="Optional ISO-8601 UTC timestamp (defaults to current UTC)"),
):
    return get_mars_time(lon=lon, utc=utc)


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
