import json
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image
from rasterio.windows import from_bounds, transform as window_transform
from rasterio.warp import transform, transform_bounds
from rasterio.enums import Resampling

OUT = Path(__file__).resolve().parent
CTX = Path.home() / "Downloads/JEZ_ctx_B_soc_008_orthoMosaic_6m_Eqc_latTs0_lon0.tif"
HIRISE = Path.home() / "Downloads/JEZ_hirise_soc_006_orthoMosaic_25cm_Eqc_latTs0_lon0_first_dd.tif"

SIZE_M = 500
GRID = 100
CELL_M = SIZE_M / GRID

with rasterio.open(CTX) as ctx, rasterio.open(HIRISE) as hi:
    hb = transform_bounds(hi.crs, ctx.crs, *hi.bounds)
    left = max(ctx.bounds.left, hb[0])
    right = min(ctx.bounds.right, hb[2])
    bottom = max(ctx.bounds.bottom, hb[1])
    top = min(ctx.bounds.top, hb[3])

    if right - left < SIZE_M or top - bottom < SIZE_M:
        raise RuntimeError("Insufficient geographic overlap")

    cx = (left + right) / 2
    cy = (bottom + top) / 2

    # Convert projected Mars coordinates to HiRISE geographic coordinates.
    corners_x = [cx - SIZE_M / 2, cx + SIZE_M / 2]
    corners_y = [cy - SIZE_M / 2, cy + SIZE_M / 2]

    lon, lat = transform(
        ctx.crs,
        hi.crs,
        [corners_x[0], corners_x[1], corners_x[0], corners_x[1]],
        [corners_y[0], corners_y[0], corners_y[1], corners_y[1]],
    )

    window = from_bounds(
        min(lon), min(lat), max(lon), max(lat),
        transform=hi.transform,
    ).round_offsets().round_lengths()

    # Downsample while reading, avoiding a massive in-memory array.
    image = hi.read(
        1,
        window=window,
        out_shape=(GRID, GRID),
        resampling=Resampling.average,
        boundless=False,
    )

    geographic_transform = hi.window_transform(window) * rasterio.Affine.scale(
        window.width / GRID,
        window.height / GRID,
    )
    geographic_crs = hi.crs.to_wkt()

valid = image != 0

if not valid.any():
    raise RuntimeError("Selected Jezero tile contains no usable imagery")

values = image[valid].astype(np.float32)
low = np.percentile(values, 12)

padded = np.pad(image.astype(np.float32), 1, mode="edge")
local_mean = sum(
    padded[dy:dy + GRID, dx:dx + GRID]
    for dy in range(3)
    for dx in range(3)
) / 9

contrast = np.abs(image.astype(np.float32) - local_mean)
high_contrast = np.percentile(contrast[valid], 92)

hazards = (
    ((image <= low) | (contrast >= high_contrast))
    & valid
)

obstacles = ~valid
risk = hazards.astype(np.float32)

np.save(OUT / "jezero_obstacles.npy", obstacles)
np.save(OUT / "jezero_risk.npy", risk)

# Preserve imagery values in a compact, lossless PNG.
Image.fromarray(image).save(OUT / "jezero_tile.png")

metadata = {
    "site": "Jezero Crater",
    "source": "HiRISE orthomosaic",
    "grid_width": GRID,
    "grid_height": GRID,
    "cell_width_m": abs(geographic_transform.a)
        * 3.141592653589793 / 180
        * 3396190
        * np.cos(np.deg2rad(geographic_transform.f)),
    "cell_height_m": abs(geographic_transform.e)
        * 3.141592653589793 / 180
        * 3396190,
    "geographic_affine_transform": list(geographic_transform)[:6],
    "geographic_crs": geographic_crs,
    "geographic_bounds": {
        "west": (geographic_transform * (0, GRID))[0],
        "north": (geographic_transform * (0, 0))[1],
        "east": (geographic_transform * (GRID, 0))[0],
        "south": (geographic_transform * (GRID, GRID))[1],
    },
    "coverage_width_m": None,
    "coverage_height_m": None,
    "source_window": {
        "col_off": int(window.col_off),
        "row_off": int(window.row_off),
        "width": int(window.width),
        "height": int(window.height),
    },
    "projected_center": {"x": cx, "y": cy},
    "projected_crs": ctx.crs.to_wkt(),
    "hazard_source": "experimental_image_heuristics",
    "slope_assessment_available": False,
    "validated_for_eva_safety": False,
    "limitations": [
        "Imagery-derived candidate hazards are not verified obstacles",
        "No elevation model is included",
        "No slope-based safety assessment is available",
    ],
}

metadata["cell_width_m"] = round(
    float(metadata["cell_width_m"]), 4
)
metadata["cell_height_m"] = round(
    float(metadata["cell_height_m"]), 4
)
metadata["coverage_width_m"] = round(
    metadata["cell_width_m"] * GRID, 2
)
metadata["coverage_height_m"] = round(
    metadata["cell_height_m"] * GRID, 2
)

(OUT / "jezero_metadata.json").write_text(
    json.dumps(metadata, indent=2)
)

print("Jezero processing completed")
print("Grid:", image.shape)
print("Valid cells:", int(valid.sum()))
print("Candidate hazard cells:", int(hazards.sum()))
print("Source window:", metadata["source_window"])
print("Output directory:", OUT)
