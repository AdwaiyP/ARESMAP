# ARES — Mount Sharp Geospatial Terrain Package

## Deliverables
- `mount_sharp_elevation.npy`: 75x74 float32 array in meters (-4492.99 m to -1809.99 m).
- `mount_sharp_obstacles.npy`: 75x74 boolean array (`True` = invalid/NoData, `False` = valid terrain).
- `mount_sharp_map.tif`: Georeferenced HiRISE mosaic (5.0 m/px) aligned to exact projected bounds.
- `mount_sharp_metadata.json`: CRS WKT, geographic/projected bounds, affine transforms, and demo endpoints.
- `process_terrain.py`: Standalone processing script.

## Installation & Execution
```bash
pip install numpy rasterio
python process_terrain.py
```

## Backend Usage (`plan_astar`)
```python
import json, numpy as np

elevation = np.load("mount_sharp/mount_sharp_elevation.npy")
obstacles = np.load("mount_sharp/mount_sharp_obstacles.npy")
with open("mount_sharp/mount_sharp_metadata.json") as f:
    meta = json.load(f)

start = meta["demo_endpoints"]["start"]
goal = meta["demo_endpoints"]["goal"]
# plan_astar(start, goal, elevation, obstacles=obstacles, cell_size_m=200.0, max_slope_deg=30.0)
```
