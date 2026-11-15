import math


def route_cells(a, b):
    """Return all grid cells touched by a route segment."""
    x0, y0 = a
    x1, y1 = b

    dx, dy = x1 - x0, y1 - y0
    nx, ny = abs(dx), abs(dy)
    sx = (dx > 0) - (dx < 0)
    sy = (dy > 0) - (dy < 0)

    x, y = x0, y0
    ix = iy = 0
    cells = {(x, y)}

    while ix < nx or iy < ny:
        lhs = (1 + 2 * ix) * ny
        rhs = (1 + 2 * iy) * nx

        if lhs == rhs:
            if sx and sy:
                cells.add((x + sx, y))
                cells.add((x, y + sy))
            x += sx
            y += sy
            ix += 1
            iy += 1
        elif lhs < rhs:
            x += sx
            ix += 1
        else:
            y += sy
            iy += 1

        cells.add((x, y))

    return cells


def validate_route_safety(
    route_result,
    obstacles,
    cell_width_m,
    cell_height_m,
    max_distance_m=None,
):
    """Fail-closed validation of available route constraints."""

    checks = {}
    failures = []

    height = len(obstacles)
    width = len(obstacles[0]) if height else 0
    route = route_result.get("route", [])

    dimensions_valid = all(
        isinstance(v, (int, float))
        and not isinstance(v, bool)
        and math.isfinite(v)
        and v > 0
        for v in (cell_width_m, cell_height_m)
    )

    route_valid = (
        route_result.get("status") == "success"
        and isinstance(route, list)
        and len(route) >= 2
    )

    checks["route"] = "pass" if route_valid else "fail"

    if not route_valid:
        failures.append("No valid route available")

    points = []

    if route_valid:
        for point in route:
            if not isinstance(point, dict):
                route_valid = False
                break

            x, y = point.get("x"), point.get("y")

            if not all(
                isinstance(v, int) and not isinstance(v, bool)
                for v in (x, y)
            ):
                route_valid = False
                break

            points.append((x, y))

    if not route_valid:
        checks["route"] = "fail"

    obstacle_ok = route_valid and width > 0 and height > 0

    if obstacle_ok:
        for a, b in zip(points, points[1:]):
            for x, y in route_cells(a, b):
                if not (0 <= x < width and 0 <= y < height):
                    obstacle_ok = False
                    break
                if obstacles[y][x]:
                    obstacle_ok = False
                    break
            if not obstacle_ok:
                break

    checks["obstacles"] = "pass" if obstacle_ok else "fail"

    if not obstacle_ok:
        failures.append("Route intersects blocked or invalid terrain")

    distance = None

    if dimensions_valid and obstacle_ok:
        distance = sum(
            math.hypot(
                (b[0] - a[0]) * cell_width_m,
                (b[1] - a[1]) * cell_height_m,
            )
            for a, b in zip(points, points[1:])
        )

        reported = route_result.get("distance_m")

        distance_ok = (
            isinstance(reported, (int, float))
            and not isinstance(reported, bool)
            and math.isfinite(reported)
            and abs(distance - reported) <= 0.01
        )
    else:
        distance_ok = False

    checks["distance"] = "pass" if distance_ok else "fail"

    if not distance_ok:
        failures.append("Route distance or geometry is invalid")

    if max_distance_m is None:
        checks["eva_budget"] = "unknown"
    elif (
        not isinstance(max_distance_m, (int, float))
        or isinstance(max_distance_m, bool)
        or not math.isfinite(max_distance_m)
        or max_distance_m <= 0
    ):
        checks["eva_budget"] = "fail"
        failures.append("Invalid EVA distance budget")
    elif distance is not None and distance <= max_distance_m:
        checks["eva_budget"] = "pass"
    else:
        checks["eva_budget"] = "fail"
        failures.append("Route exceeds EVA distance budget")

    checks["return_to_base"] = "unknown"
    checks["slope"] = "unknown"
    checks["environment"] = "unknown"

    if "fail" in checks.values():
        status = "UNSAFE"
    elif "unknown" in checks.values():
        status = "NOT_VERIFIED"
    else:
        status = "VALIDATED_WITHIN_MODEL"

    return {
        "safety_status": status,
        "approved_for_real_eva": False,
        "checks": checks,
        "failures": failures,
        "computed_distance_m": (
            round(distance, 3) if distance is not None else None
        ),
    }
