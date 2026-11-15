# 03 — Backend FastAPI Endpoint Specification

> **Scope:** Complete REST + WebSocket API specification for **Server 1 (Rocket / Habitat Edge)** and **Server 2 (Base Station / Mission Control)**. Every endpoint is parameterized by `{body}` (e.g., `mars`, `venus`, `europa`, `jupiter`) so switching planets requires only database configuration, not new routes.

---

## 1. Deployment Roles & Base URLs

- **Server 1 — Edge API (`http://edge.ares.local:8000/api/v1`)**: Low-latency, offline-capable FastAPI server talking directly to EVA Tablets over local Wi-Fi/UHF. Reads `ares_edge` MongoDB + local AOI Mission Pack.
- **Server 2 — Base Station API (`https://base.ares.local:8001/api/v1`)**: Full-archive FastAPI server managing planet-wide datasets, Parquet LOD rollups, AOI Mission Pack generation, Earth OWLT queues, and Edge sync in `ares_base` MongoDB.

---

## 2. Planet Profiles & Source Register

| Method | Endpoint | Server | Purpose |
|---|---|---|---|
| `GET` | `/api/v1/planets` | S1, S2 | List available planetary profiles (`mars`, `venus`, `europa`, etc.) |
| `GET` | `/api/v1/planets/{body}` | S1, S2 | Return active `PlanetProfile` (CRS, radius, gravity, clock model, safety thresholds) |
| `POST` | `/api/v1/planets` | S2 | Register/update a new `PlanetProfile` dynamically |
| `GET` | `/api/v1/planets/{body}/sources` | S1, S2 | Return the **Source Register** (units, timebases, spatial resolution limits, caveats) |
| `GET` | `/api/v1/missions/{mission_id}/status` | S1, S2 | Dual-clock status bar (`earth_utc`, `met`, target `LMST/Sol`, `owlt_sec`, `overall_safety_state`) |

---

## 3. Map Tiles, Terrain & Spatial Features (Planet-Scale Ready)

| Method | Endpoint | Server | Query / Body Params | Purpose |
|---|---|---|---|---|
| `GET` | `/api/v1/map/{body}/layers` | S1, S2 | `aoi_id` (optional) | List available raster/vector layers (`CTX`, `THEMIS_night`, `MOLA`, `HiRISE_DTM`, `CRISM`) with `resolution_m`, `bbox`, and `ext` |
| `GET` | `/api/v1/map/{body}/tiles/{layer_id}/{z}/{row}/{col}` | S1, S2 | — | Serve cached AOI tile first (S1) or proxy/cache from Trek WMTS / USGS WMS (S2) |
| `GET` | `/api/v1/map/{body}/features` | S1, S2 | `bbox`, `zoom`, `types` (`waypoint,hazard,traverse,themis_stamp`), `cluster` | Viewport-clipped `GeoJSON FeatureCollection` (clusters at low zoom) |
| `GET` | `/api/v1/map/{body}/terrain-profile` | S1, S2 | `lon1,lat1,lon2,lat2,samples=100` | Elevation, slope (°), and slip index along a candidate path; flags `UNKNOWN_LOW_RES` if outside high-res DTM |
| `POST` | `/api/v1/aoi-packs/build` | S2 | `{body, mission_id, bbox, max_zoom}` | Slice tiles, DTM grid, and features into a portable offline AOI Mission Pack for Server 1 |
| `GET` | `/api/v1/aoi-packs/{pack_id}/manifest` | S1, S2 | — | Inspect cached AOI bounds, size, and active DTM resolution |

### Example: `GET /api/v1/map/mars/features?bbox=137.28,-5.18,137.92,-4.62&types=waypoint,hazard`
```json
{
  "type": "FeatureCollection",
  "meta": {
    "body": "mars",
    "crs": "IAU:49900",
    "active_dtm_resolution_m": 1.0,
    "truncated": false
  },
  "features": [
    {
      "type": "Feature",
      "geometry": {"type": "Point", "coordinates": [137.38915, -4.82568, -3473.68]},
      "properties": {
        "feature_id": "wp_boxwork_01",
        "feature_type": "science_waypoint",
        "name": "Mount Sharp Boxwork Ridge A",
        "priority": "HIGH",
        "provenance": {"source_id": "msl_mmgis_waypoints", "uncertainty_m": 2.5}
      }
    }
  ]
}
```

---

## 4. Navigation, PNT, PNR, RF LOS & Buddy Tracking (Server 1 Primary)

| Method | Endpoint | Server | Purpose |
|---|---|---|---|
| `POST` | `/api/v1/eva/{eva_id}/pnt/update` | S1 | Ingest IMU/stride dead-reckoning + sun-sensor heading + UWB range; returns fused `(lon, lat, easting, northing, sigma_1_m)` and sun-azimuth correction |
| `GET` | `/api/v1/eva/{eva_id}/navigation` | S1, S2 | Current astronaut pose, $1\sigma$ uncertainty ellipse, **EVA-2 buddy vector** (`distance_m`, `bearing_deg`), and **reverse breadcrumb** `LineString` |
| `POST` | `/api/v1/eva/{eva_id}/route/plan` | S1, S2 | Compute slope + slip-aware traverse path avoiding boulders/drop-offs (`A*` over local cost grid) |
| `GET` | `/api/v1/eva/{eva_id}/pnr` | S1 | Compute dynamic **Point of No Return** GeoJSON `Polygon` using current PLSS bottleneck + terrain energy cost |
| `GET` | `/api/v1/eva/{eva_id}/rf-los` | S1 | Raycast 3D RF Line-of-Sight from astronaut to Habitat/Rocket mast (`los_clear`, `margin_m`, optional 2D LOS mask) |

---

## 5. PLSS Life Support, Alerts & Real-Time Stream (Server 1 Primary)

| Method | Endpoint | Server | Purpose |
|---|---|---|---|
| `POST` | `/api/v1/eva/{eva_id}/plss` | S1 | Ingest PLSS telemetry (`o2_primary_pct`, `o2_reserve_pct`, `ppco2_mmhg`, `scrubber_sat_pct`, `battery_kwh`, `cooling_water_l`, `heart_rate_bpm`, `metabolic_w`) |
| `GET` | `/api/v1/eva/{eva_id}/plss/latest` | S1, S2 | Latest PLSS state + computed `limiting_subsystem` and `remaining_endurance_min` |
| `GET` | `/api/v1/eva/{eva_id}/alerts` | S1, S2 | Active prioritized alerts (`DROP_OFF`, `PNR_BOUNDARY`, `BUDDY_SEPARATION`, `SEP_STORM`, `UNKNOWN_HOLD`) |
| `WS` | `/api/v1/ws/eva/{eva_id}/stream` | S1 | `1–2 Hz` push stream combining navigation pose, PNR status, PLSS endurance, safety state, and drop-off alarms |

---

## 6. Environmental, Radiation & Space Weather

| Method | Endpoint | Server | Query Params | Purpose |
|---|---|---|---|---|
| `GET` | `/api/v1/environment/{body}/state` | S1, S2 | `mission_id`, `lmst` or `utc`, `scenario` | Current `EnvironmentalState` with per-field `{value, unit, uncertainty_1sigma, status, provenance}` and `safety_state` (`NOMINAL \| CAUTION \| HAZARD \| UNKNOWN_HOLD`) |
| `GET` | `/api/v1/environment/{body}/timeline` | S1, S2 | `sol` (or date range), `lod=15m\|1sol\|raw` | LOD-aggregated diurnal or multi-sol weather & radiation curves |
| `POST` | `/api/v1/environment/{body}/ingest` | S2 | Multipart CSV / JSON + `adapter` | Run adapter (`meda_csv`, `rems_csv`, `rad_csv`, `themis_stamps`) with sentinel & QC cleaning |
| `GET` | `/api/v1/space-weather/{body}/alerts` | S1, S2 | `active_only=true` | Active/predicted CME/SEP alerts (from NASA DONKI or simulated storm) with `issued_utc`, `owlt_sec`, and target arrival window |

---

## 7. Science Waypoints, Geo-Tagged Media & RFID Samples

| Method | Endpoint | Server | Purpose |
|---|---|---|---|
| `GET` | `/api/v1/science/{body}/waypoints` | S1, S2 | Boxwork / science targets with `ChemCam`, `APXS`, `CheMin`, and `CRISM` evidence + POV imagery links |
| `POST` | `/api/v1/science/{body}/waypoints` | S1, S2 | Create a field waypoint from tablet (auto-tagged with astronaut PNT coordinates, $1\sigma$ radius, Sol/LMST) |
| `POST` | `/api/v1/science/samples` | S1 | Log collected sample with `rfid_tag`, `waypoint_id`, `suit_pose`, `photo_base64/uri`, `notes`; queued for S2 sync |
| `GET` | `/api/v1/science/samples` | S1, S2 | List logged RFID samples + sync status (`PENDING_SYNC` vs `SYNCED_BASE`) |

---

## 8. Comms Windows, Earth OWLT Queue & Edge ↔ Base Sync

| Method | Endpoint | Server | Purpose |
|---|---|---|---|
| `GET` | `/api/v1/comms/{body}/windows` | S1, S2 | Countdown to next overhead relay pass (`MRO`, `Odyssey`, etc.), link bandwidth, and current `owlt_sec` to Earth |
| `POST` | `/api/v1/comms/messages` | S2 → S1 | Queue Earth Mission Control or Base message with `origin` (`LOCAL_BASE` vs `EARTH_MCC`), `issued_utc`, and `owlt_arrival_utc` |
| `POST` | `/api/v1/sync/push` | S2 | Server 1 pushes batched breadcrumbs, PLSS snapshots, alerts, and RFID samples using idempotent `sync_seq` |
| `GET` | `/api/v1/sync/pull` | S2 | Server 1 pulls updated space-weather alerts, Earth messages, and new science waypoints since `last_sync_seq` |

---

## 9. Standard Error & Fail-Safe Semantics
- **`200 OK` with `UNKNOWN_HOLD`:** Preferred over failing silently when a sensor channel is missing—returns valid payload structure with `value: null`, `status: "UNKNOWN"`, and `safety_state: "UNKNOWN_HOLD"`.
- **`503 Service Unavailable` (Sync only):** When Base Server 2 is unreachable, Server 1 writes mutations to `sync_outbox` and continues serving all EVA endpoints uninterrupted.
