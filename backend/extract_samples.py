"""Extract aligned Gale Crater & Mount Sharp map imagery, matched THEMIS stamps, and Sol 100 telemetry.

Aligned to exact teammate bounding boxes (IAU:49900 / EPSG:4326):
- Mount Sharp: lon [137.2, 138.4], lat [-5.6, -4.6] (960x800, CTX z=10)
- Gale Crater: lon [136.1, 138.7], lat [-5.8, -3.2] (900x900, CTX z=9)
"""

from __future__ import annotations

import csv
import json
import math
import urllib.request
from collections import defaultdict
from pathlib import Path
from statistics import mean

REPO_ROOT = Path(__file__).resolve().parent.parent
RAW_CSV = Path(__file__).resolve().parent / "mars_site_complete_telemetry.csv"
THEMIS_CSV = REPO_ROOT / "Gale Crater.csv"
OUT_DIR = REPO_ROOT / "sample_data"

# Teammate-specified exact coordinate boxes: (lon_min, lat_min, lon_max, lat_max)
MOUNT_SHARP_BBOX = (137.2, -5.6, 138.4, -4.6)
GALE_BBOX = (136.1, -5.8, 138.7, -3.2)
USER_AGENT = "Mozilla/5.0 (ARES-Mars-Hackathon)"

USGS_WMS_BASE = (
    "https://planetarymaps.usgs.gov/cgi-bin/mapserv"
    "?map=/maps/mars/mars_simp_cyl.map"
)

WMS_LAYERS = {
    "themis_day_ir.png": "THEMIS_controlled",
    "themis_night_ir.png": "THEMIS_night",
    "mola_themis_blend.png": "MOLA_THEMIS_blend",
    "mola_color_topo.png": "MOLA_color",
    "mdim21_optical_color.png": "MDIM21_color",
}

GALE_LOCATIONS = [
    {
        "id": "bradbury_landing",
        "name": "Bradbury Landing (Curiosity Landing Site)",
        "lon_deg": 137.4417,
        "lat_deg": -4.5895,
        "category": "landing_site",
        "notes": "Aeolis Palus plains north of Mount Sharp (~4.59 S, 137.44 E).",
    },
    {
        "id": "vera_rubin_ridge",
        "name": "Vera Rubin Ridge (NW Mount Sharp Slope)",
        "lon_deg": 137.35,
        "lat_deg": -4.69,
        "category": "geologic_feature",
        "notes": "Lower northwest Mount Sharp ridge explored by Curiosity (~4.69 S, 137.35 E).",
    },
    {
        "id": "gale_crater_center",
        "name": "Gale Crater Center",
        "lon_deg": 137.8,
        "lat_deg": -5.4,
        "category": "landmark",
        "notes": "Central Gale Crater reference (~5.4 S, 137.8 E).",
    },
    {
        "id": "mount_sharp_summit",
        "name": "Aeolis Mons (Mount Sharp) Central Peak",
        "lon_deg": 137.85,
        "lat_deg": -5.08,
        "category": "landmark",
        "notes": "Central mound rising ~5.5 km above crater floor (~5.08 S, 137.85 E).",
    },
]

MOUNT_SHARP_LOCATIONS = [
    loc for loc in GALE_LOCATIONS
    if MOUNT_SHARP_BBOX[0] <= loc["lon_deg"] <= MOUNT_SHARP_BBOX[2]
    and MOUNT_SHARP_BBOX[1] <= loc["lat_deg"] <= MOUNT_SHARP_BBOX[3]
]


def fetch_bytes(url: str, timeout: int = 25) -> bytes:
    """Download URL bytes with a standard User-Agent header."""
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def download_usgs_wms_images(
    wms_dir: Path,
    bbox: tuple[float, float, float, float],
    width: int,
    rel_prefix: str = "images/wms",
) -> list[dict]:
    """Download pixel-aligned optical, thermal, and topographic PNGs for bbox."""
    wms_dir.mkdir(parents=True, exist_ok=True)
    # Remove any old stitched CTX image so sample_loader re-stitches to the new bbox
    for old_ctx in wms_dir.glob("ctx_optical_*.png"):
        old_ctx.unlink()

    lon_min, lat_min, lon_max, lat_max = bbox
    height = round(width * (lat_max - lat_min) / (lon_max - lon_min))
    bbox_str = f"{lon_min},{lat_min},{lon_max},{lat_max}"

    saved = []
    for filename, layer in WMS_LAYERS.items():
        url = (
            f"{USGS_WMS_BASE}&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap"
            f"&LAYERS={layer}&STYLES=&SRS=EPSG:4326"
            f"&BBOX={bbox_str}&WIDTH={width}&HEIGHT={height}&FORMAT=image/png"
        )
        data = fetch_bytes(url)
        (wms_dir / filename).write_bytes(data)
        saved.append({
            "file": f"{rel_prefix}/{filename}",
            "layer": layer,
            "source": "USGS Astrogeology Mars WMS",
            "width_px": width,
            "height_px": height,
            "bbox_lon_lat": list(bbox),
            "crs": "EPSG:4326 / IAU_2015:49900",
            "bytes": len(data),
        })
    return saved


def lonlat_to_eq_tile(lon: float, lat: float, z: int) -> tuple[int, int]:
    """Convert Equirectangular lon/lat to Mars Trek WMTS (row, col)."""
    cols = 2 * (2 ** z)
    rows = 1 * (2 ** z)
    col = int((lon + 180.0) / 360.0 * cols)
    row = int((90.0 - lat) / 180.0 * rows)
    return row, col


def eq_tile_bounds(row: int, col: int, z: int) -> list[float]:
    """Return [lon_min, lat_min, lon_max, lat_max] for a Mars Trek EQ tile."""
    cols = 2 * (2 ** z)
    rows = 1 * (2 ** z)
    lon_min = -180.0 + (col / cols) * 360.0
    lon_max = -180.0 + ((col + 1) / cols) * 360.0
    lat_max = 90.0 - (row / rows) * 180.0
    lat_min = 90.0 - ((row + 1) / rows) * 180.0
    return [round(lon_min, 6), round(lat_min, 6), round(lon_max, 6), round(lat_max, 6)]


def download_mars_trek_ctx_tiles(
    tile_dir: Path,
    bbox: tuple[float, float, float, float],
    z: int,
    rel_prefix: str,
) -> dict:
    """Download Gale Crater CTX optical tiles from NASA Mars Trek WMTS."""
    tile_dir.mkdir(parents=True, exist_ok=True)
    lon_min, lat_min, lon_max, lat_max = bbox
    row_min, col_min = lonlat_to_eq_tile(lon_min, lat_max, z)
    row_max, col_max = lonlat_to_eq_tile(lon_max, lat_min, z)

    tiles = []
    for row in range(row_min, row_max + 1):
        for col in range(col_min, col_max + 1):
            url = (
                "https://trek.nasa.gov/tiles/Mars/EQ/Gale_CTX_BlockAdj_dd/"
                f"1.0.0/default/default028mm/{z}/{row}/{col}.png"
            )
            fname = f"z{z}_r{row}_c{col}.png"
            fpath = tile_dir / fname
            data = fpath.read_bytes() if fpath.exists() else fetch_bytes(url)
            if not fpath.exists():
                fpath.write_bytes(data)
            tiles.append({
                "file": f"{rel_prefix}/{fname}",
                "z": z,
                "row": row,
                "col": col,
                "tile_px": 256,
                "bbox_lon_lat": eq_tile_bounds(row, col, z),
                "bytes": len(data),
            })

    return {
        "layer": "Gale_CTX_BlockAdj_dd",
        "source": "NASA Mars Trek WMTS",
        "crs": "IAU:49900 (Equirectangular 2:1)",
        "zoom": z,
        "tile_size_px": 256,
        "grid": {"row_min": row_min, "row_max": row_max, "col_min": col_min, "col_max": col_max},
        "tiles": tiles,
    }


def extract_themis_stamps_for_bbox(
    region_dir: Path,
    bbox: tuple[float, float, float, float],
) -> dict:
    """Filter and clean Gale Crater.csv THEMIS stamps to exact bbox coordinates."""
    lon_min, lat_min, lon_max, lat_max = bbox
    stamps = []
    features = []

    with THEMIS_CSV.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            lon = float(row["ct_lon"])
            lat = float(row["ct_lat"])
            if not (lon_min <= lon <= lon_max and lat_min <= lat <= lat_max):
                continue

            raw_temp = float(row["surf_temp_avg"])
            raw_alb = float(row["alb_avg"])
            temp_k = round(raw_temp, 3) if raw_temp > 0.0 else None
            temp_c = round(raw_temp - 273.15, 2) if raw_temp > 0.0 else None
            alb = round(raw_alb, 4) if raw_alb > 0.0 else None
            desc = " ".join(row["description"].split())
            has_desc = desc != "No Description Given" and desc != ""

            rec = {
                "file_id": row["file_id"],
                "frame_type": "IR" if row["file_id"].startswith("I") else "VIS",
                "lon_deg": round(lon, 6),
                "lat_deg": round(lat, 6),
                "surf_temp_k": temp_k,
                "surf_temp_c": temp_c,
                "alb_avg": alb,
                "bands": row["band_bin_band_number"],
                "description": desc,
                "has_description": has_desc,
                "temp_status": "OK" if temp_k is not None else "UNKNOWN",
            }
            stamps.append(rec)
            features.append({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [rec["lon_deg"], rec["lat_deg"]]},
                "properties": rec,
            })

    (region_dir / "themis_stamps.json").write_text(
        json.dumps({"bbox_lon_lat": list(bbox), "count": len(stamps), "stamps": stamps}, indent=2),
        encoding="utf-8",
    )
    (region_dir / "themis_stamps.geojson").write_text(
        json.dumps({"type": "FeatureCollection", "features": features}, indent=2),
        encoding="utf-8",
    )
    return {
        "count": len(stamps),
        "named_description_count": sum(1 for s in stamps if s["has_description"]),
        "json_file": "themis_stamps.json",
        "geojson_file": "themis_stamps.geojson",
    }


def parse_float(val: str) -> float | None:
    if not val:
        return None
    try:
        x = float(val)
        return x if math.isfinite(x) else None
    except ValueError:
        return None


def safe_mean(vals: list[float]) -> float | None:
    return round(mean(vals), 4) if vals else None


def safe_min(vals: list[float]) -> float | None:
    return round(min(vals), 4) if vals else None


def safe_max(vals: list[float]) -> float | None:
    return round(max(vals), 4) if vals else None


def extract_telemetry_samples(out_dir: Path) -> dict:
    """Clean and aggregate raw Sol 100 telemetry into 15-min buckets + raw sample rows."""
    buckets: dict[str, dict] = defaultdict(lambda: {
        "row_count": 0, "sclk": [], "ltst_first": None, "solar_zenith": [],
        "air_temp_c": [], "ground_temp_c": [], "ground_temp_unc_c": [],
        "tirs_air_temp_c": [], "down_lw_wm2": [], "up_lw_wm2": [], "up_sw_wm2": [],
        "pressure_baro1_pa": [], "pressure_baro2_pa": [],
        "humidity_a_pct": [], "humidity_a_unc_pct": [],
        "rds_top7_lg": [], "rds_top7_hg": [], "wind_b1_speed": [], "wind_b1_dir": [],
        "sun_in_tirs_fov_rows": 0, "ground_in_shadow_rows": 0,
    })

    raw_samples = []
    raw_sample_targets = {"00:00", "05:30", "12:00", "17:30", "22:30"}
    captured_per_target: dict[str, int] = defaultdict(int)

    with RAW_CSV.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames or []
        for row in reader:
            lmst = row["LMST"]
            hh = int(lmst[6:8])
            mm = int(lmst[9:11])
            bucket_key = f"00100M{hh:02d}:{(mm // 15) * 15:02d}"

            hm_key = f"{hh:02d}:{mm:02d}"
            if hm_key in raw_sample_targets and captured_per_target[hm_key] < 6:
                raw_samples.append(row)
                captured_per_target[hm_key] += 1

            b = buckets[bucket_key]
            b["row_count"] += 1
            if b["ltst_first"] is None:
                b["ltst_first"] = row["LTST"]

            if (sclk := parse_float(row["SCLK"])) is not None:
                b["sclk"].append(sclk)
            if (sza := parse_float(row["SOLAR_ZENITHAL_ANGLE"])) is not None:
                b["solar_zenith"].append(sza)

            for k in (
                "Air_Temp_ATS_LOCAL_TEMP1_C", "Air_Temp_ATS_LOCAL_TEMP2_C",
                "Air_Temp_ATS_LOCAL_TEMP3_C", "Air_Temp_ATS_LOCAL_TEMP4_C",
                "Air_Temp_ATS_LOCAL_TEMP5_C",
            ):
                if (t := parse_float(row[k])) is not None:
                    b["air_temp_c"].append(t)

            if parse_float(row["Ground_Sky_IR_Temp_SUN_OUTSIDE_TIRS_FOV"]) == 0.0:
                b["sun_in_tirs_fov_rows"] += 1
            if parse_float(row["Ground_Sky_IR_Temp_TIRS_GROUND_FOOTPRINT_NOT_IN_SHADOW"]) == 0.0:
                b["ground_in_shadow_rows"] += 1

            if (gt := parse_float(row["Ground_Sky_IR_Temp_GROUND_TEMP_C"])) is not None:
                b["ground_temp_c"].append(gt)
            if (gtu := parse_float(row["Ground_Sky_IR_Temp_GROUND_TEMP_UNCERTAINTY"])) is not None:
                b["ground_temp_unc_c"].append(gtu)
            if (tat := parse_float(row["Ground_Sky_IR_Temp_AIR_TEMP_C"])) is not None:
                b["tirs_air_temp_c"].append(tat)

            if (dlw := parse_float(row["Ground_Sky_IR_Temp_DOWNWARD_LW_IRRADIANCE"])) is not None:
                b["down_lw_wm2"].append(dlw)
            if (ulw := parse_float(row["Ground_Sky_IR_Temp_UPWARD_LW_IRRADIANCE"])) is not None:
                b["up_lw_wm2"].append(ulw)
            if (usw := parse_float(row["Ground_Sky_IR_Temp_UPWARD_SW_IRRADIANCE"])) is not None:
                b["up_sw_wm2"].append(usw)

            if (p1 := parse_float(row["Pressure_BAROCAP1_PRESSURE"])) is not None:
                b["pressure_baro1_pa"].append(p1)
            if (p2 := parse_float(row["Pressure_BAROCAP2_PRESSURE"])) is not None:
                b["pressure_baro2_pa"].append(p2)

            if (ha := parse_float(row["Humidity_HUMICAP_A_HUMIDITY"])) is not None:
                b["humidity_a_pct"].append(ha)
            if (hau := parse_float(row["Humidity_HUMICAP_A_HUMIDITY_UNCERTAINTY"])) is not None:
                b["humidity_a_unc_pct"].append(hau)

            if (r7 := parse_float(row["Radiation_Dust_RDS_TOP_7"])) is not None:
                b["rds_top7_lg"].append(r7)
            if (r7h := parse_float(row["Radiation_Dust_RDS_TOP_7_HG"])) is not None:
                b["rds_top7_hg"].append(r7h)

            if parse_float(row["Wind_BOOM1_ALG_STATE_STABLE"]) == 1.0:
                if (ws := parse_float(row["Wind_BOOM1_HORIZONTAL_WIND_SPEED"])) is not None:
                    b["wind_b1_speed"].append(ws)
                if (wd := parse_float(row["Wind_BOOM1_WIND_DIRECTION"])) is not None:
                    b["wind_b1_dir"].append(wd)

    records = []
    for key in sorted(buckets):
        b = buckets[key]
        n = b["row_count"]
        wind_cov = round(len(b["wind_b1_speed"]) / n, 3) if n else 0.0
        wind_max = safe_max(b["wind_b1_speed"])

        flags = ["pressure_uncertainty_unreported", "ionizing_rad_not_in_dataset"]
        if wind_cov == 0:
            flags.append("wind_offline")
        elif wind_cov < 0.5:
            flags.append("wind_partial_coverage")
        if b["sun_in_tirs_fov_rows"] > 0:
            flags.append("tirs_sun_in_fov_partial")
        if b["ground_in_shadow_rows"] > 0:
            flags.append("tirs_target_shadowed_partial")
        if not b["humidity_a_unc_pct"]:
            flags.append("humidity_uncertainty_unreported")

        if wind_cov == 0:
            safety_state = "UNKNOWN_HOLD"
        elif (wind_max is not None and wind_max > 15.0) or wind_cov < 0.5:
            safety_state = "CAUTION"
        else:
            safety_state = "NOMINAL"

        rds_mode = "LOW_GAIN" if b["rds_top7_lg"] else ("HIGH_GAIN" if b["rds_top7_hg"] else "MISSING")
        rds_val = safe_mean(b["rds_top7_lg"]) if b["rds_top7_lg"] else safe_mean(b["rds_top7_hg"])

        records.append({
            "lmst_bucket": key,
            "ltst_start": b["ltst_first"],
            "sclk_start": min(b["sclk"]) if b["sclk"] else None,
            "sclk_end": max(b["sclk"]) if b["sclk"] else None,
            "raw_samples_in_bucket": n,
            "solar_zenith_deg_mean": safe_mean(b["solar_zenith"]),
            "air_temp_c_mean": safe_mean(b["air_temp_c"]),
            "air_temp_c_min": safe_min(b["air_temp_c"]),
            "air_temp_c_max": safe_max(b["air_temp_c"]),
            "ground_ir_temp_c_mean": safe_mean(b["ground_temp_c"]),
            "ground_ir_temp_c_min": safe_min(b["ground_temp_c"]),
            "ground_ir_temp_c_max": safe_max(b["ground_temp_c"]),
            "ground_ir_temp_unc_c_mean": safe_mean(b["ground_temp_unc_c"]),
            "downward_lw_irradiance_wm2_mean": safe_mean(b["down_lw_wm2"]),
            "upward_lw_irradiance_wm2_mean": safe_mean(b["up_lw_wm2"]),
            "upward_sw_irradiance_wm2_mean": safe_mean(b["up_sw_wm2"]),
            "pressure_barocap1_pa_mean": safe_mean(b["pressure_baro1_pa"]),
            "pressure_barocap2_pa_mean": safe_mean(b["pressure_baro2_pa"]),
            "humidity_a_pct_mean": safe_mean(b["humidity_a_pct"]),
            "humidity_a_unc_pct_mean": safe_mean(b["humidity_a_unc_pct"]),
            "optical_rds_top7_mean": rds_val,
            "optical_rds_mode": rds_mode,
            "wind_boom1_speed_ms_mean": safe_mean(b["wind_b1_speed"]),
            "wind_boom1_speed_ms_max": wind_max,
            "wind_boom1_dir_deg_mean": safe_mean(b["wind_b1_dir"]),
            "wind_valid_fraction": wind_cov,
            "safety_state": safety_state,
            "quality_and_unknown_flags": "|".join(flags),
        })

    csv_out = out_dir / "telemetry_15min_sol100.csv"
    with csv_out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(records[0].keys()))
        writer.writeheader()
        writer.writerows(records)

    (out_dir / "telemetry_15min_sol100.json").write_text(
        json.dumps({
            "source_file": "backend/mars_site_complete_telemetry.csv",
            "note": "Stationary Sol 100 MEDA telemetry (103,011 rows -> 63 buckets; fixes -273.15 uncertainty bug).",
            "bucket_count": len(records),
            "records": records,
        }, indent=2),
        encoding="utf-8",
    )

    with (out_dir / "telemetry_raw_sample.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(raw_samples)

    return {
        "bucket_count": len(records),
        "raw_sample_rows": len(raw_samples),
        "files": ["telemetry_15min_sol100.csv", "telemetry_15min_sol100.json", "telemetry_raw_sample.csv"],
    }


def extract_region(
    region_name: str,
    region_dir: Path,
    bbox: tuple[float, float, float, float],
    width_px: int,
    ctx_zoom: int,
    locations: list[dict],
    bundle_filename: str,
    tel_info: dict,
) -> None:
    """Download WMS + CTX tiles, filter THEMIS stamps, and write spatial bundle."""
    region_dir.mkdir(parents=True, exist_ok=True)
    wms_info = download_usgs_wms_images(region_dir / "images" / "wms", bbox, width=width_px)
    ctx_rel = f"images/mars_trek_ctx_z{ctx_zoom}"
    ctx_info = download_mars_trek_ctx_tiles(region_dir / ctx_rel, bbox, ctx_zoom, rel_prefix=ctx_rel)
    stamps_info = extract_themis_stamps_for_bbox(region_dir, bbox)

    bundle = {
        "region": region_name,
        "bbox_lon_lat": list(bbox),
        "crs": "IAU:49900 / EPSG:4326 (Equirectangular)",
        "wms_aligned_layers": wms_info,
        "mars_trek_ctx_tiles": ctx_info,
        "themis_stamps": stamps_info,
        "telemetry_summary": tel_info,
        "reference_locations": locations,
    }
    (region_dir / bundle_filename).write_text(json.dumps(bundle, indent=2), encoding="utf-8")
    print(
        f"[{region_name}] {len(wms_info)} WMS ({wms_info[0]['width_px']}x{wms_info[0]['height_px']}), "
        f"{len(ctx_info['tiles'])} CTX z{ctx_zoom} tiles, "
        f"{stamps_info['count']} THEMIS stamps ({stamps_info['named_description_count']} named)"
    )


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tel_info = extract_telemetry_samples(OUT_DIR)
    extract_region(
        "Gale Crater (Overview)",
        OUT_DIR,
        GALE_BBOX,
        width_px=900,
        ctx_zoom=9,
        locations=GALE_LOCATIONS,
        bundle_filename="gale_spatial_bundle.json",
        tel_info=tel_info,
    )
    extract_region(
        "Mount Sharp / Aeolis Mons",
        OUT_DIR / "mount_sharp",
        MOUNT_SHARP_BBOX,
        width_px=960,
        ctx_zoom=10,
        locations=MOUNT_SHARP_LOCATIONS,
        bundle_filename="mount_sharp_spatial_bundle.json",
        tel_info=tel_info,
    )


if __name__ == "__main__":
    main()
