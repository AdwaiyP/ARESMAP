import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { MarsChunkManager, drawRoutePath3D, computeScaleReadout } from "./chunks3d.js";

let renderer, scene, camera, controls, activeGroup, mroSat, globeSphere;
let chunkMgr = null;
let horizonSkirt = null;
let pickables = [];
let globePlanMode = false;
let globeRouteStart = null;
let globeRouteGroup = null;
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
const globePlanBtn = document.getElementById("btn-globe-plan-eva");
const exagInput = document.getElementById("terrain-3d-exag");
const exagWrap = document.getElementById("exag-wrap");
const colorSelect = document.getElementById("terrain-3d-color");
const infoCard = document.getElementById("globe-info-card");
const infoTitle = document.getElementById("globe-info-title");
const infoBody = document.getElementById("globe-info-body");
const t3dScaleBar = document.getElementById("t3d-scale-bar");
const t3dScaleLabel = document.getElementById("t3d-scale-label");

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
  horizonSkirt = null;
  pickables = [];
  globeRouteGroup = null;
  globeRouteStart = null;
  globePlanMode = false;
  if (globePlanBtn) globePlanBtn.classList.remove("active");
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

async function handleGlobeRoutePoint(lat, lon) {
  if (!globeRouteGroup) {
    globeRouteGroup = new THREE.Group();
    activeGroup.add(globeRouteGroup);
  }
  if (!globeRouteStart) {
    globeRouteStart = { lat, lng: lon };
    while (globeRouteGroup.children.length) globeRouteGroup.remove(globeRouteGroup.children[0]);
    const startPin = new THREE.Mesh(
      new THREE.SphereGeometry(0.32, 14, 14),
      new THREE.MeshBasicMaterial({ color: 0x22c55e })
    );
    startPin.position.copy(latLonToVec3(lat, lon, GLOBE_R + 0.3));
    globeRouteGroup.add(startPin);
    statsEl.textContent = `EVA Start: ${lat.toFixed(3)}°, ${lon.toFixed(3)}° — Click Goal on Mars Globe`;
    infoCard.classList.remove("hidden");
    infoTitle.textContent = "Globe EVA Planner";
    infoBody.innerHTML = `<div>Start set at <strong>${lat.toFixed(4)}°, ${lon.toFixed(4)}°</strong>. Click a Goal point on the Mars Globe.</div>`;
    return;
  }

  const start = globeRouteStart;
  const goal = { lat, lng: lon };
  globeRouteStart = null;
  globePlanMode = false;
  if (globePlanBtn) globePlanBtn.classList.remove("active");

  const goalPin = new THREE.Mesh(
    new THREE.SphereGeometry(0.32, 14, 14),
    new THREE.MeshBasicMaterial({ color: 0xef4444 })
  );
  goalPin.position.copy(latLonToVec3(lat, lon, GLOBE_R + 0.3));
  globeRouteGroup.add(goalPin);

  infoCard.classList.remove("hidden");
  infoTitle.textContent = "Computing Globe EVA Route...";
  infoBody.innerHTML = `<div>Running terrain-aware A* / Theta* planner...</div>`;

  if (!window.planEvaBetween) {
    infoBody.innerHTML = `<div>Route planner unavailable.</div>`;
    return;
  }

  const res = await window.planEvaBetween(start, goal);
  if (!res || res.status !== "success" || !res.latLngs?.length) {
    infoTitle.textContent = "No Safe EVA Route";
    infoBody.innerHTML = `<div>${res?.message || "Blocked by steep terrain."}</div>`;
    statsEl.textContent = "Globe EVA Route: No safe path";
    return;
  }

  const pts = res.latLngs.map(([la, lo]) => latLonToVec3(la, lo, GLOBE_R + 0.24));
  const routeLine = new THREE.Line(
    new THREE.BufferGeometry().setFromPoints(pts),
    new THREE.LineBasicMaterial({ color: 0x38bdf8 })
  );
  globeRouteGroup.add(routeLine);

  infoTitle.textContent = "Globe EVA Route Ready";
  infoBody.innerHTML =
    `<div><strong>Status:</strong> ${res.routeStatus}</div>` +
    `<div><strong>Distance:</strong> ${Math.round(res.distM)} m (${res.walkMin} min)</div>` +
    `<div><strong>PLSS O₂ Est.:</strong> ~${res.o2Used}%</div>` +
    `<button id="btn-globe-walk-sv" style="margin-top:6px;width:100%;border-color:#22c55e;color:#bbf7d0;">Walk EVA in Street View</button>`;
  document.getElementById("btn-globe-walk-sv")?.addEventListener("click", () => {
    if (window.openStreetView) {
      window.openStreetView(start.lng, start.lat, "Globe EVA Route", res.stops || []);
    }
  });
  statsEl.textContent = `Globe EVA Route: ${Math.round(res.distM)} m · ${res.routeStatus}`;
}

async function inspectGlobeLocation(lat, lon, featureData = null) {
  infoCard.classList.remove("hidden");
  infoTitle.textContent = featureData?.name || "Mars Surface Point";
  const routeBtnLabel = globeRouteStart ? "Plan EVA Route to Here" : "Set as EVA Route Start";
  infoBody.innerHTML =
    `<div><strong>Lat / Lon:</strong> ${lat.toFixed(4)}°, ${lon.toFixed(4)}°</div>` +
    (featureData?.elevation_m != null ? `<div><strong>Elevation:</strong> ${featureData.elevation_m} m</div>` : "") +
    (featureData?.description ? `<div style="margin-top:3px;">${featureData.description}</div>` : "") +
    `<div id="globe-env-extra" style="margin-top:5px;">Querying elevation, thermal &amp; radiation...</div>` +
    `<button id="btn-globe-route-pt" style="margin-top:6px;width:100%;border-color:#22c55e;color:#bbf7d0;">${routeBtnLabel}</button>` +
    `<button id="btn-globe-zoom-local" style="margin-top:4px;width:100%;border-color:#38bdf8;color:#bae6fd;">Open 3D Local Terrain Here</button>`;

  document.getElementById("btn-globe-route-pt").addEventListener("click", () => {
    handleGlobeRoutePoint(lat, lon);
  });

  document.getElementById("btn-globe-zoom-local").addEventListener("click", () => {
    const pad = 0.2;
    modeSelect.value = "terrain";
    loadLocalTerrain([lon - pad, lat - pad, lon + pad, lat + pad], featureData?.name || "Selected Site");
  });

  const extraEl = document.getElementById("globe-env-extra");
  try {
    const pad = 0.25;
    const bbox = `${(lon - pad).toFixed(3)},${(lat - pad).toFixed(3)},${(lon + pad).toFixed(3)},${(lat + pad).toFixed(3)}`;
    const elevVal = featureData?.elevation_m ?? -3000;
    const [gridRes, telRes, climRes, radRes] = await Promise.all([
      fetch(`/api/v1/map/terrain-grid?bbox=${bbox}&rows=8&cols=8`),
      fetch("/api/v1/map/telemetry?station_id=jezero_meda_sol100"),
      fetch("/api/v1/climate/predict", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ latitude: lat, longitude: lon, ltst_time: "13:30", elevation_m: elevVal }),
      }).catch(() => null),
      fetch(`/api/v1/map/radiation?lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lon)}&elevation_m=${encodeURIComponent(elevVal)}`).catch(() => null),
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
    if (radRes && radRes.ok) {
      const rd = (await radRes.json()).radiation || {};
      lines.push(`<div><strong>Ionizing Rad (RAD):</strong> ${rd.total_dose_rate_usv_hr ?? "--"} µSv/hr (${rd.safety_state ?? "NOMINAL"})</div>`);
    }
    if (telRes.ok) {
      const tel = await telRes.json();
      const rec = (tel.records || [])[Math.floor((tel.records || []).length / 2)];
      if (rec) {
        lines.push(`<div><strong>MEDA Thermal (Sol 100):</strong> Air ${rec.air_temp_c_mean?.toFixed(1)}°C / Ground ${rec.ground_ir_temp_c_mean?.toFixed(1)}°C</div>`);
      }
    }
    extraEl.innerHTML = lines.join("") || "No environmental telemetry at this point.";
  } catch {
    extraEl.textContent = "Environmental query unavailable.";
  }
}

function handleGlobeClick(e) {
  const rect = canvas.getBoundingClientRect();
  pointerNDC.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
  pointerNDC.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;
  raycaster.setFromCamera(pointerNDC, camera);

  // 1. Check landmark/mineral/planned pins first
  const pinHits = raycaster.intersectObjects(pickables, false);
  if (pinHits.length > 0) {
    const ud = pinHits[0].object.userData;
    if (globePlanMode) handleGlobeRoutePoint(ud.lat, ud.lon);
    else inspectGlobeLocation(ud.lat, ud.lon, ud);
    return;
  }

  // 2. Otherwise check click on Mars sphere itself
  if (globeSphere) {
    const sphereHits = raycaster.intersectObject(globeSphere, false);
    if (sphereHits.length > 0) {
      const { lat, lon } = vec3ToLatLon(sphereHits[0].point);
      if (globePlanMode) handleGlobeRoutePoint(lat, lon);
      else inspectGlobeLocation(lat, lon, null);
    }
  }
}

function syncControlsVisibility() {
  const isGlobe = modeSelect.value === "globe";
  globeTexSelect.style.display = isGlobe ? "" : "none";
  if (globePlanBtn) globePlanBtn.style.display = isGlobe ? "" : "none";
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
  controls.minDistance = GLOBE_R + 2.5;
  controls.maxDistance = 95;
  controls.enablePan = false;
  controls.update();

  const loader = new THREE.TextureLoader();
  const tex = await new Promise((resolve, reject) => {
    loader.load(`/api/v1/map/globe-texture?style=${style}&z=2`, resolve, undefined, reject);
  });
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = renderer.capabilities.getMaxAnisotropy();

  globeSphere = new THREE.Mesh(
    new THREE.SphereGeometry(GLOBE_R, 72, 54),
    new THREE.MeshStandardMaterial({ map: tex, roughness: 0.88, metalness: 0.04 })
  );
  activeGroup.add(globeSphere);

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

  const res = await fetch("/api/v1/map/features?slim=true&limit=10000");
  const fc = await res.json();
  let pinCount = 0;
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
    activeGroup.add(pin);
    pickables.push(pin);
    pinCount++;
  }

  const trackColors = {
    msl_gale: 0x22c55e,
    mars2020_jezero: 0x38bdf8,
    mer_a_gusev: 0xf97316,
    mer_b_meridiani: 0xa855f7,
  };
  for (const [mid, pts] of Object.entries(roverTracks)) {
    if (pts.length > 1) {
      activeGroup.add(
        new THREE.Line(
          new THREE.BufferGeometry().setFromPoints(pts),
          new THREE.LineBasicMaterial({ color: trackColors[mid] || 0x38bdf8 })
        )
      );
    }
  }

  statsEl.textContent = `3D Mars Globe (2048×1024) | Click any dot or point on Mars to inspect`;
}

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
      const s = Math.max(0.14, Math.min(1.15, d / 54));
      pin.scale.setScalar(s);
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
globePlanBtn?.addEventListener("click", () => {
  globePlanMode = !globePlanMode;
  globeRouteStart = null;
  globePlanBtn.classList.toggle("active", globePlanMode);
  statsEl.textContent = globePlanMode
    ? "Globe EVA Planner: Click Start point on Mars Globe"
    : "Mars 3D Globe";
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

const btnFullscreen3d = document.getElementById("btn-fullscreen-3d");
btnFullscreen3d?.addEventListener("click", () => {
  const isFull = modal.classList.toggle("fullscreen");
  btnFullscreen3d.classList.toggle("active", isFull);
  btnFullscreen3d.textContent = isFull ? "🗗 Exit Fullscreen" : "⛶ Fullscreen";
  resizeCanvas();
});

document.getElementById("btn-close-3d").addEventListener("click", () => {
  modal.classList.add("hidden");
  modal.classList.remove("fullscreen");
  if (btnFullscreen3d) {
    btnFullscreen3d.classList.remove("active");
    btnFullscreen3d.textContent = "⛶ Fullscreen";
  }
  if (animId) {
    cancelAnimationFrame(animId);
    animId = null;
  }
});
