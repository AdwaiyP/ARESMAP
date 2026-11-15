"""A* 8-connected path planner on 2D Mars terrain grids."""

from dataclasses import dataclass
import heapq
import math

_DIRECTIONS = (
    (-1, 0), (1, 0), (0, -1), (0, 1),
    (-1, -1), (-1, 1), (1, -1), (1, 1),
)


@dataclass(frozen=True)
class _AStarGrid:
    """Validated terrain grids and traversal parameters for A*."""

    elevation: list
    obstacles: list
    risk: list
    width: int
    height: int
    cell_size_m: float
    cell_height_m: float
    max_slope_deg: float
    slope_weight: float
    risk_weight: float

    def inside(self, point):
        """Return True if point coordinates lie within grid bounds."""
        x, y = point
        return 0 <= x < self.width and 0 <= y < self.height


def _validate_astar_inputs(
    start,
    goal,
    elevation,
    obstacles,
    risk,
    cell_size_m,
    cell_height_m,
    max_slope_deg,
    slope_weight,
    risk_weight,
):
    """Validate grid shapes, numeric bounds, and start/goal states."""
    if cell_height_m is None:
        cell_height_m = cell_size_m
    if not math.isfinite(cell_height_m) or cell_height_m <= 0:
        raise ValueError("cell_height_m must be positive")

    height = len(elevation)
    if not height or not len(elevation[0]):
        raise ValueError("Elevation grid cannot be empty")

    width = len(elevation[0])
    if any(len(row) != width for row in elevation):
        raise ValueError("Elevation grid must be rectangular")

    if obstacles is None:
        obstacles = [[False] * width for _ in range(height)]
    if risk is None:
        risk = [[0.0] * width for _ in range(height)]

    if len(obstacles) != height or any(len(r) != width for r in obstacles):
        raise ValueError("Obstacle grid dimensions do not match")
    if len(risk) != height or any(len(r) != width for r in risk):
        raise ValueError("Risk grid dimensions do not match")

    _validate_scalar_params(
        cell_size_m, max_slope_deg, slope_weight, risk_weight
    )
    _validate_grid_values(elevation, risk)

    grid = _AStarGrid(
        elevation=elevation,
        obstacles=obstacles,
        risk=risk,
        width=width,
        height=height,
        cell_size_m=cell_size_m,
        cell_height_m=cell_height_m,
        max_slope_deg=max_slope_deg,
        slope_weight=slope_weight,
        risk_weight=risk_weight,
    )
    if not grid.inside(start) or not grid.inside(goal):
        raise ValueError("Start or goal is outside the grid")
    if obstacles[start[1]][start[0]] or obstacles[goal[1]][goal[0]]:
        raise ValueError("Start or goal is blocked")
    if start == goal:
        raise ValueError("Start and goal must differ")
    return grid


def _validate_scalar_params(cell_size_m, max_slope_deg, slope_weight, risk_weight):
    """Validate scalar planner weights and slope constraints."""
    if not math.isfinite(cell_size_m) or cell_size_m <= 0:
        raise ValueError("cell_size_m must be positive")
    if not 0 <= max_slope_deg < 90:
        raise ValueError("max_slope_deg must be between 0 and 90")
    if not all(
        math.isfinite(v) and v >= 0 for v in (slope_weight, risk_weight)
    ):
        raise ValueError("Weights must be finite and nonnegative")


def _validate_grid_values(elevation, risk):
    """Ensure elevation is finite and risk values lie in [0, 1]."""
    for row in elevation:
        if any(not math.isfinite(v) for v in row):
            raise ValueError("Elevation must be finite")
    for row in risk:
        if any(not math.isfinite(v) or not 0 <= v <= 1 for v in row):
            raise ValueError("Risk must be between 0 and 1")


def _heuristic(point, goal, grid):
    """Return Euclidean metric distance heuristic to goal."""
    return math.hypot(
        (goal[0] - point[0]) * grid.cell_size_m,
        (goal[1] - point[1]) * grid.cell_height_m,
    )


def _expand_astar_neighbors(grid, current, current_cost, goal, best, previous, queue):
    """Evaluate 8-connected neighbors and push improved candidates."""
    x, y = current
    for dx, dy in _DIRECTIONS:
        nxt = (x + dx, y + dy)
        if not grid.inside(nxt) or grid.obstacles[nxt[1]][nxt[0]]:
            continue

        # Prevent crossing the corners of blocked cells.
        if dx and dy and (grid.obstacles[y][x + dx] or grid.obstacles[y + dy][x]):
            continue

        distance = math.hypot(dx * grid.cell_size_m, dy * grid.cell_height_m)
        rise = grid.elevation[nxt[1]][nxt[0]] - grid.elevation[y][x]
        slope = math.degrees(math.atan2(abs(rise), distance))
        if slope > grid.max_slope_deg:
            continue

        penalty = distance * (
            grid.slope_weight * math.tan(math.radians(slope))
            + grid.risk_weight * grid.risk[nxt[1]][nxt[0]]
        )
        candidate = current_cost + distance + penalty
        if candidate + 1e-9 < best.get(nxt, math.inf):
            best[nxt] = candidate
            previous[nxt] = current
            heapq.heappush(
                queue, (candidate + _heuristic(nxt, goal, grid), candidate, nxt)
            )


def _reconstruct_astar_result(grid, previous, start, goal, total_cost, explored):
    """Reconstruct path and compute route summary metrics within a fixed bound."""
    path = [goal]
    max_steps = grid.width * grid.height + 1
    for _ in range(max_steps):
        if path[-1] == start:
            break
        path.append(previous[path[-1]])
    else:
        raise RuntimeError("A* path reconstruction exceeded grid step bound")
    path.reverse()

    distance = 0.0
    gain = 0.0
    for a, b in zip(path, path[1:]):
        distance += math.hypot(
            (b[0] - a[0]) * grid.cell_size_m,
            (b[1] - a[1]) * grid.cell_height_m,
        )
        gain += max(0.0, grid.elevation[b[1]][b[0]] - grid.elevation[a[1]][a[0]])

    return {
        "status": "success",
        "route": [{"x": x, "y": y} for x, y in path],
        "distance_m": round(distance, 3),
        "elevation_gain_m": round(gain, 3),
        "total_cost": round(total_cost, 3),
        "explored_nodes": explored,
    }


def plan_astar(
    start,
    goal,
    elevation,
    obstacles=None,
    risk=None,
    cell_size_m=10.0,
    max_slope_deg=30.0,
    slope_weight=2.0,
    risk_weight=5.0,
    cell_height_m=None,
):
    """Plan an 8-connected A* route across a 2D Mars terrain grid."""
    grid = _validate_astar_inputs(
        start,
        goal,
        elevation,
        obstacles,
        risk,
        cell_size_m,
        cell_height_m,
        max_slope_deg,
        slope_weight,
        risk_weight,
    )

    queue = [(_heuristic(start, goal, grid), 0.0, start)]
    best = {start: 0.0}
    previous = {}
    explored = 0
    max_iterations = grid.width * grid.height * 8 + 1

    for _ in range(max_iterations):
        if not queue:
            break
        _, current_cost, current = heapq.heappop(queue)
        if current_cost > best[current] + 1e-9:
            continue
        explored += 1
        if current == goal:
            return _reconstruct_astar_result(
                grid, previous, start, goal, current_cost, explored
            )
        _expand_astar_neighbors(
            grid, current, current_cost, goal, best, previous, queue
        )

    return {
        "status": "no_route",
        "route": [],
        "distance_m": None,
        "elevation_gain_m": None,
        "total_cost": None,
        "explored_nodes": explored,
    }
