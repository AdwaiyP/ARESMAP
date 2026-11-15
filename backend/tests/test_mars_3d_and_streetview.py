"""End-to-end verification tests for ARES backend APIs, 3D chunking, Street View, and routing."""

import sys
from pathlib import Path
import unittest

from fastapi.testclient import TestClient

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.main import app  # noqa: E402


class TestAresSystem(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.client = TestClient(app)

    def test_health_and_mission(self) -> None:
        r_health = self.client.get("/api/v1/health")
        self.assertEqual(r_health.status_code, 200)
        self.assertEqual(r_health.json()["status"], "ok")

        r_mission = self.client.get("/api/v1/mission")
        self.assertEqual(r_mission.status_code, 200)
        self.assertEqual(r_mission.json()["name"], "ARES")

    def test_static_frontend_assets(self) -> None:
        for path in ["/", "/app.js", "/chunks3d.js", "/terrain3d.js", "/streetview.js", "/styles.css"]:
            res = self.client.get(path)
            self.assertEqual(res.status_code, 200, f"Expected 200 for {path}")

    def test_adjacent_terrain_chunks_have_zero_seam_error(self) -> None:
        bbox1 = "137.36000,-4.72000,137.44000,-4.64000"
        bbox2 = "137.44000,-4.72000,137.52000,-4.64000"
        r1 = self.client.get(f"/api/v1/map/terrain-grid?bbox={bbox1}&rows=32&cols=32")
        r2 = self.client.get(f"/api/v1/map/terrain-grid?bbox={bbox2}&rows=32&cols=32")
        self.assertEqual(r1.status_code, 200)
        self.assertEqual(r2.status_code, 200)

        g1, g2 = r1.json(), r2.json()
        self.assertEqual(g1["rows"], 32)
        self.assertEqual(g1["cols"], 32)
        self.assertIn("elevation_m", g1)
        self.assertIn("slope_deg", g1)

        # East edge of chunk 1 must match West edge of chunk 2
        seam_diff = max(abs(g1["elevation_m"][r][-1] - g2["elevation_m"][r][0]) for r in range(32))
        self.assertAlmostEqual(seam_diff, 0.0, places=5)

    def test_regional_texture_and_cache(self) -> None:
        bbox = "137.36000,-4.72000,137.44000,-4.64000"
        r1 = self.client.get(f"/api/v1/map/regional-texture?bbox={bbox}")
        self.assertEqual(r1.status_code, 200)
        self.assertEqual(r1.headers["content-type"], "image/jpeg")
        self.assertGreater(len(r1.content), 1000)

        r2 = self.client.get(f"/api/v1/map/regional-texture?bbox={bbox}")
        self.assertEqual(r2.status_code, 200)
        self.assertEqual(r2.headers.get("x-cache"), "HIT")

    def test_globe_textures(self) -> None:
        for tex in ("viking", "mola"):
            res = self.client.get(f"/api/v1/map/globe-texture?tex={tex}&z=2")
            self.assertEqual(res.status_code, 200)
            self.assertEqual(res.headers["content-type"], "image/jpeg")
            self.assertGreater(len(res.content), 10000)

    def test_features_telemetry_streetview_and_edac(self) -> None:
        r_feat = self.client.get("/api/v1/map/features?slim=true&limit=50")
        self.assertEqual(r_feat.status_code, 200)
        self.assertEqual(r_feat.json()["type"], "FeatureCollection")

        r_tel = self.client.get("/api/v1/map/telemetry?limit=5")
        self.assertEqual(r_tel.status_code, 200)

        r_sv = self.client.get("/api/v1/map/streetview?lon=137.385&lat=-4.725&radius_m=8000&limit=5")
        self.assertEqual(r_sv.status_code, 200)
        self.assertIn("photos", r_sv.json())

        r_edac = self.client.post(
            "/api/v1/map/edac/test",
            json={"message": "SOL100:T=-69.2C:P=771Pa:OK", "inject_bit_flips": 2},
        )
        self.assertEqual(r_edac.status_code, 200)

    def test_route_plan(self) -> None:
        r_route = self.client.post(
            "/api/v1/routes/plan",
            json={"start": {"x": 0, "y": 0}, "goal": {"x": 2, "y": 2}, "elevation": [[0, 0, 0]] * 3},
        )
        self.assertEqual(r_route.status_code, 200)
        self.assertEqual(r_route.json()["status"], "success")

        r_bad_route = self.client.post(
            "/api/v1/routes/plan",
            json={"start": {"x": 0, "y": 0}, "goal": {"x": 5, "y": 5}, "elevation": [[0, 0], [0, 0]]},
        )
        self.assertEqual(r_bad_route.status_code, 422)


if __name__ == "__main__":
    unittest.main()
