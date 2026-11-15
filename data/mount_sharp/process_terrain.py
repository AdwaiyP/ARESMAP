import os
import json
import shutil
from collections import deque
import numpy as np
import rasterio
from rasterio.windows import from_bounds
from rasterio.warp import reproject, Resampling, transform_bounds
from rasterio.crs import CRS
from rasterio.transform import from_origin

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = (
    os.path.join(BASE_DIR, "extracted")
    if os.path.exists(os.path.join(BASE_DIR, "extracted", "curiosity_hirise_mosaic.tif"))
    else BASE_DIR
)

HIRISE_PATH = os.path.join(DATA_DIR, "curiosity_hirise_mosaic.tif")
DEM_PATH = os.path.join(DATA_DIR, "Mars_MOLA_blend200ppx_HRSC_DEM_clon0dd_200mpp_lzw.tif")
OUT_DIR = os.path.join(BASE_DIR, "mount_sharp")

# Overlapping Curiosity / Lower Mount Sharp Foothills region inside HiRISE bounds (-4.925 to -4.249 lat, 137.122 to 137.730 lon)
LON_MIN, LAT_MIN = 137.30, -4.90
LON_MAX, LAT_MAX = 137.55, -4.65

# IAU Mars 2000 Sphere Equirectangular Projection centered on study region
MARS_RADIUS_M = 3396190.0
MARS_PROJ_CRS = CRS.from_proj4(
    f"+proj=eqc +lat_ts=-4.775 +lat_0=0 +lon_0=137.425 +x_0=0 +y_0=0 +a={MARS_RADIUS_M} +b={MARS_RADIUS_M} +units=m +no_defs"
)

DEM_CELL_SIZE_M = 200.0
MAP_CELL_SIZE_M = 5.0


def inspect_raster(path, label):
    print(f"\n--- Inspecting {label}: {path} ---")
    if not os.path.exists(path):
        raise FileNotFoundError(f"Missing required input file: {path}")
    with rasterio.open(path) as src:
        print(f"  Driver:      {src.driver}")
        print(f"  Dimensions:  {src.width} x {src.height} (bands: {src.count}, dtype: {src.dtypes[0]})")
        print(f"  Resolution:  {src.res}")
        print(f"  NoData:      {src.nodata}")
        print(f"  CRS:         {src.crs.to_string() if src.crs else 'None'}")
        print(f"  Bounds:      {src.bounds}")
        return {
            "path": os.path.basename(path),
            "width": src.width,
            "height": src.height,
            "bands": src.count,
            "dtype": src.dtypes[0],
            "res": list(src.res),
            "nodata": src.nodata,
            "crs_string": src.crs.to_string() if src.crs else None,
            "crs_wkt": src.crs.to_wkt() if src.crs else None,
            "bounds": list(src.bounds),
        }


def find_connected_endpoints(elevation, obstacles, cell_size_m, max_slope_deg=30.0):
    rows, cols = elevation.shape
    max_dz = np.tan(np.radians(max_slope_deg)) * cell_size_m

    valid_coords = np.argwhere(~obstacles)
    if len(valid_coords) < 2:
        raise RuntimeError("Insufficient valid terrain cells found in cropped DEM.")

    target_start = np.array([rows // 4, cols // 4])
    dists = np.linalg.norm(valid_coords - target_start, axis=1)
    sr, sc = valid_coords[np.argmin(dists)]

    visited = np.zeros((rows, cols), dtype=bool)
    visited[sr, sc] = True
    queue = deque([(sr, sc)])
    farthest = (sr, sc)
    max_dist = -1.0

    neighbors = [
        (-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0),
        (-1, -1, np.sqrt(2)), (-1, 1, np.sqrt(2)), (1, -1, np.sqrt(2)), (1, 1, np.sqrt(2)),
    ]

    while queue:
        r, c = queue.popleft()
        d = np.hypot(r - sr, c - sc)
        if d > max_dist:
            max_dist = d
            farthest = (r, c)

        for dr, dc, step_mult in neighbors:
            nr, nc = r + dr, c + dc
            if 0 <= nr < rows and 0 <= nc < cols and not visited[nr, nc] and not obstacles[nr, nc]:
                dz = abs(float(elevation[nr, nc]) - float(elevation[r, c]))
                if dz <= max_dz * step_mult:
                    visited[nr, nc] = True
                    queue.append((nr, nc))

    er, ec = farthest
    return {"x": int(sc), "y": int(sr)}, {"x": int(ec), "y": int(er)}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    dem_info = inspect_raster(DEM_PATH, "MOLA/HRSC DEM")
    hirise_info = inspect_raster(HIRISE_PATH, "HiRISE Mosaic")

    geo_crs = CRS.from_proj4(f"+proj=longlat +a={MARS_RADIUS_M} +b={MARS_RADIUS_M} +no_defs")
    proj_left, proj_bottom, proj_right, proj_top = transform_bounds(
        geo_crs, MARS_PROJ_CRS, LON_MIN, LAT_MIN, LON_MAX, LAT_MAX, densify_pts=21
    )

    proj_left = np.floor(proj_left / DEM_CELL_SIZE_M) * DEM_CELL_SIZE_M
    proj_bottom = np.floor(proj_bottom / DEM_CELL_SIZE_M) * DEM_CELL_SIZE_M
    proj_right = np.ceil(proj_right / DEM_CELL_SIZE_M) * DEM_CELL_SIZE_M
    proj_top = np.ceil(proj_top / DEM_CELL_SIZE_M) * DEM_CELL_SIZE_M

    dem_width = int(round((proj_right - proj_left) / DEM_CELL_SIZE_M))
    dem_height = int(round((proj_top - proj_bottom) / DEM_CELL_SIZE_M))
    dem_transform = from_origin(proj_left, proj_top, DEM_CELL_SIZE_M, DEM_CELL_SIZE_M)

    print(f"\nTarget DEM Grid: {dem_width} x {dem_height} ({dem_width * dem_height} cells) at {DEM_CELL_SIZE_M} m/px")
    if dem_width * dem_height > 250000:
        raise ValueError("Grid exceeds FastAPI 250,000-cell limit!")

    print("Processing DEM via windowed read...")
    with rasterio.open(DEM_PATH) as src:
        s_left, s_bottom, s_right, s_top = transform_bounds(
            MARS_PROJ_CRS, geo_crs, proj_left, proj_bottom, proj_right, proj_top, densify_pts=21
        )
        pad_x = abs(src.res[0]) * 5
        pad_y = abs(src.res[1]) * 5
        win = from_bounds(
            s_left - pad_x, s_bottom - pad_y, s_right + pad_x, s_top + pad_y, transform=src.transform
        )
        win = win.intersection(rasterio.windows.Window(0, 0, src.width, src.height))
        if win.width <= 0 or win.height <= 0:
            raise ValueError("Study region does not overlap DEM bounds!")

        win_transform = src.window_transform(win)
        src_data = src.read(1, window=win).astype(np.float32)
        src_nodata = src.nodata if src.nodata is not None else -32768.0

        elevation = np.full((dem_height, dem_width), np.nan, dtype=np.float32)
        reproject(
            source=src_data,
            destination=elevation,
            src_transform=win_transform,
            src_crs=geo_crs,
            src_nodata=src_nodata,
            dst_transform=dem_transform,
            dst_crs=MARS_PROJ_CRS,
            dst_nodata=np.nan,
            resampling=Resampling.bilinear,
        )

    obstacles = ~np.isfinite(elevation)
    valid_elev = elevation[~obstacles]
    elev_min = float(np.min(valid_elev))
    elev_max = float(np.max(valid_elev))
    elevation_clean = np.where(obstacles, float(np.median(valid_elev)), elevation).astype(np.float32)

    np.save(os.path.join(OUT_DIR, "mount_sharp_elevation.npy"), elevation_clean)
    np.save(os.path.join(OUT_DIR, "mount_sharp_obstacles.npy"), obstacles)
    print(f"Saved elevation ({elevation_clean.shape}) and obstacles ({obstacles.shape}). Range: {elev_min:.2f}m to {elev_max:.2f}m")

    print("Processing HiRISE mosaic via windowed read...")
    map_width = int(round((proj_right - proj_left) / MAP_CELL_SIZE_M))
    map_height = int(round((proj_top - proj_bottom) / MAP_CELL_SIZE_M))
    map_transform = from_origin(proj_left, proj_top, MAP_CELL_SIZE_M, MAP_CELL_SIZE_M)

    with rasterio.open(HIRISE_PATH) as hsrc:
        h_left, h_bottom, h_right, h_top = transform_bounds(
            MARS_PROJ_CRS, geo_crs, proj_left, proj_bottom, proj_right, proj_top, densify_pts=21
        )
        h_pad_x = abs(hsrc.res[0]) * 10
        h_pad_y = abs(hsrc.res[1]) * 10
        h_win = from_bounds(
            h_left - h_pad_x, h_bottom - h_pad_y, h_right + h_pad_x, h_top + h_pad_y, transform=hsrc.transform
        )
        h_win = h_win.intersection(rasterio.windows.Window(0, 0, hsrc.width, hsrc.height))
        if h_win.width <= 0 or h_win.height <= 0:
            raise ValueError("Study region does not overlap HiRISE mosaic bounds!")

        h_win_transform = hsrc.window_transform(h_win)
        h_nodata = 0
        out_dtype = hsrc.dtypes[0]
        map_bands = np.zeros((hsrc.count, map_height, map_width), dtype=out_dtype)

        for b in range(1, hsrc.count + 1):
            band_data = hsrc.read(b, window=h_win)
            reproject(
                source=band_data,
                destination=map_bands[b - 1],
                src_transform=h_win_transform,
                src_crs=geo_crs,
                src_nodata=h_nodata,
                dst_transform=map_transform,
                dst_crs=MARS_PROJ_CRS,
                dst_nodata=h_nodata,
                resampling=Resampling.bilinear,
            )

        map_profile = {
            "driver": "GTiff",
            "height": map_height,
            "width": map_width,
            "count": hsrc.count,
            "dtype": out_dtype,
            "crs": MARS_PROJ_CRS,
            "transform": map_transform,
            "nodata": h_nodata,
            "compress": "lzw",
        }
        map_out_path = os.path.join(OUT_DIR, "mount_sharp_map.tif")
        with rasterio.open(map_out_path, "w", **map_profile) as dst:
            dst.write(map_bands)
    print(f"Saved georeferenced HiRISE map: {map_out_path} ({map_width} x {map_height})")

    start_pt, goal_pt = find_connected_endpoints(elevation_clean, obstacles, DEM_CELL_SIZE_M, max_slope_deg=30.0)
    print(f"Validated connected A* endpoints: start={start_pt}, goal={goal_pt}")

    metadata = {
        "project": "ARES — Astronaut Route & Exploration System",
        "study_region": "Mount Sharp lower foothills / Curiosity traverse zone, Gale Crater, Mars",
        "source_datasets": {
            "elevation_dem": dem_info,
            "optical_imagery": hirise_info,
        },
        "coordinate_system": {
            "mars_convention": "IAU Mars 2000 Sphere (R = 3,396,190 m), Planetocentric Latitude, East Longitude (0-360 / -180 to 180)",
            "projected_crs_wkt": MARS_PROJ_CRS.to_wkt(),
            "projected_crs_proj4": MARS_PROJ_CRS.to_proj4(),
        },
        "geographic_bounds_deg": {
            "lon_min": LON_MIN,
            "lat_min": LAT_MIN,
            "lon_max": LON_MAX,
            "lat_max": LAT_MAX,
        },
        "projected_bounds_m": {
            "left": proj_left,
            "bottom": proj_bottom,
            "right": proj_right,
            "top": proj_top,
        },
        "elevation_grid": {
            "width": dem_width,
            "height": dem_height,
            "total_cells": dem_width * dem_height,
            "cell_size_m": DEM_CELL_SIZE_M,
            "elevation_units": "meters",
            "elevation_min_m": elev_min,
            "elevation_max_m": elev_max,
            "nodata_mask_convention": "True = unavailable/invalid terrain, False = valid terrain",
            "affine_transform": list(dem_transform),
        },
        "map_imagery": {
            "width": map_width,
            "height": map_height,
            "cell_size_m": MAP_CELL_SIZE_M,
            "affine_transform": list(map_transform),
        },
        "demo_endpoints": {
            "start": start_pt,
            "goal": goal_pt,
        },
        "limitations": [
            "DEM spatial resolution is 200 m/pixel (MOLA/HRSC blend); sub-pixel boulders, scarps, and rover-scale hazards are not resolved.",
            "Obstacles mask strictly reflects DEM NoData/invalid cells and does not classify surface rocks or sand traps.",
        ],
    }

    with open(os.path.join(OUT_DIR, "mount_sharp_metadata.json"), "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2)

    shutil.copyfile(os.path.abspath(__file__), os.path.join(OUT_DIR, "process_terrain.py"))

    readme_lines = [
        "# ARES — Mount Sharp Geospatial Terrain Package",
        "",
        "## Deliverables",
        f"- `mount_sharp_elevation.npy`: {dem_height}x{dem_width} float32 array in meters ({elev_min:.2f} m to {elev_max:.2f} m).",
        f"- `mount_sharp_obstacles.npy`: {dem_height}x{dem_width} boolean array (`True` = invalid/NoData, `False` = valid terrain).",
        f"- `mount_sharp_map.tif`: Georeferenced HiRISE mosaic ({MAP_CELL_SIZE_M} m/px) aligned to exact projected bounds.",
        "- `mount_sharp_metadata.json`: CRS WKT, geographic/projected bounds, affine transforms, and demo endpoints.",
        "- `process_terrain.py`: Standalone processing script.",
        "",
        "## Installation & Execution",
        "```bash",
        "pip install numpy rasterio",
        "python process_terrain.py",
        "```",
        "",
        "## Backend Usage (`plan_astar`)",
        "```python",
        "import json, numpy as np",
        "",
        'elevation = np.load("mount_sharp/mount_sharp_elevation.npy")',
        'obstacles = np.load("mount_sharp/mount_sharp_obstacles.npy")',
        'with open("mount_sharp/mount_sharp_metadata.json") as f:',
        "    meta = json.load(f)",
        "",
        'start = meta["demo_endpoints"]["start"]',
        'goal = meta["demo_endpoints"]["goal"]',
        "# plan_astar(start, goal, elevation, obstacles=obstacles, cell_size_m=200.0, max_slope_deg=30.0)",
        "```",
    ]
    with open(os.path.join(OUT_DIR, "README.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(readme_lines) + "\n")

    print(f"\nSUCCESS! All 6 deliverables generated in {OUT_DIR}")


if __name__ == "__main__":
    main()