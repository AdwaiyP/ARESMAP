# ARES Technical Architecture & Specification Docs

This directory defines the end-to-end engineering blueprint for the **ARES Planetary Exploration Tablet**, **Edge Server (Rocket / Habitat)**, and **Base Station Server**, built dynamically so a single codebase can operate on **Mars** and adapt to **Venus**, **Jupiter / Europa**, or other bodies via `PlanetProfile` configuration.

| Document | Contents |
|---|---|
| [01 — System Architecture & Use Cases](01_SYSTEM_ARCHITECTURE_AND_USE_CASES.md) | `PlanetProfile` multi-planet design, Rocket Edge vs. Base Station two-server topology, planet-scale tile/LOD strategy, Mermaid architecture & use-case diagrams. |
| [02 — Data Extraction, Processing & Contracts](02_DATA_EXTRACTION_PROCESSING_AND_CONTRACTS.md) | Raw data sources & spatial limits, QC & sentinel fixes (including workspace CSV bugs), PNT/PNR/RF-LOS/Slip math, safety state machine (`NOMINAL`/`CAUTION`/`HAZARD`/`UNKNOWN_HOLD`), and frontend JSON contracts. |
| [03 — Backend FastAPI Specification](03_BACKEND_API_SPECIFICATION.md) | Complete `{body}`-parameterized REST + WebSocket endpoint catalog across Server 1 (Edge) and Server 2 (Base), plus offline fail-safe semantics. |
| [04 — MongoDB Database Layout](04_MONGODB_DATABASE_LAYOUT.md) | `ares_base` and `ares_edge` MongoDB schemas, Mermaid ER diagram, `2dsphere` & Time-Series indexes, Edge ↔ Base `sync_outbox`, and Venus / Europa profile examples. |
| [05 — Live MongoDB Data Reference](05_LIVE_MONGODB_DATA_REFERENCE.md) | Developer reference for the live `ares_base` collections, exact document shapes, `pymongo` query snippets, and `/api/v1/map/*` endpoints. |
| [06 — Handoff & API Gateway Guide](06_HANDOFF_AND_API_GATEWAY_GUIDE.md) | Summary of completed map/DB/EDAC work, integration guide for the Backend API Gateway teammate, and demo startup instructions. |
| [07 — 3D Terrain, Street View & 5×5 Chunks](07_3D_TERRAIN_STREETVIEW_AND_CHUNKS.md) | 3D Mars Globe raycast picking, Minecraft-style `5×5` chunk streaming (`chunks3d.js`), Street View, regolith bump/rocks, and NASA Trek tile caching. |
| [API Gateway Reference](API_GATEWAY.md) | Complete v1 endpoint catalog, request/response schemas, and Flutter/client integration reference. |

## Code Quality & Repository Hygiene

- **Local-only sample artifacts:** `sample_data/` is excluded from Git tracking and ignored via `.gitignore` to keep the repository lean. Run `backend/extract_samples.py` locally if you need to regenerate sample bundles.
- **Modular & bounded core services:** Core backend path-planning and climate services (`backend/app/services/theta_star.py`, `backend/app/services/astar.py`, and `backend/app/services/climate_predictor.py`) are decomposed into single-purpose helper functions (≤ 60 lines each) with explicit iteration bounds on search and path-reconstruction loops.
