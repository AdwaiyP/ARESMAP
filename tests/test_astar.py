import pytest

from app.services.astar import plan_astar


def flat_grid(size=5):
    return [[0.0] * size for _ in range(size)]


def test_basic_route():
    result = plan_astar(
        (0, 0), (4, 4), flat_grid()
    )

    assert result["status"] == "success"
    assert result["route"][0] == {"x": 0, "y": 0}
    assert result["route"][-1] == {"x": 4, "y": 4}


def test_blocked_destination():
    obstacles = [[False] * 3 for _ in range(3)]
    obstacles[2][2] = True

    with pytest.raises(ValueError):
        plan_astar(
            (0, 0), (2, 2),
            flat_grid(3),
            obstacles=obstacles,
        )


def test_no_route():
    obstacles = [
        [False, True, False],
        [True, True, False],
        [False, False, False],
    ]

    result = plan_astar(
        (0, 0), (2, 2),
        flat_grid(3),
        obstacles=obstacles,
    )

    assert result["status"] == "no_route"


def test_steep_slope_rejected():
    elevation = [
        [0.0, 100.0],
        [100.0, 100.0],
    ]

    result = plan_astar(
        (0, 0), (1, 1),
        elevation,
        cell_size_m=10,
        max_slope_deg=30,
    )

    assert result["status"] == "no_route"


def test_diagonal_corner_cutting_prevented():
    obstacles = [
        [False, True],
        [True, False],
    ]

    result = plan_astar(
        (0, 0), (1, 1),
        flat_grid(2),
        obstacles=obstacles,
    )

    assert result["status"] == "no_route"


def test_risk_avoidance():
    risk = [
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0],
    ]

    result = plan_astar(
        (0, 0), (2, 0),
        flat_grid(3),
        risk=risk,
        risk_weight=20,
    )

    assert result["status"] == "success"
    assert {"x": 1, "y": 0} not in result["route"]


def test_invalid_elevation_grid():
    with pytest.raises(ValueError):
        plan_astar(
            (0, 0), (1, 1),
            [[0.0, 0.0], [0.0]],
        )


def test_start_equals_goal():
    with pytest.raises(ValueError):
        plan_astar(
            (0, 0), (0, 0),
            flat_grid(3),
        )
