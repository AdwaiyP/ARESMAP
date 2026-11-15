import * as THREE from "three";
import { MarsChunkManager, CHUNK_DEG, CHUNK_WORLD, drawRoutePath3D, computeScaleReadout } from "./chunks3d.js";

const modal = document.getElementById("streetview-modal");
const canvas = document.getElementById("sv-canvas");
const hudHeading = document.getElementById("sv-heading");
const hudWpBadge = document.getElementById("sv-wp-badge");
const hudMeta = document.getElementById("sv-meta");
const stripEl = document.getElementById("sv-filmstrip");
const photoBox = document.getElementById("sv-photo-preview");
const photoImg = document.getElementById("sv-photo-img");
const photoLabel = document.getElementById("sv-photo-label");
const visorSafetyEl = document.getElementById("visor-safety");
const visorWpCurrentEl = document.getElementById("visor-wp-current");
const visorWpRemainingEl = document.getElementById("visor-wp-remaining");
const visorWpProgressEl = document.getElementById("visor-wp-progress");
const visorNextEl = document.getElementById("visor-next");
const visorPlssEl = document.getElementById("visor-plss");
const visorPnrEl = document.getElementById("visor-pnr");
const visorLanderEl = document.getElementById("visor-lander");
const btnDroneView = document.getElementById("sv-view-drone");
const btnAstroView = document.getElementById("sv-view-astro");
const btnRoverView = document.getElementById("sv-view-rover");
const btnPathView = document.getElementById("sv-view-path");
const btnSetLander = document.getElementById("sv-set-lander");
const btnFogToggle = document.getElementById("sv-toggle-fog");
const nearbyListEl = document.getElementById("sv-nearby-list");
const navArrowBox = document.getElementById("sv-nav-arrow");
const navPointerEl = document.getElementById("sv-nav-pointer");
const navLabelEl = document.getElementById("sv-nav-label");
const scaleLabelEl = document.getElementById("sv-scale-label");

let renderer, scene, camera, terrainGroup, routeGroup, svChunkMgr, svHorizon;
let yawDeg = 0;
let pitchDeg = -22;
let dragging = false;
let lastX = 0;
let lastY = 0;
let animId = null;
let currentLabel = "Mars Surface";
let currentStepTag = "";
let walkedMeters = 0;
let viewMode = "drone"; // "drone" | "astronaut" | "rover" | "overview"
let droneAltitude = 45;
let fogEnabled = true;
let playerPos = { x: 0, z: 0 };
let playerAvatar = null;
let landerMesh = null;
let landingSite = null; // { lon, lat, label }
const _SV_FOG_COLOR = 0x4a2c22;
const _SV_FOG_DENSITY = 0.00035;
const svKeys = new Set();

// Route stops for Prev / Next Street View stepping
let activeStops = [];
let activeStopIdx = 0;

function ensureRenderer() {
  if (renderer) return;
  renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  scene = new THREE.Scene();
  // Martian dusty butterscotch sky
  scene.background = new THREE.Color(_SV_FOG_COLOR);
  scene.fog = fogEnabled ? new THREE.FogExp2(_SV_FOG_COLOR, _SV_FOG_DENSITY) : null;

  camera = new THREE.PerspectiveCamera(68, 16 / 9, 0.05, 8000);
  camera.rotation.order = "YXZ";

  scene.add(new THREE.AmbientLight(0xffd7c2, 0.45));
  scene.add(new THREE.HemisphereLight(0xffcfb8, 0x3f2117, 0.75));
  const sun = new THREE.DirectionalLight(0xfff1e0, 1.35);
  sun.position.set(500, 700, 400);
  scene.add(sun);

  terrainGroup = new THREE.Group();
  scene.add(terrainGroup);

  routeGroup = new THREE.Group();
  scene.add(routeGroup);

  svChunkMgr = new MarsChunkManager(terrainGroup, {
    chunkWorld: 1200,
    gridN: 64,
    elevScale: 0.253,
    colorMode: "orbital",
    exag: 3.0,
    onStats: ({ loaded, centerLon, centerLat }) => {
      const tag = currentStepTag ? ` (${currentStepTag})` : "";
      hudMeta.textContent =
        `${currentLabel}${tag} · ${centerLat.toFixed(4)}°, ${centerLon.toFixed(4)}° · ` +
        `5×5 Chunks: ${loaded}/25 · WASD fly`;
    },
  });

  canvas.addEventListener("pointerdown", (e) => {
    dragging = true;
    lastX = e.clientX;
    lastY = e.clientY;
    canvas.setPointerCapture(e.pointerId);
  });
  canvas.addEventListener("pointermove", (e) => {
    if (!dragging) return;
    const dx = e.clientX - lastX;
    const dy = e.clientY - lastY;
    lastX = e.clientX;
    lastY = e.clientY;
    yawDeg = (yawDeg - dx * 0.25 + 360) % 360;
    pitchDeg = Math.max(-45, Math.min(45, pitchDeg - dy * 0.2));
    updateCameraRotation();
  });
  canvas.addEventListener("pointerup", () => {
    dragging = false;
  });
  window.addEventListener("keydown", (e) => {
    if (modal.classList.contains("hidden")) return;
    if (["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName)) return;
    svKeys.add(e.code);
  });
  window.addEventListener("keyup", (e) => {
    svKeys.delete(e.code);
  });
  window.addEventListener("resize", resizeCanvas);
}

function resizeCanvas() {
  if (!renderer || modal.classList.contains("hidden")) return;
  const rect = canvas.parentElement.getBoundingClientRect();
  renderer.setSize(rect.width, rect.height, false);
  camera.aspect = rect.width / Math.max(1, rect.height);
  camera.updateProjectionMatrix();
}

function compassDir(deg) {
  const dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
  return dirs[Math.round(((deg % 360) / 45)) % 8];
}

function updateCameraRotation() {
  if (!camera) return;
  // yawDeg=0 looks North (-Z in Three.js)
  camera.rotation.y = THREE.MathUtils.degToRad(-yawDeg);
  camera.rotation.x = THREE.MathUtils.degToRad(pitchDeg);
  if (playerAvatar && (viewMode === "astronaut" || viewMode === "rover")) {
    playerAvatar.rotation.y = THREE.MathUtils.degToRad(-yawDeg);
    positionCameraForMode();
  }
  hudHeading.textContent = `HDG ${String(Math.round(yawDeg)).padStart(3, "0")}° ${compassDir(yawDeg)}`;
  if (svChunkMgr) {
    const px = viewMode === "astronaut" || viewMode === "rover" ? playerPos.x : camera.position.x;
    const pz = viewMode === "astronaut" || viewMode === "rover" ? playerPos.z : camera.position.z;
    const { lon, lat } = svChunkMgr.worldToLonLat(px, pz);
    updateVisorHud(px, pz, lon, lat);
  }
}

function clearRouteGroup() {
  while (routeGroup.children.length) {
    const c = routeGroup.children.pop();
    c.traverse?.((obj) => {
      obj.geometry?.dispose();
      if (Array.isArray(obj.material)) obj.material.forEach((m) => m.dispose());
      else obj.material?.dispose();
    });
  }
  svHorizon = null;
  playerAvatar = null;
  landerMesh = null;
}

function buildAstronautMesh() {
  const g = new THREE.Group();
  const suitMat = new THREE.MeshStandardMaterial({ color: 0xf1f5f9, roughness: 0.55 });
  const visorMat = new THREE.MeshStandardMaterial({ color: 0xf59e0b, metalness: 0.7, roughness: 0.2 });
  const packMat = new THREE.MeshStandardMaterial({ color: 0x94a3b8, roughness: 0.6 });
  // Legs
  const legGeo = new THREE.BoxGeometry(0.22, 0.65, 0.22);
  const legL = new THREE.Mesh(legGeo, suitMat);
  legL.position.set(-0.15, 0.325, 0);
  const legR = new THREE.Mesh(legGeo, suitMat);
  legR.position.set(0.15, 0.325, 0);
  // Torso + PLSS backpack
  const torso = new THREE.Mesh(new THREE.BoxGeometry(0.54, 0.68, 0.32), suitMat);
  torso.position.set(0, 0.98, 0);
  const plss = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.56, 0.24), packMat);
  plss.position.set(0, 1.0, 0.24);
  // Helmet + gold visor (facing -Z)
  const helmet = new THREE.Mesh(new THREE.SphereGeometry(0.24, 16, 12), suitMat);
  helmet.position.set(0, 1.52, 0);
  const visor = new THREE.Mesh(new THREE.SphereGeometry(0.19, 14, 10), visorMat);
  visor.position.set(0, 1.52, -0.09);
  g.add(legL, legR, torso, plss, helmet, visor);
  g.scale.setScalar(0.32); // ~0.55 units = ~2.1 m tall EVA astronaut
  return g;
}

function buildRoverMesh() {
  const g = new THREE.Group();
  const bodyMat = new THREE.MeshStandardMaterial({ color: 0xeab308, metalness: 0.35, roughness: 0.45 });
  const darkMat = new THREE.MeshStandardMaterial({ color: 0x1e293b, roughness: 0.85 });
  const mastMat = new THREE.MeshStandardMaterial({ color: 0xe2e8f0, metalness: 0.4, roughness: 0.4 });
  const body = new THREE.Mesh(new THREE.BoxGeometry(1.3, 0.55, 2.0), bodyMat);
  body.position.set(0, 0.65, 0);
  g.add(body);
  const wheelGeo = new THREE.CylinderGeometry(0.28, 0.28, 0.22, 12);
  wheelGeo.rotateZ(Math.PI / 2);
  for (const x of [-0.76, 0.76]) {
    for (const z of [-0.75, 0, 0.75]) {
      const w = new THREE.Mesh(wheelGeo, darkMat);
      w.position.set(x, 0.28, z);
      g.add(w);
    }
  }
  const mast = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.08, 0.95, 8), mastMat);
  mast.position.set(0, 1.35, -0.65);
  const camHead = new THREE.Mesh(new THREE.BoxGeometry(0.38, 0.2, 0.24), mastMat);
  camHead.position.set(0, 1.82, -0.65);
  g.add(mast, camHead);
  g.scale.setScalar(0.45); // ~0.9 units = ~3.5 m long Mars rover
  return g;
}

function buildLanderMesh() {
  const g = new THREE.Group();
  const padMat = new THREE.MeshStandardMaterial({ color: 0x334155, roughness: 0.8 });
  const ringMat = new THREE.MeshStandardMaterial({ color: 0x38bdf8, emissive: 0x0284c7, emissiveIntensity: 0.6 });
  const hullMat = new THREE.MeshStandardMaterial({ color: 0xf8fafc, metalness: 0.3, roughness: 0.4 });
  const noseMat = new THREE.MeshStandardMaterial({ color: 0xf97316, roughness: 0.45 });
  const legMat = new THREE.MeshStandardMaterial({ color: 0x94a3b8, metalness: 0.5, roughness: 0.4 });

  const pad = new THREE.Mesh(new THREE.CylinderGeometry(3.4, 3.8, 0.22, 16), padMat);
  pad.position.y = 0.11;
  const beaconRing = new THREE.Mesh(new THREE.RingGeometry(3.5, 4.0, 24), ringMat);
  beaconRing.rotation.x = -Math.PI / 2;
  beaconRing.position.y = 0.24;

  const stage = new THREE.Mesh(new THREE.CylinderGeometry(1.2, 1.45, 2.2, 14), hullMat);
  stage.position.y = 1.6;
  const nose = new THREE.Mesh(new THREE.ConeGeometry(1.2, 1.6, 14), noseMat);
  nose.position.y = 3.5;

  for (let i = 0; i < 4; i++) {
    const ang = (i * Math.PI) / 2 + Math.PI / 4;
    const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.14, 1.5, 6), legMat);
    leg.position.set(Math.cos(ang) * 1.45, 0.65, Math.sin(ang) * 1.45);
    leg.rotation.z = Math.cos(ang) * 0.42;
    leg.rotation.x = -Math.sin(ang) * 0.42;
    g.add(leg);
  }
  g.add(pad, beaconRing, stage, nose);
  g.scale.setScalar(0.95); // ~4.1 units = ~16 m tall Mars Ascent Vehicle
  return g;
}

function scatterMarsRocks(centerX, centerZ) {
  if (!routeGroup || !svChunkMgr) return;
  const count = 240;
  const rockGeom = new THREE.DodecahedronGeometry(0.18, 0);
  const rockMat = new THREE.MeshStandardMaterial({
    color: 0x5c382c,
    roughness: 0.94,
    metalness: 0.05,
  });
  const rocks = new THREE.InstancedMesh(rockGeom, rockMat, count);
  const dummy = new THREE.Object3D();
  const c = new THREE.Color();
  // Deterministic PRNG so rocks stay consistent
  let seed = 4201;
  const rand = () => {
    seed = (seed * 16807) % 2147483647;
    return (seed - 1) / 2147483646;
  };
  for (let i = 0; i < count; i++) {
    const r = 4 + rand() * 140;
    const ang = rand() * Math.PI * 2;
    const rx = centerX + Math.cos(ang) * r;
    const rz = centerZ + Math.sin(ang) * r;
    const ry = svChunkMgr.getGroundY(rx, rz);
    const sx = 0.5 + rand() * 2.2;
    const sy = 0.35 + rand() * 1.1;
    const sz = 0.5 + rand() * 2.0;
    dummy.position.set(rx, ry + sy * 0.06, rz);
    dummy.rotation.set(rand() * Math.PI, rand() * Math.PI, rand() * Math.PI);
    dummy.scale.set(sx, sy, sz);
    dummy.updateMatrix();
    rocks.setMatrixAt(i, dummy.matrix);
    c.setHSL(0.04 + rand() * 0.03, 0.35 + rand() * 0.2, 0.22 + rand() * 0.16);
    rocks.setColorAt(i, c);
  }
  rocks.instanceMatrix.needsUpdate = true;
  if (rocks.instanceColor) rocks.instanceColor.needsUpdate = true;
  routeGroup.add(rocks);
}

function syncLanderInScene() {
  if (!routeGroup || !svChunkMgr || !landingSite) return;
  if (!landerMesh) {
    landerMesh = buildLanderMesh();
    routeGroup.add(landerMesh);
  }
  const pos = svChunkMgr.lonLatToWorld(landingSite.lon, landingSite.lat);
  const gy = svChunkMgr.getGroundY(pos.x, pos.z);
  landerMesh.position.set(pos.x, gy, pos.z);
}

function syncPlayerAvatar() {
  if (!routeGroup || !svChunkMgr) return;
  if (playerAvatar) {
    routeGroup.remove(playerAvatar);
    playerAvatar = null;
  }
  if (viewMode !== "astronaut" && viewMode !== "rover") return;
  playerAvatar = viewMode === "astronaut" ? buildAstronautMesh() : buildRoverMesh();
  const gy = svChunkMgr.getGroundY(playerPos.x, playerPos.z);
  playerAvatar.position.set(playerPos.x, gy, playerPos.z);
  playerAvatar.rotation.y = THREE.MathUtils.degToRad(-yawDeg);
  routeGroup.add(playerAvatar);
}

function positionCameraForMode() {
  if (!camera || !svChunkMgr) return;
  const gy = svChunkMgr.getGroundY(playerPos.x, playerPos.z);
  if (viewMode === "astronaut" || viewMode === "rover") {
    const az = THREE.MathUtils.degToRad(yawDeg);
    const backDist = viewMode === "astronaut" ? 1.15 : 1.75;
    const camHeight = viewMode === "astronaut" ? 0.65 : 0.95;
    const cx = playerPos.x - Math.sin(az) * backDist;
    const cz = playerPos.z + Math.cos(az) * backDist;
    const midY = svChunkMgr.getGroundY((playerPos.x + cx) * 0.5, (playerPos.z + cz) * 0.5);
    const cgy = svChunkMgr.getGroundY(cx, cz);
    camera.position.set(cx, Math.max(gy, midY, cgy) + camHeight, cz);
  } else {
    const eyeOffset = viewMode === "overview" ? Math.max(droneAltitude, 520) : droneAltitude;
    camera.position.set(playerPos.x, gy + eyeOffset, playerPos.z);
  }
}

function drawRouteBeacons(stops) {
  drawRoutePath3D(routeGroup, stops, svChunkMgr);
}

function updateVisorHud(wx, wz, lon, lat) {
  if (!svChunkMgr || !visorSafetyEl) return;
  const hereSlope = svChunkMgr.getSlopeAt(wx, wz);
  const hereY = svChunkMgr.getGroundY(wx, wz);

  // Forward terrain lookahead radar along current heading (3..15 world units ahead)
  const az = THREE.MathUtils.degToRad(yawDeg);
  const fwdX = Math.sin(az);
  const fwdZ = -Math.cos(az);
  let maxAheadSlope = 0;
  let maxDrop = 0;
  let nearestHazardUnits = Infinity;
  for (const dist of [3, 6, 9, 12, 15]) {
    const fx = wx + fwdX * dist;
    const fz = wz + fwdZ * dist;
    const s = svChunkMgr.getSlopeAt(fx, fz);
    const drop = hereY - svChunkMgr.getGroundY(fx, fz);
    maxAheadSlope = Math.max(maxAheadSlope, s);
    maxDrop = Math.max(maxDrop, drop);
    if ((s >= 22 || drop >= 2.2) && dist < nearestHazardUnits) {
      nearestHazardUnits = dist;
    }
  }

  if (hereSlope >= 25) {
    visorSafetyEl.className = "pill hazard";
    visorSafetyEl.textContent = `HAZARD · ${hereSlope.toFixed(1)}°`;
  } else if (nearestHazardUnits < Infinity) {
    const aheadM = Math.round(nearestHazardUnits * ((CHUNK_DEG * 59274) / CHUNK_WORLD));
    visorSafetyEl.className = "pill hazard";
    visorSafetyEl.innerHTML = `<svg class="lucide-icon" width="12" height="12" viewBox="0 0 24 24"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg> DROP/CLIFF AHEAD · ~${aheadM}m`;
  } else if (hereSlope >= 15 || maxAheadSlope >= 15) {
    visorSafetyEl.className = "pill caution";
    visorSafetyEl.textContent = `CAUTION · ${Math.max(hereSlope, maxAheadSlope).toFixed(1)}°`;
  } else {
    visorSafetyEl.className = "pill ok";
    visorSafetyEl.textContent = `NOMINAL · ${hereSlope.toFixed(1)}°`;
  }

  // Auto-advance activeStopIdx when Astronaut/Rover/Drone reaches a forward waypoint (<= 22m)
  if (activeStops.length > 1 && activeStopIdx < activeStops.length - 1) {
    for (let j = activeStopIdx + 1; j < activeStops.length; j++) {
      const st = activeStops[j];
      const sLatM = (st.lat - lat) * 59274;
      const sLonM = (st.lon - lon) * 59274 * Math.cos((lat * Math.PI) / 180);
      const sDistM = Math.hypot(sLonM, sLatM);
      if (sDistM <= 22) {
        activeStopIdx = j;
        currentStepTag = `${activeStopIdx + 1}/${activeStops.length}`;
      } else {
        break;
      }
    }
  }

  const totalWps = Math.max(1, activeStops.length);
  const currentWpNum = Math.min(totalWps, activeStopIdx + 1);
  const remainingWps = Math.max(0, totalWps - currentWpNum);
  const curStop = activeStops[activeStopIdx] || { label: currentLabel };
  const curStopLabel = curStop.label || `WP ${currentWpNum}`;

  const svgCheck = `<svg class="lucide-icon" width="11" height="11" viewBox="0 0 24 24"><path d="M20 6 9 17l-5-5"/></svg>`;
  const svgPin = `<svg class="lucide-icon" width="12" height="12" viewBox="0 0 24 24"><path d="M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0"/><circle cx="12" cy="10" r="3"/></svg>`;
  const svgCurrent = `<svg class="lucide-icon" width="10" height="10" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="3" fill="currentColor"/></svg>`;
  const svgPending = `<svg class="lucide-icon" width="10" height="10" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/></svg>`;

  if (visorWpCurrentEl) {
    visorWpCurrentEl.textContent = `WP ${currentWpNum} / ${totalWps} · ${curStopLabel}`;
  }
  if (visorWpRemainingEl) {
    if (remainingWps === 0 && totalWps > 1) {
      visorWpRemainingEl.className = "pill ok";
      visorWpRemainingEl.innerHTML = `0 Remaining · Complete ${svgCheck}`;
    } else {
      visorWpRemainingEl.className = remainingWps > 0 ? "pill caution" : "pill ok";
      visorWpRemainingEl.textContent = `${remainingWps} Remaining`;
    }
  }
  if (hudWpBadge) {
    hudWpBadge.innerHTML =
      remainingWps === 0 && totalWps > 1
        ? `${svgPin} WP ${currentWpNum} / ${totalWps} · COMPLETE ${svgCheck}`
        : `${svgPin} WP ${currentWpNum} / ${totalWps} · ${remainingWps} Left`;
  }
  if (visorWpProgressEl) {
    const pct = totalWps > 1 ? Math.round((currentWpNum / totalWps) * 100) : 100;
    const chipsHtml = activeStops
      .map((s, i) => {
        const cls = i < activeStopIdx ? "done" : i === activeStopIdx ? "current" : "";
        const icon = i < activeStopIdx ? svgCheck : i === activeStopIdx ? svgCurrent : svgPending;
        return `<button type="button" class="visor-wp-chip ${cls}" data-wpidx="${i}" title="Jump to WP ${i + 1}: ${s.label || ""}">${icon} WP${i + 1}</button>`;
      })
      .join("");
    const sig = `${activeStopIdx}:${totalWps}`;
    if (visorWpProgressEl.dataset.sig !== sig) {
      visorWpProgressEl.dataset.sig = sig;
      visorWpProgressEl.innerHTML = `
        <div class="visor-wp-bar"><div class="visor-wp-fill" style="width:${pct}%"></div></div>
        <div class="visor-wp-chips">${chipsHtml}</div>
      `;
      visorWpProgressEl.querySelectorAll(".visor-wp-chip").forEach((btn) => {
        btn.addEventListener("click", () => {
          const idx = Number(btn.dataset.wpidx);
          if (!Number.isNaN(idx)) loadStop(idx);
        });
      });
    }
  }

  const routeTarget = activeStops[activeStopIdx + 1] || null;
  const navTarget = routeTarget || landingSite;
  const navPrefix = routeTarget ? `WP ${currentWpNum + 1}` : "LANDER";

  if (routeTarget) {
    const dLatM = (routeTarget.lat - lat) * 59274;
    const dLonM = (routeTarget.lon - lon) * 59274 * Math.cos((lat * Math.PI) / 180);
    const distM = Math.hypot(dLonM, dLatM);
    const brg = Math.round(((Math.atan2(dLonM, dLatM) * 180) / Math.PI + 360) % 360);
    visorNextEl.textContent = `WP ${currentWpNum + 1} · ${Math.round(distM)} m @ ${String(brg).padStart(3, "0")}°`;
  } else if (totalWps > 1) {
    visorNextEl.innerHTML = `All Waypoints Reached ${svgCheck}`;
  } else {
    visorNextEl.textContent = "Free Roam";
  }

  if (navArrowBox && navPointerEl && navLabelEl && navTarget) {
    const dLatM = (navTarget.lat - lat) * 59274;
    const dLonM = (navTarget.lon - lon) * 59274 * Math.cos((lat * Math.PI) / 180);
    const distM = Math.hypot(dLonM, dLatM);
    const brg = Math.round(((Math.atan2(dLonM, dLatM) * 180) / Math.PI + 360) % 360);
    const rel = ((brg - yawDeg + 540) % 360) - 180;
    navArrowBox.classList.remove("hidden");
    const arrowScale = distM < 300 ? 1.15 : distM < 1500 ? 1.0 : 0.88;
    navArrowBox.style.transform = `translateX(-50%) scale(${arrowScale})`;
    navPointerEl.style.transform = `rotate(${rel.toFixed(1)}deg)`;
    const aligned = Math.abs(rel) < 20;
    navPointerEl.style.color = aligned ? "#22c55e" : "#facc15";
    navLabelEl.textContent = aligned
      ? `${navPrefix} AHEAD · ${Math.round(distM)} m`
      : `${navPrefix} ${rel > 0 ? "RIGHT" : "LEFT"} ${Math.abs(Math.round(rel))}° · ${Math.round(distM)} m`;
  } else {
    navArrowBox?.classList.add("hidden");
  }
  if (scaleLabelEl && camera && canvas) {
    const altUnits = Math.max(0.25, camera.position.y - hereY);
    const { barLabel, altLabel } = computeScaleReadout(
      altUnits,
      camera.fov,
      canvas.clientHeight,
      90,
      svChunkMgr.metersPerUnit
    );
    scaleLabelEl.textContent = `90px ≈ ${barLabel} · ALT ${altLabel} · 1 Chunk = 4.7 km`;
  }

  const plss = window.aresPlssState || { initO2: 82, initBat: 76, metabolicW: 310 };
  const workFactor = Math.max(0.4, (plss.metabolicW || 310) / 310);
  const o2 = Math.max(0, (plss.initO2 ?? 82) - walkedMeters * 0.012 * workFactor);
  const bat = Math.max(0, (plss.initBat ?? 76) - walkedMeters * 0.01 * workFactor);
  visorPlssEl.textContent = `${o2.toFixed(0)}% · ${bat.toFixed(0)}%`;
  const pnrOk = o2 > 35 && bat > 30;
  visorPnrEl.textContent = `${Math.round(walkedMeters)} m · ${pnrOk ? "PNR OK" : "RETURN NOW"}`;
  if (window.updatePlssWalked) window.updatePlssWalked(walkedMeters);

  if (visorLanderEl) {
    if (landingSite) {
      const lLatM = (landingSite.lat - lat) * 59274;
      const lLonM = (landingSite.lon - lon) * 59274 * Math.cos((lat * Math.PI) / 180);
      const lDist = Math.round(Math.hypot(lLonM, lLatM));
      const lBrg = Math.round(((Math.atan2(lLonM, lLatM) * 180) / Math.PI + 360) % 360);
      visorLanderEl.textContent = `${lDist} m @ ${String(lBrg).padStart(3, "0")}°`;
    } else {
      visorLanderEl.textContent = "Not Set";
    }
  }
}

function applyStreetWalk() {
  if (!svKeys.size || !camera || !svChunkMgr) return;
  const isGrounded = viewMode === "astronaut" || viewMode === "rover";
  const hereSlope = isGrounded ? svChunkMgr.getSlopeAt(playerPos.x, playerPos.z) : 0;
  const slopeFactor = isGrounded ? Math.max(0.35, 1 - hereSlope / 45) : 1;
  const baseSpeed =
    viewMode === "overview"
      ? 4.5
      : viewMode === "astronaut"
      ? 0.025
      : viewMode === "rover"
      ? 0.085
      : 2.2;
  const speed = baseSpeed * slopeFactor;
  const az = THREE.MathUtils.degToRad(yawDeg);
  const fwdX = Math.sin(az);
  const fwdZ = -Math.cos(az);
  const rightX = Math.cos(az);
  const rightZ = Math.sin(az);

  let dx = 0;
  let dz = 0;
  let altChanged = false;
  if (svKeys.has("KeyW") || svKeys.has("ArrowUp")) { dx += fwdX * speed; dz += fwdZ * speed; }
  if (svKeys.has("KeyS") || svKeys.has("ArrowDown")) { dx -= fwdX * speed; dz -= fwdZ * speed; }
  if (svKeys.has("KeyD") || svKeys.has("ArrowRight")) { dx += rightX * speed; dz += rightZ * speed; }
  if (svKeys.has("KeyA") || svKeys.has("ArrowLeft")) { dx -= rightX * speed; dz -= rightZ * speed; }
  if (!isGrounded && (svKeys.has("KeyE") || svKeys.has("Space"))) {
    droneAltitude = Math.min(900, droneAltitude + 4.0);
    altChanged = true;
  }
  if (!isGrounded && (svKeys.has("KeyQ") || svKeys.has("ShiftLeft"))) {
    droneAltitude = Math.max(4, droneAltitude - 4.0);
    altChanged = true;
  }

  if (dx === 0 && dz === 0 && !altChanged) return;
  const nx = (isGrounded ? playerPos.x : camera.position.x) + dx;
  const nz = (isGrounded ? playerPos.z : camera.position.z) + dz;
  playerPos = { x: nx, z: nz };
  if (viewMode === "drone" || isGrounded) {
    walkedMeters += Math.hypot(dx, dz) * svChunkMgr.metersPerUnit;
  }

  const groundY = svChunkMgr.getGroundY(nx, nz);
  if (playerAvatar && isGrounded) {
    playerAvatar.position.set(nx, groundY + 0.02, nz);
    playerAvatar.rotation.y = THREE.MathUtils.degToRad(-yawDeg);
  }
  positionCameraForMode();
  if (viewMode !== "overview") {
    if (svHorizon) {
      svHorizon.position.set(nx, groundY - 3, nz);
    }
    svChunkMgr.updateAround(nx, nz);
  }

  const { lon, lat } = svChunkMgr.worldToLonLat(nx, nz);
  updateVisorHud(nx, nz, lon, lat);
  const tag = currentStepTag ? ` (${currentStepTag})` : "";
  const modeAction =
    viewMode === "astronaut"
      ? "WASD walk"
      : viewMode === "rover"
      ? "WASD drive"
      : "WASD fly";
  const chunkStatus =
    viewMode === "overview"
      ? `5×5 Island Locked: ${svChunkMgr.chunks.size}/25`
      : `5×5 Chunks: ${svChunkMgr.chunks.size}/25`;
  hudMeta.textContent =
    `${currentLabel}${tag} · ${lat.toFixed(4)}°, ${lon.toFixed(4)}° · ` +
    `${chunkStatus} · ${modeAction}`;
}

function animate() {
  animId = requestAnimationFrame(animate);
  applyStreetWalk();
  renderer.render(scene, camera);
}

async function loadStop(idx) {
  if (!activeStops.length) return;
  activeStopIdx = Math.max(0, Math.min(activeStops.length - 1, idx));
  const stop = activeStops[activeStopIdx];
  window.aresLoader?.show(`Streaming Mars 360° terrain & imagery for ${stop.label || "EVA Stop"}...`, 40);
  try {
    await loadPatchAt(stop.lon, stop.lat, stop.label || "EVA Stop", `${activeStopIdx + 1}/${activeStops.length}`);
  } finally {
    window.aresLoader?.hide();
  }
  if (activeStopIdx + 1 < activeStops.length) {
    const nxt = activeStops[activeStopIdx + 1];
    const brg = (Math.atan2(nxt.lon - stop.lon, nxt.lat - stop.lat) * 180) / Math.PI;
    yawDeg = (brg + 360) % 360;
  }
  updateCameraRotation();
}

async function loadPatchAt(lon, lat, label = "Mars Surface", stepTag = "") {
  currentLabel = label;
  currentStepTag = stepTag;
  clearRouteGroup();

  hudMeta.textContent = `Streaming 3×3 chunks for ${label} (${lat.toFixed(4)}°, ${lon.toFixed(4)}°)...`;
  photoBox.classList.add("hidden");

  const start = svChunkMgr.reset(lon, lat);
  camera.position.set(start.x, 2.5, start.z);

  const [svRes] = await Promise.all([
    fetch(`/api/v1/map/streetview?lon=${lon}&lat=${lat}&radius_m=8000&limit=8`),
    svChunkMgr.updateAround(start.x, start.z),
  ]);
  const sv = await svRes.json();

  const groundY = svChunkMgr.getGroundY(start.x, start.z);
  playerPos = { x: start.x, z: start.z };
  if (!landingSite) {
    landingSite = { lon, lat, label: "Rocket Landing Site" };
  }
  syncLanderInScene();
  scatterMarsRocks(start.x, start.z);
  syncPlayerAvatar();
  positionCameraForMode();

  svHorizon = new THREE.Mesh(
    new THREE.RingGeometry(2400, 6800, 48),
    new THREE.MeshStandardMaterial({ color: 0x5c3324, roughness: 0.96, side: THREE.DoubleSide })
  );
  svHorizon.rotation.x = -Math.PI / 2;
  svHorizon.position.set(start.x, groundY - 20, start.z);
  routeGroup.add(svHorizon);

  drawRouteBeacons(activeStops);
  if (window.aresRoverTracks) {
    for (const track of Object.values(window.aresRoverTracks)) {
      if (track?.points?.length > 1) {
        drawRoutePath3D(routeGroup, track.points, svChunkMgr, {
          color: track.color,
          showBeacons: false,
          showCones: false,
          radius: 0.1,
        });
      }
    }
  }
  updateVisorHud(start.x, start.z, lon, lat);

  // Plot nearby geological/rover features as 3D pins + clickable visor intel
  const nearby = Array.isArray(sv.nearby_features) ? sv.nearby_features : [];
  for (const nf of nearby) {
    if (!nf.coordinates || nf.coordinates.length < 2) continue;
    const pos = svChunkMgr.lonLatToWorld(nf.coordinates[0], nf.coordinates[1]);
    const gy = svChunkMgr.getGroundY(pos.x, pos.z);
    const pinColor =
      nf.feature_type === "mineral_signature"
        ? 0xf59e0b
        : nf.has_panorama
        ? 0x38bdf8
        : 0x22c55e;
    const pin = new THREE.Mesh(
      new THREE.OctahedronGeometry(0.45, 0),
      new THREE.MeshStandardMaterial({ color: pinColor, emissive: pinColor, emissiveIntensity: 0.35 })
    );
    pin.position.set(pos.x, gy + 1.2, pos.z);
    routeGroup.add(pin);
  }

  if (nearbyListEl) {
    const topNearby = nearby.slice(0, 4);
    if (!topNearby.length) {
      nearbyListEl.innerHTML = `<span class="muted">No catalogued features within 12 km</span>`;
    } else {
      nearbyListEl.innerHTML =
        `<div class="visor-label" style="margin-top:4px;">NEARBY AREA INTEL (${nearby.length})</div>` +
        topNearby
          .map(
            (nf, idx) => `
          <button class="visor-nearby-btn" data-nfidx="${idx}" title="Click to look toward ${nf.name}">
            <span>${nf.has_panorama ? '<svg class="lucide-icon" width="12" height="12" viewBox="0 0 24 24"><path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"/><circle cx="12" cy="13" r="3"/></svg> ' : ""}${nf.name}</span>
            <span class="muted">${nf.distance_m < 1000 ? `${Math.round(nf.distance_m)}m` : `${(nf.distance_m / 1000).toFixed(1)}km`} @ ${Math.round(nf.bearing_deg)}°</span>
          </button>`
          )
          .join("");
      nearbyListEl.querySelectorAll(".visor-nearby-btn").forEach((b) => {
        b.addEventListener("click", () => {
          const nf = topNearby[Number(b.dataset.nfidx)];
          if (!nf) return;
          yawDeg = nf.bearing_deg || 0;
          pitchDeg = -10;
          updateCameraRotation();
        });
      });
    }
  }

  const tag = stepTag ? ` (${stepTag})` : "";
  hudMeta.textContent =
    `${label}${tag} · ${lat.toFixed(4)}°, ${lon.toFixed(4)}° · ` +
    `5×5 Chunks: ${svChunkMgr.chunks.size}/25 · WASD fly`;

  const allMedia = [
    ...(Array.isArray(sv.panoramas) ? sv.panoramas : []).map((p) => ({
      ...p,
      _kind: "360° PANO",
      instrument: p.rover || "360° Pano",
      mast_az_deg: p.bearing_deg || 0,
      mast_el_deg: 0,
    })),
    ...(Array.isArray(sv.photos) ? sv.photos : []).map((p) => ({
      ...p,
      _kind: p.mission || "ROVER CAM",
    })),
  ];

  svActiveMedia = allMedia;
  svActiveMediaIdx = -1;
  if (!allMedia.length) {
    stripEl.innerHTML = `<span class="muted">No cached rover photos or 360° panoramas nearby.</span>`;
  } else {
    stripEl.innerHTML = allMedia
      .map(
        (p, i) => `
        <button class="sv-thumb" data-pidx="${i}">
          <img src="${p.proxy_url}" alt="${p.instrument}" loading="lazy" />
          <span>${p.is_panorama ? "360° PANO · " : ""}Sol ${p.sol ?? "?"} · ${p.instrument} · ${Math.round(p.mast_az_deg || 0)}°</span>
        </button>`
      )
      .join("");
    stripEl.querySelectorAll(".sv-thumb").forEach((btn) => {
      btn.addEventListener("click", () => selectRoverPhoto(Number(btn.dataset.pidx)));
    });
  }
}

let svActiveMedia = [];
let svActiveMediaIdx = -1;

function selectRoverPhoto(idx) {
  if (!svActiveMedia.length) return;
  svActiveMediaIdx = ((idx % svActiveMedia.length) + svActiveMedia.length) % svActiveMedia.length;
  const p = svActiveMedia[svActiveMediaIdx];
  stripEl.querySelectorAll(".sv-thumb").forEach((el, i) => el.classList.toggle("active", i === svActiveMediaIdx));
  if (typeof p.mast_az_deg === "number" && !Number.isNaN(p.mast_az_deg)) {
    yawDeg = p.mast_az_deg;
    pitchDeg = Math.max(-35, Math.min(35, p.mast_el_deg || 0));
    updateCameraRotation();
  }
  photoImg.src = p.proxy_url;
  photoLabel.textContent = p.is_panorama
    ? `360° Panorama · ${p.name} (Sol ${p.sol ?? "?"}) · ${Math.round(p.distance_m)}m @ ${Math.round(p.bearing_deg)}°`
    : `${p._kind} · Sol ${p.sol ?? "?"} · ${p.instrument} · Az ${p.mast_az_deg}° · ${p.date_taken_mars || ""}`;
  photoBox.classList.remove("hidden");
}

function setPhotoExpanded(expanded) {
  photoBox.classList.toggle("expanded", expanded);
  const expBtn = document.getElementById("sv-expand-photo");
  if (expBtn) expBtn.textContent = expanded ? "Shrink" : "Enlarge";
}

function buildLocalTraverseStops(lon, lat, baseLabel = "EVA Traverse") {
  const cosLat = Math.max(0.2, Math.cos((lat * Math.PI) / 180));
  const offsetsMeters = [
    [0, 0, `${baseLabel} Start`],
    [25, 65, "Ridge Check"],
    [60, 125, "Regolith Sample"],
    [35, 195, "Outcrop Scan"],
    [80, 260, "EVA Goal"],
  ];
  return offsetsMeters.map(([eastM, northM, lbl]) => ({
    lon: lon + eastM / (59274 * cosLat),
    lat: lat + northM / 59274,
    label: lbl,
  }));
}

window.openStreetView = async function (lon, lat, label = "EVA Site", routeStops = null) {
  window.aresCloseSidebars?.();
  document.getElementById("terrain-3d-modal")?.classList.add("hidden");
  modal.classList.remove("hidden");
  ensureRenderer();
  resizeCanvas();

  walkedMeters = 0;
  if (Array.isArray(routeStops) && routeStops.length > 0) {
    activeStops = routeStops;
    activeStopIdx = 0;
  } else {
    activeStops = [{ lon, lat, label }];
    activeStopIdx = 0;
  }
  if (visorWpProgressEl) visorWpProgressEl.dataset.sig = "";

  await loadStop(activeStopIdx);
  if (!animId) animate();
};

document.getElementById("sv-prev").addEventListener("click", () => loadStop(activeStopIdx - 1));
document.getElementById("sv-next").addEventListener("click", () => loadStop(activeStopIdx + 1));

window.jumpStreetViewTo = async (lat, lon, label = "Quick Jump") => {
  if (modal.classList.contains("hidden")) {
    await window.openStreetView(lon, lat, label);
    return;
  }
  walkedMeters = 0;
  activeStops = [{ lon, lat, label }];
  activeStopIdx = 0;
  if (visorWpProgressEl) visorWpProgressEl.dataset.sig = "";
  await loadStop(0);
};

const svJumpSelect = document.getElementById("sv-jump");
const svMarkBtn = document.getElementById("sv-mark-jump");

function populateSvJump() {
  if (!svJumpSelect) return;
  const regions = window.ARES_REGIONS || {
    mtsharp: { center: [-5.1, 137.8] },
    gale: { center: [-4.5, 137.4] },
    jezero: { center: [18.45, 77.4] },
    ares_vallis: { center: [19.33, -33.55] },
    gusev: { center: [-14.57, 175.48] },
    meridiani: { center: [-1.95, -5.53] },
    valles_marineris: { center: [-13.9, -59.2] },
  };
  const labels = {
    mtsharp: "Mount Sharp",
    gale: "Gale Crater",
    jezero: "Jezero (M20)",
    ares_vallis: "Ares Vallis",
    gusev: "Gusev Crater",
    meridiani: "Meridiani Planum",
    valles_marineris: "Valles Marineris",
  };
  svJumpSelect.innerHTML = `<option value="">Quick Jump...</option>`;
  Object.entries(labels).forEach(([k, name]) => {
    const r = regions[k];
    if (!r) return;
    const opt = document.createElement("option");
    opt.value = `${r.center[0]},${r.center[1]}|${name}`;
    opt.textContent = name;
    svJumpSelect.appendChild(opt);
  });
  (window.getCustomJumps?.() || []).forEach((item) => {
    const opt = document.createElement("option");
    opt.value = `${item.lat},${item.lon}|${item.label}`;
    opt.textContent = `★ ${item.label}`;
    svJumpSelect.appendChild(opt);
  });
}

populateSvJump();
window.addEventListener("ares-custom-jumps-changed", populateSvJump);

svJumpSelect?.addEventListener("change", () => {
  const val = svJumpSelect.value;
  if (!val) return;
  const [coords, label] = val.split("|");
  const [lat, lon] = coords.split(",").map(Number);
  if (Number.isFinite(lat) && Number.isFinite(lon)) {
    window.jumpStreetViewTo(lat, lon, label || "Quick Jump");
  }
  svJumpSelect.value = "";
});

svMarkBtn?.addEventListener("click", () => {
  const stop = activeStops[activeStopIdx];
  const curLon = svChunkMgr && camera ? svChunkMgr.originLon + camera.position.x / 59274 : stop?.lon;
  const curLat = svChunkMgr && camera ? svChunkMgr.originLat - camera.position.z / 59274 : stop?.lat;
  if (!Number.isFinite(curLat) || !Number.isFinite(curLon)) return;
  const label = window.prompt(
    `Name Quick Jump at ${curLat.toFixed(4)}°, ${curLon.toFixed(4)}°:`,
    currentLabel || "Street View Bookmark"
  );
  if (label && label.trim()) {
    window.saveCustomJumpAt?.(curLat, curLon, label.trim());
  }
});

async function setExplorerViewMode(mode) {
  viewMode = mode;
  btnDroneView?.classList.toggle("active", mode === "drone");
  btnAstroView?.classList.toggle("active", mode === "astronaut");
  btnRoverView?.classList.toggle("active", mode === "rover");
  btnPathView?.classList.toggle("active", mode === "overview");
  if (mode === "overview") {
    droneAltitude = 550;
    pitchDeg = -68;
    if (activeStops.length > 1) {
      const midLon = activeStops.reduce((s, p) => s + p.lon, 0) / activeStops.length;
      const midLat = activeStops.reduce((s, p) => s + p.lat, 0) / activeStops.length;
      await loadPatchAt(midLon, midLat, "Full Path Overview", `${activeStops.length} stops`);
    } else if (camera && svChunkMgr) {
      syncPlayerAvatar();
      positionCameraForMode();
    }
    updateCameraRotation();
  } else if (mode === "astronaut" || mode === "rover") {
    pitchDeg = -14;
    if (camera && svChunkMgr) {
      syncPlayerAvatar();
      positionCameraForMode();
      updateCameraRotation();
    } else {
      await loadStop(activeStopIdx);
    }
  } else {
    droneAltitude = 45;
    pitchDeg = -22;
    if (camera && svChunkMgr) {
      syncPlayerAvatar();
      positionCameraForMode();
      updateCameraRotation();
    } else {
      await loadStop(activeStopIdx);
    }
  }
}

btnDroneView?.addEventListener("click", () => setExplorerViewMode("drone"));
btnAstroView?.addEventListener("click", () => setExplorerViewMode("astronaut"));
btnRoverView?.addEventListener("click", () => setExplorerViewMode("rover"));
btnPathView?.addEventListener("click", () => setExplorerViewMode("overview"));
btnSetLander?.addEventListener("click", () => {
  if (!svChunkMgr) return;
  const { lon, lat } = svChunkMgr.worldToLonLat(playerPos.x, playerPos.z);
  landingSite = { lon, lat, label: "Rocket Landing Site" };
  syncLanderInScene();
  updateVisorHud(playerPos.x, playerPos.z, lon, lat);
  window.aresSetLandingSiteMarker?.(lat, lon);
});
const _SVG_FOG = `<svg class="lucide-icon" width="13" height="13" viewBox="0 0 24 24"><path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242"/><path d="M16 17H7"/><path d="M17 21H9"/></svg>`;
const _SVG_MAX = `<svg class="lucide-icon" width="13" height="13" viewBox="0 0 24 24"><path d="M15 3h6v6"/><path d="M9 21H3v-6"/><path d="M21 3l-7 7"/><path d="M3 21l7-7"/></svg>`;
const _SVG_MIN = `<svg class="lucide-icon" width="13" height="13" viewBox="0 0 24 24"><path d="M4 14h6v6"/><path d="M20 10h-6V4"/><path d="M14 10l7-7"/><path d="M3 21l7-7"/></svg>`;

btnFogToggle?.addEventListener("click", () => {
  fogEnabled = !fogEnabled;
  if (scene) {
    scene.fog = fogEnabled ? new THREE.FogExp2(_SV_FOG_COLOR, _SV_FOG_DENSITY) : null;
  }
  btnFogToggle.classList.toggle("active", fogEnabled);
  btnFogToggle.innerHTML = `${_SVG_FOG} ${fogEnabled ? "Dust Fog: ON" : "Dust Fog: OFF"}`;
});
const btnSvFullscreen = document.getElementById("sv-fullscreen");
btnSvFullscreen?.addEventListener("click", () => {
  const isFull = modal.classList.toggle("fullscreen");
  btnSvFullscreen.classList.toggle("active", isFull);
  btnSvFullscreen.innerHTML = isFull ? `${_SVG_MIN} Exit Fullscreen` : `${_SVG_MAX} Fullscreen`;
  resizeCanvas();
});

document.getElementById("sv-close-photo").addEventListener("click", () => {
  photoBox.classList.add("hidden");
  setPhotoExpanded(false);
  stripEl.querySelectorAll(".sv-thumb").forEach((el) => el.classList.remove("active"));
});
document.getElementById("sv-expand-photo")?.addEventListener("click", () => {
  setPhotoExpanded(!photoBox.classList.contains("expanded"));
});
photoImg?.addEventListener("click", () => {
  setPhotoExpanded(!photoBox.classList.contains("expanded"));
});
document.getElementById("sv-photo-prev")?.addEventListener("click", () => {
  if (svActiveMedia.length) selectRoverPhoto(svActiveMediaIdx - 1);
});
document.getElementById("sv-photo-next")?.addEventListener("click", () => {
  if (svActiveMedia.length) selectRoverPhoto(svActiveMediaIdx + 1);
});
window.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && photoBox && !photoBox.classList.contains("hidden") && photoBox.classList.contains("expanded")) {
    setPhotoExpanded(false);
  }
});
document.getElementById("btn-close-sv").addEventListener("click", () => {
  modal.classList.add("hidden");
  modal.classList.remove("fullscreen");
  if (btnSvFullscreen) {
    btnSvFullscreen.classList.remove("active");
    btnSvFullscreen.innerHTML = `${_SVG_MAX} Fullscreen`;
  }
  if (animId) {
    cancelAnimationFrame(animId);
    animId = null;
  }
});
