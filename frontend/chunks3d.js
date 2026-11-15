import * as THREE from "three";

export const CHUNK_DEG = 0.08;   // ~4.7 km per Mars chunk
export const CHUNK_WORLD = 60.0; // Three.js world units per chunk (5x5 = 300x300)
export const CHUNK_RADIUS = 2;   // 5x5 sliding window (25 chunks)
export const METERS_PER_UNIT = (CHUNK_DEG * 59274) / CHUNK_WORLD; // ~79.0 m per world unit
const GRID_N = 32;               // 32x32 vertices per chunk (fast + shared border)

export function computeScaleReadout(altUnits, fovDeg, canvasHeightPx, barPx = 90, metersPerUnit = METERS_PER_UNIT) {
  const safeAlt = Math.max(0.25, altUnits);
  const safeH = Math.max(100, canvasHeightPx || 600);
  const mPerPx = ((2 * safeAlt * Math.tan(((fovDeg * Math.PI) / 180) / 2)) / safeH) * metersPerUnit;
  const barMeters = mPerPx * barPx;
  const barLabel = barMeters >= 1000 ? `${(barMeters / 1000).toFixed(1)} km` : `${Math.round(barMeters)} m`;
  const altMeters = safeAlt * metersPerUnit;
  const altLabel = altMeters >= 1000 ? `${(altMeters / 1000).toFixed(1)} km` : `${Math.round(altMeters)} m`;
  return { barLabel, altLabel };
}

let _regolithBumpTex = null;
function getRegolithBumpTexture() {
  if (_regolithBumpTex) return _regolithBumpTex;
  const size = 256;
  const c = document.createElement("canvas");
  c.width = size;
  c.height = size;
  const ctx = c.getContext("2d");
  const img = ctx.createImageData(size, size);
  let seed = 1337;
  const rand = () => {
    seed = (seed * 16807) % 2147483647;
    return (seed - 1) / 2147483646;
  };
  for (let y = 0; y < size; y++) {
    const ripple = Math.sin((y / size) * Math.PI * 16) * 20;
    for (let x = 0; x < size; x++) {
      const idx = (y * size + x) * 4;
      const grain = (rand() - 0.5) * 85;
      const pebble = rand() > 0.985 ? 70 : 0;
      const v = Math.max(0, Math.min(255, Math.round(128 + ripple + grain + pebble)));
      img.data[idx] = v;
      img.data[idx + 1] = v;
      img.data[idx + 2] = v;
      img.data[idx + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = THREE.RepeatWrapping;
  tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(48, 48);
  _regolithBumpTex = tex;
  return tex;
}

export class MarsChunkManager {
  constructor(parentGroup, opts = {}) {
    this.group = parentGroup;
    this.originCx = 0;
    this.originCy = 0;
    this.baseElev = null;
    this.chunkWorld = opts.chunkWorld ?? CHUNK_WORLD;
    this.gridN = opts.gridN ?? GRID_N;
    this.metersPerUnit = (CHUNK_DEG * 59274) / this.chunkWorld;
    this.elevScale = opts.elevScale ?? 0.06;
    this.colorMode = opts.colorMode ?? "orbital";
    this.exag = opts.exag ?? 3.0;
    this.chunks = new Map();  // key "cx,cy" -> { cx, cy, grid, texture, mesh }
    this.loading = new Set(); // keys currently fetching
    this.onStats = opts.onStats || null;
  }

  reset(centerLon, centerLat) {
    this.clear();
    this.originCx = Math.floor(centerLon / CHUNK_DEG);
    this.originCy = Math.floor(centerLat / CHUNK_DEG);
    this.baseElev = null;
    // Return camera world offset within the origin chunk
    const fracX = (centerLon / CHUNK_DEG) - this.originCx - 0.5;
    const fracZ = 0.5 - ((centerLat / CHUNK_DEG) - this.originCy);
    return { x: fracX * this.chunkWorld, z: fracZ * this.chunkWorld };
  }

  clear() {
    for (const ch of this.chunks.values()) {
      this.group.remove(ch.mesh);
      ch.mesh.geometry.dispose();
      ch.mesh.material.dispose();
      ch.texture?.dispose();
    }
    this.chunks.clear();
    this.loading.clear();
  }

  worldToLonLat(wx, wz) {
    const lon = (this.originCx + 0.5 + wx / this.chunkWorld) * CHUNK_DEG;
    const lat = (this.originCy + 0.5 - wz / this.chunkWorld) * CHUNK_DEG;
    return { lon, lat };
  }

  lonLatToWorld(lon, lat) {
    const x = (lon / CHUNK_DEG - this.originCx - 0.5) * this.chunkWorld;
    const z = (this.originCy + 0.5 - lat / CHUNK_DEG) * this.chunkWorld;
    return { x, z };
  }

  worldToChunk(wx, wz) {
    const cx = this.originCx + Math.floor(wx / this.chunkWorld + 0.5);
    const cy = this.originCy + Math.floor(0.5 - wz / this.chunkWorld);
    return { cx, cy };
  }

  async updateAround(wx, wz) {
    const { cx: curCx, cy: curCy } = this.worldToChunk(wx, wz);

    // Unload chunks outside 5x5 window (radius = 2)
    for (const [key, ch] of this.chunks.entries()) {
      if (Math.abs(ch.cx - curCx) > CHUNK_RADIUS || Math.abs(ch.cy - curCy) > CHUNK_RADIUS) {
        this.group.remove(ch.mesh);
        ch.mesh.geometry.dispose();
        ch.mesh.material.dispose();
        ch.texture?.dispose();
        this.chunks.delete(key);
      }
    }

    const innerJobs = [];
    const outerJobs = [];
    for (let ring = 0; ring <= CHUNK_RADIUS; ring++) {
      for (let dx = -ring; dx <= ring; dx++) {
        for (let dy = -ring; dy <= ring; dy++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) !== ring) continue;
          const cx = curCx + dx;
          const cy = curCy + dy;
          const key = `${cx},${cy}`;
          if (!this.chunks.has(key) && !this.loading.has(key)) {
            const p = this._loadChunk(cx, cy, key);
            if (ring <= 1) innerJobs.push(p);
            else outerJobs.push(p);
          }
        }
      }
    }

    const emitStats = () => {
      if (this.onStats) {
        const { lon, lat } = this.worldToLonLat(wx, wz);
        this.onStats({ loaded: this.chunks.size, centerLon: lon, centerLat: lat });
      }
    };

    if (innerJobs.length) {
      await Promise.all(innerJobs);
    }
    emitStats();

    if (outerJobs.length) {
      Promise.all(outerJobs).then(emitStats);
    }
  }

  async _loadChunk(cx, cy, key) {
    this.loading.add(key);
    const minLon = cx * CHUNK_DEG;
    const maxLon = (cx + 1) * CHUNK_DEG;
    const minLat = cy * CHUNK_DEG;
    const maxLat = (cy + 1) * CHUNK_DEG;
    const bbox = `${minLon.toFixed(5)},${minLat.toFixed(5)},${maxLon.toFixed(5)},${maxLat.toFixed(5)}`;

    try {
      const gridRes = await fetch(`/api/v1/map/terrain-grid?bbox=${bbox}&rows=${this.gridN}&cols=${this.gridN}`);
      if (!gridRes.ok) return;
      const grid = await gridRes.json();

      if (this.baseElev === null) {
        this.baseElev = grid.elevation_m[Math.floor(this.gridN / 2)][Math.floor(this.gridN / 2)];
      }

      // Render 3D terrain mesh immediately using vertex shading, then drape orbital imagery asynchronously
      const mesh = this._buildChunkMesh(cx, cy, grid, null);
      this.group.add(mesh);
      const ch = { cx, cy, grid, texture: null, mesh };
      this.chunks.set(key, ch);

      const texLoader = new THREE.TextureLoader();
      texLoader.load(
        `/api/v1/map/regional-texture?bbox=${bbox}`,
        (t) => {
          t.colorSpace = THREE.SRGBColorSpace;
          t.wrapS = THREE.ClampToEdgeWrapping;
          t.wrapT = THREE.ClampToEdgeWrapping;
          t.anisotropy = 16;
          if (!this.chunks.has(key)) {
            t.dispose();
            return;
          }
          ch.texture = t;
          this._applyPhotoRelief(ch);
          if (this.colorMode === "orbital") {
            mesh.material.dispose();
            mesh.material = this._applyGeometryAndMaterial(mesh.geometry, ch);
          }
          window.dispatchEvent(new CustomEvent("ares-chunk-relief"));
        }
      );
    } finally {
      this.loading.delete(key);
    }
  }

  _applyPhotoRelief(ch) {
    const img = ch.texture?.image;
    if (!img || !img.width || !img.height || ch.reliefApplied) return;
    ch.reliefApplied = true;

    const N = this.gridN;
    const c = document.createElement("canvas");
    c.width = N;
    c.height = N;
    const ctx = c.getContext("2d");
    ctx.drawImage(img, 0, 0, N, N);
    const data = ctx.getImageData(0, 0, N, N).data;

    const lum = new Float32Array(N * N);
    let mean = 0;
    for (let i = 0; i < N * N; i++) {
      const v = (0.299 * data[i * 4] + 0.587 * data[i * 4 + 1] + 0.114 * data[i * 4 + 2]) / 255;
      lum[i] = v;
      mean += v;
    }
    mean /= N * N;

    // Shape-from-shading micro-relief (tapered to 0 at chunk borders to preserve 0.0m seam alignment)
    const reliefAmp = this.chunkWorld > 200 ? 14.0 : 4.0;
    for (let r = 1; r < N - 1; r++) {
      for (let col = 1; col < N - 1; col++) {
        const borderFade = Math.min(1, Math.min(r, N - 1 - r, col, N - 1 - col) / 3);
        const delta = lum[r * N + col] - mean;
        ch.grid.elevation_m[r][col] += delta * reliefAmp * borderFade;
      }
    }
  }

  _buildChunkMesh(cx, cy, grid, tex) {
    const geom = new THREE.PlaneGeometry(this.chunkWorld, this.chunkWorld, this.gridN - 1, this.gridN - 1);
    geom.rotateX(-Math.PI / 2);
    const ch = { cx, cy, grid, texture: tex, mesh: null };
    const mat = this._applyGeometryAndMaterial(geom, ch);
    const mesh = new THREE.Mesh(geom, mat);
    mesh.position.set((cx - this.originCx) * this.chunkWorld, 0, (this.originCy - cy) * this.chunkWorld);
    return mesh;
  }

  _applyGeometryAndMaterial(geom, ch) {
    const { elevation_m, slope_deg } = ch.grid;
    const pos = geom.attributes.position;
    const colors = new Float32Array(pos.count * 3);
    const scale = this.elevScale * (this.exag / 3.0);

    for (let r = 0; r < this.gridN; r++) {
      for (let c = 0; c < this.gridN; c++) {
        const idx = r * this.gridN + c;
        const elev = elevation_m[r][c];
        pos.setY(idx, (elev - this.baseElev) * scale);

        const col = new THREE.Color();
        if (this.colorMode === "slope") {
          const deg = slope_deg[r][c];
          if (deg >= 25) col.setHex(0xef4444);
          else if (deg >= 15) col.setHex(0xfacc15);
          else col.setHex(0x22c55e);
        } else {
          const t = Math.max(0, Math.min(1, (elev - (this.baseElev - 400)) / 800));
          col.setHSL(0.04 + t * 0.05, 0.65 - t * 0.15, 0.24 + t * 0.44);
        }
        colors[idx * 3] = col.r;
        colors[idx * 3 + 1] = col.g;
        colors[idx * 3 + 2] = col.b;
      }
    }
    geom.setAttribute("color", new THREE.BufferAttribute(colors, 3));
    geom.computeVertexNormals();

    const bumpTex = this.colorMode === "orbital" && ch.texture ? ch.texture : getRegolithBumpTexture();
    const bumpScale =
      this.colorMode === "orbital" && ch.texture
        ? (this.chunkWorld > 200 ? 3.2 : 0.85)
        : (this.chunkWorld > 200 ? 0.35 : 0.08);
    if (this.colorMode === "orbital" && ch.texture) {
      return new THREE.MeshStandardMaterial({
        map: ch.texture,
        bumpMap: bumpTex,
        bumpScale,
        roughness: 0.94,
        metalness: 0.02,
      });
    }
    return new THREE.MeshStandardMaterial({
      vertexColors: true,
      bumpMap: bumpTex,
      bumpScale,
      roughness: 0.88,
      metalness: 0.04,
    });
  }

  rebuildAll(colorMode, exag) {
    this.colorMode = colorMode;
    this.exag = exag;
    for (const ch of this.chunks.values()) {
      ch.mesh.material.dispose();
      ch.mesh.material = this._applyGeometryAndMaterial(ch.mesh.geometry, ch);
    }
  }

  _sampleGridCoords(wx, wz) {
    const { cx, cy } = this.worldToChunk(wx, wz);
    const ch = this.chunks.get(`${cx},${cy}`);
    if (!ch) return null;
    const localX = wx - (cx - this.originCx) * this.chunkWorld;
    const localZ = wz - (this.originCy - cy) * this.chunkWorld;
    const u = Math.min(this.gridN - 1, Math.max(0, (localX / this.chunkWorld + 0.5) * (this.gridN - 1)));
    const v = Math.min(this.gridN - 1, Math.max(0, (localZ / this.chunkWorld + 0.5) * (this.gridN - 1)));
    const c0 = Math.min(this.gridN - 2, Math.floor(u));
    const r0 = Math.min(this.gridN - 2, Math.floor(v));
    return { grid: ch.grid, c0, r0, fx: u - c0, fz: v - r0 };
  }

  getGroundY(wx, wz) {
    const s = this._sampleGridCoords(wx, wz);
    if (!s) return 0;
    const { elevation_m } = s.grid;
    const e00 = elevation_m[s.r0][s.c0];
    const e01 = elevation_m[s.r0][s.c0 + 1];
    const e10 = elevation_m[s.r0 + 1][s.c0];
    const e11 = elevation_m[s.r0 + 1][s.c0 + 1];
    // Exact barycentric interpolation matching THREE.PlaneGeometry triangle split (fx + fz <= 1)
    const elev =
      s.fx + s.fz <= 1.0
        ? e00 + s.fx * (e01 - e00) + s.fz * (e10 - e00)
        : e11 + (1.0 - s.fx) * (e10 - e11) + (1.0 - s.fz) * (e01 - e11);
    return (elev - this.baseElev) * this.elevScale * (this.exag / 3.0);
  }

  getSlopeAt(wx, wz) {
    const s = this._sampleGridCoords(wx, wz);
    if (!s) return 0;
    const { slope_deg } = s.grid;
    const s00 = slope_deg[s.r0][s.c0];
    const s01 = slope_deg[s.r0][s.c0 + 1];
    const s10 = slope_deg[s.r0 + 1][s.c0];
    const s11 = slope_deg[s.r0 + 1][s.c0 + 1];
    return (
      s00 * (1 - s.fx) * (1 - s.fz) +
      s01 * s.fx * (1 - s.fz) +
      s10 * (1 - s.fx) * s.fz +
      s11 * s.fx * s.fz
    );
  }
}

/**
 * Plot 3D EVA route beacons, a glowing 3D path tube, and directional arrow cones
 * so the explorer can clearly see both the route and travel direction.
 */
export function drawRoutePath3D(targetGroup, stops, chunkMgr, opts = {}) {
  if (!targetGroup || !chunkMgr || !Array.isArray(stops) || !stops.length) return;
  const cw = chunkMgr.chunkWorld || CHUNK_WORLD;
  const isHumanScale = cw > 200;
  const {
    color = 0x22c55e,
    showBeacons = true,
    showCones = true,
    radius = isHumanScale ? 0.14 : 0.24,
    clearance = isHumanScale ? 0.65 : 1.35,
    beaconScale = isHumanScale ? 0.45 : 1.0,
  } = opts;
  const pts = [];
  for (const st of stops) {
    const x = (st.lon / CHUNK_DEG - chunkMgr.originCx - 0.5) * cw;
    const z = (chunkMgr.originCy + 0.5 - st.lat / CHUNK_DEG) * cw;
    const y = chunkMgr.getGroundY(x, z) + clearance;
    if (pts.length) {
      const prev = pts[pts.length - 1];
      if (Math.hypot(x - prev.x, z - prev.z) < 0.05) continue;
    }
    pts.push(new THREE.Vector3(x, y, z));
  }

  if (showBeacons) {
    for (let i = 0; i < pts.length; i++) {
      const p = pts[i];
      if (Math.abs(p.x) > cw * 3.0 || Math.abs(p.z) > cw * 3.0) continue;
      const isStart = i === 0;
      const isGoal = i === pts.length - 1 && pts.length > 1;
      const bColor = isStart ? 0x22c55e : isGoal ? 0xf59e0b : 0x38bdf8;
      const height = (isStart || isGoal ? 5.5 : 3.2) * beaconScale;
      const bRad = 0.28 * beaconScale;

      const beacon = new THREE.Mesh(
        new THREE.CylinderGeometry(bRad, bRad, height, 12),
        new THREE.MeshBasicMaterial({ color: bColor })
      );
      beacon.position.set(p.x, p.y + height * 0.4, p.z);
      targetGroup.add(beacon);

      const halo = new THREE.Mesh(
        new THREE.RingGeometry(0.45 * beaconScale, 0.75 * beaconScale, 16),
        new THREE.MeshBasicMaterial({ color: bColor, side: THREE.DoubleSide })
      );
      halo.rotation.x = -Math.PI / 2;
      halo.position.set(p.x, p.y - 0.15 * beaconScale, p.z);
      targetGroup.add(halo);
    }
  }

  if (pts.length > 1) {
    // Subsample every segment densely along the terrain surface (no Catmull-Rom overshoot)
    const sampleAboveGround = (sx, sz) => {
      const y0 = chunkMgr.getGroundY(sx, sz);
      const yMax = Math.max(
        y0,
        chunkMgr.getGroundY(sx + 0.18, sz),
        chunkMgr.getGroundY(sx - 0.18, sz),
        chunkMgr.getGroundY(sx, sz + 0.18),
        chunkMgr.getGroundY(sx, sz - 0.18)
      );
      return yMax + clearance;
    };

    const drapedPts = [];
    for (let i = 0; i < pts.length - 1; i++) {
      const a = pts[i];
      const b = pts[i + 1];
      const segLen = Math.hypot(b.x - a.x, b.z - a.z);
      const steps = Math.max(showBeacons ? 12 : 4, Math.min(80, Math.ceil(segLen * (showBeacons ? 4 : 1.5))));
      for (let s = 0; s < steps; s++) {
        const t = s / steps;
        const sx = a.x + (b.x - a.x) * t;
        const sz = a.z + (b.z - a.z) * t;
        drapedPts.push(new THREE.Vector3(sx, sampleAboveGround(sx, sz), sz));
      }
    }
    const last = pts[pts.length - 1];
    drapedPts.push(new THREE.Vector3(last.x, sampleAboveGround(last.x, last.z), last.z));

    const curvePath = new THREE.CurvePath();
    for (let i = 0; i < drapedPts.length - 1; i++) {
      if (drapedPts[i].distanceToSquared(drapedPts[i + 1]) > 1e-6) {
        curvePath.add(new THREE.LineCurve3(drapedPts[i], drapedPts[i + 1]));
      }
    }
    if (curvePath.curves.length > 0) {
      const tubeGeom = new THREE.TubeGeometry(curvePath, Math.max(32, Math.min(900, drapedPts.length)), radius, 6, false);
      const tubeMat = new THREE.MeshBasicMaterial({ color });
      const tubeMesh = new THREE.Mesh(tubeGeom, tubeMat);
      tubeMesh.renderOrder = 2;
      targetGroup.add(tubeMesh);
    }

    if (showCones) {
      // Directional cones along each segment floating cleanly above the terrain
      const up = new THREE.Vector3(0, 1, 0);
      for (let i = 0; i < pts.length - 1; i++) {
        const a = pts[i];
        const b = pts[i + 1];
        const dir = new THREE.Vector3().subVectors(b, a);
        const len = dir.length();
        if (len < 0.5) continue;
        dir.normalize();
        const mx = 0.5 * (a.x + b.x);
        const mz = 0.5 * (a.z + b.z);
        const my = chunkMgr.getGroundY(mx, mz) + 1.85;
        const cone = new THREE.Mesh(
          new THREE.ConeGeometry(0.48, 1.35, 10),
          new THREE.MeshBasicMaterial({ color: 0xfacc15 })
        );
        cone.position.set(mx, my, mz);
        cone.quaternion.setFromUnitVectors(up, dir);
        targetGroup.add(cone);
      }
    }
  }
}
