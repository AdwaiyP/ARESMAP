import json
from pathlib import Path
from urllib.request import Request, urlopen

import numpy as np
import rasterio
from PIL import Image, ImageDraw
from rasterio.windows import Window

output_dir = Path("data/mount_sharp")

payload = json.dumps({
    "start": {"x": 10, "y": 70},
    "goal": {"x": 85, "y": 30},
    "risk_weight": 20
}).encode()

request = Request(
    "http://127.0.0.1:8006/api/v1/routes/eva-local",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST"
)

with urlopen(request, timeout=30) as response:
    result = json.load(response)

if result["status"] != "success":
    raise SystemExit("No route available")

origin = result["crop_origin_pixels"]
width = result["grid_width"]
height = result["grid_height"]

with rasterio.open(output_dir / "mount_sharp_map.tif") as src:
    pixels = src.read(
        1,
        window=Window(origin["x"], origin["y"], width, height)
    )

valid = pixels[pixels != 0]
low, high = np.percentile(valid, [2, 98])

enhanced = np.clip(
    (pixels.astype(float) - low) * 255 / max(high - low, 1),
    0, 255
).astype("uint8")

image = Image.fromarray(enhanced).convert("RGB")
draw = ImageDraw.Draw(image)

path = [
    (p["x"], p["y"])
    for p in result["route"]
]

draw.line(path, fill=(0, 255, 100), width=2)

for point, color in [
    (path[0], (0, 255, 0)),
    (path[-1], (255, 50, 50)),
]:
    x, y = point
    draw.ellipse((x-2, y-2, x+2, y+2), fill=color)

image = image.resize(
    (800, 800),
    Image.Resampling.NEAREST
)

output = output_dir / "eva_route_demo.png"
image.save(output)

print("Status:", result["status"])
print("Distance:", result["distance_m"], "meters")
print("Route points:", len(path))
print("Saved:", output)
