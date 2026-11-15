# 06 — ARES Map & Data Handoff, API Gateway Guide & Demo Startup

> **Purpose:** Summary of everything built and verified for the ARES Mars Map, Database, Optimization, and Space EDAC modules, plus an integration guide for the **Backend API Gateway** teammate and step-by-step instructions to launch the demo.

---

## 1. Summary of Work Completed

### A. Cloud Databases & Data Pipelines
- **MongoDB Atlas (`ares_base`)** via `backend/push_to_mongo.py` (idempotent upserts + `2dsphere` geospatial & unique indexes):
  - `planet_profiles` (`1` doc): Mars CRS (`IAU:49900`), gravity, solar day, safety thresholds.
  - `source_register` (`5` docs): Source provenance and spatial/instrument caveats.
  - `map_layers` (`6` docs): Mars Trek WMTS URL templates (`mars_viking_red`, `mola_global_color`, `gale_ctx_optical`, `gale_dem_1m`, `jezero_hirise_25cm`, `jezero_dem_mosaic`).
  - `spatial_features` (`8,318` docs, `2dsphere` indexed):
    - `themis_stamp` (`5,836` thermal IR/VIS stamps across Gale, Jezero, Elysium & Valles Marineris)
    - `msl_waypoint` (`1,389` Curiosity Gale Crater traverse points)
    - `rover_waypoint` (`1,058` Perseverance Jezero + Spirit Gusev + Opportunity Meridiani waypoints)
    - `mars_landmark` (`29` global Mars landmarks & historical landing sites)
    - `mineral_signature` (`6` Mount Sharp boxwork & mineralogy targets)
    - `planned_waypoint` (dynamic astronaut-dropped EVA waypoints via API)
  - `telemetry_rollups_lod` (`63` docs): Sol 100 Perseverance MEDA 15-minute atmospheric rollups.
  - `raw_images` (`100` docs, `2dsphere` indexed): Latest Perseverance raw image metadata & URLs geotagged via `(site, drive)` join with `M20_waypoints.json`.
- **Supabase Storage (`ares-mars-data` public bucket)** via `backend/push_to_supabase.py`:
  - Uploaded `13` objects (`10.93 MB` total): `.json` + gzipped `.json.gz` exports for all `6` collections, plus `raw/mars_site_complete_telemetry.csv.gz` (`8.8 MB`, compressed from `61.8 MB`).
  - Optional SQL table schema prepared in `backend/supabase_schema.sql`.

### B. FastAPI Map Backend, Optimization & Space EDAC
- `backend/app/db.py` — Cached `MongoClient` connection + `.env` loader.
- `backend/app/services/space_edac.py` — Real **CRC32** packet checksums + **Hamming(7,4)** single-bit error detection and correction.
- `backend/app/services/mars_time.py` — NASA Mars24 / Allison & McEwen (2000) orbital Mars Date & Time (`MSD`, `MTC`, `MY`, `Ls`, season, `LMST`/`LTST`, live `OWLT`).
- `backend/app/api/map_data.py` — Live MongoDB-backed endpoints with `120s` in-memory TTL cache, `?slim=true` payload reduction, `X-Cache` & `X-Space-CRC32` headers, `/streetview` (nearby features, 360° panoramas & Curiosity/Perseverance rover camera feeds), and automatic cache invalidation on waypoint mutations.
- `backend/app/main.py` — Adds `GZipMiddleware(minimum_size=1024)`, `CORSMiddleware`, `GET /api/v1/time` gateway alias, `ImportError` guard on `climate_router`, and serves `frontend/` at `/`.

### C. Interactive Mars Tablet Map, 3D Terrain & Street View (`frontend/`)
- `frontend/index.html`, `frontend/styles.css`, `frontend/app.js`, `frontend/chunks3d.js`, `frontend/terrain3d.js`, `frontend/streetview.js`:
  - **Live Mars Date & Time Header:** Ticks every second (`MY · Ls · Season`, `MSD`, `MTC`, `LMST` at map center, `UTC`, and live `OWLT`).
  - **Clean Map & Selected-Point Continuity:** Dense vector overlays start unchecked by default; clicking any point, landmark, or rover waypoint highlights it with a temporary marker and starts 3D Terrain / Street View at that exact point (plus a direct **`Open 360° Street View Here`** button in the inspector).
  - **Center-Pane 3D Views + Fullscreen:** 3D Mars Globe, Regional 3D Terrain, and Mars 360° Street View render inside the middle pane so both sidebars remain visible, with an optional **`⛶ Fullscreen`** toggle.
  - **Mars 360° Street View (`streetview.js` + `chunks3d.js`):**
    - Human-scale `64×64` terrain meshes (`1 unit ≈ 3.95 m`) with exact barycentric triangle interpolation (`getGroundY`) so avatars, rovers, and cameras track steep slopes/ridges without clipping.
    - Procedural Mars regolith sand-ripple/pebble bump map, `16×` anisotropic orbital texture filtering, `240` instanced 3D surface boulders, and hemisphere atmospheric lighting for crisp close-up ground detail.
    - **4 Modes:** `🛸 Drone`, `🧑‍🚀 Astronaut` (grounded EVA walk), `🚙 Rover` (6-wheel drive), and `🗺️ Overview`.
    - **`🚀 Set Landing Site`:** Places a 3D Rocket Lander + Pad (synced to the 2D map) with live distance & bearing in the visor HUD.
    - **`🌫️ Dust Fog: ON/OFF`** toggle, **bottom direction arrow** (`#sv-nav-arrow`), terrain-draped **3D EVA route tubes**, **Nearby Area Intel** 3D pins, and mission-matched **360° Panoramas + Curiosity/Perseverance front-view filmstrip**.

---

## 2. Guide for the Backend API Gateway Teammate

If you are building an API Gateway (or unifying the Rocket Edge + Base Station services) in front of this backend, use the contract below.

### A. Upstream Endpoints to Expose / Proxy

| Method & Path | Purpose | Key Query / Body Params | Important Headers |
| :--- | :--- | :--- | :--- |
| `GET /api/v1/health` | Liveness probe | — | — |
| `GET /api/v1/mission` | Mission & DB status | — | — |
| `GET /api/v1/layers` | Active layer summary | — | — |
| `GET /api/v1/time` / `GET /api/v1/map/time` | Live Mars Date & Time (`MSD`, `MTC`, `MY`, `Ls`, season, `LMST`, `LTST`, `OWLT`) | `lon=137.4417`, `utc` (optional) | — |
| `GET /api/v1/map/planet` | Planet profile + live Mars clocks (`MSD`, `MTC`, `MY`, `Ls`, `LMST`, `OWLT`) | `body=mars`, `lon` | — |
| `GET /api/v1/map/layers` | WMTS + USGS WMS layer configs | `body=mars` | — |
| `GET /api/v1/map/features` | GeoJSON `FeatureCollection` from `spatial_features` | `bbox`, `feature_type`, `limit`, `slim=true` | `X-Cache`, `X-Space-CRC32`, `Content-Encoding: gzip` |
| `GET /api/v1/map/images` | Geotagged Perseverance raw images (`$nearSphere`) | `lon`, `lat`, `radius_m`, `sol`, `limit` | — |
| `GET /api/v1/map/streetview` | Nearby 360° panoramas, area features & Curiosity/Perseverance frames | `lon`, `lat`, `radius_m`, `limit` | — |
| `GET /api/v1/map/image-proxy` | Same-origin proxy for `mars.nasa.gov` rover images/panoramas | `url` | `Cache-Control: public` |
| `GET /api/v1/map/telemetry` | Sol 100 MEDA 15-min rollups | `station_id=jezero_meda_sol100` | `X-Cache`, `X-Space-CRC32` |
| `GET /api/v1/map/terrain-grid` | Numeric `elevation_m[][]` + `slope_deg[][]` grid | `bbox`, `rows`, `cols` | — |
| `POST /api/v1/map/waypoints` | Save astronaut-planned waypoint to MongoDB | `{ name, lon, lat, category, notes }` | Invalidates `features:` cache |
| `DELETE /api/v1/map/waypoints/{feature_id}` | Remove `planned_*` waypoint | `feature_id` | Invalidates `features:` cache |
| `POST /api/v1/map/edac/test` | Hamming(7,4) + CRC32 bit-flip recovery test | `{ message, inject_bit_flips }` | — |
| `POST /api/v1/routes/plan` | Teammate's A\* route planner | `{ start, goal, elevation, ... }` | — |
| `POST /api/v1/climate/predict` | Teammate's climate predictor (if `skops` installed) | `{ latitude, longitude, ltst_time, elevation_m }` | — |

### B. Gateway Integration Tips
1. **Preserve Compression & Integrity Headers:**
   - Pass `Accept-Encoding: gzip` upstream and forward `Content-Encoding: gzip`, `X-Space-CRC32`, and `X-Cache` to the tablet client so you keep the `~8x` bandwidth savings and CRC32 verification.
2. **Use `?slim=true` for Initial Map Loads:**
   - When the tablet boots or pans, proxy `GET /api/v1/map/features?slim=true&limit=3000` (strips heavy `provenance` and non-panoramic `images[]`).
3. **Connecting Route Planning (`astar.py`) to Map Data:**
   - Call `GET /api/v1/map/terrain-grid?bbox=<min_lon>,<min_lat>,<max_lon>,<max_lat>&rows=48&cols=48` to get real `elevation_m` and `slope_deg` matrices directly from MongoDB `spatial_features`, then feed `elevation_m` into `plan_astar(...)`.
   - Fetch target stops via `GET /api/v1/map/features?feature_type=planned_waypoint` and `GET /api/v1/map/features?feature_type=mineral_signature`.
4. **Two-Server Routing (Rocket Edge vs. Base Station):**
   - **Rocket Edge Gateway:** Serve cached `/api/v1/map/*`, `POST /api/v1/routes/plan`, and `POST /api/v1/map/waypoints` locally with low latency.
   - **Base Station Gateway:** Expose read-only mission monitoring (`/api/v1/map/features`, `/telemetry`, `/images`) backed by `ares_base` MongoDB Atlas + Supabase Storage (`ares-mars-data`).

---

## 3. How to Start the Demo

1. **Ensure `.env` exists** in the repo root (`c:\Users\HEllo\ARES\.env`) with `MONGO_URI` and `MONGO_DB="ares_base"`.
2. **Start the FastAPI + Frontend server** from `c:\Users\HEllo\ARES`:
   ```powershell
   pushd backend; .\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
   ```
3. **Open in browser:**
   - **Interactive Mars Tablet Map:** `http://127.0.0.1:8000/`
   - **Interactive Swagger API Docs:** `http://127.0.0.1:8000/docs`
4. **Quick things to show in the demo:**
   - Switch between **Mars Trek Viking Red** and **MOLA Elevation Heatmap** / **USGS THEMIS Day IR**.
   - Click **Mount Sharp** or **Jezero (M20)** to inspect mineral targets, THEMIS thermal stamps, Curiosity/Perseverance waypoints, and **360° rover panoramas**.
   - Click **+ Drop Planned Waypoint** to place a custom target and persist it to MongoDB Atlas.
   - Click **Test Bit-Flip EDAC** in the Comms card to demonstrate Hamming(7,4) + CRC32 space-link error recovery.
