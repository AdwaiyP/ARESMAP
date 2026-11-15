# 05 — Live MongoDB (`ares_base`) Data Reference for Developers

> **Purpose:** Practical developer reference for querying the live **`ares_base`** MongoDB Atlas database populated by `backend/push_to_mongo.py`, plus the corresponding FastAPI `/api/v1/map/*` HTTP endpoints.

---

## 1. Connection & Setup

1. Copy `.env.example` to `.env` in the repo root (`.env` is git-ignored):
   ```env
   MONGO_URI="mongodb://<db_username>:<db_password>@ac-t7ddu5f-shard-00-00.qhwvih5.mongodb.net:27017,..."
   MONGO_DB="ares_base"
   ```
2. Verify cluster contents anytime (read-only):
   ```powershell
   backend\.venv\Scripts\python.exe backend\push_to_mongo.py --inspect
   ```
3. Re-sync or add datasets (idempotent `upsert` — no duplicates):
   ```powershell
   backend\.venv\Scripts\python.exe backend\push_to_mongo.py --datasets all --image-limit 100
   ```

---

## 2. Live Collections & Indexes

| Collection | Live Docs | Primary Indexes | Purpose |
| :--- | ---: | :--- | :--- |
| `planet_profiles` | `1` | `_id_` | Planetary constants, CRS (`IAU:49900`), clock labels, safety thresholds |
| `source_register` | `5` | `(body, source_id)` unique | Provenance and spatial/instrument caveats |
| `map_layers` | `6` | `(body, layer_id)` unique | Mars Trek WMTS tile URL templates, zoom ranges, and `bbox` |
| `spatial_features` | `8,318` | `feature_id` unique, `geometry` (`2dsphere`), `(body, feature_type)` | Unified GeoJSON points for THEMIS stamps, rover waypoints, minerals, and landmarks |
| `telemetry_rollups_lod` | `63` | `(body, station_id, lod, bucket_key)` unique | Sol 100 MEDA 15-min environmental rollups |
| `raw_images` | `100` | `imageid` unique, `geometry` (`2dsphere`, sparse), `(sol, instrument)` | Perseverance raw image URLs + metadata geotagged via `(site, drive)` |

**Conventions:**
- All GeoJSON `Point` coordinates follow **`[longitude, latitude]`** order (`IAU:49900` degrees).
- Missing or sentinel values (`0.0` K, `-273.15` uncertainty) are normalized to **`null`**.

---

## 3. Document Shapes by Collection

### 3.1 `spatial_features` (`8,318` docs)
Discriminated by `feature_type` (`themis_stamp`: `5,836`, `msl_waypoint`: `1,389`, `rover_waypoint`: `1,058`, `mars_landmark`: `29`, `mineral_signature`: `6`):
- `themis_stamp` (`730`) — Gale Crater THEMIS IR/VIS frames (`Gale Crater.csv`)
- `msl_waypoint` (`1,389`) — Curiosity Gale Crater traverse (`MSL_waypoints.json`)
- `rover_waypoint` (`708`) — Perseverance Jezero Crater traverse + 360° panoramas (`M20_waypoints.json`)
- `mars_landmark` (`20`) — Global Mars landmarks & historical landing sites

```json
{
  "feature_id": "themis_I00988002",
  "body": "mars",
  "mission_id": "ares_gale_boxwork_01",
  "feature_type": "themis_stamp",
  "elevation_m": null,
  "geometry": {
    "type": "Point",
    "coordinates": [137.88445, -4.234628]
  },
  "properties": {
    "file_id": "I00988002",
    "frame_type": "IR",
    "lon_deg": 137.88445,
    "lat_deg": -4.234628,
    "surf_temp_k": 194.229,
    "surf_temp_c": -78.92,
    "alb_avg": null,
    "bands": "(4, 9, 10)",
    "description": "Gale Crater",
    "has_description": true,
    "temp_status": "OK"
  },
  "provenance": { "source_id": "themis_gale_csv" }
}
```

For **`rover_waypoint`** and **`msl_waypoint`**, `properties` contains:
- `RMC` (string, e.g. `"3_0"`), `site` (int), `drive` (int), `sol` (int)
- `easting`, `northing`, `elev_geoid`, `lon`, `lat`, `roll`, `pitch`, `yaw`, `yaw_rad`, `tilt`
- `dist_m`, `dist_total_m`, `dist_km`, `dist_mi`
- *(On `rover_waypoint`)* `images[]` with 360° cylindrical panoramas (`isPanoramic: true`, relative `url` under `https://mars.nasa.gov/mmgis-maps/M20/`).

For **`mars_landmark`**, `properties` contains `{ "name", "description", "lon_deg", "lat_deg" }`.

---

### 3.2 `map_layers` (`6` docs)
```json
{
  "layer_id": "mars_viking_red",
  "body": "mars",
  "region": "global",
  "category": "optical",
  "protocol": "WMTS_EQ",
  "url_template": "https://trek.nasa.gov/tiles/Mars/EQ/Mars_Viking_MDIM21_ClrMosaic_global_232m/1.0.0/default/default028mm/{z}/{y}/{x}.jpg",
  "tile_size_px": 256,
  "zoom_range": [0, 7],
  "resolution_m": 232.0,
  "bbox": [-180.0, -90.0, 180.0, 90.0]
}
```
Active `layer_id` values: `mars_viking_red`, `mola_global_color`, `gale_ctx_optical`, `gale_dem_1m`, `jezero_hirise_25cm`, `jezero_dem_mosaic`.

---

### 3.3 `telemetry_rollups_lod` (`63` docs)
15-minute buckets for Sol 100 Perseverance MEDA (`station_id: "jezero_meda_sol100"`, `lod: "15m"`):
```json
{
  "body": "mars",
  "station_id": "jezero_meda_sol100",
  "lod": "15m",
  "bucket_key": "00100M00:00",
  "lmst_bucket": "00100M00:00",
  "ltst_start": "0099 23:56:47",
  "sclk_start": 675771620.5,
  "sclk_end": 675772545.0,
  "raw_samples_in_bucket": 1850,
  "solar_zenith_deg_mean": 141.5196,
  "air_temp_c_mean": -69.1662,
  "air_temp_c_min": -71.6,
  "air_temp_c_max": -65.05,
  "ground_ir_temp_c_mean": -70.2958,
  "ground_ir_temp_unc_c_mean": 0.39,
  "pressure_barocap1_pa_mean": 770.9016,
  "pressure_barocap2_pa_mean": 761.7081,
  "humidity_a_pct_mean": 3.1228,
  "optical_rds_top7_mean": 0.0001,
  "optical_rds_mode": "HIGH_GAIN",
  "wind_boom1_speed_ms_mean": null,
  "wind_boom1_dir_deg_mean": null,
  "wind_valid_fraction": 0.0,
  "safety_state": "UNKNOWN_HOLD",
  "quality_and_unknown_flags": "pressure_uncertainty_unreported|ionizing_rad_not_in_dataset|wind_offline|humidity_uncertainty_unreported"
}
```

---

### 3.4 `raw_images` (`100` docs)
Stores image URLs and camera/pointing metadata (not raw image binaries):
```json
{
  "imageid": "LRF_2031_0847237865_241EBY_N0930000SCAM01031_0100I4J",
  "body": "mars",
  "mission_id": "mars2020_jezero",
  "sol": 2031,
  "site": 93,
  "drive": 0,
  "instrument": "SUPERCAM_RMI",
  "geometry": { "type": "Point", "coordinates": [77.23322287, 18.43559434] },
  "date_taken_mars": "Sol-02031M11:30:55.785",
  "date_taken_utc": "2026-11-06T12:16:25.848",
  "attitude": "(0.682313,0.00347943,0.0627555,0.728354)",
  "extended": { "mastAz": "-0.216032", "mastEl": "-62.1834", "sclk": "847237865.387", "xyz": "(0.0,0.0,0.0)", "dimension": "(2048,2048)" },
  "camera": { "instrument": "SUPERCAM_RMI", "filter_name": "UNK", "camera_model_type": "CAHV" },
  "image_files": {
    "small": "..._320.jpg",
    "medium": "..._800.jpg",
    "large": "..._1200.jpg",
    "full_res": "....png"
  }
}
```

---

### 3.5 `planet_profiles` (`1` doc) & `source_register` (`5` docs)
- **`planet_profiles` (`_id: "mars"`):** `crs` (`IAU:49900`, radius `3396190.0` m), `physics` (`gravity_ms2: 3.72076`, `solar_day_seconds: 88775.244`, `owlt_range_sec: [180, 1340]`), `clock_model` (`SOL`, `LMST`), `safety_thresholds`.
- **`source_register` (`5` docs):** `{ body, source_id, instrument, source_type, spatial_limitation }`.

---

## 4. Common Query Patterns

### Direct Python (`pymongo`)
```python
from backend.app.db import get_db

db = get_db()

# 1. All features in Mount Sharp bbox
mt_sharp = list(db["spatial_features"].find({
    "geometry": {"$geoWithin": {"$box": [[137.2, -5.6], [138.4, -4.6]]}}
}, {"_id": 0}))

# 2. Curiosity waypoints only
msl_wps = list(db["spatial_features"].find(
    {"feature_type": "msl_waypoint"}, {"_id": 0}
).sort("properties.sol", 1))

# 3. Geotagged Perseverance images within 2 km
imgs = list(db["raw_images"].find({
    "geometry": {
        "$nearSphere": {
            "$geometry": {"type": "Point", "coordinates": [77.2332, 18.4356]},
            "$maxDistance": 2000,
        }
    }
}, {"_id": 0}).limit(10))
```

### FastAPI HTTP Endpoints (`backend/app/api/map_data.py`)
- `GET /api/v1/map/planet?body=mars` — Planet profile + live `MSD`, `MTC`, `earth_utc`, `owlt_range_sec`
- `GET /api/v1/map/layers?body=mars` — `map_layers` + USGS WMS global layers
- `GET /api/v1/map/features?bbox=137.2,-5.6,138.4,-4.6&feature_type=themis_stamp&limit=1500` — GeoJSON `FeatureCollection`
- `GET /api/v1/map/images?lon=77.2332&lat=18.4356&radius_m=2000&limit=20` — Nearby Perseverance raw images
- `GET /api/v1/map/telemetry?station_id=jezero_meda_sol100` — 15-min weather/radiation rollups
