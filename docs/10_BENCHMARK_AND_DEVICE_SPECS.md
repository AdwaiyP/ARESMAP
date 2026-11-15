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
