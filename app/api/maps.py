import json
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

router = APIRouter(prefix="/api/v1/maps", tags=["Mars Maps"])

DATA_DIR = Path(__file__).resolve().parents[2] / "data" / "jezero"


@router.get("/jezero/metadata")
def get_jezero_metadata():
    path = DATA_DIR / "jezero_metadata.json"

    if not path.is_file():
        raise HTTPException(status_code=404, detail="Metadata unavailable")

    return json.loads(path.read_text())


@router.get("/jezero/tile")
def get_jezero_tile():
    path = DATA_DIR / "jezero_tile.png"

    if not path.is_file():
        raise HTTPException(status_code=404, detail="Map unavailable")

    return FileResponse(path, media_type="image/png")
