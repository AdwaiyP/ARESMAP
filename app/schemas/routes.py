import math

from pydantic import BaseModel, Field, model_validator


class Point(BaseModel):
    x: int = Field(ge=0)
    y: int = Field(ge=0)


class RouteRequest(BaseModel):
    start: Point
    goal: Point

    elevation: list[list[float]]
    obstacles: list[list[bool]] | None = None
    risk: list[list[float]] | None = None

    cell_size_m: float = Field(default=10.0, gt=0)
    max_slope_deg: float = Field(default=30.0, ge=0, lt=90)
    slope_weight: float = Field(default=2.0, ge=0)
    risk_weight: float = Field(default=5.0, ge=0)

    @model_validator(mode="after")
    def validate_grid(self):
        height = len(self.elevation)

        if height == 0:
            raise ValueError("Elevation grid cannot be empty")

        width = len(self.elevation[0])

        if width == 0:
            raise ValueError("Elevation grid cannot be empty")

        if height * width > 250_000:
            raise ValueError("Grid exceeds 250,000 cells")

        if any(len(row) != width for row in self.elevation):
            raise ValueError("Elevation grid must be rectangular")

        if any(
            not math.isfinite(value)
            for row in self.elevation
            for value in row
        ):
            raise ValueError("Elevation values must be finite")

        for name, grid in (
            ("obstacles", self.obstacles),
            ("risk", self.risk),
        ):
            if grid is not None:
                if len(grid) != height or any(
                    len(row) != width for row in grid
                ):
                    raise ValueError(
                        f"{name} dimensions must match elevation"
                    )

        if self.risk is not None:
            if any(
                not math.isfinite(value) or not 0 <= value <= 1
                for row in self.risk
                for value in row
            ):
                raise ValueError("Risk values must be between 0 and 1")

        for name in (
            "cell_size_m",
            "max_slope_deg",
            "slope_weight",
            "risk_weight",
        ):
            if not math.isfinite(getattr(self, name)):
                raise ValueError(f"{name} must be finite")

        if self.start == self.goal:
            raise ValueError("Start and goal must differ")

        for point in (self.start, self.goal):
            if point.x >= width or point.y >= height:
                raise ValueError("Start or goal is outside the grid")

            if self.obstacles is not None:
                if self.obstacles[point.y][point.x]:
                    raise ValueError("Start or goal is blocked")

        return self

class MountSharpRouteRequest(BaseModel):
    start: Point
    goal: Point

    max_slope_deg: float = Field(default=30.0, ge=0, lt=90)
    slope_weight: float = Field(default=2.0, ge=0)
    risk_weight: float = Field(default=5.0, ge=0)

    @model_validator(mode="after")
    def validate_request(self):
        if self.start == self.goal:
            raise ValueError("Start and goal must differ")

        for name in ("max_slope_deg", "slope_weight", "risk_weight"):
            if not math.isfinite(getattr(self, name)):
                raise ValueError(f"{name} must be finite")

        return self
