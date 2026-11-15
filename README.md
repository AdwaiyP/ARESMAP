# ARES — Astronaut Route & Exploration System

**Interactive Mars EVA Tactical Map, AI Route Planner, 3D Terrain & 360° Surface Explorer**

ARES transforms raw NASA orbital imagery, elevation grids, rover telemetry, and space-weather data into an astronaut-ready navigation and mission-planning tablet interface.

## Live Demo

- **Demo URL:** https://ares-map.onrender.com/

> [!NOTE]
> The live demo is hosted on **Render's free tier** (single worker, 512 MB RAM). Because of free-tier CPU/memory limits and cold-start behavior, processing speed is slower than local deployment and heavy terrain/3D chunk streaming or complex route requests may take longer or yield less accurate intermediate results. For full performance and fidelity, run ARES locally via Docker or Python (see [Quick Start](#quick-start)).

---

## Engineering Pipeline

```text
NASA Mars Data → Geospatial Processing & Hazard Mapping → A* / Theta* Pathfinding → EVA Safety Validation → FastAPI + MongoDB → Interactive Mars Interface (2D / 3D / 360°)
```

---

## Key Features

- **2D Tactical Mars Map (Leaflet · `IAU:49900`):**
  - Switch between **Mars Trek Viking Red**, **MOLA Elevation Heatmap**, **USGS MOLA + THEMIS Blend**, and **USGS THEMIS Day IR**, plus high-res **Gale CTX (5.5 m)**, **Gale 1 m DEM**, **Jezero HiRISE (25 cm)**, and **Jezero DEM Mosaic** overlays.
  - **Quick Jump & Custom Bookmarks:** Fly to Mount Sharp, Gale Crater, Jezero (M20), Ares Vallis, Gusev Crater, Meridiani Planum, or Valles Marineris, or save custom bookmarks (`+ Mark Quick Jump Here`).
  - **MongoDB Vector Layers:** Toggle Mineral Signatures, Planned Waypoints, EVA Tactical markers, Global Mars Landmarks, Curiosity & Perseverance waypoints, and THEMIS thermal stamps.
- **AI EVA Route Planning & Safety Validation (`A*` & `Theta*`):**
  - Computes terrain-aware paths using grid-based **A\*** or any-angle **Theta\*** with configurable distance budget, max slope (°), suit O₂ (%), reserve (%), and atmospheric condition (`Nominal`, `Dusty`, `Dust Storm`, `Unverified`).
  - Displays a floating **EVA Route Key** (`#eva-route-legend`), inline Inspector color key, and hover tooltips explaining **Red** (Steep Hazard `≥ 25°`), **Yellow** (Caution `15°–24.9°`), and **Cyan** (Safe `< 15°`) terrain cells and route segments.
- **3D Mars Globe, Regional 3D Terrain & Mars 360° Street View (Three.js):**
  - **3D Mars Globe:** Interactive planetary sphere with synced MongoDB layers, cyan 3D surface selection highlight, dynamic high-res regional texture LOD when zooming in, and 2-click **Plan EVA Route** directly on the globe with distance-scaled Start/Goal pins.
  - **5×5 Chunk-Streamed 3D Terrain & Street View:** Zero-seam terrain streaming with photo-relief micro-depth, `Drone` / `Astronaut` / `Rover` / `Overview` modes, `WASD`/Arrow controls, **Dust Fog**, **Set Landing Site** rocket beacon, single-point or EVA-route waypoint tracking, Street View Quick Jump, and mission-matched NASA rover photo galleries with an enlargeable **Prev/Next Lightbox**.
- **Live Telemetry, PLSS & Space Weather HUD:**
  - Real-time **Mars Clock** (`MY`, `Ls`, `MSD`, `MTC`, `LMST`, `UTC`, `OWLT`), configurable **PLSS Life Support (EVA-1)**, **Orbital Relay** pass countdown, **Hamming(7,4) EDAC** bit-flip recovery tester, and coordinate- & elevation-aware **MEDA/REMS** weather and **MSL RAD / NASA DONKI** radiation monitoring.
  - Includes an interactive **11-step `? Guide`** with spotlight walkthrough and a global progress loader (`#ares-loader`).

---

## Tech Stack

- **Backend:** Python 3.12, FastAPI, Uvicorn, NumPy, SciPy, scikit-learn, skops, Pillow, Rasterio, HTTPX
- **Databases:** MongoDB (`ares_base` geospatial `2dsphere` collections) & Supabase (optional Postgres + Storage bundles)
- **Frontend:** Vanilla JS (ES Modules), Leaflet, Three.js, Lucide SVG icons, CSS3 glassmorphic dual-drawer tablet UI
- **Testing & Deployment:** pytest, Docker, Docker Compose

---

## Quick Start

### Option 1: Docker (Recommended)

1. Copy the environment template and fill in your MongoDB (and optional Supabase) credentials:
   ```bash
   cp .env.example .env
   ```
2. Build and start the full system (FastAPI backend + static frontend on port `8000`):
   ```bash
   docker compose up --build
   ```
3. Open **http://127.0.0.1:8000/** in your browser.

---

### Option 2: Local Python Setup

1. Create and activate a virtual environment, then install dependencies:
   ```bash
   python -m venv backend/.venv
   # Windows PowerShell:
   backend\.venv\Scripts\Activate.ps1
   # macOS / Linux:
   # source backend/.venv/bin/activate

   pip install -r requirements.txt
   ```
2. Configure `.env`:
   ```bash
   cp .env.example .env
   ```
3. Start the server **from the `backend/` directory**:
   ```bash
   cd backend
   uvicorn app.main:app --host 127.0.0.1 --port 8000
   ```
4. Open **http://127.0.0.1:8000/** in your browser.

---

## Database Setup (New Users)

If you do not have access to the team's hosted database, see **[docs/08_DATABASE_SETUP_AND_SEEDING.md](docs/08_DATABASE_SETUP_AND_SEEDING.md)** for full MongoDB Atlas / local Docker MongoDB and Supabase setup instructions.

Quick seed into your own MongoDB instance:

```bash
python backend/push_to_mongo.py --dry-run
python backend/push_to_mongo.py --datasets all
```

---

## Running Tests

Run both test suites from the **`backend/`** directory:

```bash
cd backend
pytest tests -v                         # 146 backend tests (26 core + 120-case stress/boundary/security suite)
pytest tests/test_stress_100plus.py -v  # 120-case API stress, boundary, negative & SSRF/injection suite
pytest ../tests -v                      # 19 API, A* & EVA safety validation tests
```

---

## Project Structure

```text
ARES/
├── backend/
│   ├── app/
│   │   ├── api/            # FastAPI routers (routes, map_data, maps, climate)
│   │   ├── schemas/        # Pydantic request/response models
│   │   ├── services/       # A*, Theta*, safety, Mars time, radiation, EDAC, climate
│   │   ├── db.py           # MongoDB client helper
│   │   └── main.py         # FastAPI app & static frontend mount
│   ├── tests/              # 3D terrain/Street View, Mars time, API & 120-case stress suite
│   ├── push_to_mongo.py    # Idempotent MongoDB seeding & index setup
│   ├── push_to_supabase.py # Supabase Storage & Postgres uploader
│   └── supabase_schema.sql # Postgres schema for Supabase
├── frontend/
│   ├── index.html          # Dual-drawer tablet UI, 3D modals, ? Guide & loader
│   ├── styles.css          # Tactical dark-mode theme & responsive layout
│   ├── app.js              # 2D Leaflet map, EVA planner, PLSS/HUD & ? Guide
│   ├── terrain3d.js        # 3D Mars Globe & Regional 3D Terrain
│   ├── streetview.js       # Mars 360° Street View (Drone/Astronaut/Rover/Overview)
│   └── chunks3d.js         # Shared 5×5 chunk manager & photo-relief mesh builder
├── tests/                  # Core API, A* & safety unit tests
├── docs/                   # Architecture, API, DB & 3D technical documentation
├── Dockerfile
├── docker-compose.yml
└── .env.example
```

---

## Documentation

Full technical specifications live in **[docs/README.md](docs/README.md)**:

- [01 — System Architecture & Use Cases](docs/01_SYSTEM_ARCHITECTURE_AND_USE_CASES.md)
- [02 — Data Extraction, Processing & Contracts](docs/02_DATA_EXTRACTION_PROCESSING_AND_CONTRACTS.md)
- [03 — Backend FastAPI Specification](docs/03_BACKEND_API_SPECIFICATION.md)
- [04 — MongoDB Database Layout](docs/04_MONGODB_DATABASE_LAYOUT.md)
- [05 — Live MongoDB Data Reference](docs/05_LIVE_MONGODB_DATA_REFERENCE.md)
- [06 — Handoff & API Gateway Guide](docs/06_HANDOFF_AND_API_GATEWAY_GUIDE.md)
- [07 — 3D Terrain, Street View & 5×5 Chunks](docs/07_3D_TERRAIN_STREETVIEW_AND_CHUNKS.md)
- [08 — Database Setup & Seeding Guide](docs/08_DATABASE_SETUP_AND_SEEDING.md)
- [09 — Local Hosting & Cloudflare Tunnel Guide](docs/09_LOCAL_HOSTING_AND_CLOUDFLARE_TUNNEL.md)
- [10 — Local Server Performance & Device Specs](docs/10_BENCHMARK_AND_DEVICE_SPECS.md)
- [11 — Scientific Basis, Mathematical Formulas & Citations](docs/11_SCIENTIFIC_REFERENCES_AND_CITATIONS.md)
- [API Gateway Reference](docs/API_GATEWAY.md)
