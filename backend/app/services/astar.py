import heapq
import math


def plan_astar(start, goal, elevation, obstacles=None, risk=None,
               cell_size_m=10.0, max_slope_deg=30.0,
               slope_weight=2.0, risk_weight=5.0, cell_height_m=None):
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

    if not math.isfinite(cell_size_m) or cell_size_m <= 0:
        raise ValueError("cell_size_m must be positive")
    if not 0 <= max_slope_deg < 90:
        raise ValueError("max_slope_deg must be between 0 and 90")
    if not all(math.isfinite(v) and v >= 0
               for v in (slope_weight, risk_weight)):
        raise ValueError("Weights must be finite and nonnegative")

    for row in elevation:
        if any(not math.isfinite(v) for v in row):
            raise ValueError("Elevation must be finite")
    for row in risk:
        if any(not math.isfinite(v) or not 0 <= v <= 1 for v in row):
            raise ValueError("Risk must be between 0 and 1")

    def inside(p):
        x, y = p
        return 0 <= x < width and 0 <= y < height

    if not inside(start) or not inside(goal):
        raise ValueError("Start or goal is outside the grid")
    if obstacles[start[1]][start[0]] or obstacles[goal[1]][goal[0]]:
        raise ValueError("Start or goal is blocked")
    if start == goal:
        raise ValueError("Start and goal must differ")

    def heuristic(p):
        return math.hypot(
            (goal[0] - p[0]) * cell_size_m, (goal[1] - p[1]) * cell_height_m
        )

    directions = [
        (-1, 0), (1, 0), (0, -1), (0, 1),
        (-1, -1), (-1, 1), (1, -1), (1, 1),
    ]

    queue = [(heuristic(start), 0.0, start)]
    best = {start: 0.0}
    previous = {}
    explored = 0

    while queue:
        _, current_cost, current = heapq.heappop(queue)
        if current_cost > best[current] + 1e-9:
            continue

        explored += 1

        if current == goal:
            path = [goal]
            while path[-1] != start:
                path.append(previous[path[-1]])
            path.reverse()

            distance = 0.0
            gain = 0.0
            for a, b in zip(path, path[1:]):
                step = math.hypot(
                    (b[0] - a[0]) * cell_size_m, (b[1] - a[1]) * cell_height_m
                )
                distance += step
                gain += max(
                    0.0,
                    elevation[b[1]][b[0]] -
                    elevation[a[1]][a[0]],
                )

            return {
                "status": "success",
                "route": [{"x": x, "y": y} for x, y in path],
                "distance_m": round(distance, 3),
                "elevation_gain_m": round(gain, 3),
                "total_cost": round(current_cost, 3),
                "explored_nodes": explored,
            }

        x, y = current
        for dx, dy in directions:
            nxt = (x + dx, y + dy)
            if not inside(nxt) or obstacles[nxt[1]][nxt[0]]:
                continue

            # Prevent crossing the corners of blocked cells.
            if dx and dy:
                if (obstacles[y][x + dx] or
                        obstacles[y + dy][x]):
                    continue

            distance = math.hypot(dx * cell_size_m, dy * cell_height_m)
            rise = (
                elevation[nxt[1]][nxt[0]] -
                elevation[y][x]
            )
            slope = math.degrees(math.atan2(abs(rise), distance))

            if slope > max_slope_deg:
                continue

            penalty = distance * (
                slope_weight * math.tan(math.radians(slope)) +
                risk_weight * risk[nxt[1]][nxt[0]]
            )
            candidate = current_cost + distance + penalty

            if candidate + 1e-9 < best.get(nxt, math.inf):
                best[nxt] = candidate
                previous[nxt] = current
                heapq.heappush(
                    queue,
                    (candidate + heuristic(nxt), candidate, nxt)
                )

    return {
        "status": "no_route",
        "route": [],
        "distance_m": None,
        "elevation_gain_m": None,
        "total_cost": None,
        "explored_nodes": explored,
    }
