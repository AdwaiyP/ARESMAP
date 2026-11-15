# ARES Tablet — Mars Surface Operations

Flutter tablet client for **ARES (Astronaut Route & Exploration System)**, Team ARES' entry for the
NASA Space Apps Challenge 2026 *Interplanetary Survival Guide* challenge.

The app is a landscape mission console for Gale Crater / Aeolis Palus. It bundles real NASA archive
products, computes traverse and terrain products locally, and labels every number with how it was
obtained. It targets a 1280×800 Android tablet and runs offline-first: the demo needs no backend, and
optionally links to the FastAPI service for server-side A* when one is reachable.

> ARES is a research prototype, not flight software. It is not for operational astronaut navigation,
> mission certification, or safety-critical decisions.

## Screens

| Screen | What it does |
|---|---|
| **Mission Control** | Objective checklist tied to real app actions, PNR (point of no return) tracker, alert stack, PLSS suit telemetry, MEDA weather, comms relay window, quick actions. |
| **Surface Map** | THEMIS Day IR / CTX / MOLA layers over the Gale bbox, 730 THEMIS temperature stamps, landmarks, route overlay, tap-to-inspect, zoom and pan, traverse card, map status. |
| **Terrain Holotable** | Native 3D relief on a procedural Gale DEM with orbit, vertical exaggeration, elevation/slope shading, wireframe, route overlay, route profile, surface hazards, solar geometry. |
| **Surface Imagery** | Four NASA panorama archive frames, drag-to-pan, compass tape, pitch tape, reticle, nav overlay, frame metadata, tag-waypoint action. |
| **Science / Sample Log** | Operator sample log (seeded + field-recorded), MEDA Sol 100 charts, pressure/atmosphere panel, data-quality audit, searchable 730-stamp thermal catalog with IR/VIS/warm/albedo filters. |

Navigation uses the left rail; Android back returns to Mission Control before exiting when possible.

## Data provenance

Every panel carries a pill stating where its content comes from:

| Pill | Meaning |
|---|---|
| `ARCHIVE` | Bundled NASA-derived archive product; may be decimated or reformatted. |
| `DERIVED` | Computed locally from archived or modelled inputs. |
| `MODEL` | Procedural or approximate model, not measured data. |
| `SIM` | Synthetic demo value (suit telemetry, relay windows, HUD overlays). |
| `NO DATA` | The channel is absent from the bundle. Nothing is fabricated to fill it. |

Bundled / computed content:

- **Map imagery** — THEMIS Day IR, CTX optical mosaic and MOLA + THEMIS false colour, Gale bbox
  `136.1–138.7°E, 5.8–3.2°S`, IAU:49900 / EPSG:4326.
- **THEMIS stamps** — 730 footprints (439 IR, 291 VIS) with surface temperatures from −110 °C to
  +10.24 °C where available.
- **MEDA Sol 100** — 63 archive buckets; air/ground temperature, pressure, raw optical depth,
  humidity and wind-channel availability. Invalid optical-depth samples (60/63 outside 0.1–2.0) are
  flagged and dust risk is explicitly not assessed from them.
- **Surface imagery** — NASA/JPL-Caltech panoramas PIA16101, PIA21268, PIA19803 and PIA21717.
- **Terrain / routing** — procedural Gale DEM (72×72 display grid, 56 m route cell). A* with
  8-neighbour slope penalties, Chaikin smoothing and exact start/end stitching; metrics are
  `MODEL`/`DERIVED`, not MOLA survey data.
- **Astronomy** — Mars Sol Date and MTC clock, local solar time, solar azimuth/elevation, one-way
  light time from a low-precision circular Earth–Mars ephemeris.
- **Deliberately absent** — ionizing-radiation dose. The alert stack says the monitor is not in the
  archive and the app does not clear EVA from this display.

Surface compass/pitch overlays and geo-tags are synthetic; tag positions are approximate and marked
`SIM`. The mission clock is a fixed archive scenario, not current Mars time.

## Run it

Prerequisites: Flutter 3.47+ / Dart 3.13+, Android SDK, and an Android tablet emulator or device.

```bash
cd ares_tablet
flutter pub get
flutter run -d emulator-5554
```

The local demo target used for validation is the `ares_tablet` AVD (Android 16, 1280×800, 160 dpi, landscape).

Build and install a debug APK:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.ares.ares_tablet/.MainActivity
```

The activity is locked to `sensorLandscape` and runs edge-to-edge.

## Live backend link

The client can use the repository's FastAPI backend for route solving while remaining fully usable
offline. Every route is planned on-device first and shown immediately; if the backend is reachable it
re-solves the same locally sampled grid through `POST /api/v1/routes/plan` and replaces the path only
when the server returns a valid route. Health is probed every 20 s and the top bar reports
`LIVE API LINK` vs `ARCHIVE MODE`; `MAP STATUS` reports `BACKEND A*` or `LOCAL A*`.

- Default base URL: `http://10.0.2.2:8006` (the emulator's alias for the host, matching
  [`docs/API_GATEWAY.md`](../docs/API_GATEWAY.md)). Override at build time with
  `flutter run --dart-define=ARES_API_BASE=http://<host>:<port>`.
- Start the backend from the repository root:
  `uvicorn app.main:app --host 0.0.0.0 --port 8006`.
- Cleartext HTTP is scoped to `10.0.2.2`, `127.0.0.1` and `localhost` in
  `android/app/src/main/res/xml/network_security_config.xml`; use HTTPS for any other host.
- The tablet sends its own elevation grid and does not consume Mongo-backed map/telemetry
  endpoints, so it does not require the missing `.env` or Mount Sharp artifacts. Those endpoints
  still need provisioning before they can be demoed.

## Checks

```bash
flutter analyze
flutter test
```

Tests cover the Mars clock and formatting, procedural terrain invariants, A* route connectivity and
metrics, and a 1280×800 widget smoke test that boots the real dataset and walks the main screens.

## Structure

```text
lib/
├── main.dart              # orientation lock + bootstrap
├── app_shell.dart         # dataset load, AresState lifetime, rail/top/bottom chrome
├── state/                 # AresState, AresScope (ChangeNotifier)
├── data/                  # bundled dataset loader + optional FastAPI client
├── models/                # dataset, stamps, MEDA, route, alerts, provenance
├── util/                  # astro, procedural terrain + A*, formatting
├── theme/                 # palette, type, background
├── widgets/               # HUD shell, map, panels, charts
└── screens/               # mission, map, terrain, surface, science
assets/
├── data/                  # Gale feature bundle, THEMIS GeoJSON, MEDA Sol 100
├── images/map/            # three registered map layers
├── images/surface/        # four archive panoramas
└── fonts/                 # Barlow Condensed + IBM Plex Mono
```

## Limits

- Only the route solver is linked to the backend. Map, telemetry, climate and Mount Sharp endpoints
  remain unused until MongoDB and the DEM/climate artifacts are provisioned; all screens still run
  from the bundle.
- Terrain, route, suit state, relay state and surface HUD overlays are models/simulations and are
  labelled as such. Remote routes are computed over the same procedural client DEM, with
  `terrain_source: client_supplied_grid` and `validated_for_eva_safety: false` on the server.
- Radiation clearance and any “safe” verdict are intentionally not made.

## Credits

NASA/JPL-Caltech and the THEMIS/MOLA/MEDA instrument teams for the archive products; Team ARES for
the mission concept. Built for NASA Space Apps Challenge 2026.
