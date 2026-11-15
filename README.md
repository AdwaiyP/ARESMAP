# ARES — Astronaut Route & Exploration System

**Intelligent Mars Exploration Planning & Astronaut EVA Decision Support**

NASA Space Apps Challenge 2026 | Team ARES

ARES is a proposed Mars exploration planning application designed to help astronauts and mission planners evaluate terrain, plan routes, identify scientific exploration opportunities, and assess extravehicular activity (EVA) constraints.

The project aims to combine planetary geospatial information, scientific observations, environmental data, and route-planning algorithms into an intuitive tablet-based mission interface.

> **Project status:** Active prototype (`v0.2.0`). The FastAPI backend, MongoDB Atlas (`ares_base`) + Supabase Storage pipelines, A\* & Theta\* EVA route planner, safety validation dashboard, live Mars Date & Time API, and interactive Leaflet + Three.js 3D Globe / Terrain / Street View frontend are implemented and runnable locally.
>
> **Quick Start:**
> ```powershell
> pushd backend; .\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
> ```
> Open `http://127.0.0.1:8000/` for the interactive Mars EVA tablet UI or `http://127.0.0.1:8000/docs` for Swagger API docs. See [docs/README.md](docs/README.md) and [docs/06_HANDOFF_AND_API_GATEWAY_GUIDE.md](docs/06_HANDOFF_AND_API_GATEWAY_GUIDE.md) for architecture & API Gateway specs.

---

## Mission

Exploring Mars involves navigating unfamiliar terrain while accounting for limited EVA time, environmental hazards, equipment availability, and scientific objectives.

ARES aims to support these decisions through a unified planning system.

### Core Objectives

- **Terrain Awareness:** Visualize Martian topography, slopes, obstacles, and potential hazards.
- **Intelligent Route Planning:** Use graph-based pathfinding to identify candidate exploration routes.
- **Scientific Exploration:** Highlight locations of potential scientific interest using available planetary observations.
- **Environmental Awareness:** Present relevant atmospheric and radiation observations with their sources and timestamps.
- **EVA Planning:** Evaluate estimated travel time, equipment requirements, and mission constraints.
- **Mission Visualization:** Provide a tablet-friendly interface for route exploration and mission planning.

ARES is a research and demonstration prototype, not a flight-certified astronaut navigation or safety system.

## Proposed System Architecture

```text
                  ARES SYSTEM
                       |
          +------------+------------+
          |                         |
     Flutter App                FastAPI API
          |                         |
    Mission Dashboard       Mission Management
    Interactive Map         Data Validation
    Route Visualization     Route Planning
    EVA Safety Panels       EVA Evaluation
          |                         |
          +------------+------------+
                       |
                Data Processing
                       |
          +------------+------------+
          |            |            |
     Geospatial     Scientific   Environmental
       Data           Data          Data
          |            |            |
     DEM / Slope   Waypoints     RAD / REMS
     Obstacles     Observations  Other Sources
          |            |            |
          +------------+------------+
                       |
              NASA Data Resources
```

The architecture is subject to refinement as the team validates the available datasets.

## Technology Stack

| Component | Technologies |
|---|---|
| Backend | Python, FastAPI, Pydantic |
| Route Planning | A*, NetworkX, NumPy |
| Geospatial Processing | GDAL, Rasterio, GeoPandas, QGIS |
| Scientific Data Processing | Python, pandas |
| Frontend | Flutter, Dart |
| State Management | Riverpod |
| Maps | flutter_map |
| API Communication | REST, JSON, Dio |
| Testing | pytest, httpx |
| Version Control | Git, GitHub |

## Planned Features

### 1. Martian Terrain Visualization

Display available planetary terrain information, including elevation, slope, and relevant geological features.

### 2. Intelligent Route Planning

Develop an A*-based routing system that considers traversability, terrain difficulty, obstacles, and configurable mission constraints.

### 3. Scientific Waypoint Discovery

Integrate documented scientific observations and candidate exploration targets into the route-planning workflow.

### 4. Environmental Data Integration

Present available environmental measurements, including relevant Curiosity RAD and REMS observations, where supported by the datasets.

Historical observations will be distinguished from current conditions or forecasts.

### 5. EVA Feasibility Assessment

Estimate mission duration and evaluate route feasibility against configurable time, equipment, and safety constraints.

### 6. Interactive Mission Dashboard

Provide a tablet-oriented interface showing mission information, route options, exploration targets, and safety indicators.

## Project Structure

The repository is being organized around the following proposed structure:

```text
ARES/
├── backend/
│   ├── app/
│   │   ├── api/
│   │   ├── core/
│   │   ├── models/
│   │   ├── services/
│   │   └── main.py
│   ├── tests/
│   └── requirements.txt
│
├── frontend/
│   └── # Flutter application (planned)
│
├── data/
│   └── # Validated datasets and metadata (planned)
│
├── docs/
│   └── # Architecture and technical documentation
│
├── .gitignore
└── README.md
```

Some directories may not yet exist.

## Getting Started

### Prerequisites

- Python 3.11 or newer
- Git
- VS Code or another preferred IDE
- Flutter SDK for frontend development

### Clone the Repository

```bash
git clone https://github.com/AdwaiyP/ARES.git
cd ARES
```

The repository is currently private. Collaborators require access.

### Backend Setup

```bash
cd backend

python3 -m venv .venv
source .venv/bin/activate

python -m pip install -r requirements.txt
```

On Windows, activate the virtual environment using:

```powershell
.venv\Scripts\Activate.ps1
```

### Start the Backend

```bash
python -m uvicorn app.main:app --reload --port 8005
```

API documentation:

`http://127.0.0.1:8005/docs`

### Run Tests

```bash
python -m pytest -v
```

## Initial API Design

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/health` | Backend health check |
| `GET /api/v1/mission` | Mission information |
| `GET /api/v1/layers` | Available map-layer metadata |
| `POST /api/v1/routes/plan` | Route-planning interface |

These endpoints represent the initial backend design. Terrain-aware routing and actual NASA data integration are not yet complete.

## Development Roadmap

- [x] Define project concept and responsibilities
- [x] Establish initial backend API structure
- [ ] Finalize frontend–backend contracts
- [ ] Validate NASA datasets and geographic coverage
- [ ] Implement geospatial processing pipeline
- [ ] Implement terrain-aware A* routing
- [ ] Integrate scientific and environmental observations
- [ ] Implement EVA feasibility evaluation
- [ ] Complete Flutter mission interface
- [ ] Integrate and test the complete system
- [ ] Prepare demonstration and project submission

## Team ARES

| Team Member | Responsibility |
|---|---|
| Adwaiy Pillai | Technical Lead & Backend Engineer |
| Suraj | Geospatial Data Engineer |
| Ruhan | Science & Environmental Data Engineer |
| Rohit | Flutter Lead & Navigation Developer |
| Amol | Flutter Developer & Mission UI Engineer |
| Kaustubh | Documentation, Media & Presentation Lead |

## Data Sources and Scientific Integrity

ARES intends to use relevant publicly available NASA planetary datasets, subject to availability, geographic coverage, licensing, and technical suitability.

Potential sources include:

- [NASA Planetary Data System](https://pds.nasa.gov/)
- [NASA Mars Exploration Program](https://science.nasa.gov/mars/)
- [NASA Open Data](https://data.nasa.gov/)

Synthetic datasets may be used during technical rehearsals and testing. Such data will be explicitly labeled and will not be presented as real Martian observations.

Scientific uncertainty, coordinate reference systems, data provenance, and observation timestamps will be documented wherever applicable.

## Contributing

Team members should work on dedicated feature branches and submit pull requests for review.

Example:

```bash
git checkout -b feature/terrain-processing
git add .
git commit -m "feat: add terrain processing"
git push -u origin feature/terrain-processing
```

Do not commit virtual environments, credentials, API keys, or unnecessary generated files.

## Disclaimer

ARES is an educational and experimental prototype developed in connection with NASA Space Apps Challenge 2026.

The project is not an official NASA product and is not intended for operational astronaut navigation, mission certification, or safety-critical decision-making.

---

**ARES — Explore intelligently. Plan confidently.**