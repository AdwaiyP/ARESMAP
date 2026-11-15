from pydantic import BaseModel, Field, field_validator
import re


class ClimateRequest(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=360)
    ltst_time: str
    elevation_m: float = Field(ge=-10000, le=30000)

    @field_validator("ltst_time")
    @classmethod
    def validate_ltst(cls, value: str) -> str:
        if not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", value):
            raise ValueError("ltst_time must use HH:MM (00:00–23:59)")
        return value
