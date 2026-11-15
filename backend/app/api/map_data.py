"""Map layers, spatial features, rover imagery, and Mars clock API routes."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import io
import json
import math
import threading
import time
from typing import Any
import urllib.request
import uuid

import httpx
import numpy as np
from fastapi import APIRouter, HTTPException, Query, Response
from fastapi.responses import StreamingResponse
from PIL import Image, ImageEnhance, ImageFilter
from pydantic import BaseModel, Field

from app.db import get_db
from app.services.mars_time import compute_mars_time
from app.services.radiation import assess_surface_radiation
from app.services.space_edac import compute_crc32, simulate_space_link_transfer

router = APIRouter(prefix="/api/v1/map", tags=["Map"])

_CACHE_TTL_SEC = 120.0
_cache: dict[str, tuple[float, Any]] = {}
_tile_cache: dict[str, bytes] = {}
_tile_lock = threading.Lock()
_trek_http = httpx.Client(
    timeout=12.0,
    limits=httpx.Limits(max_connections=24, max_keepalive_connections=16),
    headers={"User-Agent": "ARES-Tablet/1.0"},
)


def _cache_get(key: str) -> Any | None:
    entry = _cache.get(key)
    if not entry:
        return None
    ts, val = entry
    if time.monotonic() - ts > _CACHE_TTL_SEC:
        _cache.pop(key, None)
        return None
    return val


def _cache_set(key: str, val: Any) -> Any:
    _cache[key] = (time.monotonic(), val)
    return val


def _invalidate_feature_cache() -> None:
    for k in [k for k in _cache if k.startswith("features:")]:
        _cache.pop(k, None)

def _compute_mars_clocks(lon: float | None = 137.4417) -> dict[str, Any]:
    return compute_mars_time(lon=lon)


@router.get("/time")
def get_mars_time(
    lon: float = Query(137.4417, ge=-180.0, le=180.0, description="East longitude in degrees for LMST/LTST (default: Gale Crater)"),
    utc: str | None = Query(None, description="Optional ISO-8601 UTC timestamp (defaults to current UTC)"),
):
    utc_dt: datetime | None = None
    if utc:
        try:
            utc_dt = datetime.fromisoformat(utc.replace("Z", "+00:00"))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=f"Invalid ISO-8601 UTC timestamp: {utc}") from exc
    return compute_mars_time(lon=lon, utc_time=utc_dt)


@router.get("/planet")
def get_planet_profile(
    body: str = "mars",
    lon: float = Query(137.4417, ge=-180.0, le=180.0, description="East longitude in degrees for LMST/LTST"),
):
    db = get_db()
    profile = db["planet_profiles"].find_one({"_id": body})
    if not profile:
        raise HTTPException(status_code=404, detail=f"Planet profile '{body}' not found")
    return {"profile": profile, "clocks": _compute_mars_clocks(lon=lon)}


@router.get("/layers")
def get_map_layers(body: str = "mars"):
    db = get_db()
    layers = list(db["map_layers"].find({"body": body}, {"_id": 0}))
    usgs_layers = [
        {
            "layer_id": "usgs_mola_themis_blend",
            "body": "mars",
            "region": "global",
            "category": "topography",
            "protocol": "WMS",
            "url_template": "https://planetarymaps.usgs.gov/cgi-bin/mapserv?map=/maps/mars/mars_simp_cyl.map",
            "wms_layers": "MOLA_THEMIS_blend",
            "bbox": [-180.0, -90.0, 180.0, 90.0],
        },
        {
            "layer_id": "usgs_themis_day_ir",
            "body": "mars",
            "region": "global",
            "category": "thermal",
            "protocol": "WMS",
            "url_template": "https://planetarymaps.usgs.gov/cgi-bin/mapserv?map=/maps/mars/mars_simp_cyl.map",
            "wms_layers": "THEMIS_controlled",
            "bbox": [-180.0, -90.0, 180.0, 90.0],
        },
    ]
    return {"body": body, "layers": layers, "external_wms": usgs_layers}


@router.get("/features")
def get_spatial_features(
    response: Response,
    bbox: str | None = Query(None, description="min_lon,min_lat,max_lon,max_lat"),
    feature_type: str | None = Query(None, description="themis_stamp or rover_waypoint"),
    limit: int = Query(1500, ge=1, le=10000),
    slim: bool = Query(False, description="Strip heavy provenance/nested fields for fast map load"),
):
    cache_key = f"features:{bbox}:{feature_type}:{limit}:{slim}"
    cached = _cache_get(cache_key)
    if cached is not None:
        payload, crc = cached
        response.headers["X-Cache"] = "HIT"
        response.headers["X-Space-CRC32"] = crc
        return payload

    db = get_db()
    query: dict[str, Any] = {"body": "mars"}
    if feature_type:
        query["feature_type"] = feature_type
    if bbox:
        try:
            parts = [float(p.strip()) for p in bbox.split(",")]
            if len(parts) != 4:
                raise ValueError
            min_lon, min_lat, max_lon, max_lat = parts
        except ValueError:
            raise HTTPException(status_code=422, detail="bbox must be min_lon,min_lat,max_lon,max_lat")
        query["geometry"] = {
            "$geoWithin": {"$box": [[min_lon, min_lat], [max_lon, max_lat]]}
        }

    projection = {"_id": 0, "provenance": 0} if slim else {"_id": 0}
    cursor = db["spatial_features"].find(query, projection).limit(limit)
    features = []
    for doc in cursor:
        props = dict(doc.get("properties") or {})
        if slim and "images" in props and isinstance(props["images"], list):
            pano = next((im for im in props["images"] if im.get("isPanoramic") and im.get("url")), None)
            props.pop("images", None)
            if pano:
                props["images"] = [{"isPanoramic": True, "url": pano["url"]}]
        feat_props = {
            "feature_id": doc.get("feature_id"),
            "feature_type": doc.get("feature_type"),
            "mission_id": doc.get("mission_id"),
            "elevation_m": doc.get("elevation_m"),
            **props,
        }
        if not slim:
            feat_props["provenance"] = doc.get("provenance")
        features.append(
            {
                "type": "Feature",
                "id": doc.get("feature_id"),
                "geometry": doc.get("geometry"),
                "properties": feat_props,
            }
        )
    payload = {"type": "FeatureCollection", "count": len(features), "features": features}
    crc = compute_crc32(json.dumps(payload, separators=(",", ":"), default=str).encode("utf-8"))
    _cache_set(cache_key, (payload, crc))
    response.headers["X-Cache"] = "MISS"
    response.headers["X-Space-CRC32"] = crc
    return payload


_climate_cache: dict[str, Any] = {"ts": 0.0, "soles": []}


def _parse_num(val: Any) -> float | None:
    if val is None or val == "--" or val == "":
        return None
    try:
        return float(val)
    except (TypeError, ValueError):
        return None


@router.get("/climate")
def get_mars_climate(
    days: int = Query(30, ge=7, le=5000),
    start_date: str | None = Query(None, description="YYYY-MM-DD"),
    end_date: str | None = Query(None, description="YYYY-MM-DD"),
):
    """Multi-sol Mars climate history from NASA Curiosity REMS (2012-present)."""
    now = time.time()
    if not _climate_cache["soles"] or now - _climate_cache["ts"] > 3600:
        url = "https://mars.nasa.gov/rss/api/?feed=weather&category=msl&feedtype=json"
        r = httpx.get(url, follow_redirects=True, timeout=20.0)
        r.raise_for_status()
        raw = r.json().get("soles", [])
        # Reverse to chronological order (oldest -> newest)
        parsed = []
        for s in reversed(raw):
            parsed.append({
                "sol": int(s["sol"]) if str(s.get("sol", "")).isdigit() else None,
                "date": s.get("terrestrial_date"),
                "ls": _parse_num(s.get("ls")),
                "season": s.get("season"),
                "min_temp": _parse_num(s.get("min_temp")),
                "max_temp": _parse_num(s.get("max_temp")),
                "min_gts_temp": _parse_num(s.get("min_gts_temp")),
                "max_gts_temp": _parse_num(s.get("max_gts_temp")),
                "pressure": _parse_num(s.get("pressure")),
                "atmo_opacity": s.get("atmo_opacity"),
                "uv_index": s.get("local_uv_irradiance_index"),
            })
        _climate_cache["soles"] = parsed
        _climate_cache["ts"] = now

    rows = _climate_cache["soles"]
    if start_date or end_date:
        rows = [
            row for row in rows
            if row.get("date")
            and (not start_date or row["date"] >= start_date)
            and (not end_date or row["date"] <= end_date)
        ]
    else:
        rows = rows[-days:]

    mins = [r["min_temp"] for r in rows if r["min_temp"] is not None]
    maxs = [r["max_temp"] for r in rows if r["max_temp"] is not None]
    press = [r["pressure"] for r in rows if r["pressure"] is not None]
    step = max(1, len(rows) // 240)
    sampled = rows[::step] if step > 1 else rows
    if rows and sampled and sampled[-1] is not rows[-1]:
        sampled.append(rows[-1])

    return {
        "source": "NASA Curiosity REMS (Gale Crater)",
        "count": len(rows),
        "summary": {
            "first_date": rows[0]["date"] if rows else None,
            "last_date": rows[-1]["date"] if rows else None,
            "first_sol": rows[0]["sol"] if rows else None,
            "last_sol": rows[-1]["sol"] if rows else None,
            "min_temp_c": min(mins) if mins else None,
            "max_temp_c": max(maxs) if maxs else None,
            "avg_pressure_pa": round(sum(press) / len(press), 1) if press else None,
            "latest": rows[-1] if rows else None,
        },
        "records": sampled,
    }


@router.get("/images")
def get_nearby_images(
    lon: float | None = Query(None, ge=-180, le=180),
    lat: float | None = Query(None, ge=-90, le=90),
    radius_m: float = Query(1500.0, gt=0, le=50000),
    sol: int | None = Query(None, ge=0),
    limit: int = Query(20, ge=1, le=100),
):
    db = get_db()
    query: dict[str, Any] = {}
    if sol is not None:
        query["sol"] = sol
    if lon is not None and lat is not None:
        query["geometry"] = {
            "$nearSphere": {
                "$geometry": {"type": "Point", "coordinates": [lon, lat]},
                "$maxDistance": radius_m,
            }
        }
        docs = list(db["raw_images"].find(query, {"_id": 0}).limit(limit))
    else:
        docs = list(
            db["raw_images"].find(query, {"_id": 0}).sort("sol", -1).limit(limit)
        )
    return {"count": len(docs), "images": docs}


@router.get("/telemetry")
def get_telemetry_rollups(response: Response, station_id: str = "jezero_meda_sol100"):
    cache_key = f"telemetry:{station_id}"
    cached = _cache_get(cache_key)
    if cached is not None:
        payload, crc = cached
        response.headers["X-Cache"] = "HIT"
        response.headers["X-Space-CRC32"] = crc
        return payload

    db = get_db()
    records = list(
        db["telemetry_rollups_lod"]
        .find({"station_id": station_id}, {"_id": 0})
        .sort("lmst_bucket", 1)
    )
    payload = {"station_id": station_id, "count": len(records), "records": records}
    crc = compute_crc32(json.dumps(payload, separators=(",", ":"), default=str).encode("utf-8"))
    _cache_set(cache_key, (payload, crc))
    response.headers["X-Cache"] = "MISS"
    response.headers["X-Space-CRC32"] = crc
    return payload


_climate_cache: dict[str, Any] = {"ts": 0.0, "soles": []}


def _parse_num(val: Any) -> float | None:
    if val is None or val == "--" or val == "":
        return None
    try:
        return float(val)
    except (TypeError, ValueError):
        return None


@router.get("/climate")
def get_mars_climate(
    days: int = Query(30, ge=7, le=5000),
    start_date: str | None = Query(None, description="YYYY-MM-DD"),
    end_date: str | None = Query(None, description="YYYY-MM-DD"),
):
    """Multi-sol Mars climate history from NASA Curiosity REMS (2012-present)."""
    now = time.time()
    if not _climate_cache["soles"] or now - _climate_cache["ts"] > 3600:
        url = "https://mars.nasa.gov/rss/api/?feed=weather&category=msl&feedtype=json"
        r = httpx.get(url, follow_redirects=True, timeout=20.0)
        r.raise_for_status()
        raw = r.json().get("soles", [])
        # Reverse to chronological order (oldest -> newest)
        parsed = []
        for s in reversed(raw):
            parsed.append({
                "sol": int(s["sol"]) if str(s.get("sol", "")).isdigit() else None,
                "date": s.get("terrestrial_date"),
                "ls": _parse_num(s.get("ls")),
                "season": s.get("season"),
                "min_temp": _parse_num(s.get("min_temp")),
                "max_temp": _parse_num(s.get("max_temp")),
                "min_gts_temp": _parse_num(s.get("min_gts_temp")),
                "max_gts_temp": _parse_num(s.get("max_gts_temp")),
                "pressure": _parse_num(s.get("pressure")),
                "atmo_opacity": s.get("atmo_opacity"),
                "uv_index": s.get("local_uv_irradiance_index"),
            })
        _climate_cache["soles"] = parsed
        _climate_cache["ts"] = now

    rows = _climate_cache["soles"]
    if start_date or end_date:
        rows = [
            row for row in rows
            if row.get("date")
            and (not start_date or row["date"] >= start_date)
            and (not end_date or row["date"] <= end_date)
        ]
    else:
        rows = rows[-days:]

    mins = [r["min_temp"] for r in rows if r["min_temp"] is not None]
    maxs = [r["max_temp"] for r in rows if r["max_temp"] is not None]
    press = [r["pressure"] for r in rows if r["pressure"] is not None]
    step = max(1, len(rows) // 240)
    sampled = rows[::step] if step > 1 else rows
    if rows and sampled and sampled[-1] is not rows[-1]:
        sampled.append(rows[-1])

    return {
        "source": "NASA Curiosity REMS (Gale Crater)",
        "count": len(rows),
        "summary": {
            "first_date": rows[0]["date"] if rows else None,
            "last_date": rows[-1]["date"] if rows else None,
            "first_sol": rows[0]["sol"] if rows else None,
            "last_sol": rows[-1]["sol"] if rows else None,
            "min_temp_c": min(mins) if mins else None,
            "max_temp_c": max(maxs) if maxs else None,
            "avg_pressure_pa": round(sum(press) / len(press), 1) if press else None,
            "latest": rows[-1] if rows else None,
        },
        "records": sampled,
    }


_elev_pts_cache: dict[str, Any] = {"ts": 0.0, "coords": None, "elevs": None}


def _get_global_elev_points(db) -> tuple[np.ndarray, np.ndarray]:
    now = time.time()
    if _elev_pts_cache["coords"] is not None and now - _elev_pts_cache["ts"] < 300:
        return _elev_pts_cache["coords"], _elev_pts_cache["elevs"]
    pts = list(
        db["spatial_features"].find(
            {"body": "mars", "elevation_m": {"$ne": None}},
            {"_id": 0, "geometry.coordinates": 1, "elevation_m": 1},
        )
    )
    if pts:
        coords = np.array([p["geometry"]["coordinates"] for p in pts], dtype=np.float64)
        elevs = np.array([float(p["elevation_m"]) for p in pts], dtype=np.float64)
    else:
        coords = np.zeros((0, 2), dtype=np.float64)
        elevs = np.zeros((0,), dtype=np.float64)
    _elev_pts_cache["coords"] = coords
    _elev_pts_cache["elevs"] = elevs
    _elev_pts_cache["ts"] = now
    return coords, elevs


@router.get("/terrain-grid")
def get_terrain_grid(
    bbox: str = Query("137.3,-4.8,137.6,-4.45", description="min_lon,min_lat,max_lon,max_lat"),
    rows: int = Query(48, ge=8, le=128),
    cols: int = Query(48, ge=8, le=128),
):
    """Build a numeric elevation_m + slope_deg grid for 3D terrain & A* routing."""
    try:
        min_lon, min_lat, max_lon, max_lat = [float(p.strip()) for p in bbox.split(",")]
    except ValueError:
        raise HTTPException(status_code=422, detail="bbox must be min_lon,min_lat,max_lon,max_lat")
    if min_lon >= max_lon or min_lat >= max_lat:
        raise HTTPException(status_code=422, detail="bbox min values must be less than max values")

    db = get_db()
    lon_grid = np.linspace(min_lon, max_lon, cols)
    lat_grid = np.linspace(max_lat, min_lat, rows)  # north-to-south for 3D/raster alignment
    gx, gy = np.meshgrid(lon_grid, lat_grid)

    all_coords, all_elevs = _get_global_elev_points(db)
    # Use consistent global point set for IDW when >= 3 points lie near this region,
    # and smoothly blend into NASA MOLA z=7 regional relief so chunk borders never seam.
    mola_mat = _mola_elev_from_trek(min_lon, min_lat, max_lon, max_lat, rows, cols)
    if len(all_coords) >= 3:
        dx = gx[:, :, None] - all_coords[:, 0][None, None, :]
        dy = gy[:, :, None] - all_coords[:, 1][None, None, :]
        dist2 = dx * dx + dy * dy + 1e-10
        min_dist2 = dist2.min(axis=2)
        blend = np.exp(-min_dist2 / (0.35 * 0.35))
        if float(blend.max()) > 0.05:
            weights = 1.0 / dist2
            idw_mat = (weights @ all_elevs) / weights.sum(axis=2)
            elev_mat = blend * idw_mat + (1.0 - blend) * mola_mat
            source_name = "mongodb_spatial_features_idw_blended"
            pts_used = int((min_dist2.min() < 1.0) and len(all_coords))
        else:
            elev_mat = mola_mat
            source_name = "nasa_mola_clrshade_z7"
            pts_used = 0
    else:
        elev_mat = mola_mat
        source_name = "nasa_mola_clrshade_z7"
        pts_used = 0

    mars_r = 3396190.0
    mid_lat_rad = math.radians(0.5 * (min_lat + max_lat))
    cell_x_m = mars_r * max(0.05, math.cos(mid_lat_rad)) * math.radians(max_lon - min_lon) / max(cols - 1, 1)
    cell_y_m = mars_r * math.radians(max_lat - min_lat) / max(rows - 1, 1)

    dz_dy, dz_dx = np.gradient(elev_mat, cell_y_m, cell_x_m)
    slope_mat = np.degrees(np.arctan(np.hypot(dz_dx, dz_dy)))

    return {
        "bbox": [min_lon, min_lat, max_lon, max_lat],
        "rows": rows,
        "cols": cols,
        "cell_size_m": round(0.5 * (cell_x_m + cell_y_m), 2),
        "min_elev_m": round(float(elev_mat.min()), 2),
        "max_elev_m": round(float(elev_mat.max()), 2),
        "sample_points_used": pts_used,
        "source": source_name,
        "elevation_m": np.round(elev_mat, 2).tolist(),
        "slope_deg": np.round(slope_mat, 2).tolist(),
    }


class PlannedWaypointIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    lon: float = Field(..., ge=-180, le=180)
    lat: float = Field(..., ge=-90, le=90)
    category: str = Field("science_target", max_length=40)
    notes: str = Field("", max_length=500)


@router.post("/waypoints")
def create_planned_waypoint(wp: PlannedWaypointIn):
    """Save a custom astronaut-planned EVA waypoint to MongoDB spatial_features."""
    db = get_db()
    fid = f"planned_{uuid.uuid4().hex[:10]}"
    doc = {
        "feature_id": fid,
        "body": "mars",
        "mission_id": "ares_gale_boxwork_01",
        "feature_type": "planned_waypoint",
        "elevation_m": None,
        "geometry": {"type": "Point", "coordinates": [wp.lon, wp.lat]},
        "properties": {
            "name": wp.name,
            "category": wp.category,
            "notes": wp.notes,
            "created_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        },
        "provenance": {"source_id": "eva_tablet_planner"},
    }
    db["spatial_features"].insert_one(doc)
    doc.pop("_id", None)
    _invalidate_feature_cache()
    return {"status": "created", "feature": doc}


@router.delete("/waypoints/{feature_id}")
def delete_planned_waypoint(feature_id: str):
    """Delete a custom planned EVA waypoint from MongoDB spatial_features."""
    if not feature_id.startswith("planned_"):
        raise HTTPException(status_code=400, detail="Only planned_ waypoints can be deleted")
    db = get_db()
    res = db["spatial_features"].delete_one({"feature_id": feature_id, "feature_type": "planned_waypoint"})
    if res.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Planned waypoint not found")
    _invalidate_feature_cache()
    return {"status": "deleted", "feature_id": feature_id}


class EdacTestRequest(BaseModel):
    message: str = Field("SOL100:T=-69.2C:P=771Pa:OK", min_length=1, max_length=256)
    inject_bit_flips: int = Field(2, ge=0, le=32)


@router.post("/edac/test")
def test_space_edac(req: EdacTestRequest):
    """Demonstrate Hamming(7,4) single-bit error correction + CRC32 verification."""
    return simulate_space_link_transfer(req.message, req.inject_bit_flips)


_ALLOWED_IMAGE_PREFIXES = (
    "https://mars.nasa.gov/mars2020-raw-images/",
    "https://mars.nasa.gov/msl-raw-images/",
    "https://mars.nasa.gov/mer-raw-images/",
    "https://mars.nasa.gov/mmgis-maps/",
)


@router.get("/image-proxy")
def proxy_mars_image(url: str = Query(..., description="NASA mars.nasa.gov rover image or panorama URL")):
    """Same-origin proxy for NASA Mars rover raw images & panoramas to avoid WebGL CORS taint."""
    if not url.startswith(_ALLOWED_IMAGE_PREFIXES):
        raise HTTPException(status_code=400, detail="Only NASA mars.nasa.gov rover image/panorama URLs are allowed")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "ARES-Tablet/1.0"})
        resp = urllib.request.urlopen(req, timeout=20)
        ctype = resp.headers.get("Content-Type", "image/jpeg")
        return StreamingResponse(resp, media_type=ctype, headers={"Cache-Control": "public, max-age=86400"})
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Failed to fetch NASA image: {exc}")


def _haversine_mars_m(lon1: float, lat1: float, lon2: float, lat2: float) -> tuple[float, float]:
    """Return (distance_m, bearing_deg) on Mars (R=3396190m)."""
    r_mars = 3396190.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    dist = 2.0 * r_mars * math.asin(min(1.0, math.sqrt(a)))
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    bearing = (math.degrees(math.atan2(y, x)) + 360.0) % 360.0
    return dist, bearing


def _fetch_nasa_rover_rss(mission: str, limit: int = 8) -> list[dict[str, Any]]:
    """Fetch & cache latest front/mastcam/navcam raw frames from NASA RSS ('msl' or 'mars2020')."""
    cache_key = f"nasa_rss_imgs:{mission}:{limit}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    url = (
        f"https://mars.nasa.gov/rss/api/?feed=raw_images&category={mission}"
        f"&feedtype=json&ver=1.2&order=sol+desc&num={max(limit, 8)}"
    )
    try:
        resp = _trek_http.get(url, timeout=15.0)
        resp.raise_for_status()
        items = resp.json().get("images") or []
    except Exception:
        return []

    out: list[dict[str, Any]] = []
    for im in items:
        files = im.get("image_files") or {}
        raw_url = files.get("medium") or files.get("small") or files.get("large")
        if not raw_url:
            continue
        ext = im.get("extended") or {}
        try:
            az = float(ext.get("mastAz", 0.0)) % 360.0
        except (TypeError, ValueError):
            az = 0.0
        try:
            el = float(ext.get("mastEl", 0.0))
        except (TypeError, ValueError):
            el = 0.0
        inst = im.get("instrument") or (im.get("camera") or {}).get("instrument") or "NAVCAM"
        out.append(
            {
                "imageid": im.get("imageid"),
                "mission": "Curiosity (MSL)" if mission == "msl" else "Perseverance (M20)",
                "sol": im.get("sol"),
                "instrument": inst,
                "title": im.get("title") or f"{inst} Sol {im.get('sol')}",
                "date_taken_mars": im.get("date_taken_mars"),
                "mast_az_deg": round(az, 1),
                "mast_el_deg": round(el, 1),
                "proxy_url": f"/api/v1/map/image-proxy?url={raw_url}",
                "direct_url": raw_url,
                "coordinates": None,
                "is_panorama": False,
            }
        )
        if len(out) >= limit:
            break
    return _cache_set(cache_key, out)


@router.get("/streetview")
def get_streetview_bundle(
    lon: float = Query(..., ge=-180, le=180),
    lat: float = Query(..., ge=-90, le=90),
    radius_m: float = Query(5000.0, gt=0, le=100000),
    limit: int = Query(8, ge=1, le=20),
):
    """Return nearby geotagged rover photos, 360 panoramas, and area features for 3D Street View."""
    in_gale = 135.5 <= lon <= 139.5 and -7.0 <= lat <= -3.0
    nearby_imgs: list[dict[str, Any]] = []
    panoramas: list[dict[str, Any]] = []
    nearby_features: list[dict[str, Any]] = []
    nearest_mode = "nearby_geotagged"

    try:
        db = get_db()
        nearby_imgs = list(
            db["raw_images"]
            .find(
                {
                    "geometry": {
                        "$nearSphere": {
                            "$geometry": {"type": "Point", "coordinates": [lon, lat]},
                            "$maxDistance": radius_m,
                        }
                    }
                },
                {"_id": 0, "imageid": 1, "sol": 1, "instrument": 1, "date_taken_mars": 1, "extended.mastAz": 1, "extended.mastEl": 1, "image_files.medium": 1, "image_files.small": 1, "geometry": 1},
            )
            .limit(limit)
        )

        # Query nearby spatial_features for 360 panoramas & local terrain/geology context
        feats = list(
            db["spatial_features"]
            .find(
                {
                    "geometry": {
                        "$nearSphere": {
                            "$geometry": {"type": "Point", "coordinates": [lon, lat]},
                            "$maxDistance": max(radius_m, 12000.0),
                        }
                    },
                    "feature_type": {"$in": ["rover_waypoint", "msl_waypoint", "mineral_signature", "mars_landmark", "planned_waypoint"]},
                },
                {"_id": 0, "feature_id": 1, "feature_type": 1, "name": 1, "geometry": 1, "properties": 1},
            )
            .limit(18)
        )
        for f in feats:
            coords = (f.get("geometry") or {}).get("coordinates") or []
            if len(coords) < 2:
                continue
            flon, flat = float(coords[0]), float(coords[1])
            dist_m, bearing_deg = _haversine_mars_m(lon, lat, flon, flat)
            props = f.get("properties") or {}
            ftype = f.get("feature_type")
            pano = props.get("panorama_url")
            if pano:
                p_url = f"/api/v1/map/image-proxy?url={pano}" if str(pano).startswith(_ALLOWED_IMAGE_PREFIXES) else pano
                panoramas.append(
                    {
                        "feature_id": f.get("feature_id"),
                        "name": f.get("name") or f"Sol {props.get('sol', '?')} Panorama",
                        "sol": props.get("sol"),
                        "rover": "Perseverance" if ftype == "rover_waypoint" else "Curiosity",
                        "panorama_url": pano,
                        "proxy_url": p_url,
                        "coordinates": [flon, flat],
                        "distance_m": round(dist_m, 1),
                        "bearing_deg": round(bearing_deg, 1),
                        "is_panorama": True,
                    }
                )
            nearby_features.append(
                {
                    "feature_id": f.get("feature_id"),
                    "feature_type": ftype,
                    "name": f.get("name") or props.get("target") or f.get("feature_id"),
                    "sol": props.get("sol"),
                    "elevation_m": props.get("elev_m") or props.get("elevation_m"),
                    "mineral": props.get("mineral") or props.get("rock_type") or props.get("notes"),
                    "coordinates": [flon, flat],
                    "distance_m": round(dist_m, 1),
                    "bearing_deg": round(bearing_deg, 1),
                    "has_panorama": bool(pano),
                }
            )
    except Exception:
        pass

    photos: list[dict[str, Any]] = []
    if nearby_imgs:
        for im in nearby_imgs:
            raw_url = (im.get("image_files") or {}).get("medium") or (im.get("image_files") or {}).get("small")
            if not raw_url:
                continue
            ext = im.get("extended") or {}
            try:
                az = float(ext.get("mastAz", 0.0)) % 360.0
            except (TypeError, ValueError):
                az = 0.0
            try:
                el = float(ext.get("mastEl", 0.0))
            except (TypeError, ValueError):
                el = 0.0
            photos.append(
                {
                    "imageid": im.get("imageid"),
                    "mission": "Perseverance (M20)",
                    "sol": im.get("sol"),
                    "instrument": im.get("instrument"),
                    "date_taken_mars": im.get("date_taken_mars"),
                    "mast_az_deg": round(az, 1),
                    "mast_el_deg": round(el, 1),
                    "proxy_url": f"/api/v1/map/image-proxy?url={raw_url}",
                    "direct_url": raw_url,
                    "coordinates": (im.get("geometry") or {}).get("coordinates"),
                    "is_panorama": False,
                }
            )
    else:
        # Match rover mission to region (Curiosity in Gale Crater, Perseverance elsewhere)
        mission = "msl" if in_gale else "mars2020"
        photos = _fetch_nasa_rover_rss(mission, limit=limit)
        nearest_mode = f"live_nasa_{mission}_fallback" if photos else "none"

    return {
        "center": [lon, lat],
        "photo_match_mode": nearest_mode,
        "count": len(photos),
        "photos": photos,
        "panoramas": panoramas[:6],
        "nearby_features": nearby_features[:12],
    }


@router.get("/globe-texture")
def get_globe_texture(
    style: str = Query("viking_red", pattern="^(viking_red|mola)$"),
    z: int = Query(2, ge=1, le=3),
):
    """Stitch Mars Trek global equirectangular tiles (z=1..3) into a JPEG for WebGL 3D Globe."""
    cache_key = f"globe_tex:{style}:z{z}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return Response(content=cached, media_type="image/jpeg", headers={"X-Cache": "HIT", "Cache-Control": "public, max-age=86400"})

    layer = (
        "Mars_Viking_MDIM21_ClrMosaic_global_232m"
        if style == "viking_red"
        else "Mars_MGS_MOLA_ClrShade_merge_global_463m"
    )
    cols, rows = 2 * (2 ** z), 2 ** z
    canvas = Image.new("RGB", (cols * 256, rows * 256))

    def _fetch_tile(rc: tuple[int, int]) -> tuple[int, int, Image.Image]:
        r, c = rc
        u = f"https://trek.nasa.gov/tiles/Mars/EQ/{layer}/1.0.0/default/default028mm/{z}/{r}/{c}.jpg"
        for attempt in range(2):
            try:
                req = urllib.request.Request(u, headers={"User-Agent": "ARES-Tablet/1.0"})
                with urllib.request.urlopen(req, timeout=20) as resp:
                    return r, c, Image.open(io.BytesIO(resp.read())).convert("RGB")
            except Exception:
                if attempt == 1:
                    return r, c, Image.new("RGB", (256, 256), (120, 66, 46))

    tasks = [(r, c) for r in range(rows) for c in range(cols)]
    with ThreadPoolExecutor(max_workers=8) as pool:
        for r, c, tile in pool.map(_fetch_tile, tasks):
            canvas.paste(tile, (c * 256, r * 256))

    buf = io.BytesIO()
    canvas.save(buf, format="JPEG", quality=88)
    raw = buf.getvalue()
    _cache_set(cache_key, raw)
    return Response(content=raw, media_type="image/jpeg", headers={"X-Cache": "MISS", "Cache-Control": "public, max-age=86400"})


@router.get("/radiation")
def get_surface_radiation(
    lat: float = Query(-4.5895, description="Martian latitude in degrees"),
    lon: float = Query(137.4417, description="Martian east longitude in degrees"),
    elevation_m: float = Query(-4500.0, description="Surface elevation in meters"),
):
    """Assess Mars surface GCR/SEP ionizing radiation and EVA safety state."""
    return assess_surface_radiation(lat, lon, elevation_m)


def _stitch_trek_bbox(
    layer: str,
    ext: str,
    max_z: int,
    min_lon: float,
    min_lat: float,
    max_lon: float,
    max_lat: float,
    out_w: int,
    out_h: int,
) -> Image.Image:
    """Stitch Mars Trek WMTS tiles with subpixel BICUBIC extent crop to eliminate chunk seams."""
    z = max_z
    while z > 2:
        total_cols = 2 * (2 ** z)
        total_rows = 2 ** z
        c0 = max(0, min(total_cols - 1, int(((min_lon + 180.0) / 360.0) * total_cols)))
        c1 = max(0, min(total_cols - 1, int(((max_lon + 180.0) / 360.0) * total_cols)))
        r0 = max(0, min(total_rows - 1, int(((90.0 - max_lat) / 180.0) * total_rows)))
        r1 = max(0, min(total_rows - 1, int(((90.0 - min_lat) / 180.0) * total_rows)))
        if (c1 - c0 + 1) <= 4 and (r1 - r0 + 1) <= 4:
            break
        z -= 1

    total_cols = 2 * (2 ** z)
    total_rows = 2 ** z
    c0 = max(0, min(total_cols - 1, int(((min_lon + 180.0) / 360.0) * total_cols)))
    c1 = max(0, min(total_cols - 1, int(((max_lon + 180.0) / 360.0) * total_cols)))
    r0 = max(0, min(total_rows - 1, int(((90.0 - max_lat) / 180.0) * total_rows)))
    r1 = max(0, min(total_rows - 1, int(((90.0 - min_lat) / 180.0) * total_rows)))

    stitched = Image.new("RGB", ((c1 - c0 + 1) * 256, (r1 - r0 + 1) * 256))

    def _fetch(rc: tuple[int, int]) -> tuple[int, int, Image.Image]:
        r, c = rc
        tkey = f"{layer}:{z}:{r}:{c}"
        with _tile_lock:
            raw_tile = _tile_cache.get(tkey)
        if raw_tile is not None:
            return r, c, Image.open(io.BytesIO(raw_tile)).convert("RGB")
        u = f"https://trek.nasa.gov/tiles/Mars/EQ/{layer}/1.0.0/default/default028mm/{z}/{r}/{c}.{ext}"
        try:
            resp = _trek_http.get(u)
            resp.raise_for_status()
            raw_tile = resp.content
            with _tile_lock:
                if len(_tile_cache) >= 512:
                    _tile_cache.pop(next(iter(_tile_cache)))
                _tile_cache[tkey] = raw_tile
            return r, c, Image.open(io.BytesIO(raw_tile)).convert("RGB")
        except Exception:
            return r, c, Image.new("RGB", (256, 256), (90, 52, 38))

    tasks = [(r, c) for r in range(r0, r1 + 1) for c in range(c0, c1 + 1)]
    with ThreadPoolExecutor(max_workers=8) as pool:
        for r, c, tile in pool.map(_fetch, tasks):
            stitched.paste(tile, ((c - c0) * 256, (r - r0) * 256))

    fx_left = (((min_lon + 180.0) / 360.0) * total_cols - c0) * 256.0
    fx_right = (((max_lon + 180.0) / 360.0) * total_cols - c0) * 256.0
    fy_top = (((90.0 - max_lat) / 180.0) * total_rows - r0) * 256.0
    fy_bot = (((90.0 - min_lat) / 180.0) * total_rows - r0) * 256.0
    return stitched.transform(
        (out_w, out_h),
        Image.Transform.EXTENT,
        (fx_left, fy_top, fx_right, fy_bot),
        resample=Image.Resampling.BICUBIC,
    )


def _mola_elev_from_trek(
    min_lon: float,
    min_lat: float,
    max_lon: float,
    max_lat: float,
    rows: int,
    cols: int,
) -> np.ndarray:
    """Estimate continuous regional elevation (m) from NASA MOLA Color-Shaded tiles with zero chunk seams."""
    layer, ext, z = "Mars_MGS_MOLA_ClrShade_merge_global_463m", "jpg", 7
    total_cols = 2 * (2 ** z)
    total_rows = 2 ** z
    # Pad by 1 tile on all sides so GaussianBlur and bilinear sampling are 100% continuous across chunk boundaries
    c0 = max(0, int(((min_lon + 180.0) / 360.0) * total_cols) - 1)
    c1 = min(total_cols - 1, int(((max_lon + 180.0) / 360.0) * total_cols) + 1)
    r0 = max(0, int(((90.0 - max_lat) / 180.0) * total_rows) - 1)
    r1 = min(total_rows - 1, int(((90.0 - min_lat) / 180.0) * total_rows) + 1)

    stitched = Image.new("RGB", ((c1 - c0 + 1) * 256, (r1 - r0 + 1) * 256))

    def _fetch(rc: tuple[int, int]) -> tuple[int, int, Image.Image]:
        r, c = rc
        tkey = f"{layer}:{z}:{r}:{c}"
        with _tile_lock:
            raw_tile = _tile_cache.get(tkey)
        if raw_tile is not None:
            return r, c, Image.open(io.BytesIO(raw_tile)).convert("RGB")
        u = f"https://trek.nasa.gov/tiles/Mars/EQ/{layer}/1.0.0/default/default028mm/{z}/{r}/{c}.{ext}"
        try:
            resp = _trek_http.get(u)
            resp.raise_for_status()
            raw_tile = resp.content
            with _tile_lock:
                if len(_tile_cache) >= 512:
                    _tile_cache.pop(next(iter(_tile_cache)))
                _tile_cache[tkey] = raw_tile
            return r, c, Image.open(io.BytesIO(raw_tile)).convert("RGB")
        except Exception:
            return r, c, Image.new("RGB", (256, 256), (90, 52, 38))

    tasks = [(r, c) for r in range(r0, r1 + 1) for c in range(c0, c1 + 1)]
    with ThreadPoolExecutor(max_workers=8) as pool:
        for r, c, tile in pool.map(_fetch, tasks):
            stitched.paste(tile, ((c - c0) * 256, (r - r0) * 256))

    stitched = stitched.filter(ImageFilter.GaussianBlur(radius=3.0))
    arr = np.asarray(stitched, dtype=np.float64) / 255.0
    h, w, _ = arr.shape

    # Sample exact vertex coordinates (linspace min..max) via bilinear interpolation so shared chunk edges match identically
    lon_v = np.linspace(min_lon, max_lon, cols)
    lat_v = np.linspace(max_lat, min_lat, rows)
    px = np.clip(((lon_v + 180.0) / 360.0 * total_cols - c0) * 256.0, 0.0, w - 1.000001)
    py = np.clip(((90.0 - lat_v) / 180.0 * total_rows - r0) * 256.0, 0.0, h - 1.000001)

    x0 = np.floor(px).astype(int)
    y0 = np.floor(py).astype(int)
    dx = (px - x0)[None, :, None]
    dy = (py - y0)[:, None, None]

    c00 = arr[y0[:, None], x0[None, :], :]
    c10 = arr[y0[:, None], x0[None, :] + 1, :]
    c01 = arr[y0[:, None] + 1, x0[None, :], :]
    c11 = arr[y0[:, None] + 1, x0[None, :] + 1, :]
    rgb = (c00 * (1.0 - dx) + c10 * dx) * (1.0 - dy) + (c01 * (1.0 - dx) + c11 * dx) * dy

    r_ch, g_ch, b_ch = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    score = r_ch * 1.15 + g_ch * 0.35 - b_ch * 0.95
    return np.clip((score - 0.15) * 8500.0, -9000.0, 15000.0)


@router.get("/regional-texture")
def get_regional_texture(
    bbox: str = Query("137.25,-4.9,137.65,-4.5", description="min_lon,min_lat,max_lon,max_lat"),
):
    """Stitch & crop real Mars Trek CTX/HiRISE/Viking tiles for a bbox to drape onto 3D terrain."""
    try:
        min_lon, min_lat, max_lon, max_lat = [float(p.strip()) for p in bbox.split(",")]
    except ValueError:
        raise HTTPException(status_code=422, detail="bbox must be min_lon,min_lat,max_lon,max_lat")

    cache_key = f"reg_tex2:{round(min_lon,4)},{round(min_lat,4)},{round(max_lon,4)},{round(max_lat,4)}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return Response(content=cached, media_type="image/jpeg", headers={"X-Cache": "HIT", "Cache-Control": "public, max-age=86400"})

    mid_lon = 0.5 * (min_lon + max_lon)
    mid_lat = 0.5 * (min_lat + max_lat)

    if 77.22 <= mid_lon <= 77.58 and 18.30 <= mid_lat <= 18.67:
        layer, ext, z = "JEZ_hirise_soc_006_orthoMosaic_25cm_Eqc_latTs0_lon0_first_dd", "png", 12
    elif 135.18 <= mid_lon <= 139.24 and -6.57 <= mid_lat <= -2.81:
        layer, ext, z = "Gale_CTX_BlockAdj_dd", "png", 11
    else:
        layer, ext, z = "Mars_Viking_MDIM21_ClrMosaic_global_232m", "jpg", 7

    cropped = _stitch_trek_bbox(layer, ext, z, min_lon, min_lat, max_lon, max_lat, 512, 512)
    cropped = ImageEnhance.Sharpness(cropped).enhance(1.25)
    buf = io.BytesIO()
    cropped.save(buf, format="JPEG", quality=88)
    raw = buf.getvalue()
    _cache_set(cache_key, raw)
    return Response(content=raw, media_type="image/jpeg", headers={"X-Cache": "MISS", "Cache-Control": "public, max-age=86400"})


@router.get("/radiation")
def get_surface_radiation(
    lat: float = Query(-4.5895, description="Martian latitude in degrees"),
    lon: float = Query(137.4417, description="Martian east longitude in degrees"),
    elevation_m: float = Query(-4500.0, description="Surface elevation in meters"),
):
    """Assess Mars surface GCR/SEP ionizing radiation and EVA safety state."""
    return assess_surface_radiation(lat, lon, elevation_m)
