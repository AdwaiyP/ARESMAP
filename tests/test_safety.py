import math

import pytest

from app.services.safety import validate_route_safety


@pytest.mark.parametrize(
    "name,points,expected_status,expected_obstacles",
    [
        ("clear", [(0, 0), (0, 2)], "NOT_VERIFIED", "pass"),
        ("blocked_waypoint", [(0, 0), (1, 1), (2, 2)], "UNSAFE", "fail"),
        ("blocked_shortcut", [(0, 0), (2, 2)], "UNSAFE", "fail"),
    ],
)
def test_route_obstacle_validation(
    name, points, expected_status, expected_obstacles
):
    obstacles = [
        [False, False, False],
        [False, True, False],
        [False, False, False],
    ]

    distance = sum(
        math.hypot((b[0] - a[0]) * 5, (b[1] - a[1]) * 5)
        for a, b in zip(points, points[1:])
    )

    result = validate_route_safety(
        route_result={
            "status": "success",
            "route": [{"x": x, "y": y} for x, y in points],
            "distance_m": round(distance, 3),
        },
        obstacles=obstacles,
        cell_width_m=5,
        cell_height_m=5,
        max_distance_m=100,
    )

    assert result["safety_status"] == expected_status, name
    assert result["checks"]["obstacles"] == expected_obstacles, name
    assert result["approved_for_real_eva"] is False


def test_rejects_incorrect_distance():
    result = validate_route_safety(
        route_result={
            "status": "success",
            "route": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
            "distance_m": 1.0,
        },
        obstacles=[[False, False]],
        cell_width_m=5,
        cell_height_m=5,
    )

    assert result["safety_status"] == "UNSAFE"
    assert result["checks"]["distance"] == "fail"
