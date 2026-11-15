import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { MarsChunkManager, drawRoutePath3D, computeScaleReadout } from "./chunks3d.js";

let renderer, scene, camera, controls, activeGroup, mroSat, globeSphere;
let globeLayers = {};
let globeRouteGroup = null;
let globeSelectionMarker = null;
let globeDetailMesh = null;
let globeDetailKey = "";
let globeDetailTimer = null;
let globePlanMode = false;
let globeRouteStart = null;
let chunkMgr = null;
let horizonSkirt = null;
let pickables = [];
let lastBbox = [137.25, -4.9, 137.65, -4.5];
let animId = null;
let mroAngle = 0;
let downPos = { x: 0, y: 0 };
const keysPressed = new Set();
const raycaster = new THREE.Raycaster();
const pointerNDC = new THREE.Vector2();

const GLOBE_R = 24;

const modal = document.getElementById("terrain-3d-modal");
const canvas = document.getElementById("terrain-3d-canvas");
const statsEl = document.getElementById("terrain-3d-stats");
const modeSelect = document.getElementById("terrain-3d-mode");
const globeTexSelect = document.getElementById("terrain-3d-globe-tex");
const exagInput = document.getElementById("terrain-3d-exag");
const exagWrap = document.getElementById("exag-wrap");
const colorSelect = document.getElementById("terrain-3d-color");
const infoCard = document.getElementById("globe-info-card");
const infoTitle = document.getElementById("globe-info-title");
const infoBody = document.getElementById("globe-info-body");
const t3dScaleBar = document.getElementById("t3d-scale-bar");
const t3dScaleLabel = document.getElementById("t3d-scale-label");
const btnPlanGlobeEva = document.getElementById("btn-plan-globe-eva");

function ensureScene() {
  if (renderer) return;
  renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x1f1411);
  scene.fog = new THREE.FogExp2(0x1f1411, 0.0045);

  camera = new THREE.PerspectiveCamera(48, 16 / 9, 0.1, 2000);
  camera.position.set(0, 18, 62);

  controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.zoomSpeed = 0.55;
  controls.addEventListener("change", scheduleGlobeDetailUpdate);

  scene.add(new THREE.AmbientLight(0xffffff, 0.7));
  const sun = new THREE.DirectionalLight(0xfff1dc, 1.25);
  sun.position.set(70, 40, 80);
  scene.add(sun);

  activeGroup = new THREE.Group();
  scene.add(activeGroup);

  canvas.addEventListener("pointerdown", (e) => {
    downPos = { x: e.clientX, y: e.clientY };
  });
  canvas.addEventListener("pointerup", (e) => {
    const dist = Math.hypot(e.clientX - downPos.x, e.clientY - downPos.y);
    if (dist < 5 && modeSelect.value === "globe") {
      handleGlobeClick(e);
    }
  });

  window.addEventListener("keydown", (e) => {
    if (modal.classList.contains("hidden")) return;
    if (["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName)) return;
    keysPressed.add(e.code);
  });
  window.addEventListener("keyup", (e) => {
    keysPressed.delete(e.code);
  });
  window.addEventListener("resize", resizeCanvas);
}

function clearGroup() {
  chunkMgr?.clear();
  if (!activeGroup) return;
  while (activeGroup.children.length) {
    const obj = activeGroup.children.pop();
    obj.traverse?.((ch) => {
      ch.geometry?.dispose();
      if (Array.isArray(ch.material)) ch.material.forEach((m) => m.dispose());
      else ch.material?.dispose();
    });
  }
  mroSat = null;
  globeSphere = null;
  globeSelectionMarker = null;
  globeDetailMesh = null;
  globeDetailKey = "";
  horizonSkirt = null;
  pickables = [];
}

function resizeCanvas() {
  if (!renderer || modal.classList.contains("hidden")) return;
  const rect = canvas.parentElement.getBoundingClientRect();
  renderer.setSize(rect.width, rect.height, false);
  camera.aspect = rect.width / Math.max(1, rect.height);
  camera.updateProjectionMatrix();
}

function latLonToVec3(lat, lon, radius) {
  const phi = THREE.MathUtils.degToRad(90 - lat);
  const theta = THREE.MathUtils.degToRad(lon + 180);
  return new THREE.Vector3(
    -radius * Math.sin(phi) * Math.cos(theta),
    radius * Math.cos(phi),
    radius * Math.sin(phi) * Math.sin(theta)
  );
}

function vec3ToLatLon(pt) {
  const n = pt.clone().normalize();
  const lat = 90 - THREE.MathUtils.radToDeg(Math.acos(Math.max(-1, Math.min(1, n.y))));
  // Invert: x = -sin(phi)*cos(theta), z = sin(phi)*sin(theta)
  let theta = Math.atan2(n.z, -n.x);
  if (theta < 0) theta += Math.PI * 2;
  const lon = THREE.MathUtils.radToDeg(theta) - 180;
  return { lat, lon };
}

function setGlobeSelectionHighlight(lat, lon) {
  if (!activeGroup || modeSelect.value !== "globe") return;
  if (!globeSelectionMarker) {
    globeSelectionMarker = new THREE.Group();
    const dot = new THREE.Mesh(
      new THREE.SphereGeometry(0.28, 16, 16),
      new THREE.MeshBasicMaterial({ color: 0x38bdf8 })
    );
    const innerRing = new THREE.Mesh(
      new THREE.RingGeometry(0.48, 0.72, 32),
      new THREE.MeshBasicMaterial({ color: 0xfacc15, side: THREE.DoubleSide })
    );
    const outerRing = new THREE.Mesh(
      new THREE.RingGeometry(0.86, 1.08, 32),
      new THREE.MeshBasicMaterial({ color: 0x38bdf8, transparent: true, opacity: 0.75, side: THREE.DoubleSide })
    );
    outerRing.name = "pulseRing";
    globeSelectionMarker.add(dot, innerRing, outerRing);
    activeGroup.add(globeSelectionMarker);
  }
  const pos = latLonToVec3(lat, lon, GLOBE_R + 0.18);
  globeSelectionMarker.position.copy(pos);
  const normal = pos.clone().normalize();
  globeSelectionMarker.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), normal);
  globeSelectionMarker.visible = true;
}

async function inspectGlobeLocation(lat, lon, featureData = null) {
  setGlobeSelectionHighlight(lat, lon);
  window.aresInspectSurface?.(lat, lon);
  infoCard.classList.remove("hidden");
  infoTitle.textContent = featureData?.name || "Mars Surface Point";
  infoBody.innerHTML =
    `<div><strong>Lat / Lon:</strong> ${lat.toFixed(4)}°, ${lon.toFixed(4)}°</div>` +
    (featureData?.elevation_m != null ? `<div><strong>Elevation:</strong> ${featureData.elevation_m} m</div>` : "") +
    (featureData?.description ? `<div style="margin-top:3px;">${featureData.description}</div>` : "") +
    `<div id="globe-env-extra" style="margin-top:5px;">Querying elevation, thermal &amp; radiation...</div>` +
    `<div style="display:flex;gap:6px;margin-top:6px;">` +
    `<button id="btn-globe-zoom-local" style="flex:1;border-color:#38bdf8;color:#bae6fd;">3D Terrain</button>` +
    `<button id="btn-globe-open-sv" style="flex:1;border-color:#22c55e;color:#bbf7d0;">360° Street View</button>` +
    `</div>`;

  document.getElementById("btn-globe-zoom-local").addEventListener("click", () => {
    const pad = 0.2;
    modeSelect.value = "terrain";
    loadLocalTerrain([lon - pad, lat - pad, lon + pad, lat + pad], featureData?.name || "Selected Site");
  });
  document.getElementById("btn-globe-open-sv").addEventListener("click", () => {
    window.openStreetView?.(lon, lat, featureData?.name || "Globe Selected Site");
  });

  const extraEl = document.getElementById("globe-env-extra");
  try {
    const pad = 0.25;
    const bbox = `${(lon - pad).toFixed(3)},${(lat - pad).toFixed(3)},${(lon + pad).toFixed(3)},${(lat + pad).toFixed(3)}`;
    const [gridRes, telRes, climRes] = await Promise.all([
      fetch(`/api/v1/map/terrain-grid?bbox=${bbox}&rows=8&cols=8`),
      fetch("/api/v1/map/telemetry?station_id=jezero_meda_sol100"),
      fetch("/api/v1/climate/predict", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ latitude: lat, longitude: lon, ltst_time: "13:30", elevation_m: featureData?.elevation_m ?? -3000 }),
      }).catch(() => null),
    ]);

    const lines = [];
    if (gridRes.ok && featureData?.elevation_m == null) {
      const g = await gridRes.json();
      lines.push(`<div><strong>Est. Elev:</strong> ${g.min_elev_m} to ${g.max_elev_m} m</div>`);
    }
    if (climRes && climRes.ok) {
      const cl = await climRes.json();
      const p = cl.predictions || {};
      if (p.air_temp_c != null) lines.push(`<div><strong>Pred. Temp:</strong> ${Number(p.air_temp_c).toFixed(1)} °C</div>`);
    }
    if (telRes.ok) {
      const tel = await telRes.json();
      const rec = (tel.records || [])[Math.floor((tel.records || []).length / 2)];
      if (rec) {
        lines.push(`<div><strong>MEDA Thermal (Sol 100):</strong> Air ${rec.air_temp_c_mean?.toFixed(1)}°C / Ground ${rec.ground_ir_temp_c_mean?.toFixed(1)}°C</div>`);
        lines.push(`<div><strong>Optical RDS / Ionizing Rad:</strong> ${rec.optical_rds_top7_mean?.toFixed(4)} / UNKNOWN</div>`);
      }
    }
    extraEl.innerHTML = lines.join("") || "No environmental telemetry at this point.";
  } catch {
    extraEl.textContent = "Environmental query unavailable.";
  }
}

async function handleGlobeRouteClick(lat, lon) {
  if (!globeRouteGroup) {
    globeRouteGroup = new THREE.Group();
    activeGroup.add(globeRouteGroup);
  }
  if (!globeRouteStart) {
    while (globeRouteGroup.children.length) globeRouteGroup.remove(globeRouteGroup.children[0]);
    globeRouteStart = { lat, lon };
    const startPin = new THREE.Mesh(
      new THREE.SphereGeometry(0.28, 14, 14),
      new THREE.MeshBasicMaterial({ color: 0x22c55e })
    );
    startPin.position.copy(latLonToVec3(lat, lon, GLOBE_R + 0.08));
    startPin.userData.isRoutePin = true;
    globeRouteGroup.add(startPin);
    statsEl.textContent = `EVA Start: ${lat.toFixed(3)}°, ${lon.toFixed(3)}° — Click Goal on Mars Globe`;
    infoTitle.textContent = "Globe EVA Start Set";
    infoBody.innerHTML = `<p>Start: ${lat.toFixed(4)}°, ${lon.toFixed(4)}°.<br/>Now click your Goal point on the 3D Mars Globe.</p>`;
    infoCard.classList.remove("hidden");
    return;
  }

  const start = globeRouteStart;
  const goal = { lat, lon };
  globeRouteStart = null;
  globePlanMode = false;
  btnPlanGlobeEva?.classList.remove("active");

  const goalPin = new THREE.Mesh(
    new THREE.SphereGeometry(0.28, 14, 14),
    new THREE.MeshBasicMaterial({ color: 0xef4444 })
  );
  goalPin.position.copy(latLonToVec3(lat, lon, GLOBE_R + 0.08));
  goalPin.userData.isRoutePin = true;
  globeRouteGroup.add(goalPin);

  statsEl.textContent = "Computing safe EVA route on Mars Globe...";
  infoTitle.textContent = "Planning EVA Route...";
  infoBody.innerHTML = "Running terrain-aware A*/Theta* pathfinding...";
  infoCard.classList.remove("hidden");

  const pad = Math.max(0.06, Math.min(1.5, Math.max(Math.abs(goal.lat - start.lat), Math.abs(goal.lon - start.lon)) * 0.65));
  const bbox = [
    Math.max(-180, Math.min(start.lon, goal.lon) - pad),
    Math.max(-90, Math.min(start.lat, goal.lat) - pad),
    Math.min(180, Math.max(start.lon, goal.lon) + pad),
    Math.min(90, Math.max(start.lat, goal.lat) + pad),
  ];

  try {
    const algo = document.getElementById("eva-algo")?.value || "theta_star";
    const maxSlope = Number(document.getElementById("eva-max-slope")?.value || 25);
    const budgetM = Number(document.getElementById("eva-budget-m")?.value || 50000);
    const res = await fetch("/api/v1/routes/plan", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        start: [start.lon, start.lat],
        goal: [goal.lon, goal.lat],
        bbox,
        grid_size: 48,
        algo,
        max_slope_deg: maxSlope,
        max_distance_m: Math.max(budgetM, 25000),
      }),
    });
    const d = await res.json();
    const coords = d.geojson?.geometry?.coordinates || [[start.lon, start.lat], [goal.lon, goal.lat]];
    const pts = coords.map(([lo, la]) => latLonToVec3(la, lo, GLOBE_R + 0.22));
    const routeLine = new THREE.Line(
      new THREE.BufferGeometry().setFromPoints(pts),
      new THREE.LineBasicMaterial({ color: 0x38bdf8 })
    );
    globeRouteGroup.add(routeLine);

    const status = d.safety?.status || (d.reachable ? "NOMINAL" : "UNREACHABLE");
    infoTitle.textContent = `Globe EVA Route · ${status}`;
    infoBody.innerHTML =
      `<div>Distance: <strong>${Math.round(d.total_distance_m || 0)} m</strong></div>` +
      `<div>Max Slope: <strong>${(d.max_slope_deg || 0).toFixed(1)}°</strong></div>` +
      `<div>Algo: <strong>${algo}</strong></div>`;
    statsEl.textContent = `3D Mars Globe | EVA Route: ${Math.round(d.total_distance_m || 0)} m (${status})`;
  } catch (err) {
    infoTitle.textContent = "Globe EVA Route Error";
    infoBody.textContent = String(err);
  }
}

function handleGlobeClick(e) {
  const rect = canvas.getBoundingClientRect();
  pointerNDC.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
  pointerNDC.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;
  raycaster.setFromCamera(pointerNDC, camera);

  const mapMode = window.aresGetClickMode?.();
  if ((globePlanMode || mapMode === "eva") && globeSphere) {
    const sphereHits = raycaster.intersectObject(globeSphere, false);
    if (sphereHits.length > 0) {
      const { lat, lon } = vec3ToLatLon(sphereHits[0].point);
      handleGlobeRouteClick(lat, lon);
      return;
    }
  }
  if (mapMode === "drop_wp" && globeSphere) {
    const sphereHits = raycaster.intersectObject(globeSphere, false);
    if (sphereHits.length > 0) {
      const { lat, lon } = vec3ToLatLon(sphereHits[0].point);
      window.aresOpenDropWaypointForm?.(lat, lon);
      return;
    }
  }
  if (mapMode === "mark_jump" && globeSphere) {
    const sphereHits = raycaster.intersectObject(globeSphere, false);
    if (sphereHits.length > 0) {
      const { lat, lon } = vec3ToLatLon(sphereHits[0].point);
      window.aresMarkCustomJumpAt?.(lat, lon);
      return;
    }
  }

  // 1. Check landmark/mineral/planned pins first
  const pinHits = raycaster.intersectObjects(pickables, false);
  if (pinHits.length > 0) {
    const ud = pinHits[0].object.userData;
    inspectGlobeLocation(ud.lat, ud.lon, ud);
    return;
  }

  // 2. Otherwise check click on Mars sphere itself
  if (globeSphere) {
    const sphereHits = raycaster.intersectObject(globeSphere, false);
    if (sphereHits.length > 0) {
      const { lat, lon } = vec3ToLatLon(sphereHits[0].point);
      inspectGlobeLocation(lat, lon, null);
    }
  }
}

function syncControlsVisibility() {
  const isGlobe = modeSelect.value === "globe";
  globeTexSelect.style.display = isGlobe ? "" : "none";
  if (btnPlanGlobeEva) btnPlanGlobeEva.style.display = isGlobe ? "" : "none";
  exagWrap.style.display = isGlobe ? "none" : "";
  colorSelect.style.display = isGlobe ? "none" : "";
  t3dScaleBar?.classList.toggle("hidden", isGlobe);
}

async function buildGlobe() {
  clearGroup();
  syncControlsVisibility();
  infoCard.classList.add("hidden");
  const style = globeTexSelect.value || "viking_red";
  statsEl.textContent = "Loading High-Res 3D Mars Globe (z=2)...";

  camera.position.set(0, 16, 62);
  controls.target.set(0, 0, 0);
  controls.minDistance = GLOBE_R + 0.8;
  controls.maxDistance = 95;
  controls.enablePan = false;
  controls.update();

  const loader = new THREE.TextureLoader();
  const tex = await new Promise((resolve, reject) => {
    loader.load(`/api/v1/map/globe-texture?style=${style}&z=2`, resolve, undefined, reject);
  });
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.magFilter = THREE.LinearFilter;

  globeSphere = new THREE.Mesh(
    new THREE.SphereGeometry(GLOBE_R, 96, 72),
    new THREE.MeshStandardMaterial({
      map: tex,
      bumpMap: tex,
      bumpScale: 0.28,
      roughness: 0.88,
      metalness: 0.04,
    })
  );
  activeGroup.add(globeSphere);

  // Progressively upgrade base globe texture to z=3 (4096x2048) in background
  const currentSphere = globeSphere;
  loader.load(`/api/v1/map/globe-texture?style=${style}&z=3`, (hiTex) => {
    if (globeSphere !== currentSphere) {
      hiTex.dispose();
      return;
    }
    hiTex.colorSpace = THREE.SRGBColorSpace;
    hiTex.anisotropy = renderer.capabilities.getMaxAnisotropy();
    hiTex.minFilter = THREE.LinearMipmapLinearFilter;
    hiTex.magFilter = THREE.LinearFilter;
    currentSphere.material.map = hiTex;
    currentSphere.material.bumpMap = hiTex;
    currentSphere.material.needsUpdate = true;
  });

  const atmo = new THREE.Mesh(
    new THREE.SphereGeometry(GLOBE_R * 1.025, 48, 32),
    new THREE.MeshBasicMaterial({ color: 0xe07a5f, transparent: true, opacity: 0.1, side: THREE.BackSide })
  );
  activeGroup.add(atmo);

  const orbitPts = [];
  const R_orb = GLOBE_R + 3.8;
  for (let i = 0; i <= 128; i++) {
    const a = (i / 128) * Math.PI * 2;
    orbitPts.push(new THREE.Vector3(Math.cos(a) * R_orb, Math.sin(a) * R_orb, 0));
  }
  const orbitLine = new THREE.Line(
    new THREE.BufferGeometry().setFromPoints(orbitPts),
    new THREE.LineBasicMaterial({ color: 0x38bdf8, transparent: true, opacity: 0.65 })
  );
  orbitLine.rotation.y = THREE.MathUtils.degToRad(35);
  activeGroup.add(orbitLine);

  mroSat = new THREE.Mesh(new THREE.SphereGeometry(0.55, 12, 12), new THREE.MeshBasicMaterial({ color: 0x38bdf8 }));
  orbitLine.add(mroSat);

  globeLayers = {
    landmarks: new THREE.Group(),
    minerals: new THREE.Group(),
    planned: new THREE.Group(),
    msl: new THREE.Group(),
    waypoints: new THREE.Group(),
    themis: new THREE.Group(),
    aoi: new THREE.Group(),
  };
  Object.values(globeLayers).forEach((g) => activeGroup.add(g));

  // Mount Sharp & Gale AOI bounding outline on 3D Globe
  const aoiCorners = [
    [-5.0, 137.25],
    [-5.0, 137.65],
    [-4.5, 137.65],
    [-4.5, 137.25],
    [-5.0, 137.25],
  ].map(([la, lo]) => latLonToVec3(la, lo, GLOBE_R + 0.16));
  globeLayers.aoi.add(
    new THREE.Line(
      new THREE.BufferGeometry().setFromPoints(aoiCorners),
      new THREE.LineBasicMaterial({ color: 0xf97316 })
    )
  );

  window.aresLoader?.show("Loading 3D Mars Globe & NASA orbital vectors...", 45);
  try {
    const res = await fetch("/api/v1/map/features?slim=true&limit=10000");
    const fc = await res.json();
    const pinGeom = new THREE.SphereGeometry(0.28, 12, 12);
    const roverTracks = { msl_gale: [], mars2020_jezero: [], mer_a_gusev: [], mer_b_meridiani: [] };
    for (const feat of fc.features || []) {
      const props = feat.properties || {};
      const ft = props.feature_type;
      const [lon, lat] = feat.geometry.coordinates;
      if (ft === "msl_waypoint") {
        roverTracks.msl_gale.push(latLonToVec3(lat, lon, GLOBE_R + 0.12));
        continue;
      }
      if (ft === "rover_waypoint") {
        const mid = props.mission_id || "mars2020_jezero";
        if (roverTracks[mid]) roverTracks[mid].push(latLonToVec3(lat, lon, GLOBE_R + 0.12));
        continue;
      }
      if (ft === "themis_stamp") {
        const coords = feat.geometry?.coordinates?.[0];
        if (Array.isArray(coords) && coords.length > 0) {
          const avgLon = coords.reduce((s, c) => s + c[0], 0) / coords.length;
          const avgLat = coords.reduce((s, c) => s + c[1], 0) / coords.length;
          const dot = new THREE.Mesh(
            new THREE.SphereGeometry(0.14, 8, 8),
            new THREE.MeshBasicMaterial({ color: props.temp_kelvin ? 0xef4444 : 0x38bdf8 })
          );
          dot.position.copy(latLonToVec3(avgLat, avgLon, GLOBE_R + 0.18));
          dot.userData = { name: props.file_id || "THEMIS Stamp", lat: avgLat, lon: avgLon, description: props.temp_kelvin ? `Temp: ${props.temp_kelvin} K` : "Temp Unknown" };
          globeLayers.themis.add(dot);
          pickables.push(dot);
        }
        continue;
      }
      if (!["mars_landmark", "mineral_signature", "planned_waypoint"].includes(ft)) continue;
      const color = ft === "mineral_signature" ? 0xeab308 : ft === "planned_waypoint" ? 0xec4899 : 0xa855f7;
      const pin = new THREE.Mesh(pinGeom, new THREE.MeshBasicMaterial({ color }));
      pin.position.copy(latLonToVec3(lat, lon, GLOBE_R + 0.28));
      pin.userData = {
        name: props.name || props.feature_id,
        lat,
        lon,
        elevation_m: props.elevation_m,
        description: props.description || props.mineral_class || props.category || "",
      };
      const targetGroup =
        ft === "mineral_signature"
          ? globeLayers.minerals
          : ft === "planned_waypoint"
            ? globeLayers.planned
            : globeLayers.landmarks;
      targetGroup.add(pin);
      pickables.push(pin);
    }

    const trackColors = {
      msl_gale: 0x22c55e,
      mars2020_jezero: 0x38bdf8,
      mer_a_gusev: 0xf97316,
      mer_b_meridiani: 0xa855f7,
    };
    for (const [mid, pts] of Object.entries(roverTracks)) {
      if (pts.length > 1) {
        const line = new THREE.Line(
          new THREE.BufferGeometry().setFromPoints(pts),
          new THREE.LineBasicMaterial({ color: trackColors[mid] || 0x38bdf8 })
        );
        if (mid === "msl_gale") globeLayers.msl.add(line);
        else globeLayers.waypoints.add(line);
      }
    }

    window.syncGlobeLayers?.();
    statsEl.textContent = `3D Mars Globe (2048×1024) | Click any dot or point on Mars to inspect`;
  } finally {
    window.aresLoader?.hide();
  }
}

window.syncGlobeLayers = () => {
  const checked = (id) => Boolean(document.getElementById(id)?.checked);
  if (globeLayers.landmarks) globeLayers.landmarks.visible = checked("toggle-landmarks");
  if (globeLayers.minerals) globeLayers.minerals.visible = checked("toggle-minerals");
  if (globeLayers.planned) globeLayers.planned.visible = checked("toggle-planned");
  if (globeLayers.msl) globeLayers.msl.visible = checked("toggle-msl");
  if (globeLayers.waypoints) globeLayers.waypoints.visible = checked("toggle-waypoints");
  if (globeLayers.themis) globeLayers.themis.visible = checked("toggle-themis");
  if (globeLayers.aoi) globeLayers.aoi.visible = checked("toggle-aoi");
  if (globeRouteGroup) globeRouteGroup.visible = checked("toggle-eva") || globeRouteGroup.children.length > 0;
};

window.jumpGlobeTo = (lat, lon, label = "Quick Jump", zoom = 8) => {
  if (!camera || !controls || modeSelect.value !== "globe") return;
  const dist = zoom <= 2 ? 64 : zoom <= 6 ? 38 : 28;
  const targetPos = latLonToVec3(lat, lon, dist);
  camera.position.copy(targetPos);
  controls.target.set(0, 0, 0);
  controls.update();
  setGlobeSelectionHighlight(lat, lon);
  scheduleGlobeDetailUpdate();
  statsEl.textContent = `3D Mars Globe | Focused on ${label} (${lat.toFixed(2)}°, ${lon.toFixed(2)}°)`;
};

function scheduleGlobeDetailUpdate() {
  if (!camera || !globeSphere || modeSelect.value !== "globe" || modal.classList.contains("hidden")) return;
  if (globeDetailTimer) clearTimeout(globeDetailTimer);
  globeDetailTimer = setTimeout(updateGlobeDetailPatch, 260);
}

async function updateGlobeDetailPatch() {
  if (!camera || !globeSphere || !activeGroup || modeSelect.value !== "globe" || modal.classList.contains("hidden")) return;
  const dist = camera.position.length();
  const alt = dist - GLOBE_R;
  if (alt >= 22) {
    if (globeDetailMesh) globeDetailMesh.visible = false;
    return;
  }

  raycaster.setFromCamera(new THREE.Vector2(0, 0), camera);
  const hits = raycaster.intersectObject(globeSphere, false);
  if (!hits.length) return;
  const { lat, lon } = vec3ToLatLon(hits[0].point);

  const fovRad = THREE.MathUtils.degToRad((camera.fov || 48) * 0.5);
  const aspect = Math.max(1.0, camera.aspect || 1.6);
  const worldHalf = alt * Math.tan(fovRad) * aspect * 1.55;
  const halfLatDeg = Math.max(0.45, Math.min(14.0, THREE.MathUtils.radToDeg(worldHalf / GLOBE_R)));
  const cosLat = Math.max(0.25, Math.cos(THREE.MathUtils.degToRad(lat)));
  const halfLonDeg = Math.max(0.45, Math.min(18.0, halfLatDeg / cosLat));

  const minLat = Math.max(-85, lat - halfLatDeg);
  const maxLat = Math.min(85, lat + halfLatDeg);
  const minLon = Math.max(-179.5, lon - halfLonDeg);
  const maxLon = Math.min(179.5, lon + halfLonDeg);
  if (maxLon - minLon < 0.05 || maxLat - minLat < 0.05) return;

  const key = `${minLon.toFixed(2)},${minLat.toFixed(2)},${maxLon.toFixed(2)},${maxLat.toFixed(2)}`;
  if (key === globeDetailKey && globeDetailMesh) {
    globeDetailMesh.visible = true;
    return;
  }
  globeDetailKey = key;

  const loader = new THREE.TextureLoader();
  const patchTex = await new Promise((resolve) => {
    loader.load(`/api/v1/map/regional-texture?bbox=${key}&size=1024`, resolve, undefined, () => resolve(null));
  });
  if (!patchTex || globeDetailKey !== key || modeSelect.value !== "globe") {
    patchTex?.dispose();
    return;
  }
  patchTex.colorSpace = THREE.SRGBColorSpace;
  patchTex.anisotropy = renderer.capabilities.getMaxAnisotropy();
  patchTex.minFilter = THREE.LinearMipmapLinearFilter;
  patchTex.magFilter = THREE.LinearFilter;

  const phiStart = THREE.MathUtils.degToRad(minLon + 180);
  const phiLength = THREE.MathUtils.degToRad(maxLon - minLon);
  const thetaStart = THREE.MathUtils.degToRad(90 - maxLat);
  const thetaLength = THREE.MathUtils.degToRad(maxLat - minLat);

  const geom = new THREE.SphereGeometry(GLOBE_R + 0.025, 48, 32, phiStart, phiLength, thetaStart, thetaLength);
  if (globeDetailMesh) {
    globeDetailMesh.geometry.dispose();
    globeDetailMesh.material.map?.dispose();
    globeDetailMesh.material.dispose();
    activeGroup.remove(globeDetailMesh);
  }
  globeDetailMesh = new THREE.Mesh(
    geom,
    new THREE.MeshStandardMaterial({
      map: patchTex,
      bumpMap: patchTex,
      bumpScale: 0.32,
      roughness: 0.88,
      metalness: 0.03,
    })
  );
  activeGroup.add(globeDetailMesh);
}

window.setGlobeTextureStyle = (layerId) => {
  const mapped = layerId === "mola_global_color" ? "mola" : "viking_red";
  if (globeTexSelect) globeTexSelect.value = mapped;
  if (!modal.classList.contains("hidden") && modeSelect.value === "globe") {
    buildGlobe();
  }
};

window.setGlobePlanMode = (enabled) => {
  globePlanMode = Boolean(enabled);
  globeRouteStart = null;
  btnPlanGlobeEva?.classList.toggle("active", globePlanMode);
};

async function loadLocalTerrain(bbox, label = "3D Local Terrain") {
  lastBbox = bbox;
  clearGroup();
  syncControlsVisibility();
  infoCard.classList.add("hidden");
  controls.minDistance = 5;
  controls.maxDistance = 180;
  controls.enablePan = true;
  controls.rotateSpeed = 0.7;

  const centerLon = (bbox[0] + bbox[2]) / 2;
  const centerLat = (bbox[1] + bbox[3]) / 2;

  if (!chunkMgr) {
    chunkMgr = new MarsChunkManager(activeGroup, {
      elevScale: 0.08,
      colorMode: colorSelect.value,
      exag: Number(exagInput.value || 3),
      onStats: ({ loaded, centerLon: cLon, centerLat: cLat }) => {
        statsEl.textContent =
          `${label} | 5×5 Chunks Active: ${loaded}/25 | Center: ${cLat.toFixed(3)}°, ${cLon.toFixed(3)}° | WASD/Arrows move`;
      },
    });
  } else {
    chunkMgr.colorMode = colorSelect.value;
    chunkMgr.exag = Number(exagInput.value || 3);
  }

  const start = chunkMgr.reset(centerLon, centerLat);
  horizonSkirt = new THREE.Mesh(
    new THREE.RingGeometry(145, 560, 48),
    new THREE.MeshStandardMaterial({ color: 0x4d2b1f, roughness: 0.95, side: THREE.DoubleSide })
  );
  horizonSkirt.rotation.x = -Math.PI / 2;
  horizonSkirt.position.set(start.x, -4, start.z);
  activeGroup.add(horizonSkirt);

  controls.target.set(start.x, 0, start.z);
  camera.position.set(start.x, 38, start.z + 55);
  controls.update();

  statsEl.textContent = `Streaming 3×3 Mars chunks around ${centerLat.toFixed(3)}°, ${centerLon.toFixed(3)}°...`;
  await chunkMgr.updateAround(start.x, start.z);
  if (Array.isArray(window.aresRouteStops) && window.aresRouteStops.length) {
    drawRoutePath3D(activeGroup, window.aresRouteStops, chunkMgr);
  }
  if (window.aresRoverTracks) {
    for (const track of Object.values(window.aresRoverTracks)) {
      if (track?.points?.length > 1) {
        drawRoutePath3D(activeGroup, track.points, chunkMgr, {
          color: track.color,
          showBeacons: false,
          showCones: false,
          radius: 0.18,
        });
      }
    }
  }
}

function applyGameMovement() {
  if (!keysPressed.size || !camera || !controls || modeSelect.value === "globe") return;
  const speed = 0.75;
  const forward = new THREE.Vector3();
  camera.getWorldDirection(forward);
  forward.y = 0;
  if (forward.lengthSq() > 1e-6) forward.normalize();
  const right = new THREE.Vector3().crossVectors(forward, new THREE.Vector3(0, 1, 0)).normalize();

  const delta = new THREE.Vector3();
  if (keysPressed.has("KeyW") || keysPressed.has("ArrowUp")) delta.addScaledVector(forward, speed);
  if (keysPressed.has("KeyS") || keysPressed.has("ArrowDown")) delta.addScaledVector(forward, -speed);
  if (keysPressed.has("KeyD") || keysPressed.has("ArrowRight")) delta.addScaledVector(right, speed);
  if (keysPressed.has("KeyA") || keysPressed.has("ArrowLeft")) delta.addScaledVector(right, -speed);
  if (keysPressed.has("KeyE") || keysPressed.has("Space")) delta.y += speed * 0.7;
  if (keysPressed.has("KeyQ") || keysPressed.has("ShiftLeft")) delta.y -= speed * 0.7;

  if (delta.lengthSq() > 0) {
    camera.position.add(delta);
    controls.target.add(delta);
    if (horizonSkirt) {
      horizonSkirt.position.x = controls.target.x;
      horizonSkirt.position.z = controls.target.z;
    }
    chunkMgr?.updateAround(controls.target.x, controls.target.z);
  }
}

function animate() {
  animId = requestAnimationFrame(animate);
  applyGameMovement();
  if (modeSelect.value === "globe" && controls) {
    // Scale rotation speed smoothly by altitude above Mars surface so close-up zooming isn't twitchy
    const dist = camera.position.length();
    controls.rotateSpeed = Math.max(0.12, Math.min(0.85, (dist - GLOBE_R) / 30));
    // Keep globe pins constant apparent size as user zooms in
    for (const pin of pickables) {
      const d = camera.position.distanceTo(pin.position);
      const s = Math.max(0.03, Math.min(1.15, d / 54));
      pin.scale.setScalar(s);
    }
    if (globeRouteGroup) {
      for (const child of globeRouteGroup.children) {
        if (!child.userData?.isRoutePin) continue;
        const d = camera.position.distanceTo(child.position);
        const s = Math.max(0.03, Math.min(1.15, d / 48));
        child.scale.setScalar(s);
      }
    }
    if (globeSelectionMarker && globeSelectionMarker.visible) {
      const d = camera.position.distanceTo(globeSelectionMarker.position);
      const s = Math.max(0.03, Math.min(1.35, d / 48));
      globeSelectionMarker.scale.setScalar(s);
      const pulse = globeSelectionMarker.getObjectByName("pulseRing");
      if (pulse) {
        const t = 1.0 + 0.22 * Math.sin(performance.now() * 0.005);
        pulse.scale.setScalar(t);
      }
    }
  }
  if (mroSat) {
    mroAngle += 0.01;
    const R_orb = GLOBE_R + 3.8;
    mroSat.position.set(Math.cos(mroAngle) * R_orb, Math.sin(mroAngle) * R_orb, 0);
  }
  controls.update();
  if (modeSelect.value === "terrain" && chunkMgr && t3dScaleLabel && controls && canvas) {
    const dist = camera.position.distanceTo(controls.target);
    const { barLabel, altLabel } = computeScaleReadout(dist, camera.fov, canvas.clientHeight, 90);
    t3dScaleLabel.textContent = `90px ≈ ${barLabel} · Dist ${altLabel} · 1 Chunk = 4.7 km`;
  }
  renderer.render(scene, camera);
}

window.open3DGlobe = async function () {
  document.getElementById("streetview-modal")?.classList.add("hidden");
  modal.classList.remove("hidden");
  ensureScene();
  resizeCanvas();
  modeSelect.value = "globe";
  await buildGlobe();
  if (!animId) animate();
};

window.open3DTerrain = async function (bbox, label = "3D Local Terrain") {
  document.getElementById("streetview-modal")?.classList.add("hidden");
  modal.classList.remove("hidden");
  ensureScene();
  resizeCanvas();
  modeSelect.value = "terrain";
  await loadLocalTerrain(bbox, label);
  if (!animId) animate();
};

modeSelect.addEventListener("change", () => {
  if (modeSelect.value === "globe") buildGlobe();
  else loadLocalTerrain(lastBbox, "Regional 3D Terrain");
});
globeTexSelect.addEventListener("change", () => {
  if (modeSelect.value === "globe") buildGlobe();
});
exagInput.addEventListener("input", () => {
  if (modeSelect.value === "terrain") chunkMgr?.rebuildAll(colorSelect.value, Number(exagInput.value || 3));
});
colorSelect.addEventListener("change", () => {
  if (modeSelect.value === "terrain") chunkMgr?.rebuildAll(colorSelect.value, Number(exagInput.value || 3));
});

document.getElementById("globe-info-close").addEventListener("click", () => {
  infoCard.classList.add("hidden");
});

btnPlanGlobeEva?.addEventListener("click", () => {
  globePlanMode = !globePlanMode;
  globeRouteStart = null;
  btnPlanGlobeEva.classList.toggle("active", globePlanMode);
  statsEl.textContent = globePlanMode
    ? "Globe EVA Mode: Click Start point on Mars Globe"
    : "3D Mars Globe (2048×1024) | Click any dot or point on Mars to inspect";
});

const _SVG_3D_MAX = `<svg class="lucide-icon" width="13" height="13" viewBox="0 0 24 24"><path d="M15 3h6v6"/><path d="M9 21H3v-6"/><path d="M21 3l-7 7"/><path d="M3 21l7-7"/></svg>`;
const _SVG_3D_MIN = `<svg class="lucide-icon" width="13" height="13" viewBox="0 0 24 24"><path d="M4 14h6v6"/><path d="M20 10h-6V4"/><path d="M14 10l7-7"/><path d="M3 21l7-7"/></svg>`;

const btnFullscreen3d = document.getElementById("btn-fullscreen-3d");
btnFullscreen3d?.addEventListener("click", () => {
  const isFull = modal.classList.toggle("fullscreen");
  btnFullscreen3d.classList.toggle("active", isFull);
  btnFullscreen3d.innerHTML = isFull ? `${_SVG_3D_MIN} Exit Fullscreen` : `${_SVG_3D_MAX} Fullscreen`;
  resizeCanvas();
});

document.getElementById("btn-close-3d").addEventListener("click", () => {
  modal.classList.add("hidden");
  modal.classList.remove("fullscreen");
  if (btnFullscreen3d) {
    btnFullscreen3d.classList.remove("active");
    btnFullscreen3d.innerHTML = `${_SVG_3D_MAX} Fullscreen`;
  }
  if (animId) {
    cancelAnimationFrame(animId);
    animId = null;
  }
});
