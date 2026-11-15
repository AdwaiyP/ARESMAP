from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_mission():
    response = client.get("/api/v1/mission")
    assert response.status_code == 200
    assert response.json()["name"] == "ARES"


def test_route_success():
    response = client.post(
        "/api/v1/routes/plan",
        json={
            "start": {"x": 0, "y": 0},
            "goal": {"x": 2, "y": 2},
            "elevation": [[0, 0, 0]] * 3,
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["route"][0] == {"x": 0, "y": 0}
    assert data["route"][-1] == {"x": 2, "y": 2}


def test_invalid_route():
    response = client.post(
        "/api/v1/routes/plan",
        json={
            "start": {"x": 0, "y": 0},
            "goal": {"x": 5, "y": 5},
            "elevation": [[0, 0], [0, 0]],
        },
    )
    assert response.status_code == 422


def test_invalid_climate_coordinates():
    response = client.post(
        "/api/v1/climate/predict",
        json={
            "latitude": 100,
            "longitude": 137.385,
            "ltst_time": "13:30",
            "elevation_m": -4150,
        },
    )
    assert response.status_code == 422


def test_invalid_climate_time():
    response = client.post(
        "/api/v1/climate/predict",
        json={
            "latitude": -4.725,
            "longitude": 137.385,
            "ltst_time": "25:99",
            "elevation_m": -4150,
        },
    )
    assert response.status_code == 422


def test_climate_prediction():
    response = client.post(
        "/api/v1/climate/predict",
        json={
            "latitude": -4.725,
            "longitude": 137.385,
            "ltst_time": "13:30",
            "elevation_m": -4150,
        },
    )

    assert response.status_code == 200
    data = response.json()

    assert "predictions" in data
    assert "safety_alerts" in data
    assert data["model_metadata"]["model_count"] == 10
    assert data["model_metadata"]["validated_for_eva_safety"] is False

    for value in data["safety_alerts"].values():
        assert isinstance(value, bool)


def test_surface_radiation():
    response = client.get(
        "/api/v1/map/radiation",
        params={"lat": -4.5895, "lon": 137.4417, "elevation_m": -4500},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    rad = data["radiation"]
    assert rad["gcr_dose_msv_day"] > 0
    assert rad["total_dose_rate_usv_hr"] > 0
    assert rad["safety_state"] in {"NOMINAL", "CAUTION", "HAZARD"}
