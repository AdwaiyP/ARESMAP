import heapq
import math

import numpy as np


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
    if cell_height_m is None:
        cell_height_m = cell_size_m
    if not math.isfinite(cell_height_m) or cell_height_m <= 0:
        raise ValueError("cell_height_m must be positive")

    elevation = np.asarray(elevation, dtype=float)
    obstacles = np.asarray(obstacles, dtype=bool)
    risk = (
        np.zeros_like(elevation)
        if risk is None
        else np.asarray(risk, dtype=float)
    )

    if elevation.ndim != 2 or obstacles.shape != elevation.shape or risk.shape != elevation.shape:
        raise ValueError("Terrain arrays must be matching 2D grids")

    if not np.isfinite(elevation).all() or not np.isfinite(risk).all():
        raise ValueError("Terrain arrays must contain finite values")

    if np.any(risk < 0):
        raise ValueError("Risk values must be nonnegative")

    for name, value in {
        "cell_size_m": cell_size_m,
        "max_slope_deg": max_slope_deg,
        "slope_weight": slope_weight,
        "risk_weight": risk_weight,
    }.items():
        if not math.isfinite(value):
            raise ValueError(f"{name} must be finite")

    if cell_size_m <= 0 or not 0 < max_slope_deg < 90:
        raise ValueError("Invalid cell size or maximum slope")

    if slope_weight < 0 or risk_weight < 0:
        raise ValueError("Weights must be nonnegative")

    height, width = elevation.shape
    start = tuple(start)
    goal = tuple(goal)

    def valid(p):
        x, y = p
        return (
            0 <= x < width
            and 0 <= y < height
            and not obstacles[y, x]
        )

    if not valid(start) or not valid(goal):
        return {"status": "invalid_start_or_goal", "route": []}

    if start == goal:
        return {
            "status": "success",
            "route": [{"x": start[0], "y": start[1]}],
            "distance_m": 0.0,
            "elevation_gain_m": 0.0,
            "cost": 0.0,
            "nodes_explored": 0,
        }

    def heuristic(p):
        return math.hypot((goal[0] - p[0]) * cell_size_m, (goal[1] - p[1]) * cell_height_m)

    def line_cells(a, b):
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

        while ix < nx or iy < ny:
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

    def segment_cost(a, b):
        cells = line_cells(a, b)

        if any(not valid(p) for p in cells):
            return math.inf

        distance = math.hypot((b[0] - a[0]) * cell_size_m, (b[1] - a[1]) * cell_height_m)

        if distance == 0:
            return 0.0

        # Conservative check across all touched cells.
        z_values = [elevation[y, x] for x, y in cells]
        max_grade = (max(z_values) - min(z_values)) / distance

        if math.degrees(math.atan(max_grade)) > max_slope_deg:
            return math.inf

        # Approximate risk integral over the traversed cells.
        mean_risk = sum(risk[y, x] for x, y in cells) / len(cells)

        return (
            distance
            + slope_weight * (max(z_values) - min(z_values))
            + risk_weight * distance * mean_risk
        )

    g = {start: 0.0}
    parent = {start: start}
    heap = [(heuristic(start), 0.0, start)]
    explored = 0
    closed = set()

    while heap:
        _, current_g, current = heapq.heappop(heap)

        if current in closed or current_g > g[current] + 1e-9:
            continue

        closed.add(current)
        explored += 1

        if current == goal:
            break

        x, y = current

        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue

                neighbor = (x + dx, y + dy)

                if not valid(neighbor) or neighbor in closed:
                    continue

                # Standard adjacent relaxation.
                best_parent = current
                best_g = g[current] + segment_cost(current, neighbor)

                # Theta*: attempt line-of-sight from current's parent.
                candidate_parent = parent[current]

                if candidate_parent != current:
                    shortcut_cost = segment_cost(candidate_parent, neighbor)
                    candidate_g = g[candidate_parent] + shortcut_cost

                    if candidate_g < best_g:
                        best_g = candidate_g
                        best_parent = candidate_parent

                if best_g < g.get(neighbor, math.inf):
                    g[neighbor] = best_g
                    parent[neighbor] = best_parent
                    heapq.heappush(
                        heap,
                        (best_g + heuristic(neighbor), best_g, neighbor),
                    )

    if goal not in g:
        return {
            "status": "no_path",
            "route": [],
            "nodes_explored": explored,
        }

    path = []
    node = goal

    while True:
        path.append(node)
        if node == start:
            break
        node = parent[node]

    path.reverse()

    distance = sum(
        math.hypot((b[0] - a[0]) * cell_size_m, (b[1] - a[1]) * cell_height_m)
        for a, b in zip(path, path[1:])
    )

    elevation_gain = sum(
        max(0.0, elevation[b[1], b[0]] - elevation[a[1], a[0]])
        for a, b in zip(path, path[1:])
    )

    return {
        "status": "success",
        "algorithm": "theta_star",
        "route": [{"x": x, "y": y} for x, y in path],
        "distance_m": round(distance, 3),
        "elevation_gain_m": round(float(elevation_gain), 3),
        "cost": round(g[goal], 3),
        "nodes_explored": explored,
    }
