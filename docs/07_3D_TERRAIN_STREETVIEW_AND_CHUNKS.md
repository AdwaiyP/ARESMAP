# 07 — 3D Mars Globe, Local Terrain, Street View & 5×5 Chunk Streaming

This document covers the interactive 3D visualization, grounded & aerial Street View, Minecraft-style `5×5` chunk streaming, and backend texture caching implemented in ARES.

---

## 1. Architecture Overview

```
frontend/
├── terrain3d.js    # 3D Mars Globe (raycast picking + adaptive orbit) & 3D Local Terrain (WASD + 5×5 chunks)
├── streetview.js   # Mars 360° Street View (Drone / Astronaut / Rover / Overview + Rocket Lander + NASA photos)
└── chunks3d.js     # Shared MarsChunkManager (5×5 sliding window, 64×64 Street View mesh, regolith bump map, barycentric getGroundY)

backend/app/api/
└── map_data.py     # /terrain-grid, /regional-texture (tile cache + httpx pool), /globe-texture, /streetview, /image-proxy, /time
```

---

## 2. 3D Mars Globe (`frontend/terrain3d.js`)

- **High-Res Global Texture:** Fetches a `2048×1024` equirectangular Mars mosaic from `/api/v1/map/globe-texture?tex=viking|mola&z=2`.
- **Interactive Raycast Picking:** Clicking anywhere on the globe (`pointerup` with `< 5 px` drag) raycasts against:
  1. **Feature Pins** (`mars_landmark`, `mineral_signature`, `planned_waypoint` from `/api/v1/map/features?slim=true`).
  2. **Mars Surface (`globeSphere`):** Converts the 3D hit point back to `(lat, lon)` and queries `/api/v1/map/telemetry` and `/api/v1/map/terrain-grid` to display elevation, radiation, temperature, and pressure in `#globe-info-card`.
- **Altitude-Scaled Orbit Controls:** `controls.rotateSpeed` scales dynamically with camera altitude above `GLOBE_R = 24` (`Math.max(0.12, Math.min(0.85, (dist - GLOBE_R) / 30))`) with `zoomSpeed = 0.55`, preventing overshooting when zoomed close to craters.

---

## 3. Minecraft-Style 5×5 Chunk Streaming (`frontend/chunks3d.js`)

Both **3D Local Terrain** and **Mars 360° Street View** share `MarsChunkManager`:

| Constant / Option | Value | Meaning |
|---|---|---|
| `CHUNK_DEG` | `0.08°` | Angular span per chunk (~4.7 km at Mars equator) |
| `CHUNK_WORLD` | `60.0` (Regional) / `1200.0` (Street View) | Three.js world units per chunk (`1 unit ≈ 3.95 m` in Street View) |
| `CHUNK_RADIUS` | `2` | `5×5` sliding window (25 chunks) |
| `gridN` | `32` (Regional) / `64` (Street View) | Elevation vertices per chunk (`64×64` in Street View) |

### How Seamless Chunking & Progressive Loading Work
1. **Sliding 5×5 Window:** `updateAround(wx, wz)` computes the active chunk `(curCx, curCy)`, unloads and disposes any chunk outside `CHUNK_RADIUS = 2`, and fetches only the newly exposed edge chunks.
2. **Zero-Seam Borders:** `/api/v1/map/terrain-grid` samples `np.linspace(min_lon, max_lon, cols)` and `np.linspace(max_lat, min_lat, rows)` over the same MongoDB elevation dataset, so shared edges between adjacent chunks have `0.0 m` height mismatch.
3. **Instant Progressive Rendering & Surface Detail:**
   - `_loadChunk` fetches `/api/v1/map/terrain-grid` first and immediately renders the 3D mesh with elevation/slope vertex shading + a procedural **Mars regolith sand-ripple & pebble bump map**.
   - `/api/v1/map/regional-texture` loads asynchronously in the background and drapes real NASA Trek imagery (Jezero HiRISE / Gale CTX / Viking) with `16×` anisotropic filtering.
4. **Exact Ground Following & Live Controls:**
   - `getGroundY(wx, wz)` uses exact barycentric triangle interpolation matching `PlaneGeometry`'s triangulation so Astronaut, Rover, Lander, and cameras track steep ridges and craters without clipping.
   - `rebuildAll(colorMode, exag)` updates vertical exaggeration and color mode (`orbital`, `elevation`, `slope`) across all loaded chunks without re-fetching.

---

## 4. Center-Pane 3D Views & Mars 360° Street View

- **Center-Pane Layout + Optional Fullscreen:** 3D Globe, 3D Local Terrain, and Mars 360° Street View open inside the middle map pane (keeping both sidebars visible), with a **`⛶ Fullscreen`** toggle on each view.
- **Mars 360° Street View (`streetview.js`):**
  - **4 Explorer Modes:** `🛸 Drone`, `🧑‍🚀 Astronaut` (grounded EVA walk), `🚙 Rover` (6-wheel drive), and `🗺️ Overview`, with slope-aware movement and `240` instanced 3D surface boulders.
  - **`🚀 Set Landing Site`:** Places a 3D Rocket Lander + Pad (synced to the 2D map) with live distance & bearing in the visor HUD.
  - **`🌫️ Dust Fog: ON/OFF`** toggle, **bottom direction arrow** (`#sv-nav-arrow`), terrain-draped **3D EVA route tubes**, **Nearby Area Intel** 3D pins, and mission-matched **360° Panoramas + Curiosity/Perseverance** photos via `/api/v1/map/streetview` and `/api/v1/map/image-proxy`.

---

## 5. Backend Texture Caching, Subpixel Cropping & MOLA Relief (`backend/app/api/map_data.py`)

- **Tile Cache (`_tile_cache`):** Caches raw NASA Trek PNG/JPG tiles by `{layer}:{z}:{r}:{c}` (capped at 512 entries) so overlapping `0.08°` chunks reuse already-downloaded orbital tiles.
- **HTTP Keep-Alive Pool (`_trek_http`):** Uses a shared `httpx.Client` (`max_connections=24`, `max_keepalive_connections=16`) instead of opening new TLS connections per tile.
- **Subpixel Seamless Cropping & High-Res Zoom:** `_stitch_trek_bbox` uses `Image.Transform.EXTENT` with `BICUBIC` resampling + `1.25×` sharpness enhancement (`z=12` Jezero HiRISE, `z=11` Gale CTX, `z=7` global Viking), paired with `anisotropy = 8` in `chunks3d.js`.
- **Global MOLA Elevation Fallback (`_mola_elev_from_trek`):** Outside Gale and Jezero (where MongoDB has `< 3` local elevation points, e.g., Valles Marineris, Olympus Mons, Arcadia Planitia), `/terrain-grid` derives continuous regional relief from NASA Trek's `Mars_MGS_MOLA_ClrShade_merge_global_463m` (`z=7`).
- **Stitched Chunk Cache:** Caches final `512×512` JPEG textures in `_cache` (`TTL = 120s`, `X-Cache: HIT/MISS`).

---

## 6. Hyperlocal EVA Spacewalk Mode (500 m A*) & Astronaut Visor HUD

To address NASA's hyperlocal individual-spacewalk requirement:
- **Live Map A* Routing (`frontend/app.js`):**
  - Clicking **Plan Hyperlocal EVA (500m A*)** lets the astronaut click **Start** and **Goal** anywhere on Mars.
  - Fetches a `50×50` hyperlocal grid from `/api/v1/map/terrain-grid`, computes slope-based `risk` weights (`slope_deg / 25.0`), overlays **Caution (`15°–25°`, yellow)** and **Hazard (`≥ 25°`, red)** cells on the map, and calls `POST /api/v1/routes/plan` (`plan_astar()`).
  - Displays route distance (`m`), walk time (`1.2 m/s`), hazard cell count, and one-way PLSS O₂ budget, with a **Walk EVA in Visor Street View** launcher.
- **Astronaut Helmet-Visor HUD (`frontend/streetview.js`):**
  - Displays real-time **EVA Safety State** (`NOMINAL` `< 15°`, `CAUTION` `15°–25°`, `HAZARD` `≥ 25°`) via `MarsChunkManager.getSlopeAt(wx, wz)` plus forward terrain lookahead radar, **Next Stop** distance & bearing, **PLSS O₂ / Battery (%)**, and **Walked Distance / Point-of-No-Return (`PNR OK` / `RETURN NOW`)**.
  - **Rocket-League-style Bottom Nav Arrow & Scale Bar (`computeScaleReadout`):** Shows a distance-scaled directional pointer and live ground scale bar (`90px ≈ ... · ALT ... · 1 Chunk = 4.7 km`).
  - **5×5 Chunk Streaming & Full Path Overview Island Lock:** Streams a `5×5` (`25`-chunk) sliding window around the drone, and locks the `5×5` terrain island in **Full Path Overview** mode regardless of camera movement.
  - **Turning-Point Waypoints & Zero-Seam Terrain:** Preserves every A\*/Theta\* turning point as a temporary waypoint in 3D, renders all 4 NASA rover traverse tracks (`Curiosity`, `Perseverance`, `Spirit`, `Opportunity`) on the 3D Globe (with distance-scaled pins) and 3D terrain, and aligns MOLA/IDW chunk borders to `0.0 m` seam error.

---

## 7. 3D Mars Globe Parity, Configurable PLSS & Radiation HUD

- **3D Mars Globe Feature Parity (`frontend/terrain3d.js` + `frontend/app.js`):**
  - **Globe EVA Route Planning:** Users can plan A\*/Theta\* routes directly on the 3D Mars Globe via the **`Plan EVA Route`** toolbar button (2-click Start → Goal) or via **`Set as EVA Route Start`** / **`Plan EVA Route to Here`** in the Globe inspector card. Computed routes render on both the 3D Globe and the 2D map and can launch directly into 3D Street View.
  - **Quick Jump & Layer Sync:** Sidebar **Quick Jump** buttons (`window.jumpGlobeTo`), **Global Base Layer** radios (`window.setGlobeTextureStyle`), **`+ Drop Planned Waypoint`** (`window.openDropWaypointForm`), and all **MongoDB Vector Layer** checkboxes (`window.syncGlobeLayers`) operate seamlessly on the 3D Globe.
- **Configurable PLSS Life Support & Orbital Relay (`frontend/index.html` + `frontend/app.js`):**
  - **PLSS Life Support (EVA-1):** Users can pre-enter `Init O₂ (%)`, `Init Bat (%)`, `H₂O (L)`, `Work (W)` (metabolic rate), and `Press (kPa)`; remaining endurance, `ppCO₂`, walked depletion, and planned route O₂ estimates update dynamically and sync with the 3D Street View visor HUD.
  - **Satellite Orbital Relay:** Users can configure **Orbit (min)** (default `112` min) and **Offset (min)**, or click **`Sat Nearby (Reset Pass)`** to mark the relay overhead and reset the pass countdown.
- **Surface Radiation & Space Weather (`backend/app/services/radiation.py`, `GET /api/v1/map/radiation`):**
  - Computes elevation-adjusted MSL RAD GCR dose rate (`µSv/hr`, `mSv/day`), atmospheric CO₂ column shielding (`g/cm²`), 4-hour EVA dose, and live/cached NASA DONKI Solar Energetic Particle (`SEP`) storm alerts in both the sidebar HUD and the 3D Globe inspector.

