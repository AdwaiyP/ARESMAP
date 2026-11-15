"""Theta* any-angle path planner on 2D Mars terrain grids."""

from dataclasses import dataclass
import heapq
import math

import numpy as np


@dataclass(frozen=True)
class _ThetaGrid:
    """Validated terrain arrays and traversal parameters."""

    elevation: np.ndarray
    obstacles: np.ndarray
    risk: np.ndarray
    width: int
    height: int
    cell_size_m: float
    cell_height_m: float
    max_slope_deg: float
    slope_weight: float
    risk_weight: float

    def is_valid(self, point):
        """Return True if point is inside bounds and not blocked."""
        x, y = point
        return (
            0 <= x < self.width
            and 0 <= y < self.height
            and not self.obstacles[y, x]
        )


def _validate_theta_scalars(
    cell_size_m, cell_height_m, max_slope_deg, slope_weight, risk_weight
):
    """Validate scalar traversal parameters for Theta*."""
    if not math.isfinite(cell_height_m) or cell_height_m <= 0:
        raise ValueError("cell_height_m must be positive")
    for name, value in (
        ("cell_size_m", cell_size_m),
        ("max_slope_deg", max_slope_deg),
        ("slope_weight", slope_weight),
        ("risk_weight", risk_weight),
    ):
        if not math.isfinite(value):
            raise ValueError(f"{name} must be finite")
    if cell_size_m <= 0 or not 0 < max_slope_deg < 90:
        raise ValueError("Invalid cell size or maximum slope")
    if slope_weight < 0 or risk_weight < 0:
        raise ValueError("Weights must be nonnegative")


def _validate_theta_grid(
    elevation,
    obstacles,
    risk,
    cell_size_m,
    cell_height_m,
    max_slope_deg,
    slope_weight,
    risk_weight,
):
    """Validate terrain grids and scalar parameters, returning a _ThetaGrid."""
    if cell_height_m is None:
        cell_height_m = cell_size_m
    _validate_theta_scalars(
        cell_size_m, cell_height_m, max_slope_deg, slope_weight, risk_weight
    )

    elev_arr = np.asarray(elevation, dtype=float)
    obs_arr = np.asarray(obstacles, dtype=bool)
    risk_arr = np.zeros_like(elev_arr) if risk is None else np.asarray(risk, dtype=float)

    if elev_arr.ndim != 2 or obs_arr.shape != elev_arr.shape or risk_arr.shape != elev_arr.shape:
        raise ValueError("Terrain arrays must be matching 2D grids")
    if not np.isfinite(elev_arr).all() or not np.isfinite(risk_arr).all():
        raise ValueError("Terrain arrays must contain finite values")
    if np.any(risk_arr < 0):
        raise ValueError("Risk values must be nonnegative")

    height, width = elev_arr.shape
    return _ThetaGrid(
        elevation=elev_arr, obstacles=obs_arr, risk=risk_arr,
        width=width, height=height, cell_size_m=cell_size_m,
        cell_height_m=cell_height_m, max_slope_deg=max_slope_deg,
        slope_weight=slope_weight, risk_weight=risk_weight,
    )


def _line_cells(a, b):
    """Conservative grid supercover, including corner-touching cells."""
    x0, y0 = a
    x1, y1 = b
    dx, dy = x1 - x0, y1 - y0
    nx, ny = abs(dx), abs(dy)
    sx = 1 if dx > 0 else -1 if dx < 0 else 0
    sy = 1 if dy > 0 else -1 if dy < 0 else 0
    x, y = x0, y0
    cells = [(x, y)]
    ix = iy = 0

    for _ in range(nx + ny + 1):
        if ix >= nx and iy >= ny:
            break
        lhs = (1 + 2 * ix) * ny
        rhs = (1 + 2 * iy) * nx
        if lhs == rhs:
            if sx and sy:
                cells.extend([(x + sx, y), (x, y + sy)])
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
        cells.append((x, y))

    return list(dict.fromkeys(cells))


def _segment_cost(grid, a, b):
    """Compute traversability cost for a straight-line segment a -> b."""
    cells = _line_cells(a, b)
    if any(not grid.is_valid(p) for p in cells):
        return math.inf

    distance = math.hypot(
        (b[0] - a[0]) * grid.cell_size_m,
        (b[1] - a[1]) * grid.cell_height_m,
    )
    if distance == 0:
        return 0.0

    # Conservative check across all touched cells.
    z_values = [grid.elevation[y, x] for x, y in cells]
    z_span = max(z_values) - min(z_values)
    if math.degrees(math.atan(z_span / distance)) > grid.max_slope_deg:
        return math.inf

    mean_risk = sum(grid.risk[y, x] for x, y in cells) / len(cells)
    return (
        distance
        + grid.slope_weight * z_span
        + grid.risk_weight * distance * mean_risk
    )


def _relax_neighbors(grid, current, goal, g, parent, heap, closed):
    """Relax all 8-connected neighbors of current using Theta* line-of-sight."""
    x, y = current
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            neighbor = (x + dx, y + dy)
            if not grid.is_valid(neighbor) or neighbor in closed:
                continue

            best_parent = current
            best_g = g[current] + _segment_cost(grid, current, neighbor)

            # Theta*: attempt line-of-sight shortcut from current's parent.
            candidate_parent = parent[current]
            if candidate_parent != current:
                shortcut_cost = _segment_cost(grid, candidate_parent, neighbor)
                candidate_g = g[candidate_parent] + shortcut_cost
                if candidate_g < best_g:
                    best_g = candidate_g
                    best_parent = candidate_parent

            if best_g < g.get(neighbor, math.inf):
                g[neighbor] = best_g
                parent[neighbor] = best_parent
                h = math.hypot(
                    (goal[0] - neighbor[0]) * grid.cell_size_m,
                    (goal[1] - neighbor[1]) * grid.cell_height_m,
                )
                heapq.heappush(heap, (best_g + h, best_g, neighbor))


def _reconstruct_path(parent, start, goal, max_steps):
    """Walk parent pointers from goal back to start within a fixed step bound."""
    path = []
    node = goal
    for _ in range(max_steps):
        path.append(node)
        if node == start:
            path.reverse()
            return path
        node = parent[node]
    raise RuntimeError("Path reconstruction exceeded grid step bound")


def _summarize_theta_route(grid, path, total_cost, explored):
    """Compute final route metrics and format the Theta* response payload."""
    distance = sum(
        math.hypot(
            (b[0] - a[0]) * grid.cell_size_m,
            (b[1] - a[1]) * grid.cell_height_m,
        )
        for a, b in zip(path, path[1:])
    )
    elevation_gain = sum(
        max(0.0, grid.elevation[b[1], b[0]] - grid.elevation[a[1], a[0]])
        for a, b in zip(path, path[1:])
    )
    return {
        "status": "success",
        "algorithm": "theta_star",
        "route": [{"x": x, "y": y} for x, y in path],
        "distance_m": round(distance, 3),
        "elevation_gain_m": round(float(elevation_gain), 3),
        "cost": round(total_cost, 3),
        "nodes_explored": explored,
    }


def _run_theta_search(grid, start, goal):
    """Execute bounded Theta* search and return (g, parent, explored)."""
    g = {start: 0.0}
    parent = {start: start}
    start_h = math.hypot(
        (goal[0] - start[0]) * grid.cell_size_m,
        (goal[1] - start[1]) * grid.cell_height_m,
    )
    heap = [(start_h, 0.0, start)]
    closed = set()
    explored = 0

    for _ in range(grid.width * grid.height * 8 + 1):
        if not heap:
            break
        _, current_g, current = heapq.heappop(heap)
        if current in closed or current_g > g[current] + 1e-9:
            continue
        closed.add(current)
        explored += 1
        if current == goal:
            break
        _relax_neighbors(grid, current, goal, g, parent, heap, closed)

    return g, parent, explored


def plan_theta_star(
    start,
    goal,
    elevation,
    obstacles,
    risk=None,
    cell_size_m=5.0,
    max_slope_deg=30.0,
    slope_weight=1.0,
    risk_weight=20.0,
    cell_height_m=None,
):
    """Plan an any-angle Theta* route across a 2D terrain grid."""
    grid = _validate_theta_grid(
        elevation, obstacles, risk, cell_size_m, cell_height_m,
        max_slope_deg, slope_weight, risk_weight,
    )
    start, goal = tuple(start), tuple(goal)
    if not grid.is_valid(start) or not grid.is_valid(goal):
        return {"status": "invalid_start_or_goal", "route": []}
    if start == goal:
        return {
            "status": "success",
            "route": [{"x": start[0], "y": start[1]}],
            "distance_m": 0.0, "elevation_gain_m": 0.0,
            "cost": 0.0, "nodes_explored": 0,
        }

    g, parent, explored = _run_theta_search(grid, start, goal)
    if goal not in g:
        return {"status": "no_path", "route": [], "nodes_explored": explored}

    path = _reconstruct_path(parent, start, goal, grid.width * grid.height + 1)
    return _summarize_theta_route(grid, path, g[goal], explored)
