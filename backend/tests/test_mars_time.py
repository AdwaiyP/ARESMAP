"""Tests for Mars Date & Time calculations and API gateway endpoints."""

from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app.main import app
from app.services.mars_time import compute_mars_time

client = TestClient(app)


def test_compute_mars_time_j2000_reference():
    # NASA Mars24 reference: 2000-01-06 00:00:00 UTC is MSD ~ 44796.0
    dt = datetime(2000, 1, 6, 0, 0, 0, tzinfo=timezone.utc)
    res = compute_mars_time(lon=0.0, utc_time=dt)
    assert 44795.9 < res["mars_sol_date"] < 44796.1
    assert res["earth_utc"] == "2000-01-06T00:00:00Z"
    assert 0.0 <= res["solar_longitude_deg"] < 360.0
    assert 1 <= res["mars_month"] <= 12
    assert res["lmst"] == res["mtc"]
    assert res["owlt_sec"] > 0


def test_api_map_time_and_gateway_alias():
    r1 = client.get("/api/v1/map/time?lon=137.4417&utc=2026-11-15T00:00:00Z")
    assert r1.status_code == 200
    d1 = r1.json()
    for key in (
        "earth_utc",
        "mars_sol_date",
        "mtc",
        "mars_year",
        "solar_longitude_deg",
        "mars_month",
        "mars_season",
        "sol_of_year",
        "equation_of_time_min",
        "owlt_sec",
        "owlt_formatted",
        "local_lon_deg",
        "lmst",
        "ltst",
    ):
        assert key in d1
    assert d1["local_lon_deg"] == 137.4417
    assert d1["mars_year"] >= 38

    r2 = client.get("/api/v1/time?lon=77.4509&utc=2026-11-15T00:00:00Z")
    assert r2.status_code == 200
    d2 = r2.json()
    assert d2["mars_sol_date"] == d1["mars_sol_date"]
    assert d2["local_lon_deg"] == 77.4509
    assert d2["lmst"] != d1["lmst"]


def test_api_time_invalid_utc():
    r = client.get("/api/v1/time?utc=not-a-timestamp")
    assert r.status_code == 400
