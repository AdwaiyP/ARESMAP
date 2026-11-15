"""Comprehensive 120-case stress, boundary, negative, and security test suite for ARES."""
import math
import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app, raise_server_exceptions=False)


def _flat_grid(rows: int, cols: int, val: float = 0.0) -> list[list[float]]:
    return [[val for _ in range(cols)] for _ in range(rows)]


# =====================================================================
# 1. SYSTEM HEALTH, TIME, MISSION, PLANET & LAYERS (12 cases)
# =====================================================================

def test_001_health_ok():
    r = client.get("/api/v1/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_002_mission_ok():
    r = client.get("/api/v1/mission")
    assert r.status_code == 200
    assert r.json()["name"] == "ARES"


def test_003_planet_mars_ok():
    r = client.get("/api/v1/map/planet")
    assert r.status_code == 200
    d = r.json()
    assert d["profile"]["_id"] == "mars"
    assert "clocks" in d


def test_004_layers_mars_ok():
    r = client.get("/api/v1/map/layers?body=mars")
    assert r.status_code == 200
    assert "layers" in r.json()


def test_005_layers_alias_ok():
    r = client.get("/api/v1/layers")
    assert r.status_code == 200


def test_006_time_default_ok():
    r = client.get("/api/v1/map/time")
    assert r.status_code == 200
    d = r.json()
    assert "mars_sol_date" in d and "ltst" in d


@pytest.mark.parametrize("utc", [
    "2000-01-06T00:00:00Z",      # J2000 Mars epoch
    "2024-02-29T23:59:59Z",      # Leap day
    "1999-12-31T23:59:59Z",      # Pre-J2000
    "2035-07-04T12:30:00+00:00", # Offset format
])
def test_007_to_010_time_edge_utcs(utc):
    r = client.get(f"/api/v1/time?utc={utc.replace('+', '%2B')}&lon=137.4417")
    assert r.status_code == 200
    assert math.isfinite(r.json()["mars_sol_date"])


@pytest.mark.parametrize("utc", ["not-a-date", "2026-13-45T99:99:99Z"])
def test_011_to_012_time_invalid_utc_rejected(utc):
    r = client.get(f"/api/v1/time?utc={utc}")
    assert r.status_code in (400, 422)


# =====================================================================
# 2. CLIMATE PREDICTION /api/v1/climate/predict (14 cases)
# =====================================================================

@pytest.mark.parametrize("lat,lon,elev,ltst", [
    (-4.5895, 137.4417, -4500.0, "12:00"),   # Gale Crater
    (18.38, 77.58, -2500.0, "06:30"),        # Jezero Crater
    (18.65, 226.2, 21200.0, "15:45"),        # Olympus Mons (lon > 180)
    (-42.4, 70.5, -7152.0, "00:00"),         # Hellas Planum
    (90.0, 0.0, 0.0, "23:59"),               # North Pole
    (-90.0, -180.0, -10000.0, "01:15"),      # South Pole + min elev
    (0.0, 360.0, 30000.0, "18:00"),          # Max lon + max elev
])
def test_013_to_019_climate_valid_and_extreme(lat, lon, elev, ltst):
    r = client.post("/api/v1/climate/predict", json={
        "latitude": lat, "longitude": lon, "elevation_m": elev, "ltst_time": ltst,
    })
    assert r.status_code == 200
    d = r.json()["predictions"]
    assert math.isfinite(d["air_temp_c"])
    assert math.isfinite(d["pressure_pa"])


@pytest.mark.parametrize("payload", [
    {"latitude": 91.0, "longitude": 0.0, "elevation_m": 0.0, "ltst_time": "12:00"},
    {"latitude": -91.0, "longitude": 0.0, "elevation_m": 0.0, "ltst_time": "12:00"},
    {"latitude": 0.0, "longitude": -181.0, "elevation_m": 0.0, "ltst_time": "12:00"},
    {"latitude": 0.0, "longitude": 361.0, "elevation_m": 0.0, "ltst_time": "12:00"},
    {"latitude": 0.0, "longitude": 0.0, "elevation_m": -15000.0, "ltst_time": "12:00"},
    {"latitude": 0.0, "longitude": 0.0, "elevation_m": 0.0, "ltst_time": "25:99"},
    {"latitude": 0.0, "longitude": 0.0, "elevation_m": 0.0, "ltst_time": "invalid"},
])
def test_020_to_026_climate_invalid_rejected(payload):
    r = client.post("/api/v1/climate/predict", json=payload)
    assert r.status_code in (400, 422)


# =====================================================================
# 3. SURFACE RADIATION /api/v1/map/radiation (10 cases)
# =====================================================================

@pytest.mark.parametrize("lat,lon,elev", [
    (-4.5895, 137.4417, -4500.0),
    (18.38, 77.58, -2500.0),
    (18.65, -133.8, 21200.0),
    (-42.4, 70.5, -8200.0),
    (89.9, 179.9, 0.0),
    (-89.9, -179.9, 5000.0),
])
def test_027_to_032_radiation_valid(lat, lon, elev):
    r = client.get(f"/api/v1/map/radiation?lat={lat}&lon={lon}&elevation_m={elev}")
    assert r.status_code == 200
    d = r.json()["radiation"]
    assert d["total_dose_rate_usv_hr"] > 0
    assert d["column_depth_g_cm2"] > 0


@pytest.mark.parametrize("qs", [
    "lat=95&lon=0&elevation_m=0",
    "lat=-95&lon=0&elevation_m=0",
    "lat=0&lon=400&elevation_m=0",
    "lat=0&lon=0&elevation_m=999999",
])
def test_033_to_036_radiation_out_of_range_rejected(qs):
    r = client.get(f"/api/v1/map/radiation?{qs}")
    assert r.status_code == 422


# =====================================================================
# 4. A* & THETA* ROUTE PLANNING /api/v1/routes/plan (28 cases)
# =====================================================================

def test_037_route_plan_astar_nominal():
    r = client.post("/api/v1/routes/plan", json={
        "start": {"x": 0, "y": 0}, "goal": {"x": 4, "y": 4},
        "elevation": _flat_grid(5, 5, 100.0), "algorithm": "astar", "env_condition": "nominal",
    })
    assert r.status_code == 200
    assert r.json()["status"] == "success"


def test_038_route_plan_theta_star_nominal():
    r = client.post("/api/v1/routes/plan", json={
        "start": {"x": 0, "y": 0}, "goal": {"x": 4, "y": 4},
        "elevation": _flat_grid(5, 5, 100.0), "algorithm": "theta_star", "env_condition": "nominal",
    })
    assert r.status_code == 200
    assert r.json()["status"] == "success"


def test_039_route_start_equals_goal():
    r = client.post("/api/v1/routes/plan", json={
        "start": {"x": 2, "y": 2}, "goal": {"x": 2, "y": 2},
        "elevation": _flat_grid(5, 5, 0.0),
    })
    assert r.status_code == 422


def test_040_route_1x1_grid():
    r = client.post("/api/v1/routes/plan", json={
        "start": {"x": 0, "y": 0}, "goal": {"x": 0, "y": 0},
        "elevation": [[10.0]],
    })
    assert r.status_code == 422


def test_041_route_obstacle_wall_unreachable():
    obs = [[False] * 5 for _ in range(5)]
    for y in range(5):
        obs[y][2] = True
    r = client.post("/api/v1/routes/plan", json={
        "start": {"x": 0, "y": 2}, "goal": {"x": 4, "y": 2},
        "elevation": _flat_grid(5, 5, 0.0), "obstacles": obs,
    })
    assert r.status_code == 200
    assert r.json()["status"] != "success"


def test_042_route_steep_cliff_rejected():
    elev = [[0.0, 0.0, 500.0, 500.0, 500.0] for _ in range(5)]
    r = client.post("/api/v1/routes/plan", json={
        "start": {"x": 0, "y": 2}, "goal": {"x": 4, "y": 2},
        "elevation": elev, "max_slope_deg": 25.0,
    })
    assert r.status_code == 200
    assert r.json()["status"] != "success"


def test_043_route_risk_avoidance():
    risk = _flat_grid(5, 5, 0.0)
    risk[2][1] = risk[2][2] = risk[2][3] = 0.99
    r = client.post("/api/v1/routes/plan", json={
        "start": {"x": 0, "y": 2}, "goal": {"x": 4, "y": 2},
        "elevation": _flat_grid(5, 5, 0.0), "risk": risk, "risk_weight": 50.0,
    })
    assert r.status_code == 200
    assert r.json()["status"] == "success"


def test_044_route_eva_budget_exceeded_unsafe():
    r = client.post("/api/v1/routes/plan", json={
        "start": {"x": 0, "y": 0}, "goal": {"x": 9, "y": 0},
        "elevation": _flat_grid(10, 10, 0.0), "cell_size_m": 100.0, "eva_budget_m": 500.0,
    })
    assert r.status_code == 200
    assert r.json()["safety"]["safety_status"] == "UNSAFE"


def test_045_route_return_to_base_o2_fail():
    r = client.post("/api/v1/routes/plan", json={
        "start": {"x": 0, "y": 0}, "goal": {"x": 9, "y": 0},
        "elevation": _flat_grid(10, 10, 0.0), "cell_size_m": 200.0,
        "eva_budget_m": 5000.0, "plss_o2_pct": 30.0, "min_reserve_pct": 25.0,
    })
    assert r.status_code == 200
    assert r.json()["safety"]["checks"]["return_to_base"] == "fail"


@pytest.mark.parametrize("env,expected", [
    ("nominal", "pass"), ("caution", "fail"), ("storm", "fail"), ("unknown", "unknown"),
])
def test_046_to_049_route_env_conditions(env, expected):
    r = client.post("/api/v1/routes/plan", json={
        "start": {"x": 0, "y": 0}, "goal": {"x": 2, "y": 2},
        "elevation": _flat_grid(3, 3, 0.0), "env_condition": env,
    })
    assert r.status_code == 200
    assert r.json()["safety"]["checks"]["environment"] == expected


@pytest.mark.parametrize("bad_payload", [
    {"start": {"x": -1, "y": 0}, "goal": {"x": 2, "y": 2}, "elevation": _flat_grid(3, 3)},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 10, "y": 2}, "elevation": _flat_grid(3, 3)},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 0, "y": 0}, "elevation": []},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 0, "y": 0}, "elevation": [[]]},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 1, "y": 1}, "elevation": [[0.0, 0.0], [0.0]]},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 1, "y": 1}, "elevation": _flat_grid(2, 2), "obstacles": [[False]]},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 1, "y": 1}, "elevation": _flat_grid(2, 2), "risk": [[0.5]]},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 1, "y": 1}, "elevation": _flat_grid(2, 2), "risk": [[1.5, 0.0], [0.0, 0.0]]},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 1, "y": 1}, "elevation": _flat_grid(2, 2), "risk": [[-0.1, 0.0], [0.0, 0.0]]},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 1, "y": 1}, "elevation": _flat_grid(2, 2), "cell_size_m": 0},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 1, "y": 1}, "elevation": _flat_grid(2, 2), "cell_size_m": -5},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 1, "y": 1}, "elevation": _flat_grid(2, 2), "max_slope_deg": 90},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 1, "y": 1}, "elevation": _flat_grid(2, 2), "max_slope_deg": -1},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 1, "y": 1}, "elevation": _flat_grid(2, 2), "algorithm": "dijkstra"},
    {"start": {"x": 0, "y": 0}, "goal": {"x": 1, "y": 1}, "elevation": _flat_grid(2, 2), "env_condition": "tornado"},
])
def test_050_to_064_route_invalid_inputs_422(bad_payload):
    r = client.post("/api/v1/routes/plan", json=bad_payload)
    assert r.status_code == 422


# =====================================================================
# 5. MOUNT SHARP & EVA LOCAL ROUTES (10 cases)
# =====================================================================

@pytest.mark.parametrize("algo", ["astar", "theta_star"])
def test_065_to_066_eva_local_mount_sharp(algo):
    r = client.post("/api/v1/routes/eva-local", json={
        "site": "mount_sharp", "start": {"x": 2, "y": 2}, "goal": {"x": 10, "y": 10}, "algorithm": algo,
    })
    assert r.status_code in (200, 503)


@pytest.mark.parametrize("algo", ["astar", "theta_star"])
def test_067_to_068_eva_local_jezero(algo):
    r = client.post("/api/v1/routes/eva-local", json={
        "site": "jezero", "start": {"x": 2, "y": 2}, "goal": {"x": 10, "y": 10}, "algorithm": algo,
    })
    assert r.status_code == 200


def test_069_mount_sharp_route_valid():
    r = client.post("/api/v1/routes/mount-sharp", json={
        "start": {"x": 2, "y": 2}, "goal": {"x": 10, "y": 10},
    })
    assert r.status_code in (200, 503)


@pytest.mark.parametrize("bad", [
    {"site": "olympus", "start": {"x": 0, "y": 0}, "goal": {"x": 5, "y": 5}},
    {"site": "jezero", "start": {"x": -1, "y": 0}, "goal": {"x": 5, "y": 5}},
    {"site": "jezero", "start": {"x": 0, "y": 0}, "goal": {"x": 99999, "y": 99999}},
    {"site": "mount_sharp", "start": {"x": 0, "y": 0}, "goal": {"x": 5, "y": 5}, "algorithm": "bad"},
    {"site": "mount_sharp", "start": {"x": 0, "y": 0}},
])
def test_070_to_074_eva_local_invalid(bad):
    r = client.post("/api/v1/routes/eva-local", json=bad)
    assert r.status_code in (400, 422)


# =====================================================================
# 6. TERRAIN GRID /api/v1/map/terrain-grid (12 cases)
# =====================================================================

@pytest.mark.parametrize("bbox,rows,cols", [
    ("137.3,-4.8,137.6,-4.45", 16, 16),   # Gale
    ("77.3,18.3,77.6,18.6", 16, 16),      # Jezero
    ("-97.2,23.8,-97.0,24.0", 16, 16),    # Tharsis crater
    ("-179.9,89.0,-179.5,89.9", 8, 8),    # Near North Pole + min grid
    ("179.0,-89.9,179.9,-89.0", 8, 8),    # Near South Pole + dateline
])
def test_075_to_079_terrain_grid_valid(bbox, rows, cols):
    r = client.get(f"/api/v1/map/terrain-grid?bbox={bbox}&rows={rows}&cols={cols}")
    assert r.status_code == 200
    d = r.json()
    assert len(d["elevation_m"]) == rows
    assert len(d["elevation_m"][0]) == cols


@pytest.mark.parametrize("qs", [
    "bbox=10,10,5,20&rows=16&cols=16",         # min_lon >= max_lon
    "bbox=10,20,20,10&rows=16&cols=16",        # min_lat >= max_lat
    "bbox=bad-bbox&rows=16&cols=16",           # malformed
    "bbox=10,10,20,20&rows=2&cols=16",         # rows < 8
    "bbox=10,10,20,20&rows=500&cols=16",       # rows > 128
    "bbox=-200,10,-190,20&rows=16&cols=16",    # lon < -180
    "bbox=10,-95,20,-91&rows=16&cols=16",      # lat < -90
])
def test_080_to_086_terrain_grid_invalid_rejected(qs):
    r = client.get(f"/api/v1/map/terrain-grid?{qs}")
    assert r.status_code in (400, 422)


# =====================================================================
# 7. FEATURES, TELEMETRY, IMAGES & STREET VIEW (14 cases)
# =====================================================================

def test_087_features_default():
    r = client.get("/api/v1/map/features?limit=50")
    assert r.status_code == 200
    assert r.json()["type"] == "FeatureCollection"


def test_088_features_slim():
    r = client.get("/api/v1/map/features?slim=true&limit=20")
    assert r.status_code == 200


def test_089_features_filter_type():
    r = client.get("/api/v1/map/features?feature_type=mars_landmark&limit=20")
    assert r.status_code == 200


def test_090_features_bad_bbox():
    r = client.get("/api/v1/map/features?bbox=not,a,bbox,val")
    assert r.status_code in (400, 422)


@pytest.mark.parametrize("station_id", [
    "jezero_meda_sol100",
    "gale_rems_sol100",
    "jezero_meda_sol200",
])
def test_091_to_093_telemetry_stations(station_id):
    r = client.get(f"/api/v1/map/telemetry?station_id={station_id}")
    assert r.status_code == 200


def test_094_telemetry_unknown_station():
    r = client.get("/api/v1/map/telemetry?station_id=nonexistent_station_xyz")
    assert r.status_code == 200
    assert r.json()["count"] == 0


def test_095_images_valid():
    r = client.get("/api/v1/map/images?limit=5")
    assert r.status_code == 200


def test_096_images_invalid_limit():
    r = client.get("/api/v1/map/images?limit=5000")
    assert r.status_code == 422


def test_097_streetview_gale():
    r = client.get("/api/v1/map/streetview?lon=137.4417&lat=-4.5895&radius_m=8000&limit=5")
    assert r.status_code == 200


def test_098_streetview_tharsis_orbital_only():
    r = client.get("/api/v1/map/streetview?lon=-97.0765&lat=23.9223&radius_m=8000&limit=8")
    assert r.status_code == 200
    d = r.json()
    assert d["photo_match_mode"] == "orbital_only"
    assert d["photos"] == []


@pytest.mark.parametrize("qs", [
    "lon=200&lat=0",
    "lon=0&lat=-95",
])
def test_099_to_100_streetview_invalid_coords(qs):
    r = client.get(f"/api/v1/map/streetview?{qs}")
    assert r.status_code == 422


# =====================================================================
# 8. WAYPOINTS CRUD & SECURITY / SSRF / INJECTION (10 cases)
# =====================================================================

def test_101_waypoint_create_and_delete():
    cr = client.post("/api/v1/map/waypoints", json={
        "name": "Stress Test WP", "lon": 137.45, "lat": -4.60, "notes": "automated test",
    })
    assert cr.status_code == 200
    fid = cr.json()["feature"]["feature_id"]
    dr = client.delete(f"/api/v1/map/waypoints/{fid}")
    assert dr.status_code == 200


def test_102_waypoint_delete_nonexistent():
    r = client.delete("/api/v1/map/waypoints/nonexistent_wp_999999")
    assert r.status_code in (200, 400, 404)


@pytest.mark.parametrize("bad_wp", [
    {"name": "", "lon": 0.0, "lat": 0.0},
    {"name": "Bad Lat", "lon": 0.0, "lat": 120.0},
    {"name": "Bad Lon", "lon": 300.0, "lat": 0.0},
])
def test_103_to_105_waypoint_invalid_rejected(bad_wp):
    r = client.post("/api/v1/map/waypoints", json=bad_wp)
    assert r.status_code == 422


@pytest.mark.parametrize("ssrf_url", [
    "http://127.0.0.1:8000/api/v1/health",
    "http://169.254.169.254/latest/meta-data/",
    "file:///etc/passwd",
    "https://evil.example.com/payload.png",
])
def test_106_to_109_image_proxy_blocks_ssrf(ssrf_url):
    r = client.get(f"/api/v1/map/image-proxy?url={ssrf_url}")
    assert r.status_code in (400, 403, 422)


def test_110_nosql_injection_in_feature_type():
    r = client.get('/api/v1/map/features?feature_type={"$ne":null}')
    assert r.status_code in (200, 400, 422)
    assert r.status_code != 500


# =====================================================================
# 9. EDAC, TEXTURES, TILES & STATIC ASSETS (10 cases)
# =====================================================================

@pytest.mark.parametrize("flips", [0, 2, 32])
def test_111_to_113_edac_valid_flips(flips):
    r = client.post("/api/v1/map/edac/test", json={"message": "ARES_TEST_FRAME", "inject_bit_flips": flips})
    assert r.status_code == 200
    assert "recovered" in r.json()


def test_114_edac_empty_message_rejected():
    r = client.post("/api/v1/map/edac/test", json={"message": "", "inject_bit_flips": 1})
    assert r.status_code == 422


def test_115_edac_excess_flips_rejected():
    r = client.post("/api/v1/map/edac/test", json={"message": "OK", "inject_bit_flips": 999})
    assert r.status_code == 422


def test_116_globe_texture_invalid_style():
    r = client.get("/api/v1/map/globe-texture?style=invalid_tex&z=2")
    assert r.status_code == 422


def test_117_globe_texture_invalid_zoom():
    r = client.get("/api/v1/map/globe-texture?style=viking_red&z=99")
    assert r.status_code == 422


def test_118_regional_texture_invalid_bbox():
    r = client.get("/api/v1/map/regional-texture?bbox=bad&size=512")
    assert r.status_code == 422


def test_119_regional_texture_inverted_bbox():
    r = client.get("/api/v1/map/regional-texture?bbox=10,10,5,20&size=512")
    assert r.status_code in (400, 422)


def test_120_frontend_root_and_scripts():
    for path in ["/", "/app.js", "/terrain3d.js", "/streetview.js", "/chunks3d.js", "/styles.css"]:
        r = client.get(path)
        assert r.status_code == 200, f"Failed {path}"
