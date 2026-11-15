# 10 — Local Server Performance Benchmark & Host Device Specifications

Measured against the local ARES FastAPI (`uvicorn`) server running on `http://127.0.0.1:8000` (with MongoDB Atlas connected).

---

## 1. Host Device Specifications

| Component | Specification |
|---|---|
| **Device Name** | `DESKTOP-K089POR` |
| **Model** | HP ZBook 15 G5 |
| **Processor** | Intel(R) Core(TM) i7-8850H CPU @ 2.60GHz (2.59 GHz) |
| **Installed RAM** | 16.0 GB (15.8 GB usable) · Speed: 2667 MT/s |
| **Graphics Cards** | NVIDIA Quadro P2000 (4 GB) + Intel(R) UHD Graphics 630 (128 MB) |
| **Storage** | 477 GB (230 GB used) |
| **System Type** | 64-bit operating system, x64-based processor (Windows 11) |

---

## 2. Backend API Processing & Latency Metrics

| Endpoint / Workload | Cold / First Call | Min | Avg | p95 | Max | Runs / Notes |
|---|---|---|---|---|---|---|
| `GET /api/v1/health` | — | 4.95 ms | **6.50 ms** | 6.96 ms | 12.86 ms | 20 runs (`200 OK`) |
| `GET /api/v1/mission` | — | 4.96 ms | **6.66 ms** | 7.89 ms | 9.02 ms | 20 runs (`200 OK`) |
| `GET /api/v1/map/time` | — | 5.32 ms | **6.69 ms** | 8.06 ms | 9.13 ms | 20 runs (`200 OK`) |
| `GET /api/v1/map/radiation` | — | 5.01 ms | **6.62 ms** | 7.89 ms | 9.46 ms | 10 runs (`200 OK`) |
| `POST /api/v1/climate/predict` | — | 5.48 ms | **6.75 ms** | 7.78 ms | 9.71 ms | 15 runs (RandomForest inference) |
| `POST /api/v1/routes/plan` (A\* `32×32`) | — | 9.95 ms | **12.92 ms** | 17.12 ms | 17.96 ms | 10 runs (`200 OK`) |
| `POST /api/v1/routes/plan` (Theta\* `64×64`) | — | 27.59 ms | **43.56 ms** | 55.32 ms | 61.73 ms | 10 runs (`200 OK`) |
| `GET /api/v1/map/streetview` (Gale) | — | 21.49 ms | **70.99 ms** | 26.82 ms | 489.36 ms | 10 runs (`200 OK`) |
| `GET /api/v1/map/features?slim=true&limit=200` | — | 75.57 ms | **91.44 ms** | 96.02 ms | 126.40 ms | 10 runs (MongoDB Atlas query) |
| `GET /api/v1/map/terrain-grid` (`32×32`) | **378.15 ms** | 19.04 ms | **22.62 ms** | 27.22 ms | 32.20 ms | 15 cached runs (**16.7×** speedup) |
| `GET /api/v1/map/regional-texture` (`512×512`) | **1351.91 ms** | 6.33 ms | **7.72 ms** | 8.49 ms | 8.71 ms | 15 cached runs (**175×** speedup, `51,755` B JPEG) |

### Server Resource & UI Verification Summary
- **Backend Memory (`uvicorn`):** **221 MB** Working Set RAM (cumulative CPU time: `48.7 s`).
- **Browser Rendering Verification (`http://127.0.0.1:8000`):** 2D Tactical Map, 3D Mars Globe, and Mars 360° Street View (`5×5 Chunks: 25/25`) all rendered cleanly with **0 console errors**.
- **Automated Test Coverage:** 146 backend tests (`tests/`) + 19 core tests (`../tests/`) + 32 Flutter tests (`ares_tablet/test/`).

---

## 3. Accuracy Evaluation vs. Ground Truth

Measured directly against the live local server (`http://127.0.0.1:8000`) using NASA reference standards and stored Mars 2020 MEDA Sol 100 telemetry:

### 3.1 Mars Timekeeping (`GET /api/v1/time`) vs. NASA Mars24 Reference
- **Benchmark:** J2000 Epoch (`2000-01-06T00:00:00Z`, `lon=0.0°`) — NASA Mars24 reference Mars Sol Date (MSD) = `44796.0`.
- **ARES Output:** `mars_sol_date = 44796.0`, `MTC = 23:59:44`
- **Absolute Error:** **`0.000000 sols`** (exact agreement with Allison & McEwen 2000 / NASA Mars24).

### 3.2 Surface Radiation (`GET /api/v1/map/radiation`) vs. MSL RAD Benchmark
- **Benchmark:** Curiosity Mars Science Laboratory RAD quiet-Sun surface average at Gale Crater (`0.67 mSv/day`, Hassler et al., *Science* 2014).
- **ARES Output across Elevation Regimes:**

| Location | Coordinates / Elevation | GCR Dose (`mSv/day`) | Total Dose Rate (`µSv/hr`) | Atmospheric Column (`g/cm²`) | SEP Status |
|---|---|---|---|---|---|
| **Gale Crater (MSL RAD ref)** | `-4.5895°, 137.4417°`, `-4500 m` | **`0.67`** | `27.92` | `21.40` | `QUIET` |
| **Jezero Crater** | `18.38°, 77.58°`, `-2500 m` | `0.71` | `29.57` | `17.87` | `QUIET` |
| **Hellas Planum (deep basin)** | `-42.4°, 70.5°`, `-7152 m` | `0.627` | `26.14` | `27.18` | `QUIET` |
| **Olympus Mons (summit)** | `18.65°, 226.2°`, `+21200 m` | `0.941` | `39.22` | `2.11` | `QUIET` |

- **Gale Crater Relative Error vs. `0.67 mSv/day`:** **`0.00%`**, with physically consistent exponential atmospheric shielding across `-7.1 km` to `+21.2 km` elevation.

### 3.3 Climate Predictor (`POST /api/v1/climate/predict`) vs. Mars 2020 MEDA Sol 100 Telemetry
- **Benchmark:** Real Perseverance MEDA Sol 100 observations at Jezero Crater (`18.38°, 77.58°, -2500 m`) stored in MongoDB (`station_id=jezero_meda_sol100`, **63** 15-minute LMST buckets; 63 valid air/ground/pressure records, 36 valid wind records).
- **Observed Error Metrics:**

| Variable | Records Evaluated | Mean Absolute Error (MAE) | Max Absolute Error |
|---|---|---|---|
| **Air Temperature** | 63 | **`7.39 °C`** | `15.10 °C` |
| **Ground IR Temperature** | 63 | **`7.91 °C`** | `23.64 °C` |
| **Surface Pressure** | 63 | **`38.42 Pa`** | `57.40 Pa` |
| **Wind Speed** | 36 | **`3.41 m/s`** | `6.35 m/s` |

- *Note:* The RandomForest climate model provides fast (`~6.75 ms`) diurnal estimates without needing live telemetry; residual error reflects local crater-rim turbulence, dust opacity variations, and seasonal pressure drift not captured by static `(lat, lon, elev, LTST)` features alone.

### 3.4 Route Planning (`POST /api/v1/routes/plan`) on Real Gale Crater Terrain
- **Grid:** `32×32` Gale Crater DEM (`bbox=137.35,-4.75,137.45,-4.65`), `source=mongodb_spatial_features_idw_blended`, `cell_size_m=190.89 m`, elevation range `-4412.57 m` to `-3884.71 m`.
- **Start `(2, 2)` → Goal `(29, 29)` (`max_slope_deg=35.0°`, `eva_budget_m=50000 m`):**
  - **A\*:** `distance_m = 7288.899 m`, `elevation_gain_m = 466.32 m`, `total_cost = 8284.879`, `explored_nodes = 354`
  - **Theta\*:** `distance_m = 7288.899 m`, `elevation_gain_m = 434.65 m` (**31.67 m / 6.8% less elevation gain** than A\* along the same diagonal corridor)

### 3.5 Known Terrain & Imagery Limitations
- Outside high-resolution local DEMs (Gale/Jezero/Elysium) or when NASA Mars Trek WMTS tiles are unreachable/slow (such as on free-tier cloud hosting), terrain elevation falls back to MongoDB spatial-feature IDW interpolation or global shaded-relief sampling, which reduces fine-grained micro-terrain precision in 3D Street View.
