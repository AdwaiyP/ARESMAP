"""FastAPI Mount Sharp & Gale Crater Explorer with Coordinate-Matched Descriptions.

Run with: backend/.venv/Scripts/python.exe backend/local_viewer.py
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

import uvicorn
from fastapi import FastAPI, Query
from fastapi.responses import HTMLResponse, Response

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from backend.sample_loader import (
    LAYER_NAMES,
    REGIONS,
    STAMP_MODES,
    build_diurnal_figure,
    composite_map_image,
    fig_to_png_bytes,
    find_nearest_stamps,
    load_bundle,
    load_telemetry_15min,
    load_themis_stamps,
)

app = FastAPI(title="ARES — Mount Sharp & Gale Crater Explorer")
REGION_NAMES = list(REGIONS.keys())
DEFAULT_REGION = REGION_NAMES[0]
RECORDS = load_telemetry_15min()


@app.get("/api/meta")
def get_meta() -> dict:
    regions_meta = {}
    for rname in REGION_NAMES:
        b = load_bundle(rname)
        wms0 = b["wms_aligned_layers"][0]
        regions_meta[rname] = {
            "region": b["region"],
            "bbox_lon_lat": b["bbox_lon_lat"],
            "width_px": wms0["width_px"],
            "height_px": wms0["height_px"],
            "crs": b["crs"],
            "ctx_zoom": b["mars_trek_ctx_tiles"]["zoom"],
            "reference_locations": b["reference_locations"],
            "themis_stamps_summary": b["themis_stamps"],
        }
    return {
        "default_region": DEFAULT_REGION,
        "regions": regions_meta,
        "layers": LAYER_NAMES,
        "stamp_modes": STAMP_MODES,
        "telemetry": RECORDS,
    }


@app.get("/api/stamps")
def get_stamps(region: str = Query(DEFAULT_REGION)) -> dict:
    if region not in REGIONS:
        region = DEFAULT_REGION
    return {"region": region, "stamps": load_themis_stamps(region)}


@app.get("/api/lookup")
def lookup_coordinate(
    region: str = Query(DEFAULT_REGION),
    lon: float = Query(...),
    lat: float = Query(...),
    only_named: bool = Query(False),
) -> dict:
    if region not in REGIONS:
        region = DEFAULT_REGION
    matches = find_nearest_stamps(region, lon, lat, only_named=only_named, limit=5)
    return {"region": region, "clicked": {"lon_deg": lon, "lat_deg": lat}, "nearest_stamps": matches}


@app.get("/api/map")
def get_map(
    region: str = Query(DEFAULT_REGION),
    base: str = Query(LAYER_NAMES[0]),
    overlay: str = Query("None"),
    opacity: int = Query(40, ge=0, le=100),
    landmarks: bool = Query(True),
    stamp_mode: str = Query("Named Descriptions Only"),
    stamp_labels: bool = Query(False),
) -> Response:
    if region not in REGIONS:
        region = DEFAULT_REGION
    if base not in LAYER_NAMES:
        base = LAYER_NAMES[0]
    if stamp_mode not in STAMP_MODES:
        stamp_mode = STAMP_MODES[0]
    img = composite_map_image(region, base, overlay, opacity, landmarks, stamp_mode, stamp_labels)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return Response(content=buf.getvalue(), media_type="image/png")


@app.get("/api/chart")
def get_chart(lmst: str = Query("00100M12:00")) -> Response:
    fig = build_diurnal_figure(RECORDS, lmst)
    return Response(content=fig_to_png_bytes(fig), media_type="image/png")


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    return """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>ARES — Mount Sharp & Gale Crater Explorer</title>
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; background: #0b1017; color: #e5e7eb; }
    header { padding: 14px 24px; background: #121924; border-bottom: 1px solid #263244; }
    h1 { margin: 0; font-size: 20px; }
    .sub { color: #9ca3af; font-size: 13px; margin-top: 4px; }
    .grid { display: grid; grid-template-columns: 1.2fr 1fr; gap: 18px; padding: 18px 24px; }
    .card { background: #121924; border: 1px solid #263244; border-radius: 10px; padding: 16px; }
    .controls { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 12px; }
    label { font-size: 12px; color: #9ca3af; display: block; margin-bottom: 4px; }
    select, input[type=range] { width: 100%; background: #0b1017; color: #e5e7eb; border: 1px solid #334155; border-radius: 6px; padding: 6px; }
    .map-wrap { position: relative; width: 100%; }
    .map-wrap img { width: 100%; display: block; border-radius: 8px; border: 1px solid #263244; cursor: crosshair; }
    .map-wrap svg { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; }
    .pin { pointer-events: auto; cursor: pointer; }
    .tooltip { position: absolute; z-index: 20; display: none; max-width: 280px; background: rgba(11,16,23,0.95); border: 1px solid #38bdf8; border-radius: 8px; padding: 8px 10px; font-size: 12px; pointer-events: none; box-shadow: 0 8px 24px rgba(0,0,0,0.5); }
    .match-box { margin-top: 10px; background: #0b1017; border: 1px solid #1e293b; border-radius: 8px; padding: 10px 12px; font-size: 13px; }
    .match-item { padding: 6px 0; border-top: 1px solid #1e293b; }
    .match-item:first-child { border-top: none; padding-top: 0; }
    .tag { display: inline-block; padding: 1px 7px; border-radius: 999px; font-size: 11px; font-weight: 700; background: #0e7490; color: #cffafe; }
    .pill { display: inline-block; padding: 3px 10px; border-radius: 999px; font-weight: 700; font-size: 12px; }
    .NOMINAL { background: #064e3b; color: #6ee7b7; }
    .CAUTION { background: #78350f; color: #fcd34d; }
    .UNKNOWN_HOLD { background: #7f1d1d; color: #fca5a5; }
    .kv { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin: 12px 0; font-size: 13px; }
    .kv div { background: #0b1017; padding: 8px 10px; border-radius: 6px; border: 1px solid #1e293b; }
    .warn { font-size: 12px; color: #fca5a5; background: #1f1215; border: 1px solid #7f1d1d; padding: 8px 10px; border-radius: 6px; margin-top: 8px; }
  </style>
</head>
<body>
  <header>
    <h1>ARES — Mount Sharp & Gale Crater Sample Explorer</h1>
    <div class="sub">Coordinate-Matched Mars Trek CTX + USGS THEMIS Day/Night IR + MOLA + Gale Crater.csv Descriptions + Sol 100 Telemetry</div>
  </header>
  <div class="grid">
    <div class="card">
      <div class="controls">
        <div><label>Region</label><select id="region"></select></div>
        <div><label>THEMIS Coordinate Pins</label><select id="stampMode"></select></div>
        <div><label>Base Layer</label><select id="base"></select></div>
        <div><label>Overlay Layer</label><select id="overlay"></select></div>
        <div><label>Overlay Opacity: <span id="opVal">40</span>%</label><input id="opacity" type="range" min="0" max="100" step="5" value="40" /></div>
        <div style="display:flex;flex-direction:column;justify-content:end;gap:4px;padding-bottom:4px;">
          <label style="display:flex;align-items:center;gap:6px;margin:0;color:#e5e7eb;"><input id="landmarks" type="checkbox" checked style="width:auto;" /> Show Landmarks (Orange)</label>
          <label style="display:flex;align-items:center;gap:6px;margin:0;color:#e5e7eb;"><input id="stampLabels" type="checkbox" style="width:auto;" /> Burn Descriptions onto Image</label>
        </div>
      </div>
      <div class="map-wrap" id="mapWrap">
        <img id="mapImg" alt="Mount Sharp Map" />
        <svg id="pinSvg"></svg>
        <div id="tooltip" class="tooltip"></div>
      </div>
      <div id="regionMeta" class="sub" style="margin-top:8px;"></div>
      <div id="matchBox" class="match-box">Hover any cyan/purple pin for its description, or click anywhere on the map to match coordinates against <code>Gale Crater.csv</code>.</div>
    </div>
    <div class="card">
      <label>Sol 100 LMST Window (15-min bucket)</label>
      <select id="lmst"></select>
      <div id="telReadout" style="margin-top:12px;"></div>
      <img id="chartImg" alt="Diurnal Telemetry Chart" style="width:100%;border-radius:8px;border:1px solid #263244;margin-top:12px;" />
    </div>
  </div>
<script>
let meta = null;
let stampsCache = {};
const fmt = (v, u='') => (v === null || v === undefined) ? 'UNKNOWN' : `${Number(v).toFixed(2)}${u}`;

async function init() {
  meta = await (await fetch('/api/meta')).json();
  const regEl = document.getElementById('region');
  Object.keys(meta.regions).forEach((r) => regEl.add(new Option(r, r, r === meta.default_region, r === meta.default_region)));
  const smEl = document.getElementById('stampMode');
  meta.stamp_modes.forEach((m, i) => smEl.add(new Option(m, m, i === 0, i === 0)));
  const baseEl = document.getElementById('base');
  const ovEl = document.getElementById('overlay');
  ovEl.add(new Option('None', 'None'));
  meta.layers.forEach((l, i) => {
    baseEl.add(new Option(l, l, i === 0, i === 0));
    ovEl.add(new Option(l, l, i === 2, i === 2));
  });
  const lmstEl = document.getElementById('lmst');
  meta.telemetry.forEach((r) => lmstEl.add(new Option(`${r.lmst_bucket} (${r.safety_state})`, r.lmst_bucket)));
  lmstEl.value = '00100M12:00';

  ['region','stampMode','base','overlay','opacity','landmarks','stampLabels'].forEach(id =>
    document.getElementById(id).addEventListener('input', updateMap)
  );
  lmstEl.addEventListener('change', updateTelemetry);
  document.getElementById('mapImg').addEventListener('click', (e) => {
    const reg = document.getElementById('region').value;
    const rmeta = meta.regions[reg];
    const rect = e.target.getBoundingClientRect();
    const [lonMin, latMin, lonMax, latMax] = rmeta.bbox_lon_lat;
    const lon = lonMin + ((e.clientX - rect.left) / rect.width) * (lonMax - lonMin);
    const lat = latMax - ((e.clientY - rect.top) / rect.height) * (latMax - latMin);
    lookupCoord(reg, lon, lat);
  });
  await updateMap();
  updateTelemetry();
}

async function ensureStamps(reg) {
  if (!stampsCache[reg]) {
    const res = await (await fetch(`/api/stamps?region=${encodeURIComponent(reg)}`)).json();
    stampsCache[reg] = res.stamps;
  }
  return stampsCache[reg];
}

function renderPins(reg, stamps, mode) {
  const svg = document.getElementById('pinSvg');
  const rmeta = meta.regions[reg];
  svg.setAttribute('viewBox', `0 0 ${rmeta.width_px} ${rmeta.height_px}`);
  svg.innerHTML = '';
  if (mode === 'Off') return;

  const [lonMin, latMin, lonMax, latMax] = rmeta.bbox_lon_lat;
  const tip = document.getElementById('tooltip');
  const wrap = document.getElementById('mapWrap');

  stamps.forEach((s) => {
    if (mode === 'Named Descriptions Only' && !s.has_description) return;
    const x = ((s.lon_deg - lonMin) / (lonMax - lonMin)) * rmeta.width_px;
    const y = ((latMax - s.lat_deg) / (latMax - latMin)) * rmeta.height_px;
    const c = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
    c.setAttribute('cx', x);
    c.setAttribute('cy', y);
    c.setAttribute('r', s.has_description ? 7 : 4);
    c.setAttribute('fill', 'transparent');
    c.setAttribute('stroke', s.has_description ? 'rgba(0,229,255,0.6)' : 'transparent');
    c.setAttribute('stroke-width', '1.5');
    c.classList.add('pin');
    c.addEventListener('mouseenter', (ev) => {
      const rect = wrap.getBoundingClientRect();
      const tempTxt = s.surf_temp_c !== null ? `${s.surf_temp_c} °C (${s.surf_temp_k} K)` : 'UNKNOWN (0.0 sentinel)';
      tip.innerHTML = `<b>${s.file_id}</b> (${s.frame_type})<br/>
        <b>Desc:</b> ${s.description}<br/>
        <b>Coords:</b> ${s.lat_deg.toFixed(4)}° N, ${s.lon_deg.toFixed(4)}° E<br/>
        <b>Surf Temp:</b> ${tempTxt}<br/>
        <b>Albedo:</b> ${s.alb_avg !== null ? s.alb_avg : 'UNKNOWN'} | <b>Bands:</b> ${s.bands}`;
      tip.style.left = `${Math.min(rect.width - 290, Math.max(8, ev.clientX - rect.left + 12))}px`;
      tip.style.top = `${Math.max(8, ev.clientY - rect.top - 10)}px`;
      tip.style.display = 'block';
    });
    c.addEventListener('mouseleave', () => { tip.style.display = 'none'; });
    c.addEventListener('click', (ev) => {
      ev.stopPropagation();
      lookupCoord(reg, s.lon_deg, s.lat_deg);
    });
    svg.appendChild(c);
  });
}

async function lookupCoord(reg, lon, lat) {
  const mode = document.getElementById('stampMode').value;
  const onlyNamed = (mode === 'Named Descriptions Only');
  const res = await (await fetch(`/api/lookup?region=${encodeURIComponent(reg)}&lon=${lon}&lat=${lat}&only_named=${onlyNamed}`)).json();
  const rows = res.nearest_stamps.slice(0, 3).map((s) => {
    const tempTxt = s.surf_temp_c !== null ? `${s.surf_temp_c} °C (${s.surf_temp_k} K)` : 'UNKNOWN';
    return `<div class="match-item">
      <span class="tag">${s.file_id} (${s.frame_type})</span>
      <b>${s.description}</b>
      <span class="sub"> — ${s.distance_km} km away</span><br/>
      <span class="sub">Coords: ${s.lat_deg.toFixed(5)}° N, ${s.lon_deg.toFixed(5)}° E | Temp: ${tempTxt} | Albedo: ${s.alb_avg ?? 'UNKNOWN'} | Bands: ${s.bands}</span>
    </div>`;
  }).join('');
  document.getElementById('matchBox').innerHTML =
    `<b>Clicked:</b> <code>${lat.toFixed(4)}° N, ${lon.toFixed(4)}° E</code> — Nearest <code>Gale Crater.csv</code> matches:${rows}`;
}

async function updateMap() {
  const reg = document.getElementById('region').value;
  const rmeta = meta.regions[reg];
  const sm = document.getElementById('stampMode').value;
  document.getElementById('regionMeta').textContent =
    `${rmeta.region} | CTX zoom ${rmeta.ctx_zoom} | BBOX lon [${rmeta.bbox_lon_lat[0]}, ${rmeta.bbox_lon_lat[2]}], lat [${rmeta.bbox_lon_lat[1]}, ${rmeta.bbox_lon_lat[3]}] | THEMIS Stamps: ${rmeta.themis_stamps_summary.count} (${rmeta.themis_stamps_summary.named_description_count} named)`;
  const b = encodeURIComponent(document.getElementById('base').value);
  const o = encodeURIComponent(document.getElementById('overlay').value);
  const op = document.getElementById('opacity').value;
  document.getElementById('opVal').textContent = op;
  const lm = document.getElementById('landmarks').checked;
  const sl = document.getElementById('stampLabels').checked;
  document.getElementById('mapImg').src = `/api/map?region=${encodeURIComponent(reg)}&base=${b}&overlay=${o}&opacity=${op}&landmarks=${lm}&stamp_mode=${encodeURIComponent(sm)}&stamp_labels=${sl}`;
  const stamps = await ensureStamps(reg);
  renderPins(reg, stamps, sm);
}

function updateTelemetry() {
  const lmst = document.getElementById('lmst').value;
  const r = meta.telemetry.find(x => x.lmst_bucket === lmst);
  document.getElementById('telReadout').innerHTML = `
    <span class="pill ${r.safety_state}">${r.safety_state}</span>
    <span class="sub" style="margin-left:8px;">LTST ${r.ltst_start} | Solar Zenith ${fmt(r.solar_zenith_deg_mean,'°')}</span>
    <div class="kv">
      <div><b>Air Temp (ATS)</b><br/>${fmt(r.air_temp_c_mean,' °C')} (${fmt(r.air_temp_c_min)}..${fmt(r.air_temp_c_max)})</div>
      <div><b>Ground IR (TIRS)</b><br/>${fmt(r.ground_ir_temp_c_mean,' °C')} ± ${fmt(r.ground_ir_temp_unc_c_mean,' °C')}</div>
      <div><b>Optical RDS Top-7</b><br/>${fmt(r.optical_rds_top7_mean)} (${r.optical_rds_mode})</div>
      <div><b>IR Flux (W/m²)</b><br/>Down LW ${fmt(r.downward_lw_irradiance_wm2_mean)} | Up LW ${fmt(r.upward_lw_irradiance_wm2_mean)}</div>
      <div><b>Pressure</b><br/>B1 ${fmt(r.pressure_barocap1_pa_mean,' Pa')} | B2 ${fmt(r.pressure_barocap2_pa_mean,' Pa')}</div>
      <div><b>Wind (BOOM1)</b><br/>${fmt(r.wind_boom1_speed_ms_mean,' m/s')} (max ${fmt(r.wind_boom1_speed_ms_max)}) | ${(r.wind_valid_fraction*100).toFixed(0)}% valid</div>
    </div>
    <div class="warn"><b>Flags:</b> ${r.quality_and_unknown_flags.split('|').join(', ')}</div>`;
  document.getElementById('chartImg').src = `/api/chart?lmst=${encodeURIComponent(lmst)}`;
}
init();
</script>
</body>
</html>"""


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
