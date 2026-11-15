# 02 — Data Extraction, Processing Pipelines & Frontend Contracts

> **Scope:** Defines what raw data is extracted from each official/hackathon source, how it is cleaned and transformed (including real bugs found in the sample files), and the exact JSON contracts shared with the EVA Tablet and Base Station frontends.

---

## 1. Data Extraction Inventory (By Source)

Every ingested dataset is registered in `source_register` with canonical SI units, timestamps, and spatial resolution limits.

| Source / Dataset | What We Extract | Native Format & CRS | Spatial / Temporal Limits | Multi-Planet Equivalent |
|---|---|---|---|---|
| **NASA Solar System Treks WMTS** (`trek.nasa.gov/tiles/{body}/EQ/...`) | Optical base tiles (`Gale_CTX_BlockAdj_dd` `.png`, zooms `0–12`), Global shaded relief (`Mars_MGS_MOLA_ClrShade_merge_global_463m` `.jpg`, zooms `0–7`), `WMTSCapabilities.xml` | `256×256` PNG/JPG tiles, `IAU:49900` (`2:1` Equirectangular) | CTX restricted to Gale `bbox`; MOLA global `463 m/px` cannot detect boulders | Venus Magellan SAR / Europa Galileo Trek `{body}` endpoints |
| **USGS Astrogeology WMS / COGs** (`planetarymaps.usgs.gov`) | `THEMIS_controlled` (Day IR), `THEMIS_night` (thermal inertia proxy), `MOLA_THEMIS_blend`, `MOLA_color`, `MDIM21_color`, **HiRISE `0.25–1 m/px` DTMs** | PNG / GeoTIFF (COG), `EPSG:4326` / `IAU_2015:49900` | THEMIS `~100 m/px` (regional slip only); HiRISE DTM required for `1 m` slope/drop-off | Planetary WMS/COG layers mapped via `PlanetProfile` |
| **ASU THEMIS Stamp Catalog** (`Gale Crater.csv`) | `file_id` (`I*` IR / `V*` VIS), `ct_lon`, `ct_lat`, `surf_temp_avg` (`K`), `alb_avg`, `band_bin_band_number`, `description` | CSV (`1,053` rows) | Center-point of wide swath only; **no timestamps**; `0.0` is missing sentinel | Any orbital observation stamp catalog |
| **Curiosity Traverse & Waypoints** (`MSL_waypoints.json`, `MSL_traverse.json`) | `RMC`, `site`, `drive`, `sol`, `lon`, `lat`, `easting`, `northing`, `elev_geoid` (`m`), `tilt` (°), `dist_total_m`, 3D `[lon, lat, elev_m]` path | GeoJSON (`1,388` waypoints, `1,316` segments, Sol `3–5070`) | Historical rover track; gives real local metric `easting/northing` & elevation | Past lander/probe/aerobot tracks |
| **Surface Weather Telemetry** (`mars_site_complete_telemetry.csv` / REMS `MODRDR`) | `SCLK`, `LMST`, `LTST`, `SOLAR_ZENITHAL_ANGLE`, `ATS` air temp, `TIRS` ground IR temp + LW/SW flux, `BAROCAP` pressure, `HUMICAP` RH, `RDS` optical/UV, `BOOM1/2` wind + FOV/stability flags | CSV (`103,011` rows @ ~2 Hz, Sol 100 MEDA schema) | **Single stationary point**; `44%` wind offline; 25 all-empty columns; optical `RDS` ≠ ionizing `RAD` | Venus atmospheric sonde ($P, T, \text{wind}$) / Titan meteo |
| **RAD Ionizing Radiation** (`MSL-M-RAD-3-RDR-V1.0`) | `UTC`, `SOL`, absorbed dose rate (`mGy/day`), dose equivalent rate (`mSv/day`), charged vs. neutral channels, SEP event spikes | PDS RDR CSV/TAB | Point dosimeter with rover/terrain shielding caveats | Jupiter/Europa energetic particle monitor (`rad/hr`) |
| **Science Chemistry & Mineralogy** (`ChemCam`, `APXS`, `CheMin`, `CRISM`) | `ChemCam` PLS oxides (`SiO2..K2O` wt%), `APXS` dry oxides (`SO3`, `Cl`, `CaO`, `MgO`, `FeOT` wt% + $1\sigma$), `CheMin` XRD mineral `wt%` + amorphous, `CRISM` mineral indices | PDS RDR CSV / GeoTIFF | `ChemCam` `300–600 µm` spot; `APXS` `1.7 cm` contact; `CheMin` drill hole; `CRISM` `~18 m/px` | Venus Raman/XRF; Europa NIR/mass-spec ice chemistry |
| **NASA DONKI Space Weather** (`api.nasa.gov/DONKI/...`) | `sepID`, `eventTime`, `CMEAnalysis` (speed, half-angle), `WSAEnlilSimulations` (shock arrival), linked flare/CME IDs | JSON REST | Earth/heliospheric UTC; must add **OWLT** + propagation time for target body | Solar-wind/CME alerts for any inner/outer planet |
| **Suit PLSS & PNT Streams** *(Hardware / Hackathon Sim)* | Primary/reserve $\text{O}_2$ (pressure, flow), $\text{ppCO}_2$ (`mmHg`), scrubber `%`, battery (`kWh`), cooling $\text{H}_2\text{O}$ (`L`), HR/RR/metabolic `W`, IMU/odometry, sun-sensor heading, buddy UWB range, RFID sample ID | WebSocket / JSON | Simulated or live hardware feed; tagged `source_type = "eva_sim_stream"` | Any pressurized suit, pressurized rover, or robotic platform |

---

## 2. Backend Data Processing Pipelines

### A. Ingestion QC & Sentinel Normalization
Before data enters MongoDB or Parquet:
1. **Sentinel & Bug Cleaning (Real Fixes Observed in Workspace Data):**
   - **CSV `*_UNCERTAINTY_C` Offset Bug (`mars_site_complete_telemetry.csv`):** Raw Celsius uncertainty columns subtracted `273.15` from Kelvin error deltas (e.g., `0.11 K` became `-273.04`). Pipeline **discards `*_UNCERTAINTY_C`** and copies Kelvin uncertainty directly (`1 ΔK == 1 Δ°C`).
   - **Zero-Sentinel Filtering (`Gale Crater.csv`):** `surf_temp_avg == 0.0` (`471` rows) and `alb_avg == 0.0` (`917` rows) are coerced to `null` (`status = "UNKNOWN"`), never converted to `-273.15 °C`.
   - **Quality Flag Gating:** Reject wind speeds where `Wind_BOOM*_ALG_STATE_STABLE != 1`; tag TIRS ground IR temperatures when `SUN_OUTSIDE_TIRS_FOV == 0` or `TIRS_GROUND_FOOTPRINT_NOT_IN_SHADOW == 0`; stitch `RDS` low-gain (`_TOP_7`) and high-gain (`_TOP_7_HG`) with explicit `gain_mode` provenance.
   - **Empty Channels:** All-null columns (e.g. `MASTHEAD_*`, `BAROCAP*_UNCERTAINTY`, vertical wind) are tagged `uncertainty_type = "unreported"`, never coerced to `0`.

2. **Multi-Planet Unit & Clock Normalization:**
   - Convert all temperatures to canonical `K` (plus `°C` helper), pressures to `Pa`, winds to `m/s`, radiation to `mGy/day` & `mSv/day`.
   - Compute dual-clock envelope using `PlanetProfile.clock_model`:
     - Earth `utc` + `met_sec` (Mission Elapsed Time) + `owlt_sec` (Earth-to-target one-way light time).
     - Target body local time: e.g. Mars `sol`, `lmst`, `ltst`, `ls_deg` (using $1\ \text{sol} = 88,775.244\ \text{s}$), or Venus/Europa local clock.

3. **LOD Time-Series Rollups:**
   - Raw `~2 Hz` rows are archived in Parquet / `telemetry_timeseries`.
   - Aggregation job emits **15-minute diurnal buckets** (`telemetry_rollups_lod`, e.g., `103,011` rows → `63` buckets) preserving `min`, `max`, `mean`, `std`, `valid_fraction`, `unknown_fields[]`, and `safety_state`.

---

### B. Real-Time Spatial & Safety Calculations (Server 1 Edge Engine)

1. **Dead-Reckoning + Solar Azimuth + Buddy PNT Fusion:**
   - Advance local `(easting, northing)` from stride/wheel odometry and IMU heading; expand position $1\sigma$ uncertainty radius $\sigma_{\text{pos}}$ proportionally to distance traveled since last fix.
   - Compute expected solar azimuth $\psi_{\odot}(\text{lat}, \text{lon}, L_s, \text{LTST})$ from `PlanetProfile` ephemeris; fuse with helmet/rover sun sensor to reset heading drift (avoiding Mars' localized crustal magnetic anomalies).
   - Compute relative **Buddy Vector** `(distance_m, bearing_deg)` to EVA-2 (`Rule of 2` alert if separation exceeds `max_buddy_range_m`).

2. **Terrain-Weighted Point of No Return (PNR) Isochrone:**
   - Over a local DTM + slope + THEMIS thermal-inertia slip grid around the astronaut:
     - Traversal speed $v(\theta, s_{\text{slip}})$ slows with uphill slope $\theta$ and low thermal-inertia dust slip index $s_{\text{slip}}$.
     - Metabolic / power burn rate $P(\theta, s_{\text{slip}}, g_{\text{body}})$ scales with planetary gravity $g_{\text{body}}$ and slope work.
     - Compute limiting PLSS time:
       $$T_{\text{limit}} = \min(T_{\text{O}_2},\ T_{\text{CO}_2\text{ scrub}},\ T_{\text{battery}},\ T_{\text{cool H}_2\text{O}}) - T_{\text{reserve}}$$
   - Run Dijkstra / Fast-Marching cost from the Habitat/Rocket return point to output the **PNR GeoJSON Polygon** (all points reachable with round-trip cost $\le T_{\text{limit}}$).

3. **RF Line-of-Sight (LOS) & Terrain Masking:**
   - Raycast along the 3D elevation profile from `(astronaut_pos, h_ground + 1.6 m)` to `(base_pos, h_ground + mast_m)` on the local DTM + planetary curvature correction $d^2 / (2 R_{\text{body}})$.
   - Output `los_clear: bool`, `first_obstruction_m`, `margin_m`, and a 2D coverage heatmap overlay.

4. **Drop-Off, Regolith Slip & Boulder Hazard Layers:**
   - **Drop-Off Alert:** Triggered when high-res DTM slope $|\nabla z| > \theta_{\text{cliff}}$ within lookahead radius (e.g., `10 m`), **only** when `active_dtm_resolution_m <= 2.0` (otherwise raise `UNKNOWN_LOW_RES`).
   - **Regolith Slip Index:** Normalized inverse thermal inertia from `THEMIS_night` (`0.0` = hard bedrock, `1.0` = loose dust/sand trap).
   - **Boulder Density:** Pre-computed obstacle density where rock height exceeds suit step-over clearance.

5. **Deterministic Safety State Machine:**
   - **`HAZARD` (`NO_GO`):** Drop-off cliff proximity, PNR exceeded, PLSS critical (`< 15%`), SEP radiation storm threshold breached, or extreme atmospheric limit (e.g., Venus pressure/temp breach).
   - **`CAUTION`:** High wind gusts, RF LOS obstructed (relying on orbital relay countdown), low-inertia slip zone, elevated GCR, or partial sensor coverage (`wind_valid_fraction < 0.5`).
   - **`UNKNOWN_HOLD`:** Required safety telemetry missing/stale beyond `max_staleness_sec`, or traversing outside high-res DTM coverage (`UNKNOWN_LOW_RES`). Never renders blank data as green or `0`.
   - **`NOMINAL`:** All safety-critical channels fresh, calibrated, and within `PlanetProfile` limits.

---

## 3. Data Shared With the Frontend / EVA Tablet

The tablet consumes **5 lean, contract-driven payloads** (plus raster map tiles):

1. **Status Bar & Dual-Clock Envelope:**
   ```json
   {
     "body": "mars",
     "mission_id": "ares_gale_boxwork_01",
     "clocks": {
       "earth_utc": "2026-11-12T11:15:00Z",
       "met": "02:41:10",
       "target_day_label": "SOL 184",
       "target_local_time": "11:24:00 LMST",
       "ls_deg": 142.6,
       "owlt_sec": 860
     },
     "overall_safety_state": "CAUTION",
     "active_alerts": [
       {"code": "WIND_PARTIAL", "severity": "CAUTION", "message": "Wind uncertainty unreported; 1-boom mode active"}
     ]
   }
   ```
2. **Navigation, PNR & Comms Overlay (`GeoJSON` + vectors):**
   - Astronaut pose `(lon, lat, easting, northing, elev_m, sigma_1_m)` + sun-compass heading
   - Buddy pose & relative `(distance_m, bearing_deg)`
   - Reverse breadcrumb `LineString` + planned route `LineString`
   - Dynamic `pnr_isochrone` `Polygon` + `rf_los` status (`clear / masked`) + next relay countdown (`MRO`, `T-minus 18m 40s`)
3. **Environmental & Space-Weather Bundle (`EnvironmentalState`):**
   - Atmospheric & optical fields wrapped in `{ value, unit, uncertainty_1sigma, uncertainty_type, status, provenance }`
   - Radiation (`gcr_dose_rate_msv_day`, `cumulative_eva_msv`, `sep_alert_state`, `donki_owlt_age_sec`)
4. **PLSS & Biometrics (`SuitPLSSState`):**
   - Primary/reserve $\text{O}_2$ (`%`, `kPa`, `min_remaining`), $\text{ppCO}_2$ (`mmHg`), scrubber `%`, battery (`kWh`, `%`), cooling $\text{H}_2\text{O}$ (`L`), metabolic output (`W`), heart rate (`bpm`), bottleneck subsystem driving PNR.
5. **Science Waypoints & RFID Sample Logger (`ScienceWaypoint` GeoJSON):**
   - Boxwork target coordinates + uncertainty radius, geologic unit, prior `ChemCam`/`APXS`/`CheMin`/`CRISM` evidence cards (with exact spot-size limits), POV reference photos, and RFID sample capture records (`sample_id`, `rfid_tag`, `lon`, `lat`, `sol`, `lmst`, `photo_uri`).
