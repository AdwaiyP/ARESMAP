from fastapi import APIRouter, HTTPException

from app.schemas.climate import ClimateRequest
from app.services.climate_predictor import predict_climate

router = APIRouter(
    prefix="/api/v1/climate",
    tags=["Climate"],
)


@router.post("/predict")
def predict_climate_endpoint(request: ClimateRequest):
    try:
        return predict_climate(
            latitude=request.latitude,
            longitude=request.longitude,
            ltst_time=request.ltst_time,
            elevation_m=request.elevation_m,
        )
    except (OSError, RuntimeError, ValueError) as exc:
        raise HTTPException(
            status_code=503,
            detail="Climate inference is temporarily unavailable",
        ) from exc
