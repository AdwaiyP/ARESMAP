"""Shared loader and rendering helpers for Gale Crater and Mount Sharp sample data."""

from __future__ import annotations

import csv
import io
import json
import math
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parent.parent
SAMPLE_DIR = REPO_ROOT / "sample_data"
MARS_RADIUS_KM = 3396.19

REGIONS = {
    "Mount Sharp (Zoomed)": {
        "dir": SAMPLE_DIR / "mount_sharp",
        "bundle": "mount_sharp_spatial_bundle.json",
        "ctx_filename": "ctx_optical_mount_sharp.png",
    },
    "Gale Crater (Overview)": {
        "dir": SAMPLE_DIR,
        "bundle": "gale_spatial_bundle.json",
        "ctx_filename": "ctx_optical_gale.png",
    },
}

LAYER_SPECS = [
    ("ctx", "Mars Trek CTX Optical", "NASA Mars Trek (Gale_CTX_BlockAdj_dd)"),
    ("themis_day_ir.png", "THEMIS Day IR (Thermal)", "USGS WMS (THEMIS_controlled)"),
    ("themis_night_ir.png", "THEMIS Night IR (Thermal Inertia)", "USGS WMS (THEMIS_night)"),
    ("mola_themis_blend.png", "MOLA + THEMIS Blend", "USGS WMS (MOLA_THEMIS_blend)"),
    ("mola_color_topo.png", "MOLA Color Topography", "USGS WMS (MOLA_color)"),
    ("mdim21_optical_color.png", "Viking MDIM21 Optical Color", "USGS WMS (MDIM21_color)"),
]

LAYER_NAMES = [label for _, label, _ in LAYER_SPECS]
STAMP_MODES = ["Named Descriptions Only", "All Stamps", "Off"]


def _resolve_layer(region: str, layer_name: str) -> tuple[Path, str]:
    """Return (image_path, source_label) for a given region and display layer name."""
    reg = REGIONS[region]
    wms_dir = reg["dir"] / "images" / "wms"
    for key, label, src in LAYER_SPECS:
        if label == layer_name:
            fname = reg["ctx_filename"] if key == "ctx" else key
            return wms_dir / fname, src
    return wms_dir / reg["ctx_filename"], LAYER_SPECS[0][2]


def load_bundle(region: str = "Mount Sharp (Zoomed)") -> dict:
    """Load spatial manifest and reference locations for the selected region."""
    reg = REGIONS[region]
    return json.loads((reg["dir"] / reg["bundle"]).read_text(encoding="utf-8"))


def load_themis_stamps(region: str = "Mount Sharp (Zoomed)") -> list[dict]:
    """Load coordinate-matched THEMIS stamp records for the selected region."""
    reg = REGIONS[region]
    data = json.loads((reg["dir"] / "themis_stamps.json").read_text(encoding="utf-8"))
    return data["stamps"]


def mars_distance_km(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
    """Approximate surface distance in km between two Martian coordinates."""
    lat1_r, lat2_r = math.radians(lat1), math.radians(lat2)
    dlat = lat2_r - lat1_r
    dlon = math.radians(lon2 - lon1) * math.cos(0.5 * (lat1_r + lat2_r))
    return round(MARS_RADIUS_KM * math.hypot(dlat, dlon), 3)


def find_nearest_stamps(
    region: str,
    lon: float,
    lat: float,
    only_named: bool = False,
    limit: int = 5,
) -> list[dict]:
    """Return nearest THEMIS stamps to (lon, lat) sorted by surface distance."""
    stamps = load_themis_stamps(region)
    if only_named:
        stamps = [s for s in stamps if s["has_description"]]
    ranked = []
    for s in stamps:
        dist = mars_distance_km(lon, lat, s["lon_deg"], s["lat_deg"])
        ranked.append({**s, "distance_km": dist})
    ranked.sort(key=lambda x: x["distance_km"])
    return ranked[:limit]


def _parse_opt_float(value: str) -> float | None:
    if not value:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def load_telemetry_15min() -> list[dict]:
    """Load cleaned 15-minute Sol 100 telemetry records without pandas."""
    rows: list[dict] = []
    numeric_cols = {
        "sclk_start", "sclk_end", "raw_samples_in_bucket", "solar_zenith_deg_mean",
        "air_temp_c_mean", "air_temp_c_min", "air_temp_c_max",
        "ground_ir_temp_c_mean", "ground_ir_temp_c_min", "ground_ir_temp_c_max",
        "ground_ir_temp_unc_c_mean", "downward_lw_irradiance_wm2_mean",
        "upward_lw_irradiance_wm2_mean", "upward_sw_irradiance_wm2_mean",
        "pressure_barocap1_pa_mean", "pressure_barocap2_pa_mean",
        "humidity_a_pct_mean", "humidity_a_unc_pct_mean", "optical_rds_top7_mean",
        "wind_boom1_speed_ms_mean", "wind_boom1_speed_ms_max",
        "wind_boom1_dir_deg_mean", "wind_valid_fraction",
    }
    with (SAMPLE_DIR / "telemetry_15min_sol100.csv").open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            rows.append({k: (_parse_opt_float(v) if k in numeric_cols else v) for k, v in row.items()})
    return rows


def ensure_stitched_ctx(region: str = "Mount Sharp (Zoomed)") -> Path:
    """Stitch Mars Trek CTX tiles for a region and crop to its shared WMS bbox."""
    reg = REGIONS[region]
    reg_dir = reg["dir"]
    out_path = reg_dir / "images" / "wms" / reg["ctx_filename"]
    if out_path.exists():
        return out_path

    bundle = load_bundle(region)
    ctx = bundle["mars_trek_ctx_tiles"]
    grid = ctx["grid"]
    z = ctx["zoom"]
    tile_px = ctx["tile_size_px"]
    r_min, r_max = grid["row_min"], grid["row_max"]
    c_min, c_max = grid["col_min"], grid["col_max"]

    canvas = Image.new("RGBA", ((c_max - c_min + 1) * tile_px, (r_max - r_min + 1) * tile_px))
    for t in ctx["tiles"]:
        tile_img = Image.open(reg_dir / t["file"]).convert("RGBA")
        x = (t["col"] - c_min) * tile_px
        y = (t["row"] - r_min) * tile_px
        canvas.paste(tile_img, (x, y))

    cols = 2 * (2 ** z)
    rows = 1 * (2 ** z)
    grid_lon_min = -180.0 + (c_min / cols) * 360.0
    grid_lon_max = -180.0 + ((c_max + 1) / cols) * 360.0
    grid_lat_max = 90.0 - (r_min / rows) * 180.0
    grid_lat_min = 90.0 - ((r_max + 1) / rows) * 180.0

    lon_min, lat_min, lon_max, lat_max = bundle["bbox_lon_lat"]
    w, h = canvas.size
    left = round((lon_min - grid_lon_min) / (grid_lon_max - grid_lon_min) * w)
    right = round((lon_max - grid_lon_min) / (grid_lon_max - grid_lon_min) * w)
    top = round((grid_lat_max - lat_max) / (grid_lat_max - grid_lat_min) * h)
    bottom = round((grid_lat_max - lat_min) / (grid_lat_max - grid_lat_min) * h)

    target_w = bundle["wms_aligned_layers"][0]["width_px"]
    target_h = bundle["wms_aligned_layers"][0]["height_px"]
    cropped = canvas.crop((left, top, right, bottom)).resize((target_w, target_h), Image.Resampling.LANCZOS)
    cropped.save(out_path)
    return out_path


def lonlat_to_pixel(lon: float, lat: float, bbox: list[float], width: int, height: int) -> tuple[int, int]:
    """Map equirectangular lon/lat to image pixel coordinates."""
    lon_min, lat_min, lon_max, lat_max = bbox
    px = round((lon - lon_min) / (lon_max - lon_min) * width)
    py = round((lat_max - lat) / (lat_max - lat_min) * height)
    return px, py


def pixel_to_lonlat(px: int, py: int, bbox: list[float], width: int, height: int) -> tuple[float, float]:
    """Map image pixel coordinates back to equirectangular Martian lon/lat."""
    lon_min, lat_min, lon_max, lat_max = bbox
    lon = lon_min + (px / width) * (lon_max - lon_min)
    lat = lat_max - (py / height) * (lat_max - lat_min)
    return round(lon, 4), round(lat, 4)


def _draw_pill_label(draw: ImageDraw.ImageDraw, px: int, py: int, text: str, width: int, bg=(12, 16, 22, 205)) -> None:
    """Draw a compact, clamped text badge near (px, py)."""
    lx = min(px + 10, max(6, width - len(text) * 6 - 10))
    draw.rectangle((lx, py - 9, lx + 4 + len(text) * 6, py + 7), fill=bg)
    draw.text((lx + 2, py - 7), text, fill=(255, 255, 255, 255))


def composite_map_image(
    region: str,
    base_layer: str,
    overlay_layer: str = "None",
    overlay_opacity: int = 40,
    show_landmarks: bool = True,
    stamp_mode: str = "Named Descriptions Only",
    show_stamp_labels: bool = False,
) -> Image.Image:
    """Blend base + overlay, draw THEMIS coordinate pins/descriptions, and plot landmarks."""
    bundle = load_bundle(region)
    ensure_stitched_ctx(region)

    base_path, _ = _resolve_layer(region, base_layer)
    img = Image.open(base_path).convert("RGBA")

    if overlay_layer != "None" and overlay_layer in LAYER_NAMES and overlay_opacity > 0:
        ov_path, _ = _resolve_layer(region, overlay_layer)
        ov = Image.open(ov_path).convert("RGBA").resize(img.size, Image.Resampling.BILINEAR)
        alpha = max(0.0, min(1.0, overlay_opacity / 100.0))
        img = Image.blend(img, ov, alpha)

    draw = ImageDraw.Draw(img)
    bbox = bundle["bbox_lon_lat"]
    w, h = img.size

    if stamp_mode != "Off":
        stamps = load_themis_stamps(region)
        for s in stamps:
            if stamp_mode == "Named Descriptions Only" and not s["has_description"]:
                continue
            px, py = lonlat_to_pixel(s["lon_deg"], s["lat_deg"], bbox, w, h)
            if s["has_description"]:
                color = (0, 229, 255, 235) if s["frame_type"] == "IR" else (167, 139, 250, 235)
                r = 5
                draw.ellipse((px - r, py - r, px + r, py + r), fill=color, outline=(255, 255, 255, 255), width=1)
                if show_stamp_labels:
                    short_desc = s["description"][:26] + ("…" if len(s["description"]) > 26 else "")
                    _draw_pill_label(draw, px, py, f"{s['file_id']}: {short_desc}", w, bg=(8, 32, 46, 210))
            else:
                r = 3
                draw.ellipse((px - r, py - r, px + r, py + r), fill=(148, 163, 184, 150))

    if show_landmarks:
        for loc in bundle["reference_locations"]:
            px, py = lonlat_to_pixel(loc["lon_deg"], loc["lat_deg"], bbox, w, h)
            r = 8
            draw.ellipse((px - r, py - r, px + r, py + r), fill=(255, 152, 0, 235), outline=(255, 255, 255, 255), width=2)
            label = f"{loc['name'].split(' (')[0]} ({loc['lat_deg']:.2f}N, {loc['lon_deg']:.2f}E)"
            _draw_pill_label(draw, px, py, label, w)

    return img.convert("RGB")


def build_diurnal_figure(records: list[dict], selected_lmst: str | None = None) -> plt.Figure:
    """Render a 2-panel dark-mode diurnal plot of thermal, optical, and wind data."""
    hours = [int(r["lmst_bucket"][6:8]) + int(r["lmst_bucket"][9:11]) / 60.0 for r in records]
    air_t = [r["air_temp_c_mean"] for r in records]
    gnd_t = [r["ground_ir_temp_c_mean"] for r in records]
    rds = [r["optical_rds_top7_mean"] for r in records]
    wind = [r["wind_boom1_speed_ms_mean"] for r in records]

    plt.style.use("dark_background")
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(8.5, 5.2), sharex=True, dpi=110)
    fig.patch.set_facecolor("#0f141b")
    for ax in (ax1, ax2):
        ax.set_facecolor("#151c26")
        ax.grid(alpha=0.2, linestyle="--")

    ax1.plot(hours, air_t, "o-", color="#38bdf8", markersize=3, label="Air Temp Mean (°C)")
    ax1.plot(hours, gnd_t, "s-", color="#fb923c", markersize=3, label="Ground IR Temp Mean (°C)")
    ax1.set_ylabel("Temp (°C)")
    ax1.set_title("Sol 100 Diurnal Thermal, Optical & Wind Telemetry (15-min buckets)")
    ax1.legend(loc="upper left", fontsize=8)

    ax2.plot(hours, rds, "o-", color="#facc15", markersize=3, label="Optical RDS Top-7")
    ax2_w = ax2.twinx()
    ax2_w.plot(hours, wind, "^-", color="#34d399", markersize=4, label="Wind Mean (m/s)")
    ax2.set_ylabel("Optical RDS", color="#facc15")
    ax2_w.set_ylabel("Wind (m/s)", color="#34d399")
    ax2.set_xlabel("Local Mean Solar Time (LMST Hour, Sol 100)")

    for hr, rec in zip(hours, records):
        if rec["safety_state"] == "UNKNOWN_HOLD":
            ax1.axvspan(hr - 0.1, hr + 0.1, color="#ef4444", alpha=0.14)
            ax2.axvspan(hr - 0.1, hr + 0.1, color="#ef4444", alpha=0.14)

    if selected_lmst:
        sel_hr = int(selected_lmst[6:8]) + int(selected_lmst[9:11]) / 60.0
        ax1.axvline(sel_hr, color="#ffffff", linestyle=":", linewidth=1.5)
        ax2.axvline(sel_hr, color="#ffffff", linestyle=":", linewidth=1.5)

    fig.tight_layout()
    return fig


def fig_to_png_bytes(fig: plt.Figure) -> bytes:
    """Serialize a Matplotlib figure to PNG bytes and close it."""
    buf = io.BytesIO()
    fig.savefig(buf, format="png", bbox_inches="tight")
    plt.close(fig)
    return buf.getvalue()
