"""Push ARES datasets to Supabase Storage (compressed + JSON) and Postgres tables.

Usage:
  1. Ensure SUPABASE_URL and SUPABASE_SECRET_KEY are set in .env.
  2. Upload datasets to Supabase Storage bucket (`ares-mars-data`):
       python backend/push_to_supabase.py --mode storage
  3. After running `backend/supabase_schema.sql` in Supabase SQL Editor, upsert rows:
       python backend/push_to_supabase.py --mode tables
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from app.db import REPO_ROOT, _load_env_file, get_db

BUCKET_NAME = "ares-mars-data"
SAMPLE_DIR = REPO_ROOT / "sample_data"
RAW_TELEMETRY_CSV = REPO_ROOT / "backend" / "mars_site_complete_telemetry.csv"


def _supa_cfg() -> tuple[str, str]:
    _load_env_file(REPO_ROOT / ".env")
    url = os.getenv("SUPABASE_URL", "").strip().rstrip("/")
    key = os.getenv("SUPABASE_SECRET_KEY", "").strip()
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SECRET_KEY must be set in .env")
    return url, key


def _request(method: str, url: str, key: str, data: bytes | None = None, content_type: str = "application/json", extra_headers: dict[str, str] | None = None) -> tuple[int, bytes]:
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": content_type,
    }
    if extra_headers:
        headers.update(extra_headers)
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def ensure_bucket(url: str, key: str, bucket: str = BUCKET_NAME) -> None:
    status, body = _request("GET", f"{url}/storage/v1/bucket/{bucket}", key)
    if status == 200:
        return
    payload = json.dumps({"id": bucket, "name": bucket, "public": True}).encode("utf-8")
    c_status, c_body = _request("POST", f"{url}/storage/v1/bucket", key, data=payload)
    if c_status not in (200, 201):
        raise RuntimeError(f"Failed to create bucket '{bucket}': HTTP {c_status} {c_body.decode('utf-8', errors='ignore')}")


def upload_bytes(url: str, key: str, object_path: str, data: bytes, content_type: str) -> int:
    endpoint = f"{url}/storage/v1/object/{BUCKET_NAME}/{object_path}"
    status, body = _request(
        "POST",
        endpoint,
        key,
        data=data,
        content_type=content_type,
        extra_headers={"x-upsert": "true"},
    )
    if status not in (200, 201):
        raise RuntimeError(f"Upload failed for {object_path}: HTTP {status} {body.decode('utf-8', errors='ignore')}")
    return len(data)


def push_storage(url: str, key: str) -> None:
    ensure_bucket(url, key, BUCKET_NAME)
    db = get_db()

    # Export collections from live MongoDB ares_base so both DBs stay 100% in sync
    collections = {
        "planet_profiles": list(db["planet_profiles"].find({})),
        "source_register": list(db["source_register"].find({}, {"_id": 0})),
        "map_layers": list(db["map_layers"].find({}, {"_id": 0})),
        "spatial_features": list(db["spatial_features"].find({}, {"_id": 0})),
        "telemetry_rollups_lod": list(db["telemetry_rollups_lod"].find({}, {"_id": 0})),
        "raw_images": list(db["raw_images"].find({}, {"_id": 0})),
    }

    total_uploaded = 0
    for name, docs in collections.items():
        raw_json = json.dumps(docs).encode("utf-8")
        gz_json = gzip.compress(raw_json, compresslevel=9)
        n1 = upload_bytes(url, key, f"datasets/{name}.json", raw_json, "application/json")
        n2 = upload_bytes(url, key, f"datasets/{name}.json.gz", gz_json, "application/gzip")
        total_uploaded += n1 + n2
        print(f"[storage] {name}: {len(docs)} docs | json={n1:,} B | gz={n2:,} B")

    # Compress and upload the 61.8 MB Sol-100 raw MEDA CSV as .csv.gz
    if RAW_TELEMETRY_CSV.exists():
        gz_csv = gzip.compress(RAW_TELEMETRY_CSV.read_bytes(), compresslevel=9)
        n_csv = upload_bytes(url, key, "raw/mars_site_complete_telemetry.csv.gz", gz_csv, "application/gzip")
        total_uploaded += n_csv
        print(f"[storage] mars_site_complete_telemetry.csv.gz: {n_csv:,} B (compressed from {RAW_TELEMETRY_CSV.stat().st_size:,} B)")

    # Upload sample Mount Sharp & Gale preview images
    for img_path in sorted((SAMPLE_DIR / "images").glob("*.png")) if (SAMPLE_DIR / "images").exists() else []:
        n_img = upload_bytes(url, key, f"previews/{img_path.name}", img_path.read_bytes(), "image/png")
        total_uploaded += n_img
        print(f"[storage] previews/{img_path.name}: {n_img:,} B")

    print(f"Supabase Storage upload complete -> bucket '{BUCKET_NAME}' ({total_uploaded / (1024 * 1024):.2f} MB total).")


def upsert_table(url: str, key: str, table: str, rows: list[dict[str, Any]], batch_size: int = 250) -> int:
    for i in range(0, len(rows), batch_size):
        chunk = rows[i : i + batch_size]
        status, body = _request(
            "POST",
            f"{url}/rest/v1/{table}",
            key,
            data=json.dumps(chunk).encode("utf-8"),
            content_type="application/json",
            extra_headers={"Prefer": "resolution=merge-duplicates,return=minimal"},
        )
        if status not in (200, 201, 204):
            msg = body.decode("utf-8", errors="ignore")
            raise RuntimeError(
                f"Table upsert failed for '{table}': HTTP {status} {msg}. "
                f"Did you run backend/supabase_schema.sql in the Supabase SQL Editor?"
            )
    return len(rows)


def push_tables(url: str, key: str) -> None:
    db = get_db()

    pp_rows = [
        {
            "id": d["_id"],
            "display_name": d.get("display_name"),
            "trek_body_id": d.get("trek_body_id"),
            "crs": d.get("crs"),
            "physics": d.get("physics"),
            "clock_model": d.get("clock_model"),
            "safety_thresholds": d.get("safety_thresholds"),
        }
        for d in db["planet_profiles"].find({})
    ]
    print(f"[tables] planet_profiles: {upsert_table(url, key, 'planet_profiles', pp_rows)}")

    ml_rows = [
        {
            "layer_id": d["layer_id"],
            "body": d.get("body", "mars"),
            "region": d.get("region"),
            "category": d.get("category"),
            "protocol": d.get("protocol"),
            "url_template": d["url_template"],
            "tile_size_px": d.get("tile_size_px"),
            "zoom_range": d.get("zoom_range"),
            "resolution_m": d.get("resolution_m"),
            "bbox": d.get("bbox"),
        }
        for d in db["map_layers"].find({}, {"_id": 0})
    ]
    print(f"[tables] map_layers: {upsert_table(url, key, 'map_layers', ml_rows)}")

    sf_rows = [
        {
            "feature_id": d["feature_id"],
            "body": d.get("body", "mars"),
            "mission_id": d.get("mission_id"),
            "feature_type": d["feature_type"],
            "lon": d["geometry"]["coordinates"][0],
            "lat": d["geometry"]["coordinates"][1],
            "elevation_m": d.get("elevation_m"),
            "geometry": d["geometry"],
            "properties": d.get("properties", {}),
            "provenance": d.get("provenance"),
        }
        for d in db["spatial_features"].find({}, {"_id": 0})
    ]
    print(f"[tables] spatial_features: {upsert_table(url, key, 'spatial_features', sf_rows)}")

    tr_rows = [
        {
            "id": f"{d['body']}_{d['station_id']}_{d['lod']}_{d['bucket_key']}",
            "body": d["body"],
            "station_id": d["station_id"],
            "lod": d["lod"],
            "bucket_key": d["bucket_key"],
            "lmst_bucket": d["lmst_bucket"],
            "ltst_start": d.get("ltst_start"),
            "sclk_start": d.get("sclk_start"),
            "sclk_end": d.get("sclk_end"),
            "raw_samples_in_bucket": d.get("raw_samples_in_bucket"),
            "solar_zenith_deg_mean": d.get("solar_zenith_deg_mean"),
            "air_temp_c_mean": d.get("air_temp_c_mean"),
            "ground_ir_temp_c_mean": d.get("ground_ir_temp_c_mean"),
            "pressure_barocap1_pa_mean": d.get("pressure_barocap1_pa_mean"),
            "humidity_a_pct_mean": d.get("humidity_a_pct_mean"),
            "optical_rds_top7_mean": d.get("optical_rds_top7_mean"),
            "safety_state": d.get("safety_state"),
            "payload": d,
        }
        for d in db["telemetry_rollups_lod"].find({}, {"_id": 0})
    ]
    print(f"[tables] telemetry_rollups_lod: {upsert_table(url, key, 'telemetry_rollups_lod', tr_rows)}")

    img_rows = [
        {
            "imageid": d["imageid"],
            "body": d.get("body", "mars"),
            "mission_id": d.get("mission_id"),
            "sol": d.get("sol"),
            "site": d.get("site"),
            "drive": d.get("drive"),
            "instrument": d.get("instrument"),
            "lon": d["geometry"]["coordinates"][0] if d.get("geometry") else None,
            "lat": d["geometry"]["coordinates"][1] if d.get("geometry") else None,
            "date_taken_mars": d.get("date_taken_mars"),
            "date_taken_utc": d.get("date_taken_utc"),
            "image_files": d.get("image_files", {}),
            "camera": d.get("camera"),
            "extended": d.get("extended"),
        }
        for d in db["raw_images"].find({}, {"_id": 0})
    ]
    print(f"[tables] raw_images: {upsert_table(url, key, 'raw_images', img_rows)}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Push ARES datasets to Supabase.")
    parser.add_argument("--mode", choices=["storage", "tables", "all"], default="storage")
    args = parser.parse_args()
    url, key = _supa_cfg()
    if args.mode in ("storage", "all"):
        push_storage(url, key)
    if args.mode in ("tables", "all"):
        push_tables(url, key)


if __name__ == "__main__":
    main()
