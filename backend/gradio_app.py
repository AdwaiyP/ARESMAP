"""Gradio Mount Sharp & Gale Crater Explorer with Coordinate-Matched Descriptions.

Note: Uses backend/sample_loader.py (pure CSV/PIL/Matplotlib) for all data loading.
Run with: python -m backend.gradio_app (from repo root) or python backend/gradio_app.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import gradio as gr

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from backend.sample_loader import (
    LAYER_NAMES,
    LAYER_SPECS,
    REGIONS,
    STAMP_MODES,
    build_diurnal_figure,
    composite_map_image,
    find_nearest_stamps,
    load_bundle,
    load_telemetry_15min,
    pixel_to_lonlat,
)

REGION_NAMES = list(REGIONS.keys())
DEFAULT_REGION = REGION_NAMES[0]
RECORDS = load_telemetry_15min()
LMST_CHOICES = [r["lmst_bucket"] for r in RECORDS]
SOURCE_BY_NAME = {label: src for _, label, src in LAYER_SPECS}


def render_map(
    region: str,
    base_layer: str,
    overlay_layer: str,
    opacity: int,
    show_landmarks: bool,
    stamp_mode: str,
    show_stamp_labels: bool,
):
    bundle = load_bundle(region)
    img = composite_map_image(
        region, base_layer, overlay_layer, opacity, show_landmarks, stamp_mode, show_stamp_labels
    )
    base_src = SOURCE_BY_NAME.get(base_layer, "")
    ov_src = SOURCE_BY_NAME.get(overlay_layer, "None") if overlay_layer != "None" else "None"
    bbox = bundle["bbox_lon_lat"]
    zoom = bundle["mars_trek_ctx_tiles"]["zoom"]
    st = bundle["themis_stamps"]
    meta = (
        f"**Region:** {bundle['region']} (CTX zoom `{zoom}`) | **CRS:** `{bundle['crs']}`  \n"
        f"**BBOX:** `lon [{bbox[0]}, {bbox[2]}]`, `lat [{bbox[1]}, {bbox[3]}]` | "
        f"**THEMIS Stamps:** `{st['count']}` (`{st['named_description_count']}` named)  \n"
        f"**Base:** {base_src} | **Overlay:** {ov_src} ({opacity}%)"
    )
    return img, meta


def on_map_click(region: str, stamp_mode: str, evt: gr.SelectData) -> str:
    bundle = load_bundle(region)
    px, py = evt.index
    w = bundle["wms_aligned_layers"][0]["width_px"]
    h = bundle["wms_aligned_layers"][0]["height_px"]
    lon, lat = pixel_to_lonlat(px, py, bundle["bbox_lon_lat"], w, h)
    matches = find_nearest_stamps(region, lon, lat, only_named=(stamp_mode == "Named Descriptions Only"), limit=3)

    lines = [f"**Clicked ({region}):** `lat = {lat:.4f}° N`, `lon = {lon:.4f}° E` (pixel `{px}, {py}`)"]
    for m in matches:
        temp_txt = f"{m['surf_temp_c']} °C ({m['surf_temp_k']} K)" if m["surf_temp_c"] is not None else "UNKNOWN"
        alb_txt = str(m["alb_avg"]) if m["alb_avg"] is not None else "UNKNOWN"
        lines.append(
            f"- **`{m['file_id']}` ({m['frame_type']}, {m['distance_km']} km away):** "
            f"**{m['description']}** | Coords `{m['lat_deg']:.4f}° N, {m['lon_deg']:.4f}° E` | "
            f"Temp `{temp_txt}` | Albedo `{alb_txt}` | Bands `{m['bands']}`"
        )
    return "\n".join(lines)


def format_val(val: float | None, unit: str = "") -> str:
    return f"{val:.2f}{unit}" if val is not None else "UNKNOWN"


def render_telemetry(lmst_bucket: str):
    rec = next((r for r in RECORDS if r["lmst_bucket"] == lmst_bucket), RECORDS[0])
    state = rec["safety_state"]
    badge = {"NOMINAL": "🟢 NOMINAL", "CAUTION": "🟡 CAUTION", "UNKNOWN_HOLD": "🔴 UNKNOWN_HOLD"}[state]

    summary_md = f"""
### {badge} — `{rec['lmst_bucket']}` (`LTST {rec['ltst_start']}`)
- **Solar Zenith Angle:** `{format_val(rec['solar_zenith_deg_mean'], '°')}`
- **Air Temp (ATS 1–5):** `{format_val(rec['air_temp_c_mean'], ' °C')}` (range `{format_val(rec['air_temp_c_min'])}` to `{format_val(rec['air_temp_c_max'], ' °C')}`)
- **Ground IR Temp (TIRS):** `{format_val(rec['ground_ir_temp_c_mean'], ' °C')}` ± `{format_val(rec['ground_ir_temp_unc_c_mean'], ' °C')}`
- **Irradiance (W/m²):** Down LW `{format_val(rec['downward_lw_irradiance_wm2_mean'])}` | Up LW `{format_val(rec['upward_lw_irradiance_wm2_mean'])}` | Up SW `{format_val(rec['upward_sw_irradiance_wm2_mean'])}`
- **Optical RDS Top-7:** `{format_val(rec['optical_rds_top7_mean'])}` (`{rec['optical_rds_mode']}`)
- **Pressure:** BAROCAP1 `{format_val(rec['pressure_barocap1_pa_mean'], ' Pa')}` | BAROCAP2 `{format_val(rec['pressure_barocap2_pa_mean'], ' Pa')}`
- **Humidity (A):** `{format_val(rec['humidity_a_pct_mean'], '%')}` (unc: `{format_val(rec['humidity_a_unc_pct_mean'], '%')}`)
- **Wind (BOOM1 stable):** mean `{format_val(rec['wind_boom1_speed_ms_mean'], ' m/s')}`, max `{format_val(rec['wind_boom1_speed_ms_max'], ' m/s')}`, dir `{format_val(rec['wind_boom1_dir_deg_mean'], '°')}` (`{rec['wind_valid_fraction'] * 100:.1f}%` valid)
- **Active Quality / Unknown Flags:** `{rec['quality_and_unknown_flags']}`
"""
    return summary_md, build_diurnal_figure(RECORDS, lmst_bucket)


def build_app() -> gr.Blocks:
    table_headers = [
        "lmst_bucket", "solar_zenith_deg_mean", "air_temp_c_mean",
        "ground_ir_temp_c_mean", "pressure_barocap1_pa_mean",
        "optical_rds_top7_mean", "wind_boom1_speed_ms_mean", "safety_state",
    ]
    table_rows = [[r[col] for col in table_headers] for r in RECORDS]
    landmark_rows = []
    for rname in REGION_NAMES:
        for loc in load_bundle(rname)["reference_locations"]:
            landmark_rows.append([rname, loc["name"], loc["lat_deg"], loc["lon_deg"], loc["category"], loc["notes"]])

    with gr.Blocks(title="ARES — Mount Sharp & Gale Crater Sample Explorer") as demo:
        gr.Markdown(
            "# ARES — Mount Sharp & Gale Crater Explorer\n"
            "Matches teammate bounding boxes and overlays coordinate-matched `Gale Crater.csv` THEMIS descriptions onto the map."
        )

        with gr.Tab("1. Mount Sharp & Gale Layered Map"):
            with gr.Row():
                region_dd = gr.Dropdown(REGION_NAMES, value=DEFAULT_REGION, label="Region")
                stamp_dd = gr.Dropdown(STAMP_MODES, value=STAMP_MODES[0], label="THEMIS Coordinate Pins")
                base_dd = gr.Dropdown(LAYER_NAMES, value=LAYER_NAMES[0], label="Base Layer")
                ov_dd = gr.Dropdown(["None", *LAYER_NAMES], value=LAYER_NAMES[2], label="Overlay Layer")
            with gr.Row():
                opacity_sl = gr.Slider(0, 100, value=40, step=5, label="Overlay Opacity (%)")
                landmarks_cb = gr.Checkbox(value=True, label="Show Landmarks")
                labels_cb = gr.Checkbox(value=False, label="Burn Stamp Descriptions onto Image")

            map_img = gr.Image(
                value=composite_map_image(DEFAULT_REGION, LAYER_NAMES[0], LAYER_NAMES[2], 40, True, STAMP_MODES[0], False),
                label="Click anywhere on the map to match coordinates & view descriptions",
                type="pil",
            )
            map_meta = gr.Markdown()
            click_coords = gr.Markdown("**Clicked Coordinate:** Click on the map above to see matched THEMIS descriptions.")

            for ctrl in (region_dd, base_dd, ov_dd, opacity_sl, landmarks_cb, stamp_dd, labels_cb):
                ctrl.change(
                    render_map,
                    [region_dd, base_dd, ov_dd, opacity_sl, landmarks_cb, stamp_dd, labels_cb],
                    [map_img, map_meta],
                )
            map_img.select(on_map_click, [region_dd, stamp_dd], click_coords)

        with gr.Tab("2. Sol 100 Environmental & Safety Timeline"):
            lmst_dd = gr.Dropdown(LMST_CHOICES, value="00100M12:00", label="Select Sol 100 LMST Window (15-min bucket)")
            with gr.Row():
                tel_md = gr.Markdown()
                tel_plot = gr.Plot()
            lmst_dd.change(render_telemetry, lmst_dd, [tel_md, tel_plot])
            demo.load(render_telemetry, lmst_dd, [tel_md, tel_plot])

        with gr.Tab("3. Coordinates, Table & Data Caveats"):
            gr.Dataframe(
                value=landmark_rows,
                headers=["Region", "Landmark", "Lat (°N)", "Lon (°E)", "Category", "Notes"],
                label="Reference Coordinates",
            )
            gr.Dataframe(value=table_rows, headers=table_headers, label="Cleaned 15-min Telemetry (63 buckets)")

    return demo


if __name__ == "__main__":
    build_app().launch()
