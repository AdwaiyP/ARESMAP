# ARES Sample Data & Demo Guide (Mount Sharp & Gale Crater)

This folder contains a pre-fetched, pixel-aligned sample dataset and interactive explorer for **Mount Sharp (Aeolis Mons)** and **Gale Crater**, built to unblock both `frontend/` map development and `backend/` environmental/safety logic.

---

## 1. Quick Start: Run the Interactive Demo

From the repository root (`ARES/`):

### Option A — FastAPI Web Explorer (Recommended, zero `pandas` issues)
```bash
backend/.venv/Scripts/python.exe backend/local_viewer.py
```
Then open **`http://127.0.0.1:8000`** in your browser.

### Option B — Gradio Explorer (On machines where `pandas` DLLs are permitted)
```bash
backend/.venv/Scripts/python.exe backend/gradio_app.py
```
*(Note: On Windows PCs with strict Application Control policies that block `pandas._libs.tslibs.period`, use Option A—both apps share the same `backend/sample_loader.py` logic.)*

---

## 2. How to Use the Demo UI

1. **Switch Region:** Choose **`Mount Sharp (Zoomed)`** (default, covers Vera Rubin Ridge, NW foothills/boxwork slopes, and Aeolis Mons peak) or **`Gale Crater (Overview)`**.
2. **Blend Layers:** Pick a **Base Layer** (e.g., `Mars Trek CTX Optical`) and an **Overlay Layer** (e.g., `THEMIS Night IR (Thermal Inertia)` or `MOLA Color Topography`) and drag **Overlay Opacity** (`0–100%`) to compare terrain ridges against thermal inertia (bright = exposed bedrock, dark = loose dust/sand) and elevation.
3. **Inspect Coordinate-Matched Descriptions:** Hover any cyan/purple THEMIS coordinate pin on the map for a live tooltip showing `file_id`, `description`, `(lat, lon)`, `surf_temp_c`, and `alb_avg`, or **click anywhere on the map** to match the nearest `Gale Crater.csv` records. Toggle **Burn Descriptions onto Image** if you want the labels rendered directly onto the PNG.
4. **Inspect Sol 100 Environmental & Safety States:** Use the **Sol 100 LMST Window** dropdown to scrub 15-minute buckets (`00:00` → `23:00 LMST`) and view air/ground temperatures, irradiances, optical `RDS`, pressure, wind, safety states (`NOMINAL`, `CAUTION`, `UNKNOWN_HOLD`), and red-shaded wind-offline bands on the diurnal plot.

---

## 3. What Data Is Included in `sample_data/`

### Map Images & Matched Stamps (All Pixel-Aligned Per Region, `EPSG:4326 / IAU:49900`)
- **`sample_data/mount_sharp/`** — `bbox = [137.2, -5.6, 138.4, -4.6]`
  - `images/wms/ctx_optical_mount_sharp.png` (`960 × 800`, stitched from 48 `z=10` Mars Trek CTX tiles in `images/mars_trek_ctx_z10/`)
  - `images/wms/themis_day_ir.png`, `themis_night_ir.png`, `mola_themis_blend.png`, `mola_color_topo.png`, `mdim21_optical_color.png`
  - `themis_stamps.json` & `themis_stamps.geojson` (`327` coordinate-matched `Gale Crater.csv` records, `51` with named descriptions; `0.0` sentinels cleaned to `null`)
  - `mount_sharp_spatial_bundle.json` (bounding box, CRS, tile bounds, reference landmarks)
- **`sample_data/`** — Gale Crater overview, `bbox = [136.1, -5.8, 138.7, -3.2]`
  - `images/wms/ctx_optical_gale.png` (`900 × 900`, stitched from 64 `z=9` Mars Trek CTX tiles in `images/mars_trek_ctx_z9/`)
  - Same 5 aligned USGS WMS layers + `themis_stamps.json/.geojson` (`730` matched records, `100` named) + `gale_spatial_bundle.json`

### Cleaned Numerical Telemetry (From `backend/mars_site_complete_telemetry.csv`)
- `telemetry_15min_sol100.csv` & `telemetry_15min_sol100.json` — All 103,011 raw Sol 100 rows aggregated into 63 15-min `LMST` buckets with `safety_state` and `quality_and_unknown_flags`.
- `telemetry_raw_sample.csv` — 18 representative raw rows for quick schema inspection.

To re-fetch or adjust bounding boxes/zoom levels, edit `GALE_BBOX` / `MOUNT_SHARP_BBOX` in `backend/extract_samples.py` and re-run it.

---

## 4. Key Caveats & API Notes for Teammates

- **Stationary Point Weather Only:** `mars_site_complete_telemetry.csv` has **no GPS/lat-lon coordinates**; it is 1 parked sol (Sol 100) using a Perseverance MEDA schema.
- **Optical `RDS` ≠ Ionizing `RAD`:** `optical_rds_top7_mean` measures optical/UV solar & dust light (`LOW_GAIN` day / `HIGH_GAIN` night), **not** astronaut-harming ionizing radiation (`mGy/day`, `mSv/day`).
- **Fixed Uncertainty Bug:** The raw CSV's `*_UNCERTAINTY_C` columns mistakenly subtracted `273.15` from Kelvin uncertainties; our cleaned outputs use the Kelvin uncertainty directly as `±°C`.
- **Direct Tile/WMS Gotchas (if fetching live in `frontend/`):**
  - **Mars Trek (`Gale_CTX_BlockAdj_dd`):** Uses Equirectangular `2:1` `256 × 256` PNG tiles in `/{z}/{row}/{col}.png` order (`.jpg` for global MOLA).
  - **USGS WMS (`THEMIS_*`, `MOLA_*`):** Works in browsers (`Access-Control-Allow-Origin: *`), but Python requests require a standard `User-Agent` header or USGS returns `403`.
