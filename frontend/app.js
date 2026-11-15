const REGIONS = {
  mars: { center: [0, 90], zoom: 1 },
  mtsharp: { center: [-5.1, 137.8], zoom: 9 },
  gale: { center: [-4.5, 137.4], zoom: 8 },
  jezero: { center: [18.45, 77.4], zoom: 10 },
  ares_vallis: { center: [19.33, -33.55], zoom: 9 },
  gusev: { center: [-14.57, 175.48], zoom: 9 },
  meridiani: { center: [-1.95, -5.53], zoom: 9 },
  valles_marineris: { center: [-13.9, -59.2], zoom: 6 },
};

const map = L.map("map", {
  crs: L.CRS.EPSG4326,
  center: REGIONS.mars.center,
  zoom: REGIONS.mars.zoom,
  minZoom: 0,
  maxZoom: 14,
  maxBounds: [[-90, -180], [90, 180]],
});

const baseLayers = {};
const overlayLayers = {};
let activeBaseId = "mars_viking_red";

function makeToggleGroup(toggleId) {
  const g = L.layerGroup();
  if (document.getElementById(toggleId)?.checked) g.addTo(map);
  return g;
}

const mineralGroup = makeToggleGroup("toggle-minerals");
const plannedGroup = makeToggleGroup("toggle-planned");
const evaGroup = makeToggleGroup("toggle-eva");
const landmarkGroup = makeToggleGroup("toggle-landmarks");
const mslGroup = makeToggleGroup("toggle-msl");
const themisGroup = makeToggleGroup("toggle-themis");
const wpGroup = makeToggleGroup("toggle-waypoints");
const aoiGroup = makeToggleGroup("toggle-aoi");
const evaPlanGroup = L.layerGroup().addTo(map);

let dropWaypointMode = false;
let evaPlanMode = false;
let evaStart = null;
let plannedCount = 0;

const inspectorBadge = document.getElementById("inspector-badge");
const inspectorBody = document.getElementById("inspector-body");
const leftSidebar = document.getElementById("left-sidebar");
const rightSidebar = document.getElementById("inspector");
const btnToggleLeft = document.getElementById("btn-toggle-left");
const btnToggleRight = document.getElementById("btn-toggle-right");
const btnCloseLeft = document.getElementById("btn-close-left");
const btnCloseRight = document.getElementById("btn-close-right");

function setSidebarOpen(side, isOpen) {
  const panel = side === "left" ? leftSidebar : rightSidebar;
  const fab = side === "left" ? btnToggleLeft : btnToggleRight;
  if (!panel || !fab) return;
  panel.classList.toggle("collapsed", !isOpen);
  fab.classList.toggle("hidden-fab", isOpen);
  fab.setAttribute("aria-expanded", String(isOpen));
}

function revealInspector() {
  setSidebarOpen("right", true);
}

window.aresCloseSidebars = function () {
  setSidebarOpen("left", false);
  setSidebarOpen("right", false);
};

btnToggleLeft?.addEventListener("click", () => setSidebarOpen("left", true));
btnCloseLeft?.addEventListener("click", () => setSidebarOpen("left", false));
btnToggleRight?.addEventListener("click", () => setSidebarOpen("right", true));
btnCloseRight?.addEventListener("click", () => setSidebarOpen("right", false));

function buildLayerInstance(cfg) {
  if (cfg.protocol === "WMS") {
    return L.tileLayer.wms(cfg.url_template, {
      layers: cfg.wms_layers,
      format: "image/png",
      transparent: false,
      attribution: "USGS Astrogeology",
    });
  }
  const opts = {
    tileSize: cfg.tile_size_px || 256,
    maxNativeZoom: cfg.zoom_range ? cfg.zoom_range[1] : 12,
    maxZoom: 14,
    noWrap: true,
    attribution: "NASA Mars Trek",
  };
  if (cfg.bbox && cfg.region !== "global") {
    opts.bounds = [
      [cfg.bbox[1], cfg.bbox[0]],
      [cfg.bbox[3], cfg.bbox[2]],
    ];
  }
  return L.tileLayer(cfg.url_template, opts);
}

function drawAoiBoxes() {
  L.rectangle([[-5.6, 137.2], [-4.6, 138.4]], {
    color: "#facc15",
    weight: 2,
    dashArray: "6 4",
    fillOpacity: 0.05,
  })
    .bindTooltip("Mount Sharp Boxwork AOI")
    .addTo(aoiGroup);

  L.rectangle([[-5.8, 136.1], [-3.2, 138.7]], {
    color: "#38bdf8",
    weight: 1.5,
    dashArray: "4 4",
    fillOpacity: 0.02,
  })
    .bindTooltip("Gale Crater Bounds")
    .addTo(aoiGroup);
}

function renderKV(rows) {
  return `<table class="kv-table">${rows
    .map(([k, v]) => `<tr><td>${k}</td><td><strong>${v ?? "N/A"}</strong></td></tr>`)
    .join("")}</table>`;
}

function inspectThemis(props) {
  revealInspector();
  inspectorBadge.textContent = "THEMIS";
  const tempText =
    props.surf_temp_k != null
      ? `${props.surf_temp_k} K (${props.surf_temp_c} °C)`
      : `UNKNOWN (${props.temp_status})`;
  inspectorBody.innerHTML = renderKV([
    ["File ID", props.file_id],
    ["Frame Type", props.frame_type],
    ["Coordinates", `${props.lat_deg}°, ${props.lon_deg}°`],
    ["Surface Temp", tempText],
    ["Bands", props.bands],
    ["Description", props.description],
  ]);
}

let selectedMapPoint = null;
let selectedPointMarkerGroup = null;
let landingSiteMarkerGroup = null;

window.aresSetLandingSiteMarker = function (lat, lon) {
  if (!landingSiteMarkerGroup) {
    landingSiteMarkerGroup = L.layerGroup().addTo(map);
  }
  landingSiteMarkerGroup.clearLayers();
  L.circleMarker([lat, lon], {
    radius: 9,
    color: "#f87171",
    weight: 2.5,
    fillColor: "#f97316",
    fillOpacity: 0.85,
  })
    .bindTooltip(`Rocket Landing Site (${lat.toFixed(4)}°, ${lon.toFixed(4)}°)`)
    .addTo(landingSiteMarkerGroup);
};

function setSelectedMapPoint(lat, lon, label = "Selected Point") {
  selectedMapPoint = { lat, lon, label };
  revealInspector();
  if (!selectedPointMarkerGroup) {
    selectedPointMarkerGroup = L.layerGroup().addTo(map);
  }
  selectedPointMarkerGroup.clearLayers();
  L.circleMarker([lat, lon], {
    radius: 11,
    color: "#38bdf8",
    weight: 2,
    fillColor: "#38bdf8",
    fillOpacity: 0.15,
    interactive: false,
  }).addTo(selectedPointMarkerGroup);
  L.circleMarker([lat, lon], {
    radius: 4.5,
    color: "#ffffff",
    weight: 1.5,
    fillColor: "#facc15",
    fillOpacity: 1,
  })
    .bindTooltip(`${label} (${lat.toFixed(4)}°, ${lon.toFixed(4)}°)`)
    .addTo(selectedPointMarkerGroup);
}

function bindStreetViewBtn(container, lon, lat, label) {
  const btn = container.querySelector(".btn-sv-here");
  if (!btn) return;
  btn.addEventListener("click", () => {
    if (window.openStreetView) {
      window.openStreetView(lon, lat, label);
    }
  });
}

function streetViewBtnHtml() {
  return `<button class="btn-full btn-primary btn-sv-here" style="margin:8px 0;"><svg class="lucide-icon" width="14" height="14" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76"/></svg> Open 360° Street View Here</button>`;
}

async function inspectWaypoint(props, lat, lon) {
  const missionName = props.mission_id === "mer_a_gusev"
    ? "Spirit (MER-A)"
    : props.mission_id === "mer_b_meridiani"
    ? "Opportunity (MER-B)"
    : "Perseverance (M20)";
  const label = `${missionName} · Sol ${props.sol ?? "?"}`;
  setSelectedMapPoint(lat, lon, label);
  inspectorBadge.textContent = missionName.toUpperCase();
  let html = renderKV([
    ["Mission", missionName],
    ["RMC", props.RMC],
    ["Sol", props.sol],
    ["Lat / Lon", `${lat.toFixed(5)}°, ${lon.toFixed(5)}°`],
    ["Elevation (geoid)", `${props.elev_geoid} m`],
    ["Total Drive", `${props.dist_total_m} m`],
    ["Note", props.Note || "—"],
  ]) + streetViewBtnHtml();

  const imgs = Array.isArray(props.images) ? props.images : [];
  const pano = imgs.find((im) => im.isPanoramic && im.url);
  if (pano) {
    const panoUrl = `https://mars.nasa.gov/mmgis-maps/M20/${pano.url}`;
    html += `
      <div class="pano-box">
        <div class="pano-scroll">
          <img src="${panoUrl}" alt="360 Rover Panorama" loading="lazy" />
        </div>
        <div class="pano-caption">360° Cylindrical Panorama (drag horizontally to pan)</div>
      </div>`;
  }

  html += `<div id="nearby-raw"><p class="muted">Loading nearby Perseverance raw images...</p></div>`;
  inspectorBody.innerHTML = html;
  bindStreetViewBtn(inspectorBody, lon, lat, label);

  try {
    const res = await fetch(`/api/v1/map/images?lon=${lon}&lat=${lat}&radius_m=2000&limit=6`);
    const data = await res.json();
    const target = document.getElementById("nearby-raw");
    if (!data.images || data.images.length === 0) {
      target.innerHTML = `<p class="muted">No cached raw images within 2 km of this waypoint.</p>`;
      return;
    }
    target.innerHTML = `
      <h4 class="inspector-subhead">Nearby Raw Images (${data.count})</h4>
      <div class="raw-grid">
        ${data.images
          .map((im) => {
            const thumb = im.image_files?.small || im.image_files?.medium || "";
            const full = im.image_files?.medium || im.image_files?.large || thumb;
            return `
              <a class="raw-card" href="${full}" target="_blank" rel="noopener">
                <img src="${thumb}" alt="${im.instrument}" loading="lazy" />
                <div class="meta">Sol ${im.sol} · ${im.instrument}</div>
              </a>`;
          })
          .join("")}
      </div>`;
  } catch (err) {
    console.error(err);
  }
}

async function inspectSurfacePoint(lat, lon) {
  setSelectedMapPoint(lat, lon, "Selected Surface Point");
  inspectorBadge.textContent = "SURFACE";
  inspectorBody.innerHTML =
    renderKV([
      ["Latitude", `${lat.toFixed(5)}°`],
      ["Longitude", `${lon.toFixed(5)}°`],
    ]) +
    streetViewBtnHtml() +
    `<p class="muted">Querying climate model...</p>`;
  bindStreetViewBtn(inspectorBody, lon, lat, "Selected Surface Point");

  try {
    const res = await fetch("/api/v1/climate/predict", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        latitude: lat,
        longitude: lon,
        ltst_time: "13:30",
        elevation_m: -3500,
      }),
    });
    if (!res.ok) return;
    const data = await res.json();
    const preds = data.predictions || {};
    const rows = Object.entries(preds).slice(0, 6).map(([k, v]) => [k, typeof v === "number" ? v.toFixed(2) : v]);
    inspectorBody.innerHTML =
      renderKV([
        ["Latitude", `${lat.toFixed(5)}°`],
        ["Longitude", `${lon.toFixed(5)}°`],
      ]) +
      streetViewBtnHtml() +
      `<h4 class="inspector-subhead">Predicted Climate (13:30 LTST)</h4>` +
      renderKV(rows);
    bindStreetViewBtn(inspectorBody, lon, lat, "Selected Surface Point");
  } catch {
    // climate model optional
  }
}

let _marsClockMeta = {
  mars_year: null,
  solar_longitude_deg: null,
  mars_season_short: null,
  mars_season: null,
  sol_of_year: null,
  equation_of_time_min: 0,
  owlt_formatted: null,
};

function formatHmsFromHours(hours) {
  const norm = ((hours % 24) + 24) % 24;
  const totalSec = Math.floor(norm * 3600) % 86400;
  const hh = Math.floor(totalSec / 3600);
  const mm = Math.floor((totalSec % 3600) / 60);
  const ss = totalSec % 60;
  return `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}:${String(ss).padStart(2, "0")}`;
}

function applyMarsClockPayload(c) {
  if (!c) return;
  _marsClockMeta = { ..._marsClockMeta, ...c };
  if (c.mars_year != null && c.solar_longitude_deg != null) {
    const season = c.mars_season_short || "";
    const el = document.getElementById("clock-mars-date");
    if (el) {
      el.textContent = `MY ${c.mars_year} · Ls ${Number(c.solar_longitude_deg).toFixed(1)}° (${season})`;
      el.title = `Sol ${c.sol_of_year ?? "--"} of MY ${c.mars_year} · Month ${c.mars_month ?? "--"}/12 · ${c.mars_season || season}`;
    }
  }
  if (c.owlt_formatted) {
    const owltEl = document.getElementById("clock-owlt");
    if (owltEl) {
      owltEl.textContent = c.owlt_formatted;
      owltEl.title = `Live Earth-Mars One-Way Light Time (${c.owlt_sec}s; range 3m–22m)`;
    }
  }
  renderLiveMarsClock();
}

function renderLiveMarsClock() {
  const nowMs = Date.now();
  const jdUtc = 2440587.5 + nowMs / 86400000.0;
  const jdTt = jdUtc + 69.184 / 86400.0;
  const dtJ2000 = jdTt - 2451545.0;
  const msd = (dtJ2000 - 4.5) / 1.0274912517 + 44796.0 - 0.0009626;
  const mtcHours = (msd % 1.0) * 24.0;
  const centerLon = map ? map.getCenter().lng : 137.4417;
  const lmstHours = mtcHours + centerLon / 15.0;
  const eotHours = (_marsClockMeta.equation_of_time_min || 0) / 60.0;
  const ltstHours = lmstHours + eotHours;

  const msdEl = document.getElementById("clock-msd");
  const mtcEl = document.getElementById("clock-mtc");
  const lmstEl = document.getElementById("clock-lmst");
  const lmstWrap = document.getElementById("clock-lmst-wrap");
  const utcEl = document.getElementById("clock-utc");

  if (msdEl) msdEl.textContent = msd.toFixed(3);
  if (mtcEl) mtcEl.textContent = formatHmsFromHours(mtcHours);
  if (lmstEl) lmstEl.textContent = formatHmsFromHours(lmstHours);
  if (lmstWrap) {
    lmstWrap.title = `Local Mean Solar Time at ${centerLon.toFixed(2)}°E · LTST: ${formatHmsFromHours(ltstHours)}`;
  }
  if (utcEl) utcEl.textContent = new Date(nowMs).toISOString().slice(0, 19) + "Z";
}

async function syncMarsTime() {
  try {
    const lon = map ? map.getCenter().lng : 137.4417;
    const res = await fetch(`/api/v1/map/time?lon=${encodeURIComponent(lon.toFixed(4))}`);
    if (res.ok) {
      const data = await res.json();
      applyMarsClockPayload(data);
    }
  } catch {
    renderLiveMarsClock();
  }
}

function startLiveMarsClock() {
  renderLiveMarsClock();
  setInterval(renderLiveMarsClock, 1000);
  setInterval(syncMarsTime, 60000);
}

async function init() {
  drawAoiBoxes();
  await syncMarsTime();
  startLiveMarsClock();

  // 1. Load clocks & planet metadata
  const planetRes = await fetch("/api/v1/map/planet?body=mars");
  if (planetRes.ok) {
    const p = await planetRes.json();
    applyMarsClockPayload(p.clocks);
  }

  // 2. Load map layers
  const layersRes = await fetch("/api/v1/map/layers?body=mars");
  const layersData = await layersRes.json();
  const allLayers = [...(layersData.layers || []), ...(layersData.external_wms || [])];

  for (const cfg of allLayers) {
    const inst = buildLayerInstance(cfg);
    if (cfg.region === "global") {
      baseLayers[cfg.layer_id] = inst;
    } else {
      overlayLayers[cfg.layer_id] = inst;
    }
  }

  if (baseLayers[activeBaseId]) baseLayers[activeBaseId].addTo(map);
  if (overlayLayers.gale_ctx_optical) overlayLayers.gale_ctx_optical.addTo(map);
  if (overlayLayers.jezero_hirise_25cm) overlayLayers.jezero_hirise_25cm.addTo(map);

  // 3. Load spatial_features from MongoDB (slim + gzip + TTL cached)
  const featRes = await fetch("/api/v1/map/features?slim=true&limit=10000");
  const cacheHdr = featRes.headers.get("X-Cache") || "LIVE";
  const crcHdr = featRes.headers.get("X-Space-CRC32") || "";
  document.getElementById("hud-cache").textContent = cacheHdr;
  if (crcHdr) document.getElementById("hud-edac").textContent = `CRC ${crcHdr.slice(0, 6)}`;
  const fc = await featRes.json();
  let mineralCount = 0;
  let landmarkCount = 0;
  let mslCount = 0;
  let themisCount = 0;
  let wpCount = 0;
  const wpCoordsByMission = {};
  const mslCoords = [];

  for (const feat of fc.features || []) {
    const [lon, lat] = feat.geometry.coordinates;
    const props = feat.properties || {};
    if (props.feature_type === "mars_landmark") {
      landmarkCount++;
      const marker = L.circleMarker([lat, lon], {
        radius: 6,
        color: "#f3e8ff",
        fillColor: "#a855f7",
        fillOpacity: 0.9,
        weight: 1.5,
      }).bindTooltip(props.name || "Landmark");
      marker.on("click", (e) => {
        L.DomEvent.stopPropagation(e);
        const lbl = props.name || "Landmark";
        setSelectedMapPoint(lat, lon, lbl);
        inspectorBadge.textContent = "LANDMARK";
        inspectorBody.innerHTML =
          renderKV([
            ["Name", props.name],
            ["Coordinates", `${lat.toFixed(4)}°, ${lon.toFixed(4)}°`],
            ["Elevation", `${props.elevation_m} m`],
            ["Description", props.description],
          ]) + streetViewBtnHtml();
        bindStreetViewBtn(inspectorBody, lon, lat, lbl);
      });
      marker.addTo(landmarkGroup);
    } else if (props.feature_type === "msl_waypoint") {
      mslCount++;
      mslCoords.push([lat, lon]);
      const marker = L.circleMarker([lat, lon], {
        radius: 3.5,
        color: "#dcfce7",
        fillColor: "#22c55e",
        fillOpacity: 0.85,
        weight: 1,
      });
      marker.on("click", (e) => {
        L.DomEvent.stopPropagation(e);
        const lbl = `Curiosity (MSL) · Sol ${props.sol ?? "?"}`;
        setSelectedMapPoint(lat, lon, lbl);
        inspectorBadge.textContent = "MSL CURIOSITY";
        inspectorBody.innerHTML =
          renderKV([
            ["RMC", props.RMC],
            ["Sol", props.sol],
            ["Coordinates", `${lat.toFixed(5)}°, ${lon.toFixed(5)}°`],
            ["Elevation (geoid)", `${props.elev_geoid} m`],
            ["Total Drive", `${props.dist_total_m} m`],
          ]) + streetViewBtnHtml();
        bindStreetViewBtn(inspectorBody, lon, lat, lbl);
      });
      marker.addTo(mslGroup);
    } else if (props.feature_type === "themis_stamp") {
      themisCount++;
      const ok = props.temp_status === "OK";
      const marker = L.circleMarker([lat, lon], {
        radius: 4,
        color: ok ? "#f97316" : "#64748b",
        fillColor: ok ? "#f97316" : "#64748b",
        fillOpacity: 0.75,
        weight: 1,
      });
      marker.on("click", (e) => {
        L.DomEvent.stopPropagation(e);
        inspectThemis(props);
      });
      marker.addTo(themisGroup);
    } else if (props.feature_type === "rover_waypoint") {
      wpCount++;
      const mid = props.mission_id || "mars2020_jezero";
      (wpCoordsByMission[mid] ||= []).push([lat, lon]);
      const wpColor = mid === "mer_a_gusev" ? "#f97316" : mid === "mer_b_meridiani" ? "#a855f7" : "#38bdf8";
      const marker = L.circleMarker([lat, lon], {
        radius: 4.5,
        color: "#e0f2fe",
        fillColor: wpColor,
        fillOpacity: 0.9,
        weight: 1,
      });
      marker.on("click", (e) => {
        L.DomEvent.stopPropagation(e);
        inspectWaypoint(props, lat, lon);
      });
      marker.addTo(wpGroup);
    } else if (props.feature_type === "mineral_signature") {
      mineralCount++;
      const marker = L.circleMarker([lat, lon], {
        radius: 6.5,
        color: "#fef08a",
        fillColor: "#eab308",
        fillOpacity: 0.9,
        weight: 2,
      }).bindTooltip(props.name || "Mineral Target");
      marker.on("click", (e) => {
        L.DomEvent.stopPropagation(e);
        revealInspector();
        inspectorBadge.textContent = "MINERALOGY";
        inspectorBody.innerHTML = renderKV([
          ["Target", props.name],
          ["Mineral Class", props.mineral_class],
          ["Coordinates", `${lat.toFixed(4)}°, ${lon.toFixed(4)}°`],
          ["Elevation", `${feat.properties.elevation_m} m`],
          ["Description", props.description],
        ]);
      });
      marker.addTo(mineralGroup);
    } else if (props.feature_type === "planned_waypoint") {
      addPlannedMarker(feat);
    }
  }

  if (mslCoords.length > 1) {
    L.polyline(mslCoords, { color: "#22c55e", weight: 2, opacity: 0.7 }).addTo(mslGroup);
  }
  for (const [mid, coords] of Object.entries(wpCoordsByMission)) {
    if (coords.length > 1) {
      const lineColor = mid === "mer_a_gusev" ? "#f97316" : mid === "mer_b_meridiani" ? "#a855f7" : "#38bdf8";
      L.polyline(coords, { color: lineColor, weight: 2, opacity: 0.75 }).addTo(wpGroup);
    }
  }
  window.aresRoverTracks = {
    msl_gale: { color: 0x22c55e, points: mslCoords.map(([la, lo]) => ({ lat: la, lon: lo })) },
    mars2020_jezero: { color: 0x38bdf8, points: (wpCoordsByMission.mars2020_jezero || []).map(([la, lo]) => ({ lat: la, lon: lo })) },
    mer_a_gusev: { color: 0xf97316, points: (wpCoordsByMission.mer_a_gusev || []).map(([la, lo]) => ({ lat: la, lon: lo })) },
    mer_b_meridiani: { color: 0xa855f7, points: (wpCoordsByMission.mer_b_meridiani || []).map(([la, lo]) => ({ lat: la, lon: lo })) },
  };

  // Expose ordered route stops for Mars Street View stepping (Mount Sharp minerals + planned)
  window.aresRouteStops = (fc.features || [])
    .filter((f) => ["mineral_signature", "planned_waypoint"].includes(f.properties?.feature_type))
    .map((f) => ({
      lon: f.geometry.coordinates[0],
      lat: f.geometry.coordinates[1],
      label: f.properties.name || f.properties.feature_id,
    }));

  document.getElementById("count-minerals").textContent = mineralCount;
  document.getElementById("count-planned").textContent = plannedCount;
  document.getElementById("count-landmarks").textContent = landmarkCount;
  document.getElementById("count-msl").textContent = mslCount;
  document.getElementById("count-themis").textContent = themisCount;
  document.getElementById("count-wp").textContent = wpCount;

  drawEvaTacticalOverlays();
  loadWeatherHud();
  initPlssControls();
  startRelayCountdown();
}

function addPlannedMarker(feat) {
  const [lon, lat] = feat.geometry.coordinates;
  const props = feat.properties || {};
  plannedCount++;
  document.getElementById("count-planned").textContent = plannedCount;
  const marker = L.circleMarker([lat, lon], {
    radius: 6,
    color: "#fdf2f8",
    fillColor: "#ec4899",
    fillOpacity: 0.95,
    weight: 2,
  }).bindTooltip(props.name || "Planned Waypoint");

  marker.on("click", (e) => {
    L.DomEvent.stopPropagation(e);
    revealInspector();
    inspectorBadge.textContent = "PLANNED WP";
    inspectorBody.innerHTML =
      renderKV([
        ["Name", props.name],
        ["Category", props.category],
        ["Coordinates", `${lat.toFixed(5)}°, ${lon.toFixed(5)}°`],
        ["Notes", props.notes || "—"],
      ]) +
      `<button id="btn-del-wp" class="btn-danger">Delete Waypoint</button>`;
    document.getElementById("btn-del-wp").addEventListener("click", async () => {
      const res = await fetch(`/api/v1/map/waypoints/${props.feature_id}`, { method: "DELETE" });
      if (res.ok) {
        plannedGroup.removeLayer(marker);
        plannedCount = Math.max(0, plannedCount - 1);
        document.getElementById("count-planned").textContent = plannedCount;
        inspectorBody.innerHTML = `<p class="muted">Waypoint deleted from MongoDB.</p>`;
      }
    });
  });
  marker.addTo(plannedGroup);
}

function drawEvaTacticalOverlays() {
  const hab = [-4.5895, 137.4416];
  const eva1 = [-4.7700, 137.3810];
  const eva2 = [-4.7620, 137.3895];
  const breadcrumb = [hab, [-4.65, 137.42], [-4.72, 137.40], eva1];

  // PNR Isochrone Ring (2.5 km safe return radius around Habitat)
  L.circle(hab, {
    radius: 25000,
    color: "#f59e0b",
    weight: 1.5,
    dashArray: "8 6",
    fillOpacity: 0.03,
  }).bindTooltip("Point of No Return (PNR) Boundary").addTo(evaGroup);

  // Reverse Breadcrumb Trail
  L.polyline(breadcrumb, {
    color: "#06b6d4",
    weight: 2.5,
    dashArray: "5 5",
    opacity: 0.85,
  }).bindTooltip("EVA-1 Reverse Breadcrumb Trail").addTo(evaGroup);

  // Buddy Vector (EVA-1 <-> EVA-2)
  L.polyline([eva1, eva2], { color: "#a855f7", weight: 2, opacity: 0.9 }).addTo(evaGroup);

  L.circleMarker(hab, { radius: 7, color: "#fff", fillColor: "#22c55e", fillOpacity: 1, weight: 2 })
    .bindTooltip("Habitat Base (UHF Primary)").addTo(evaGroup);
  L.circleMarker(eva1, { radius: 6, color: "#fff", fillColor: "#06b6d4", fillOpacity: 1, weight: 2 })
    .bindTooltip("EVA-1 (You)").addTo(evaGroup);
  L.circleMarker(eva2, { radius: 6, color: "#fff", fillColor: "#a855f7", fillOpacity: 1, weight: 2 })
    .bindTooltip("EVA-2 Partner (180m @ 048°)").addTo(evaGroup);
}

function renderClimateChart(records, summary) {
  const chartEl = document.getElementById("hud-weather-chart");
  if (!chartEl) return;
  const pts = records.filter((r) => r.min_temp != null || r.max_temp != null);
  if (pts.length < 2) {
    chartEl.classList.add("hidden");
    return;
  }
  const W = 260;
  const H = 56;
  const vals = pts.flatMap((r) => [r.min_temp, r.max_temp].filter((v) => v != null));
  const lo = Math.min(...vals);
  const hi = Math.max(...vals, lo + 1);
  const toXY = (arr, key) =>
    arr
      .map((r, i) => {
        const v = r[key];
        if (v == null) return null;
        const x = (i / Math.max(1, arr.length - 1)) * W;
        const y = H - 6 - ((v - lo) / (hi - lo)) * (H - 12);
        return `${x.toFixed(1)},${y.toFixed(1)}`;
      })
      .filter(Boolean)
      .join(" ");

  chartEl.classList.remove("hidden");
  chartEl.innerHTML = `
    <svg viewBox="0 0 ${W} ${H}" width="100%" height="56" style="display:block;">
      <polyline fill="none" stroke="#f97316" stroke-width="1.5" points="${toXY(pts, "max_temp")}" />
      <polyline fill="none" stroke="#38bdf8" stroke-width="1.5" points="${toXY(pts, "min_temp")}" />
    </svg>
    <div style="display:flex;justify-content:space-between;font-size:10px;color:#94a3b8;">
      <span>${summary.first_date || ""} (Sol ${summary.first_sol ?? ""})</span>
      <span style="color:#f97316;">Max ${summary.max_temp_c ?? "--"}°</span>
      <span style="color:#38bdf8;">Min ${summary.min_temp_c ?? "--"}°</span>
      <span>${summary.last_date || ""}</span>
    </div>
  `;
}

async function loadRadiationHud(lat = -4.5895, lon = 137.4417, elevationM = -4500) {
  const el = document.getElementById("hud-radiation");
  const badge = document.getElementById("hud-rad-badge");
  if (!el) return;
  try {
    const res = await fetch(`/api/v1/map/radiation?lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lon)}&elevation_m=${encodeURIComponent(elevationM)}`);
    if (!res.ok) return;
    const data = await res.json();
    const r = data.radiation || {};
    if (badge) badge.textContent = r.safety_state || "NOMINAL";
    el.innerHTML = `
      <div>Dose Rate: <strong>${r.total_dose_rate_usv_hr ?? "--"} µSv/hr</strong></div>
      <div>Daily GCR: <strong>${r.gcr_dose_msv_day ?? "--"} mSv/d</strong></div>
      <div>4h EVA Dose: <strong>${r.eva_4h_dose_msv ?? "--"} mSv</strong></div>
      <div>SEP Storm: <strong>${r.sep_alert_level ?? "QUIET"}</strong></div>
      <div>Shielding: <strong>${r.column_depth_g_cm2 ?? "--"} g/cm²</strong></div>
      <div>Source: <strong>${data.source === "nasa_donki_live+msl_rad" ? "DONKI+RAD" : "MSL RAD"}</strong></div>
    `;
  } catch (err) {
    console.warn("Radiation HUD failed:", err);
  }
}

async function loadWeatherHud() {
  loadRadiationHud();
  const el = document.getElementById("hud-weather");
  const titleEl = document.getElementById("hud-weather-title");
  const rangeEl = document.getElementById("weather-range");
  const datesRow = document.getElementById("weather-dates");
  const chartEl = document.getElementById("hud-weather-chart");
  const mode = rangeEl ? rangeEl.value : "sol100";

  if (datesRow) datesRow.classList.toggle("hidden", mode !== "custom");

  try {
    if (mode === "sol100") {
      if (titleEl) titleEl.textContent = "Space Weather / MEDA (Sol 100)";
      chartEl?.classList.add("hidden");
      const res = await fetch("/api/v1/map/telemetry?station_id=jezero_meda_sol100");
      if (!res.ok) return;
      const data = await res.json();
      const recs = data.records || [];
      const noon = recs[Math.floor(recs.length / 2)] || recs[0];
      if (!noon) return;
      el.innerHTML = `
        <div>Air Temp: <strong>${noon.air_temp_c_mean?.toFixed(1) ?? "N/A"} °C</strong></div>
        <div>Ground IR: <strong>${noon.ground_ir_temp_c_mean?.toFixed(1) ?? "N/A"} °C</strong></div>
        <div>Pressure: <strong>${noon.pressure_barocap1_pa_mean?.toFixed(0) ?? "N/A"} Pa</strong></div>
        <div>Optical RDS: <strong>${noon.optical_rds_top7_mean?.toFixed(4) ?? "N/A"}</strong></div>
        <div>Ionizing Rad: <strong>UNKNOWN</strong></div>
        <div>State: <strong>${noon.safety_state}</strong></div>
      `;
      return;
    }

    if (titleEl) titleEl.textContent = "Mars Climate / REMS (Gale)";
    el.innerHTML = `<div>Loading NASA REMS climate...</div>`;
    let url = `/api/v1/map/climate?days=${encodeURIComponent(mode)}`;
    if (mode === "custom") {
      const s = document.getElementById("weather-start")?.value || "2024-01-01";
      const e = document.getElementById("weather-end")?.value || "2026-08-25";
      url = `/api/v1/map/climate?start_date=${encodeURIComponent(s)}&end_date=${encodeURIComponent(e)}`;
    }
    const res = await fetch(url);
    if (!res.ok) throw new Error("climate fetch failed");
    const data = await res.json();
    const s = data.summary || {};
    const lat = s.latest || {};
    el.innerHTML = `
      <div>Duration: <strong>${data.count} Sols</strong></div>
      <div>Season (Ls): <strong>${lat.ls ?? "--"}° (${lat.season ?? "--"})</strong></div>
      <div>Air Range: <strong>${s.min_temp_c ?? "--"}..${s.max_temp_c ?? "--"} °C</strong></div>
      <div>Avg Press: <strong>${s.avg_pressure_pa ?? "--"} Pa</strong></div>
      <div>Opacity: <strong>${lat.atmo_opacity ?? "--"}</strong></div>
      <div>UV Index: <strong>${lat.uv_index ?? "--"}</strong></div>
    `;
    renderClimateChart(data.records || [], s);
  } catch {
    el.innerHTML = `<div>Telemetry unavailable</div>`;
  }
}

document.getElementById("weather-range")?.addEventListener("change", loadWeatherHud);
document.getElementById("weather-apply")?.addEventListener("click", loadWeatherHud);

window.aresPlssState = {
  initO2: 82,
  initBat: 76,
  initH2O: 3.2,
  metabolicW: 310,
  pressureKpa: 29.6,
  walkedMeters: 0,
  plannedDistM: 0,
};

function updatePlssSimulation() {
  const s = window.aresPlssState;
  const reservePct = Math.min(80, Math.max(5, Number(document.getElementById("eva-reserve-pct")?.value || 25)));
  const workFactor = Math.max(0.4, s.metabolicW / 310);
  const o2UsedWalk = s.walkedMeters * 0.012 * workFactor;
  const batUsedWalk = s.walkedMeters * 0.01 * workFactor;
  const h2oUsedWalk = s.walkedMeters * 0.00025 * workFactor;

  const curO2 = Math.max(0, s.initO2 - o2UsedWalk);
  const curBat = Math.max(0, s.initBat - batUsedWalk);
  const curH2O = Math.max(0, s.initH2O - h2oUsedWalk);
  const o2RateHr = 14.0 * workFactor;
  const remMin = Math.max(0, Math.round((curO2 / o2RateHr) * 60));
  const remH = Math.floor(remMin / 60);
  const remM = remMin % 60;
  const ppco2 = (1.1 + 0.7 * workFactor + (curO2 < 30 ? 0.9 : 0)).toFixed(1);

  const o2El = document.getElementById("hud-o2-readout");
  const ppEl = document.getElementById("hud-ppco2");
  const prEl = document.getElementById("hud-press-readout");
  const batEl = document.getElementById("hud-bat-readout");
  const metEl = document.getElementById("hud-metabolic-readout");
  const routeEl = document.getElementById("hud-route-plss");
  const pillEl = document.getElementById("hud-plss-status");

  if (o2El) o2El.textContent = `${curO2.toFixed(1)}% (${remH}h ${String(remM).padStart(2, "0")}m)`;
  if (ppEl) ppEl.textContent = `${ppco2} mmHg`;
  if (prEl) prEl.textContent = `${s.pressureKpa.toFixed(1)} kPa`;
  if (batEl) batEl.textContent = `${curBat.toFixed(1)}% · ${curH2O.toFixed(2)}L`;
  if (metEl) metEl.textContent = `${Math.round(s.metabolicW)} W`;
  if (routeEl) {
    const estPct = (s.plannedDistM * 0.012 * workFactor).toFixed(1);
    routeEl.textContent = s.plannedDistM > 0 ? `-${estPct}% O₂ (${Math.round(s.plannedDistM)}m)` : `${Math.round(s.walkedMeters)}m walked`;
  }
  if (pillEl) {
    const hazard = curO2 <= 20 || curBat <= 15 || Number(ppco2) > 4.0;
    const caution = !hazard && (curO2 <= reservePct || curBat <= 30);
    pillEl.textContent = hazard ? "HAZARD" : caution ? "CAUTION" : "NOMINAL";
    pillEl.className = `pill ${hazard ? "danger" : caution ? "warn" : "ok"}`;
  }
}

window.updatePlssWalked = (meters) => {
  window.aresPlssState.walkedMeters = Math.max(0, Number(meters) || 0);
  updatePlssSimulation();
};

function initPlssControls() {
  const evaO2Input = document.getElementById("eva-plss-o2");
  const initO2Input = document.getElementById("plss-init-o2");
  const initBatInput = document.getElementById("plss-init-bat");
  const initH2OInput = document.getElementById("plss-init-h2o");
  const metInput = document.getElementById("plss-metabolic");
  const pressInput = document.getElementById("plss-pressure");

  const syncFromInputs = () => {
    const s = window.aresPlssState;
    s.initO2 = Math.min(100, Math.max(10, Number(initO2Input?.value || 82)));
    s.initBat = Math.min(100, Math.max(10, Number(initBatInput?.value || 76)));
    s.initH2O = Math.min(6, Math.max(0.2, Number(initH2OInput?.value || 3.2)));
    s.metabolicW = Math.min(650, Math.max(150, Number(metInput?.value || 310)));
    s.pressureKpa = Math.min(45, Math.max(20, Number(pressInput?.value || 29.6)));
    if (evaO2Input) evaO2Input.value = String(Math.round(s.initO2));
    updatePlssSimulation();
  };

  initO2Input?.addEventListener("input", syncFromInputs);
  initBatInput?.addEventListener("input", syncFromInputs);
  initH2OInput?.addEventListener("input", syncFromInputs);
  metInput?.addEventListener("input", syncFromInputs);
  pressInput?.addEventListener("input", syncFromInputs);
  evaO2Input?.addEventListener("input", () => {
    if (initO2Input) initO2Input.value = evaO2Input.value;
    syncFromInputs();
  });
  document.getElementById("btn-plss-reset")?.addEventListener("click", () => {
    window.aresPlssState.walkedMeters = 0;
    window.aresPlssState.plannedDistM = 0;
    syncFromInputs();
  });
  syncFromInputs();
}

function startRelayCountdown() {
  const el = document.getElementById("hud-relay");
  const orbitInput = document.getElementById("sat-orbit-min");
  const offsetInput = document.getElementById("sat-offset-min");
  const nearbyBtn = document.getElementById("btn-sat-nearby");
  let phaseSecs = Math.round((Number(offsetInput?.value || 18.7)) * 60);

  const renderRelay = () => {
    const orbitSecs = Math.max(600, Math.round((Number(orbitInput?.value || 112)) * 60));
    const passWindowSecs = Math.min(480, Math.round(orbitSecs * 0.08));
    const modPhase = ((phaseSecs % orbitSecs) + orbitSecs) % orbitSecs;
    if (modPhase < passWindowSecs) {
      const rem = passWindowSecs - modPhase;
      el.textContent = `IN PASS (${Math.floor(rem / 60)}m ${String(rem % 60).padStart(2, "0")}s)`;
    } else {
      const untilPass = orbitSecs - modPhase;
      el.textContent = `T-${String(Math.floor(untilPass / 60)).padStart(2, "0")}m ${String(untilPass % 60).padStart(2, "0")}s`;
    }
  };

  const applyOffset = () => {
    const orbitSecs = Math.max(600, Math.round((Number(orbitInput?.value || 112)) * 60));
    const offsetSecs = Math.max(0, Math.round((Number(offsetInput?.value || 0)) * 60));
    phaseSecs = (orbitSecs - (offsetSecs % orbitSecs)) % orbitSecs;
    renderRelay();
  };

  orbitInput?.addEventListener("change", applyOffset);
  offsetInput?.addEventListener("change", applyOffset);
  nearbyBtn?.addEventListener("click", () => {
    phaseSecs = 0;
    if (offsetInput) offsetInput.value = "0";
    renderRelay();
  });

  applyOffset();
  setInterval(() => {
    phaseSecs += 1;
    renderRelay();
  }, 1000);
}

function openDropWaypointForm(lat, lon) {
  revealInspector();
  inspectorBadge.textContent = "NEW WAYPOINT";
  inspectorBody.innerHTML = `
    <div class="wp-form">
      <div class="muted">Coords: <strong>${lat.toFixed(5)}°, ${lon.toFixed(5)}°</strong></div>
      <input id="wp-name" type="text" placeholder="Waypoint name (e.g. Boxwork Sample 1)" />
      <select id="wp-cat">
        <option value="science_target">Science Target</option>
        <option value="sample_site">RFID Sample Site</option>
        <option value="shelter">Emergency Safe Haven</option>
      </select>
      <textarea id="wp-notes" rows="2" placeholder="EVA notes..."></textarea>
      <button id="wp-save" class="accent">Save to MongoDB</button>
    </div>
  `;
  document.getElementById("wp-save").addEventListener("click", async () => {
    const name = document.getElementById("wp-name").value.trim() || "Planned EVA Waypoint";
    const category = document.getElementById("wp-cat").value;
    const notes = document.getElementById("wp-notes").value.trim();
    const res = await fetch("/api/v1/map/waypoints", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name, lon, lat, category, notes }),
    });
    if (res.ok) {
      const data = await res.json();
      addPlannedMarker({
        type: "Feature",
        geometry: data.feature.geometry,
        properties: { feature_id: data.feature.feature_id, ...data.feature.properties },
      });
      dropWaypointMode = false;
      document.getElementById("btn-drop-wp").classList.remove("active");
      inspectorBody.innerHTML = `<p class="muted">Saved <strong>${name}</strong> to <code>ares_base.spatial_features</code>.</p>`;
    }
  });
}

// UI Bindings
map.on("moveend", () => {
  renderLiveMarsClock();
});

map.on("mousemove", (e) => {
  document.getElementById("cursor-coords").textContent =
    `${e.latlng.lat.toFixed(4)}°, ${e.latlng.lng.toFixed(4)}°`;
});

map.on("click", (e) => {
  if (evaPlanMode) {
    handleEvaPlanClick(e.latlng.lat, e.latlng.lng);
  } else if (dropWaypointMode) {
    openDropWaypointForm(e.latlng.lat, e.latlng.lng);
  } else {
    inspectSurfacePoint(e.latlng.lat, e.latlng.lng);
  }
});

document.querySelectorAll("button[data-jump]").forEach((btn) => {
  btn.addEventListener("click", () => {
    const r = REGIONS[btn.dataset.jump];
    if (r) map.setView(r.center, r.zoom);
  });
});

document.querySelectorAll("input[name='baselayer']").forEach((radio) => {
  radio.addEventListener("change", () => {
    if (baseLayers[activeBaseId]) map.removeLayer(baseLayers[activeBaseId]);
    activeBaseId = radio.value;
    if (baseLayers[activeBaseId]) baseLayers[activeBaseId].addTo(map);
  });
});

document.querySelectorAll("input[data-overlay]").forEach((cb) => {
  cb.addEventListener("change", () => {
    const layer = overlayLayers[cb.dataset.overlay];
    if (!layer) return;
    if (cb.checked) layer.addTo(map);
    else map.removeLayer(layer);
  });
});

document.getElementById("toggle-minerals").addEventListener("change", (e) => {
  if (e.target.checked) mineralGroup.addTo(map);
  else map.removeLayer(mineralGroup);
});

document.getElementById("toggle-planned").addEventListener("change", (e) => {
  if (e.target.checked) plannedGroup.addTo(map);
  else map.removeLayer(plannedGroup);
});

document.getElementById("toggle-eva").addEventListener("change", (e) => {
  if (e.target.checked) evaGroup.addTo(map);
  else map.removeLayer(evaGroup);
});

async function handleEvaPlanClick(lat, lng) {
  if (!evaStart) {
    evaStart = { lat, lng };
    evaPlanGroup.clearLayers();
    L.circleMarker([lat, lng], { radius: 7, color: "#22c55e", fillColor: "#22c55e", fillOpacity: 0.9 })
      .bindTooltip("EVA Start")
      .addTo(evaPlanGroup);
    inspectorBadge.textContent = "EVA GOAL";
    inspectorBody.innerHTML = `<p class="muted">Start set at <strong>${lat.toFixed(4)}°, ${lng.toFixed(4)}°</strong>. Now click your <strong>EVA Goal</strong> (~100–600 m away).</p>`;
    return;
  }

  const start = evaStart;
  const goal = { lat, lng };
  evaPlanMode = false;
  evaStart = null;
  document.getElementById("btn-plan-eva").classList.remove("active");

  const midLat = 0.5 * (start.lat + goal.lat);
  const midLon = 0.5 * (start.lng + goal.lng);
  const spanDeg = Math.max(0.01, Math.abs(goal.lat - start.lat) * 1.6, Math.abs(goal.lng - start.lng) * 1.6);
  const half = spanDeg / 2;
  const minLon = midLon - half;
  const maxLon = midLon + half;
  const minLat = midLat - half;
  const maxLat = midLat + half;
  const bboxStr = [minLon, minLat, maxLon, maxLat].map((v) => v.toFixed(5)).join(",");

  inspectorBadge.textContent = "ROUTING A*";
  inspectorBody.innerHTML = `<p class="muted">Computing hyperlocal slope-aware A* EVA path...</p>`;

  const N = 50;
  const gridRes = await fetch(`/api/v1/map/terrain-grid?bbox=${bboxStr}&rows=${N}&cols=${N}`);
  const grid = await gridRes.json();

  const toCol = (lo) => Math.min(N - 1, Math.max(0, Math.round(((lo - minLon) / (maxLon - minLon)) * (N - 1))));
  const toRow = (la) => Math.min(N - 1, Math.max(0, Math.round(((maxLat - la) / (maxLat - minLat)) * (N - 1))));

  const sx = toCol(start.lng);
  const sy = toRow(start.lat);
  const gx = toCol(goal.lng);
  const gy = toRow(goal.lat);

  const cellLat = (maxLat - minLat) / (N - 1);
  const cellLon = (maxLon - minLon) / (N - 1);
  let hazardCount = 0;
  const riskGrid = (grid.slope_deg || []).map((row, r) =>
    row.map((s, c) => {
      if (s >= 15) {
        hazardCount++;
        const cLat = maxLat - r * cellLat;
        const cLon = minLon + c * cellLon;
        const color = s >= 25 ? "#ef4444" : "#eab308";
        L.rectangle(
          [[cLat - cellLat / 2, cLon - cellLon / 2], [cLat + cellLat / 2, cLon + cellLon / 2]],
          { color, weight: 0, fillColor: color, fillOpacity: s >= 25 ? 0.45 : 0.25 }
        ).addTo(evaPlanGroup);
      }
      return Math.min(1.0, s / 25.0);
    })
  );

  const algo = document.getElementById("eva-algo")?.value || "astar";
  const evaBudgetM = Math.max(100, Number(document.getElementById("eva-budget-m")?.value || 2000));
  const maxSlopeDeg = Math.min(45, Math.max(5, Number(document.getElementById("eva-max-slope")?.value || 25)));
  const plssO2Pct = Math.min(100, Math.max(0, Number(document.getElementById("eva-plss-o2")?.value || 82)));
  const minReservePct = Math.min(90, Math.max(0, Number(document.getElementById("eva-reserve-pct")?.value || 25)));
  const envCondition = document.getElementById("eva-env-state")?.value || "nominal";

  const routeRes = await fetch("/api/v1/routes/plan", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      start: { x: sx, y: sy },
      goal: { x: gx, y: gy },
      elevation: grid.elevation_m,
      risk: riskGrid,
      risk_weight: 10.0,
      cell_size_m: grid.cell_size_m || 10.0,
      max_slope_deg: maxSlopeDeg,
      algorithm: algo,
      eva_budget_m: evaBudgetM,
      plss_o2_pct: plssO2Pct,
      min_reserve_pct: minReservePct,
      env_condition: envCondition,
    }),
  });
  const route = await routeRes.json();
  if (route.status !== "success" || !Array.isArray(route.route)) {
    inspectorBadge.textContent = "NO ROUTE";
    inspectorBody.innerHTML = `<p class="muted">No safe EVA path found (&lt; 25° slope): ${route.message || "blocked"}.</p>`;
    return;
  }

  const latLngs = route.route.map((pt) => {
    const lo = minLon + (pt.x / (N - 1)) * (maxLon - minLon);
    const la = maxLat - (pt.y / (N - 1)) * (maxLat - minLat);
    return [la, lo];
  });

  L.circleMarker([goal.lat, goal.lng], { radius: 7, color: "#38bdf8", fillColor: "#38bdf8", fillOpacity: 0.9 })
    .bindTooltip("EVA Goal")
    .addTo(evaPlanGroup);

  let cautionSegs = 0;
  let hazardSegs = 0;
  for (let i = 0; i < route.route.length - 1; i++) {
    const p1 = route.route[i];
    const p2 = route.route[i + 1];
    const s1 = grid.slope_deg?.[p1.y]?.[p1.x] ?? 0;
    const s2 = grid.slope_deg?.[p2.y]?.[p2.x] ?? 0;
    const segSlope = Math.max(s1, s2);
    let segColor = "#38bdf8";
    if (segSlope >= 25) {
      segColor = "#ef4444";
      hazardSegs++;
    } else if (segSlope >= 15) {
      segColor = "#facc15";
      cautionSegs++;
    }
    L.polyline([latLngs[i], latLngs[i + 1]], { color: segColor, weight: 4.0, opacity: 0.95 }).addTo(evaPlanGroup);
  }

  // Extract Start, every turning point, and Goal as temporary waypoints so 3D Street View preserves all turns
  const stops = [{ lat: latLngs[0][0], lon: latLngs[0][1], label: "EVA Start" }];
  for (let i = 1; i < route.route.length - 1; i++) {
    const prev = route.route[i - 1];
    const curr = route.route[i];
    const next = route.route[i + 1];
    const dx1 = curr.x - prev.x;
    const dy1 = curr.y - prev.y;
    const dx2 = next.x - curr.x;
    const dy2 = next.y - curr.y;
    const len1 = Math.hypot(dx1, dy1);
    const len2 = Math.hypot(dx2, dy2);
    const dot = len1 > 0 && len2 > 0 ? (dx1 * dx2 + dy1 * dy2) / (len1 * len2) : 1;
    if (dot < 0.995) {
      const [tLat, tLon] = latLngs[i];
      stops.push({ lat: tLat, lon: tLon, label: `Turn WP ${stops.length}` });
      L.circleMarker([tLat, tLon], {
        radius: 3.5,
        color: "#facc15",
        fillColor: "#fde047",
        fillOpacity: 0.95,
        weight: 1,
      })
        .bindTooltip(`Turn WP ${stops.length - 1}`)
        .addTo(evaPlanGroup);
    }
  }
  const last = latLngs[latLngs.length - 1];
  if (stops[stops.length - 1].lat !== last[0] || stops[stops.length - 1].lon !== last[1]) {
    stops.push({ lat: last[0], lon: last[1], label: "EVA Goal" });
  }
  window.aresRouteStops = stops;

  const distM = route.distance_m ?? route.total_distance_m ?? Math.round(latLngs.length * (grid.cell_size_m || 10));
  const walkMin = (distM / 1.2 / 60).toFixed(1);
  const workFactor = Math.max(0.4, (window.aresPlssState?.metabolicW || 310) / 310);
  const o2Used = (distM * 0.012 * workFactor).toFixed(1);
  if (window.aresPlssState) {
    window.aresPlssState.plannedDistM = distM;
    updatePlssSimulation();
  }
  const routeStatus =
    hazardSegs > 0
      ? `HAZARD (${hazardSegs} steep segments ≥25°)`
      : distM > 2000
        ? "ROVER REQUIRED (> 2 km EVA limit)"
        : cautionSegs > 0
          ? `CAUTION (${cautionSegs} segments 15°–25°)`
          : "SAFE (< 15° nominal slope)";

  const safety = route.safety || {};
  const checks = safety.checks || {};
  const checkLabels = [
    ["route", "Route Integrity"],
    ["obstacles", "Obstacle Collision"],
    ["distance", "Distance Validation"],
    ["eva_budget", "EVA Distance Budget"],
    ["return_to_base", "Return-to-Base"],
    ["slope", "Terrain Slope"],
    ["environment", "Environmental Safety"],
  ];
  const badgeCls =
    safety.safety_status === "UNSAFE"
      ? "fail"
      : safety.safety_status === "VALIDATED_WITHIN_MODEL"
        ? "pass"
        : "unknown";
  const safetyHtml = `
    <div class="safety-dash">
      <div class="safety-dash-hdr">
        <span style="display:inline-flex;align-items:center;gap:5px;"><svg class="lucide-icon" width="14" height="14" viewBox="0 0 24 24"><path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/></svg> Astronaut Safety Dashboard</span>
        <span class="safety-pill ${badgeCls}">${safety.safety_status || "UNVERIFIED"}</span>
      </div>
      ${checkLabels
        .map(([k, lbl]) => {
          const st = checks[k] || "unknown";
          const txt = st === "pass" ? "PASS" : st === "fail" ? "FAIL" : "UNVERIFIED";
          return `<div class="safety-row"><span>${lbl}</span><span class="safety-pill ${st}">${txt}</span></div>`;
        })
        .join("")}
      ${(safety.failures || []).length ? `<div style="margin-top:4px;font-size:10px;color:#fca5a5;">${safety.failures.join(" · ")}</div>` : ""}
    </div>
  `;

  revealInspector();
  inspectorBadge.textContent = hazardSegs > 0 || distM > 2000 || safety.safety_status === "UNSAFE" ? "EVA WARN" : "EVA READY";
  inspectorBody.innerHTML =
    renderKV([
      ["Algorithm", algo === "theta_star" ? "Theta* (Any-Angle)" : "A* (Grid)"],
      ["EVA Route Status", routeStatus],
      ["Total Distance", `${Math.round(distM)} m`],
      ["Est. Walk Time", `${walkMin} min (@ 1.2 m/s)`],
      ["Grid Cell Size", `${Math.round(grid.cell_size_m || 10)} m/cell`],
      ["Hazard/Caution Cells", `${hazardCount} (≥ 15° slope)`],
      ["PLSS O₂ Budget", `~${o2Used}% (One-Way)`],
      ["Waypoints", `${stops.length} visor beacons`],
    ]) +
    safetyHtml +
    `<button id="btn-walk-eva-sv" class="btn-full btn-primary" style="margin-top:8px;"><svg class="lucide-icon" width="14" height="14" viewBox="0 0 24 24"><circle cx="12" cy="8" r="5"/><path d="M20 21a8 8 0 0 0-16 0"/></svg> Walk EVA in Visor Street View</button>`;

  document.getElementById("btn-walk-eva-sv").addEventListener("click", () => {
    if (window.openStreetView) {
      window.openStreetView(start.lng, start.lat, "Hyperlocal EVA", stops);
    }
  });
}

document.getElementById("btn-plan-eva").addEventListener("click", (e) => {
  evaPlanMode = !evaPlanMode;
  evaStart = null;
  dropWaypointMode = false;
  document.getElementById("btn-drop-wp").classList.remove("active");
  e.currentTarget.classList.toggle("active", evaPlanMode);
  inspectorBadge.textContent = evaPlanMode ? "EVA START" : "READY";
  if (evaPlanMode) {
    inspectorBody.innerHTML = `<p class="muted">Click <strong>Start</strong> point on the Mars map to plan a 500 m hyperlocal slope-aware A* EVA spacewalk.</p>`;
  }
});

document.getElementById("btn-drop-wp").addEventListener("click", (e) => {
  dropWaypointMode = !dropWaypointMode;
  e.currentTarget.classList.toggle("active", dropWaypointMode);
  inspectorBadge.textContent = dropWaypointMode ? "DROP MODE" : "READY";
  if (dropWaypointMode) {
    inspectorBody.innerHTML = `<p class="muted">Click anywhere on the Mars map to place a planned EVA waypoint.</p>`;
  }
});

document.getElementById("toggle-landmarks").addEventListener("change", (e) => {
  if (e.target.checked) landmarkGroup.addTo(map);
  else map.removeLayer(landmarkGroup);
});

document.getElementById("toggle-msl").addEventListener("change", (e) => {
  if (e.target.checked) mslGroup.addTo(map);
  else map.removeLayer(mslGroup);
});

document.getElementById("toggle-themis").addEventListener("change", (e) => {
  if (e.target.checked) themisGroup.addTo(map);
  else map.removeLayer(themisGroup);
});

document.getElementById("toggle-waypoints").addEventListener("change", (e) => {
  if (e.target.checked) wpGroup.addTo(map);
  else map.removeLayer(wpGroup);
});

document.getElementById("toggle-aoi").addEventListener("change", (e) => {
  if (e.target.checked) aoiGroup.addTo(map);
  else map.removeLayer(aoiGroup);
});

document.getElementById("btn-open-globe").addEventListener("click", () => {
  window.aresCloseSidebars?.();
  if (window.open3DGlobe) {
    window.open3DGlobe();
  }
});

document.getElementById("btn-open-3d").addEventListener("click", () => {
  window.aresCloseSidebars?.();
  let bbox;
  let title = "Regional 3D Terrain";
  if (selectedMapPoint) {
    const pad = 0.2;
    bbox = [
      Math.max(-180, selectedMapPoint.lon - pad),
      Math.max(-90, selectedMapPoint.lat - pad),
      Math.min(180, selectedMapPoint.lon + pad),
      Math.min(90, selectedMapPoint.lat + pad),
    ];
    title = `3D Terrain · ${selectedMapPoint.label}`;
  } else {
    const b = map.getBounds();
    bbox = [
      Math.max(-180, b.getWest()),
      Math.max(-90, b.getSouth()),
      Math.min(180, b.getEast()),
      Math.min(90, b.getNorth()),
    ];
    // If zoomed out to whole Mars, focus local 3D terrain on Gale Crater / Mount Sharp
    if (bbox[2] - bbox[0] > 30 || bbox[3] - bbox[1] > 30) {
      bbox = [137.25, -4.9, 137.65, -4.5];
    }
  }
  if (window.open3DTerrain) {
    window.open3DTerrain(bbox, title);
  }
});

document.getElementById("btn-open-sv").addEventListener("click", () => {
  const pt = selectedMapPoint || { lng: map.getCenter().lng, lat: map.getCenter().lat, label: "Current Map Center" };
  const lon = pt.lon ?? pt.lng;
  if (window.openStreetView) {
    window.openStreetView(lon, pt.lat, pt.label || "Selected Point");
  }
});

document.getElementById("btn-test-edac").addEventListener("click", async () => {
  inspectorBadge.textContent = "EDAC LINK";
  const res = await fetch("/api/v1/map/edac/test", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message: "SOL100:T=-69.2C:P=771Pa:OK", inject_bit_flips: 3 }),
  });
  const d = await res.json();
  inspectorBody.innerHTML = renderKV([
    ["Scheme", d.edac_scheme],
    ["Codewords Sent", d.codewords_sent],
    ["Injected Bit Flips", d.injected_bit_flips],
    ["Corrected Bits", d.corrected_bits],
    ["TX CRC32", d.tx_crc32],
    ["RX CRC32", d.rx_crc32],
    ["CRC Match", d.crc_match ? "PASS (100% Recovered)" : "FAIL"],
    ["Recovered Payload", d.recovered],
  ]);
});

init();
