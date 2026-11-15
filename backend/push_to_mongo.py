"""Idempotent MongoDB ingestion script for ARES datasets.

Pushes planetary config, source provenance, Mars Trek map layers, THEMIS stamps
(Gale Crater), MEDA Sol-100 15-min telemetry rollups, and Mars Perseverance
waypoints + geotagged raw images into MongoDB Atlas (`ares_base`).

Usage:
  1. Copy `.env.example` to `.env` and fill in your MongoDB credentials.
  2. Dry run (no DB connection required):
       python backend/push_to_mongo.py --dry-run
  3. Push all datasets:
       python backend/push_to_mongo.py --datasets all
  4. Push specific datasets:
       python backend/push_to_mongo.py --datasets themis_stamps,telemetry_rollups
"""

from __future__ import annotations

import argparse
import json
import os
import urllib.request
from pathlib import Path
from typing import Any

from pymongo import MongoClient, UpdateOne

try:
    from dotenv import load_dotenv
except ImportError:
    def load_dotenv(path: Path) -> None:
        if not path.exists():
            return
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

REPO_ROOT = Path(__file__).resolve().parent.parent
SAMPLE_DIR = REPO_ROOT / "sample_data"

M20_WAYPOINTS_URL = "https://mars.nasa.gov/mmgis-maps/M20/Layers/json/M20_waypoints.json"
MSL_WAYPOINTS_URL = "https://mars.nasa.gov/mmgis-maps/MSL/Layers/json/MSL_waypoints.json"
M20_RAW_IMAGES_URL = (
    "https://mars.nasa.gov/rss/api/"
    "?feed=raw_images&category=mars2020&feedtype=json&ver=1.2&order=sol+desc"
)

ALL_DATASETS = [
    "planet_profiles",
    "source_register",
    "map_layers",
    "themis_stamps",
    "telemetry_rollups",
    "perseverance_waypoints",
    "msl_waypoints",
    "mars_landmarks",
    "mineral_signatures",
    "perseverance_images",
]


def fetch_json(url: str, timeout: int = 25) -> dict[str, Any]:
    """Fetch JSON from a public NASA endpoint using a standard User-Agent."""
    req = urllib.request.Request(url, headers={"User-Agent": "ARES-Ingestion/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def build_planet_profiles() -> list[dict[str, Any]]:
    """Return multi-planet profile documents (Mars active)."""
    return [
        {
            "_id": "mars",
            "display_name": "Mars",
            "trek_body_id": "Mars",
            "crs": {
                "code": "IAU:49900",
                "proj4": "+proj=longlat +a=3396190 +b=3396190 +no_defs",
                "semi_major_m": 3396190.0,
                "semi_minor_m": 3396190.0,
            },
            "physics": {
                "gravity_ms2": 3.72076,
                "solar_day_seconds": 88775.244,
                "has_global_magnetic_field": False,
                "owlt_range_sec": [180, 1340],
            },
            "clock_model": {
                "day_unit_label": "SOL",
                "local_time_label": "LMST",
                "seasonal_metric": "ls_deg",
            },
            "safety_thresholds": {
                "wind_speed_ms": {"caution": 15.0, "hazard": 28.0},
                "radiation_dose_msv_day": {"caution": 1.5, "hazard": 10.0},
                "slope_deg": {"caution": 20.0, "hazard": 30.0},
                "max_staleness_sec": {"wind": 120, "radiation": 300, "plss": 10},
            },
        }
    ]


def build_source_register() -> list[dict[str, Any]]:
    """Return provenance and limitation records for all active Mars sources."""
    return [
        {
            "source_id": "themis_gale_csv",
            "body": "mars",
            "instrument": "Mars Odyssey THEMIS (IR/VIS)",
            "source_type": "csv_stamp_catalog",
            "spatial_limitation": {
                "note": "Point stamps represent image centers; surf_temp_k=0.0 treated as null/UNKNOWN.",
            },
        },
        {
            "source_id": "meda_sol100_csv",
            "body": "mars",
            "instrument": "Perseverance MEDA",
            "source_type": "telemetry_csv",
            "timebases": ["SCLK", "SOL", "LMST", "LTST"],
            "spatial_limitation": {
                "site": "Jezero Crater",
                "note": "Stationary Sol 100 telemetry; RDS is optical radiation, not ionizing GCR/SEP.",
            },
        },
        {
            "source_id": "mars_trek_wmts",
            "body": "mars",
            "instrument": "MOLA / CTX / HiRISE / HRSC",
            "source_type": "ogc_wmts",
            "base_url": "https://trek.nasa.gov/tiles/Mars/EQ/",
        },
        {
            "source_id": "mars2020_raw_images",
            "body": "mars",
            "instrument": "Perseverance Cameras (NAVCAM, MCZ, SUPERCAM, HAZCAM)",
            "source_type": "nasa_rss_json_api",
            "spatial_limitation": {
                "note": "Raw images include site/drive/xyz but no lat/lon; geotagged via join with mars2020_waypoints.",
            },
        },
        {
            "source_id": "mars2020_waypoints",
            "body": "mars",
            "instrument": "Perseverance Rover Localization",
            "source_type": "nasa_mmgis_geojson",
            "url": M20_WAYPOINTS_URL,
        },
    ]


def build_map_layers() -> list[dict[str, Any]]:
    """Return Mars Trek WMTS layer definitions for global Mars, Gale & Jezero."""
    return [
        {
            "layer_id": "mars_viking_red",
            "body": "mars",
            "region": "global",
            "category": "optical",
            "protocol": "WMTS_EQ",
            "url_template": "https://trek.nasa.gov/tiles/Mars/EQ/Mars_Viking_MDIM21_ClrMosaic_global_232m/1.0.0/default/default028mm/{z}/{y}/{x}.jpg",
            "tile_size_px": 256,
            "zoom_range": [0, 7],
            "resolution_m": 232.0,
            "bbox": [-180.0, -90.0, 180.0, 90.0],
        },
        {
            "layer_id": "mola_global_color",
            "body": "mars",
            "region": "global",
            "category": "topography",
            "protocol": "WMTS_EQ",
            "url_template": "https://trek.nasa.gov/tiles/Mars/EQ/Mars_MGS_MOLA_ClrShade_merge_global_463m/1.0.0/default/default028mm/{z}/{y}/{x}.jpg",
            "tile_size_px": 256,
            "zoom_range": [0, 7],
            "resolution_m": 463.0,
            "bbox": [-180.0, -90.0, 180.0, 90.0],
        },
        {
            "layer_id": "gale_ctx_optical",
            "body": "mars",
            "region": "Gale Crater",
            "category": "optical",
            "protocol": "WMTS_EQ",
            "url_template": "https://trek.nasa.gov/tiles/Mars/EQ/Gale_CTX_BlockAdj_dd/1.0.0/default/default028mm/{z}/{y}/{x}.png",
            "tile_size_px": 256,
            "zoom_range": [0, 12],
            "resolution_m": 5.5,
            "bbox": [135.1842593, -6.5732988, 139.2413012, -2.8077809],
        },
        {
            "layer_id": "gale_dem_1m",
            "body": "mars",
            "region": "Gale Crater",
            "category": "topography",
            "protocol": "WMTS_EQ",
            "url_template": "https://trek.nasa.gov/tiles/Mars/EQ/Gale_DEM_SMG_1m/1.0.0/default/default028mm/{z}/{y}/{x}.png",
            "tile_size_px": 256,
            "resolution_m": 1.0,
            "bbox": [137.1224711, -4.9254743, 137.7298129, -4.2489631],
        },
        {
            "layer_id": "jezero_hirise_25cm",
            "body": "mars",
            "region": "Jezero Crater",
            "category": "optical",
            "protocol": "WMTS_EQ",
            "url_template": "https://trek.nasa.gov/tiles/Mars/EQ/JEZ_hirise_soc_006_orthoMosaic_25cm_Eqc_latTs0_lon0_first_dd/1.0.0/default/default028mm/{z}/{y}/{x}.png",
            "tile_size_px": 256,
            "resolution_m": 0.25,
            "bbox": [77.2229331, 18.3067994, 77.583964, 18.669315],
        },
        {
            "layer_id": "jezero_dem_mosaic",
            "body": "mars",
            "region": "Jezero Crater",
            "category": "topography",
            "protocol": "WMTS_EQ",
            "url_template": "https://trek.nasa.gov/tiles/Mars/EQ/NES_JEZ_MID_DEM_Mosaic_HiRISE_CTX_HRSC_GCS_MARS_07-10-2018/1.0.0/default/default028mm/{z}/{y}/{x}.png",
            "tile_size_px": 256,
            "bbox": [76.7912656, 17.5791481, 77.7314457, 18.6926322],
        },
    ]


def build_themis_stamps() -> list[dict[str, Any]]:
    """Load Gale Crater THEMIS stamps from sample_data/themis_stamps.geojson."""
    path = SAMPLE_DIR / "themis_stamps.geojson"
    if not path.exists():
        print(f"[warn] {path} not found; skipping themis_stamps (run backend/extract_samples.py if you have raw data).")
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    docs: list[dict[str, Any]] = []
    for feat in data.get("features", []):
        props = feat.get("properties", {})
        file_id = props.get("file_id")
        if not file_id:
            continue
        docs.append(
            {
                "feature_id": f"themis_{file_id}",
                "body": "mars",
                "mission_id": "ares_gale_boxwork_01",
                "feature_type": "themis_stamp",
                "geometry": feat["geometry"],
                "properties": props,
                "provenance": {"source_id": "themis_gale_csv"},
            }
        )
    return docs


def build_telemetry_rollups() -> list[dict[str, Any]]:
    """Load 15-min Sol 100 MEDA telemetry rollups from sample_data/telemetry_15min_sol100.json."""
    path = SAMPLE_DIR / "telemetry_15min_sol100.json"
    if not path.exists():
        print(f"[warn] {path} not found; skipping telemetry_rollups (run backend/extract_samples.py if you have raw data).")
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    docs: list[dict[str, Any]] = []
    for rec in data.get("records", []):
        bucket_key = rec["lmst_bucket"]
        docs.append(
            {
                "body": "mars",
                "station_id": "jezero_meda_sol100",
                "lod": "15m",
                "bucket_key": bucket_key,
                "source_id": "meda_sol100_csv",
                **rec,
            }
        )
    return docs


def fetch_perseverance_waypoints() -> tuple[list[dict[str, Any]], dict[tuple[int, int], dict[str, Any]]]:
    """Fetch M20_waypoints.json and build spatial_features docs + (site, drive) lookup."""
    wp_data = fetch_json(M20_WAYPOINTS_URL)
    docs: list[dict[str, Any]] = []
    lookup: dict[tuple[int, int], dict[str, Any]] = {}
    for feat in wp_data.get("features", []):
        props = feat.get("properties", {})
        coords = feat.get("geometry", {}).get("coordinates", [])
        if len(coords) < 2:
            continue
        site = props.get("site")
        drive = props.get("drive")
        if site is not None and drive is not None:
            lookup[(int(site), int(drive))] = {
                "lon": float(coords[0]),
                "lat": float(coords[1]),
                "elev_geoid": props.get("elev_geoid"),
                "rmc": props.get("RMC"),
                "sol": props.get("sol"),
            }
        rmc = props.get("RMC") or f"{site}_{drive}"
        docs.append(
            {
                "feature_id": f"m20_wp_{rmc}",
                "body": "mars",
                "mission_id": "mars2020_jezero",
                "feature_type": "rover_waypoint",
                "geometry": {"type": "Point", "coordinates": [float(coords[0]), float(coords[1])]},
                "elevation_m": props.get("elev_geoid"),
                "properties": props,
                "provenance": {"source_id": "mars2020_waypoints", "rmc": rmc, "sol": props.get("sol")},
            }
        )
    return docs, lookup


def fetch_perseverance_images(
    limit: int,
    waypoint_lookup: dict[tuple[int, int], dict[str, Any]],
) -> list[dict[str, Any]]:
    """Fetch recent Mars 2020 raw images and geotag via (site, drive) waypoint lookup."""
    url = f"{M20_RAW_IMAGES_URL}&num={limit}&page=0"
    data = fetch_json(url)
    docs: list[dict[str, Any]] = []
    for img in data.get("images", []):
        site = img.get("site")
        drive = img.get("drive")
        geo = None
        if site is not None and drive is not None:
            wp = waypoint_lookup.get((int(site), int(drive)))
            if wp:
                geo = {"type": "Point", "coordinates": [wp["lon"], wp["lat"]]}
        docs.append(
            {
                "imageid": img["imageid"],
                "body": "mars",
                "mission_id": "mars2020_jezero",
                "sol": img.get("sol"),
                "site": int(site) if site is not None else None,
                "drive": int(drive) if drive is not None else None,
                "geometry": geo,
                "date_taken_mars": img.get("date_taken_mars"),
                "date_taken_utc": img.get("date_taken_utc"),
                "date_received": img.get("date_received"),
                "instrument": img.get("camera", {}).get("instrument"),
                "camera": img.get("camera"),
                "extended": img.get("extended"),
                "attitude": img.get("attitude"),
                "image_files": img.get("image_files"),
                "title": img.get("title"),
                "caption": img.get("caption"),
                "credit": img.get("credit"),
                "link": img.get("link"),
                "source_id": "mars2020_raw_images",
            }
        )
    return docs


def upsert_batch(collection, docs: list[dict[str, Any]], key_fields: list[str], dry_run: bool) -> int:
    """Upsert documents into a MongoDB collection using key_fields as the match filter."""
    if not docs or dry_run:
        return len(docs)
    ops = [
        UpdateOne({k: doc[k] for k in key_fields}, {"$set": doc}, upsert=True)
        for doc in docs
    ]
    collection.bulk_write(ops, ordered=False)
    return len(ops)


def ensure_indexes(db) -> None:
    """Create geospatial and uniqueness indexes matching ARES schema."""
    db["source_register"].create_index([("body", 1), ("source_id", 1)], unique=True)
    db["map_layers"].create_index([("body", 1), ("layer_id", 1)], unique=True)
    db["spatial_features"].create_index([("feature_id", 1)], unique=True)
    db["spatial_features"].create_index([("geometry", "2dsphere")])
    db["spatial_features"].create_index([("body", 1), ("feature_type", 1)])
    db["telemetry_rollups_lod"].create_index(
        [("body", 1), ("station_id", 1), ("lod", 1), ("bucket_key", 1)], unique=True
    )
    db["raw_images"].create_index([("imageid", 1)], unique=True)
    db["raw_images"].create_index([("geometry", "2dsphere")], sparse=True)
    db["raw_images"].create_index([("sol", -1), ("instrument", 1)])


def resolve_mongo_uri() -> str:
    """Resolve MONGO_URI from environment or build it from MONGO_USERNAME/MONGO_PASSWORD."""
    load_dotenv(REPO_ROOT / ".env")
    uri = os.getenv("MONGO_URI", "").strip()
    if not uri:
        raise RuntimeError("MONGO_URI is not set. Add it to .env (see .env.example).")
    if "<db_username>" in uri or "<db_password>" in uri:
        raise RuntimeError(
            "MONGO_URI still contains <db_username>/<db_password> placeholders. "
            "Replace them in .env before running without --dry-run."
        )
    return uri


def inspect_cluster(client: MongoClient) -> None:
    """List non-system databases, collections, document counts, and sample keys."""
    db_names = [d for d in client.list_database_names() if d not in ("admin", "local", "config")]
    if not db_names:
        print("No user databases found on cluster.")
        return
    for db_name in db_names:
        d = client[db_name]
        cols = d.list_collection_names()
        print(f"\n=== Database: {db_name} ({len(cols)} collections) ===")
        for col_name in sorted(cols):
            col = d[col_name]
            count = col.estimated_document_count()
            sample = col.find_one({}, {"_id": 0})
            keys = list(sample.keys()) if isinstance(sample, dict) else []
            print(f"  - {col_name}: ~{count} docs | sample keys: {keys}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Push ARES datasets to MongoDB Atlas.")
    parser.add_argument(
        "--inspect",
        action="store_true",
        help="List existing databases, collections, counts, and sample keys, then exit.",
    )
    parser.add_argument(
        "--datasets",
        default="all",
        help=f"Comma-separated list from: {', '.join(ALL_DATASETS)} or 'all'",
    )
    parser.add_argument(
        "--image-limit",
        type=int,
        default=100,
        help="Number of latest Perseverance raw images to fetch and push (default: 100).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Prepare all documents and print counts without connecting to MongoDB.",
    )
    args = parser.parse_args()

    if args.inspect:
        uri = resolve_mongo_uri()
        client = MongoClient(uri, serverSelectionTimeoutMS=15000)
        client.admin.command("ping")
        inspect_cluster(client)
        return

    selected = ALL_DATASETS if args.datasets == "all" else [s.strip() for s in args.datasets.split(",") if s.strip()]
    unknown = [s for s in selected if s not in ALL_DATASETS]
    if unknown:
        raise SystemExit(f"Unknown dataset(s): {unknown}. Valid choices: {ALL_DATASETS}")

    db = None
    if not args.dry_run:
        uri = resolve_mongo_uri()
        db_name = os.getenv("MONGO_DB", "ares_base")
        client = MongoClient(uri, serverSelectionTimeoutMS=15000)
        client.admin.command("ping")
        db = client[db_name]
        ensure_indexes(db)
        print(f"Connected to MongoDB database '{db_name}' and verified indexes.")

    waypoint_lookup: dict[tuple[int, int], dict[str, Any]] = {}

    if "planet_profiles" in selected:
        docs = build_planet_profiles()
        n = upsert_batch(db["planet_profiles"] if db is not None else None, docs, ["_id"], args.dry_run)
        print(f"[planet_profiles] prepared/upserted: {n}")

    if "source_register" in selected:
        docs = build_source_register()
        n = upsert_batch(db["source_register"] if db is not None else None, docs, ["body", "source_id"], args.dry_run)
        print(f"[source_register] prepared/upserted: {n}")

    if "map_layers" in selected:
        docs = build_map_layers()
        n = upsert_batch(db["map_layers"] if db is not None else None, docs, ["body", "layer_id"], args.dry_run)
        print(f"[map_layers] prepared/upserted: {n}")

    if "themis_stamps" in selected:
        docs = build_themis_stamps()
        n = upsert_batch(db["spatial_features"] if db is not None else None, docs, ["feature_id"], args.dry_run)
        print(f"[themis_stamps -> spatial_features] prepared/upserted: {n}")

    if "telemetry_rollups" in selected:
        docs = build_telemetry_rollups()
        n = upsert_batch(
            db["telemetry_rollups_lod"] if db is not None else None,
            docs,
            ["body", "station_id", "lod", "bucket_key"],
            args.dry_run,
        )
        print(f"[telemetry_rollups -> telemetry_rollups_lod] prepared/upserted: {n}")

    if "perseverance_waypoints" in selected or "perseverance_images" in selected:
        wp_docs, waypoint_lookup = fetch_perseverance_waypoints()
        if "perseverance_waypoints" in selected:
            n = upsert_batch(
                db["spatial_features"] if db is not None else None, wp_docs, ["feature_id"], args.dry_run
            )
            print(f"[perseverance_waypoints -> spatial_features] prepared/upserted: {n}")

    if "msl_waypoints" in selected:
        msl_data = fetch_json(MSL_WAYPOINTS_URL)
        msl_docs = []
        for feat in msl_data.get("features", []):
            props = feat.get("properties", {})
            coords = feat.get("geometry", {}).get("coordinates", [])
            if len(coords) < 2:
                continue
            rmc = props.get("RMC") or f"{props.get('site')}_{props.get('drive')}"
            msl_docs.append(
                {
                    "feature_id": f"msl_wp_{rmc}",
                    "body": "mars",
                    "mission_id": "msl_gale",
                    "feature_type": "msl_waypoint",
                    "geometry": {"type": "Point", "coordinates": [float(coords[0]), float(coords[1])]},
                    "elevation_m": props.get("elev_geoid"),
                    "properties": props,
                    "provenance": {"source_id": "msl_mmgis_waypoints", "rmc": rmc, "sol": props.get("sol")},
                }
            )
        n = upsert_batch(db["spatial_features"] if db is not None else None, msl_docs, ["feature_id"], args.dry_run)
        print(f"[msl_waypoints -> spatial_features] prepared/upserted: {n}")

    if "mars_landmarks" in selected:
        landmarks = [
            ("olympus_mons", "Olympus Mons", -133.8, 18.65, 21229, "Shield Volcano (tallest on Mars)"),
            ("valles_marineris", "Valles Marineris", -59.2, -13.9, -7000, "Tectonic Canyon System (>4,000 km)"),
            ("hellas_planitia", "Hellas Planitia", 70.0, -42.4, -7152, "Largest Impact Basin on Mars"),
            ("argyre_planitia", "Argyre Planitia", -43.9, -49.7, -5200, "Major Southern Impact Basin"),
            ("ascraeus_mons", "Ascraeus Mons", -104.1, 11.9, 18225, "Tharsis Montes Shield Volcano"),
            ("pavonis_mons", "Pavonis Mons", -112.9, 1.48, 14058, "Central Tharsis Montes Volcano"),
            ("arsia_mons", "Arsia Mons", -120.1, -8.26, 17761, "Southern Tharsis Montes Volcano"),
            ("elysium_mons", "Elysium Mons", 147.2, 25.02, 14028, "Elysium Volcanic Province Peak"),
            ("alba_mons", "Alba Mons", -109.9, 40.5, 6800, "Broadest Martian Shield Volcano"),
            ("syrtis_major", "Syrtis Major Planum", 67.9, 8.4, 0, "Dark Basaltic Volcanic Shield"),
            ("gale_curiosity", "Gale Crater / Mount Sharp (Curiosity)", 137.4416, -4.5895, -4501, "MSL Curiosity Landing Site & Boxwork Target"),
            ("jezero_perseverance", "Jezero Crater (Perseverance)", 77.4509, 18.4446, -2570, "Mars 2020 Perseverance Landing Site"),
            ("gusev_spirit", "Gusev Crater (Spirit)", 175.4726, -14.5684, -1900, "MER-A Spirit Landing Site (2004)"),
            ("meridiani_opportunity", "Meridiani Planum (Opportunity)", -5.5266, -1.9462, -1400, "MER-B Opportunity Landing Site (2004)"),
            ("chryse_viking1", "Chryse Planitia (Viking 1)", -47.9513, 22.27, -3600, "Viking 1 Lander Site (1976)"),
            ("utopia_viking2", "Utopia Planitia (Viking 2)", 134.29, 47.67, -4200, "Viking 2 Lander Site (1976)"),
            ("ares_pathfinder", "Ares Vallis (Mars Pathfinder)", -33.22, 19.13, -3680, "Pathfinder & Sojourner Site (1997)"),
            ("vastitas_phoenix", "Vastitas Borealis (Phoenix)", -125.7, 68.22, -4100, "Phoenix Polar Lander Site (2008)"),
            ("elysium_insight", "Elysium Planitia (InSight)", 135.6234, 4.5024, -2655, "InSight Seismic Lander Site (2018)"),
            ("utopia_zhurong", "Southern Utopia Planitia (Zhurong)", 109.925, 25.066, -4099, "Tianwen-1 Zhurong Rover Site (2021)"),
        ]
        lm_docs = [
            {
                "feature_id": f"landmark_{lid}",
                "body": "mars",
                "mission_id": "mars_global",
                "feature_type": "mars_landmark",
                "geometry": {"type": "Point", "coordinates": [lon, lat]},
                "elevation_m": elev,
                "properties": {"name": name, "description": desc, "lon_deg": lon, "lat_deg": lat},
                "provenance": {"source_id": "iau_nasa_landmarks"},
            }
            for lid, name, lon, lat, elev, desc in landmarks
        ]
        n = upsert_batch(db["spatial_features"] if db is not None else None, lm_docs, ["feature_id"], args.dry_run)
        print(f"[mars_landmarks -> spatial_features] prepared/upserted: {n}")

    if "mineral_signatures" in selected:
        minerals = [
            ("boxwork_ridge_a", "Mount Sharp Boxwork Ridge A", 137.3892, -4.8257, -3474, "Mg-Sulfate & Ca-Sulfate Veins", "Polygonal fracture-fill mineral ridges cemented by late groundwater"),
            ("boxwork_hollow_b", "Mount Sharp Boxwork Hollow B", 137.3945, -4.8310, -3460, "Hydrated Magnesium Sulfate", "Recessed inter-ridge hollow with high sulfate signature"),
            ("vera_rubin_ridge", "Vera Rubin Ridge (Hematite)", 137.3690, -4.7490, -4120, "Crystalline Hematite (Fe2O3)", "Erosion-resistant iron-oxide ridge mapped from CRISM & MSL"),
            ("glen_torridon_clay", "Glen Torridon Clay Trough", 137.3760, -4.7560, -4145, "Smectite Phyllosilicate Clay", "Clay-bearing unit indicating ancient neutral-pH lakebeds"),
            ("gediz_vallis_ridge", "Gediz Vallis Sulfate Channel", 137.3830, -4.7820, -3950, "Sulfur & Sulfate-Rich Debris", "Debris flow channel cutting into sulfate-bearing Mount Sharp strata"),
            ("murray_buttes", "Murray Buttes Sandstone", 137.3580, -4.7250, -4230, "Cross-Bedded Aeolian Sandstone", "Stimson formation sandstone capping mudstone layers"),
        ]
        min_docs = [
            {
                "feature_id": f"mineral_{mid}",
                "body": "mars",
                "mission_id": "ares_gale_boxwork_01",
                "feature_type": "mineral_signature",
                "geometry": {"type": "Point", "coordinates": [lon, lat]},
                "elevation_m": elev,
                "properties": {
                    "name": name,
                    "mineral_class": mclass,
                    "description": desc,
                    "lon_deg": lon,
                    "lat_deg": lat,
                },
                "provenance": {"source_id": "crism_msl_mineralogy"},
            }
            for mid, name, lon, lat, elev, mclass, desc in minerals
        ]
        n = upsert_batch(db["spatial_features"] if db is not None else None, min_docs, ["feature_id"], args.dry_run)
        print(f"[mineral_signatures -> spatial_features] prepared/upserted: {n}")

    if "perseverance_images" in selected:
        img_docs = fetch_perseverance_images(args.image_limit, waypoint_lookup)
        geotagged = sum(1 for d in img_docs if d["geometry"] is not None)
        n = upsert_batch(db["raw_images"] if db is not None else None, img_docs, ["imageid"], args.dry_run)
        print(f"[perseverance_images -> raw_images] prepared/upserted: {n} (geotagged via waypoints: {geotagged})")


if __name__ == "__main__":
    main()
