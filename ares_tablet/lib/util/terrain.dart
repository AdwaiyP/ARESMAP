import 'dart:math' as math;
import 'dart:typed_data';

import '../models/ares_models.dart';
import 'astro.dart';

class GridCell {
  const GridCell(this.x, this.y);

  final int x;
  final int y;
}

/// Sampling window handed to the route solver. Column zero is [minLon] and
/// row zero is [maxLat], matching the backend's row-major elevation contract.
class RouteGrid {
  const RouteGrid({
    required this.start,
    required this.target,
    required this.minLon,
    required this.maxLon,
    required this.minLat,
    required this.maxLat,
    required this.cols,
    required this.rows,
    required this.elevations,
    required this.startX,
    required this.startY,
    required this.goalX,
    required this.goalY,
  });

  final GeoPoint start;
  final GeoPoint target;
  final double minLon;
  final double maxLon;
  final double minLat;
  final double maxLat;
  final int cols;
  final int rows;
  final Float64List elevations;
  final int startX;
  final int startY;
  final int goalX;
  final int goalY;

  double get lonSpan => maxLon - minLon;
  double get latSpan => maxLat - minLat;

  GeoPoint pointFor(int x, int y) => GeoPoint(
    minLon + (x / (cols - 1)) * lonSpan,
    maxLat - (y / (rows - 1)) * latSpan,
  );

  double elevationAt(int x, int y) => elevations[y * cols + x];

  double get cellSizeM => haversineKm(pointFor(0, 0), pointFor(1, 0)) * 1000;

  double get meanCellSizeM {
    final xCell = cellSizeM;
    final yCell = haversineKm(pointFor(0, 0), pointFor(0, 1)) * 1000;
    return (xCell + yCell) / 2;
  }
}

/// Procedural Gale Crater analog. The landforms follow the published
/// relief of Gale (floor, rim, Aeolis Mons) but are not a survey-grade DEM.
class TerrainModel {
  TerrainModel({required this.bounds}) {
    _displayGrid = _sampleGrid(72, 72);
    _slopeGrid = _sampleSlopes(64, 64);
  }

  final MapBounds bounds;

  static const _floorM = -4450.0;
  static const _moundLon = 137.85;
  static const _moundLat = -5.08;
  static const _centerLon = 137.8;
  static const _centerLat = -5.4;

  late final List<List<double>> _displayGrid;
  late final List<List<double>> _slopeGrid;

  List<List<double>> get displayGrid => _displayGrid;
  List<List<double>> get slopeGrid => _slopeGrid;

  double get minElevation {
    var minValue = double.infinity;
    for (final row in _displayGrid) {
      for (final value in row) {
        if (value < minValue) minValue = value;
      }
    }
    return minValue;
  }

  double get maxElevation {
    var maxValue = -double.infinity;
    for (final row in _displayGrid) {
      for (final value in row) {
        if (value > maxValue) maxValue = value;
      }
    }
    return maxValue;
  }

  List<List<double>> _sampleGrid(int cols, int rows) {
    return List.generate(rows, (y) {
      final lat = bounds.maxLat - (y / (rows - 1)) * bounds.heightDeg;
      return List.generate(cols, (x) {
        final lon = bounds.minLon + (x / (cols - 1)) * bounds.widthDeg;
        return elevationAt(lon, lat);
      });
    });
  }

  List<List<double>> _sampleSlopes(int cols, int rows) {
    return List.generate(rows, (y) {
      final lat = bounds.maxLat - (y / (rows - 1)) * bounds.heightDeg;
      return List.generate(cols, (x) {
        final lon = bounds.minLon + (x / (cols - 1)) * bounds.widthDeg;
        return slopeAt(lon, lat);
      });
    });
  }

  double elevationAt(double lon, double lat) {
    final dMound = _degreeDistance(lon, lat, _moundLon, _moundLat);
    final dCenter = _degreeDistance(lon, lat, _centerLon, _centerLat);

    // Broad asymmetric mound and summit block of Aeolis Mons.
    var z = _floorM;
    z += 5850 * math.exp(-math.pow(dMound / 0.46, 1.75));
    z += 1250 * math.exp(-math.pow(dMound / 0.15, 2));
    // Gale rim contributes at the edge of the view.
    z += 2300 * math.exp(-math.pow((dCenter - 1.02) / 0.14, 2));
    // Sinuous depression north of the mound (route-friendly terrain).
    final channelLat = -4.63 - (lon - 137.44) * 0.28;
    z -= 170 * math.exp(-math.pow((lat - channelLat) / 0.035, 2));
    // Multi-octave relief texture.
    z += _fbm(lon, lat, octaves: 4) * 210;
    return z;
  }

  double slopeAt(double lon, double lat) {
    const d = 0.006;
    final dzdx = elevationAt(lon + d, lat) - elevationAt(lon - d, lat);
    final dzdy = elevationAt(lon, lat + d) - elevationAt(lon, lat - d);
    final dx = 2 * d * 59.16 * math.cos(lat * math.pi / 180) * 1000;
    final dy = 2 * d * 59.16 * 1000;
    final gradient = math.sqrt(math.pow(dzdx / dx, 2) + math.pow(dzdy / dy, 2));
    return math.atan(gradient) * 180 / math.pi;
  }

  double _degreeDistance(double lon1, double lat1, double lon2, double lat2) {
    final dx = (lon2 - lon1) * math.cos(((lat1 + lat2) / 2) * math.pi / 180);
    final dy = lat2 - lat1;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _fbm(double lon, double lat, {required int octaves}) {
    var value = 0.0;
    var amplitude = 1.0;
    var frequency = 1.0;
    var total = 0.0;
    for (var i = 0; i < octaves; i++) {
      value +=
          _valueNoise(lon * 38 * frequency, lat * 38 * frequency) * amplitude;
      total += amplitude;
      amplitude *= 0.5;
      frequency *= 2.03;
    }
    return value / total - 0.5;
  }

  double _valueNoise(double x, double y) {
    final xi = x.floor();
    final yi = y.floor();
    final xf = x - xi;
    final yf = y - yi;
    final u = xf * xf * (3 - 2 * xf);
    final v = yf * yf * (3 - 2 * yf);
    final a = _hash(xi, yi);
    final b = _hash(xi + 1, yi);
    final c = _hash(xi, yi + 1);
    final d = _hash(xi + 1, yi + 1);
    return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v;
  }

  double _hash(int x, int y) {
    final value = math.sin(x * 127.1 + y * 311.7) * 43758.5453123;
    return value - value.floorToDouble();
  }

  RouteGrid buildRouteGrid(GeoPoint start, GeoPoint target) {
    final padLon = math.max((target.lon - start.lon).abs() * 0.35, 0.035);
    final padLat = math.max((target.lat - start.lat).abs() * 0.35, 0.035);
    final minLon = math.min(start.lon, target.lon) - padLon;
    final maxLon = math.max(start.lon, target.lon) + padLon;
    final minLat = math.min(start.lat, target.lat) - padLat;
    final maxLat = math.max(start.lat, target.lat) + padLat;

    final lonSpan = maxLon - minLon;
    final latSpan = maxLat - minLat;
    final cols = 128;
    final rows = (cols * latSpan / lonSpan).round().clamp(72, 160);

    final elevations = Float64List(cols * rows);
    for (var y = 0; y < rows; y++) {
      final lat = maxLat - (y / (rows - 1)) * latSpan;
      for (var x = 0; x < cols; x++) {
        final lon = minLon + (x / (cols - 1)) * lonSpan;
        elevations[y * cols + x] = elevationAt(lon, lat);
      }
    }

    int indexX(double lon) =>
        ((lon - minLon) / lonSpan * (cols - 1)).round().clamp(0, cols - 1);
    int indexY(double lat) =>
        ((maxLat - lat) / latSpan * (rows - 1)).round().clamp(0, rows - 1);

    return RouteGrid(
      start: start,
      target: target,
      minLon: minLon,
      maxLon: maxLon,
      minLat: minLat,
      maxLat: maxLat,
      cols: cols,
      rows: rows,
      elevations: elevations,
      startX: indexX(start.lon),
      startY: indexY(start.lat),
      goalX: indexX(target.lon),
      goalY: indexY(target.lat),
    );
  }

  TraversePlan planRoute(GeoPoint start, GeoPoint target, String targetName) {
    return planRouteOnGrid(buildRouteGrid(start, target), targetName);
  }

  TraversePlan planRouteOnGrid(RouteGrid grid, String targetName) {
    final cells = solveLocalGrid(grid);
    final rawPoints = cells.isEmpty
        ? const <GeoPoint>[]
        : cells.map((cell) => grid.pointFor(cell.x, cell.y)).toList();
    return _assemblePlan(grid, rawPoints, targetName);
  }

  /// Assembles a traverse from grid cells returned by a remote solver. Falls
  /// back to the on-device solve when the path is unusable.
  TraversePlan planRouteFromCells(
    RouteGrid grid,
    List<GridCell> cells,
    String targetName,
  ) {
    if (cells.length < 2) return planRouteOnGrid(grid, targetName);
    for (final cell in cells) {
      if (cell.x < 0 || cell.x >= grid.cols) {
        return planRouteOnGrid(grid, targetName);
      }
      if (cell.y < 0 || cell.y >= grid.rows) {
        return planRouteOnGrid(grid, targetName);
      }
    }
    return _assemblePlan(
      grid,
      cells.map((cell) => grid.pointFor(cell.x, cell.y)).toList(),
      targetName,
    );
  }

  TraversePlan _assemblePlan(
    RouteGrid grid,
    List<GeoPoint> rawPoints,
    String targetName,
  ) {
    var path = rawPoints.length < 2
        ? <GeoPoint>[grid.start, grid.target]
        : _chaikin(rawPoints, 2);
    if (haversineKm(grid.start, path.first) * 1000 > 1) {
      path = [grid.start, ...path];
    }
    if (haversineKm(path.last, grid.target) * 1000 > 1) {
      path = [...path, grid.target];
    }

    final routeElevations = path.map((p) => elevationAt(p.lon, p.lat)).toList();
    var distanceM = 0.0;
    var gain = 0.0;
    var maxSlope = 0.0;
    var durationSeconds = 0.0;
    var hazardCells = 0;
    for (var i = 1; i < path.length; i++) {
      final segmentM = haversineKm(path[i - 1], path[i]) * 1000;
      final dElev = routeElevations[i] - routeElevations[i - 1];
      distanceM += segmentM;
      if (dElev > 0) gain += dElev;
      final slopeDeg =
          math.atan(dElev.abs() / math.max(segmentM, 0.1)) * 180 / math.pi;
      if (slopeDeg > maxSlope) maxSlope = slopeDeg;
      if (slopeDeg > 13) hazardCells++;
      final speed = 0.4 * (1 - (slopeDeg / 45).clamp(0.0, 0.72));
      durationSeconds += segmentM / math.max(speed, 0.08);
    }

    return TraversePlan(
      points: path,
      elevations: routeElevations,
      distanceKm: distanceM / 1000,
      elevationGainM: gain,
      maxSlopeDeg: maxSlope,
      duration: Duration(seconds: durationSeconds.round()),
      targetName: targetName,
      target: grid.target,
      cellSizeM: grid.cellSizeM,
      hazardCells: hazardCells,
    );
  }

  List<GridCell> solveLocalGrid(RouteGrid grid, {double? maxSlopeDeg}) {
    final cols = grid.cols;
    final rows = grid.rows;
    final total = cols * rows;
    final gScore = Float64List(total)..fillRange(0, total, double.infinity);
    final parent = Int32List(total)..fillRange(0, total, -1);
    final closed = Uint8List(total);
    final startIndex = grid.startY * cols + grid.startX;
    final targetIndex = grid.goalY * cols + grid.goalX;
    if (startIndex == targetIndex) {
      return [GridCell(grid.startX, grid.startY)];
    }
    gScore[startIndex] = 0;

    final heap = _MinHeap();
    heap.push(startIndex, 0);
    var found = false;
    const neighbors = [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
      [-1, -1],
      [1, -1],
      [-1, 1],
      [1, 1],
    ];

    while (heap.isNotEmpty) {
      final current = heap.pop();
      if (closed[current] == 1) continue;
      closed[current] = 1;
      if (current == targetIndex) {
        found = true;
        break;
      }
      final cx = current % cols;
      final cy = current ~/ cols;
      for (final delta in neighbors) {
        final nx = cx + delta[0];
        final ny = cy + delta[1];
        if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) continue;
        final next = ny * cols + nx;
        if (closed[next] == 1) continue;
        final from = grid.pointFor(cx, cy);
        final to = grid.pointFor(nx, ny);
        final stepM = haversineKm(from, to) * 1000;
        final slope =
            (grid.elevations[next] - grid.elevations[current]).abs() / stepM;
        final slopeDeg = math.atan(slope) * 180 / math.pi;
        if (maxSlopeDeg != null && slopeDeg > maxSlopeDeg) continue;
        var penalty = 1.0 + math.pow(slopeDeg / 9, 2) * 2.2;
        if (slopeDeg > 18) penalty += 6.0;
        if (slopeDeg > 28) penalty += 18.0;
        final tentative = gScore[current] + stepM * penalty;
        if (tentative < gScore[next]) {
          gScore[next] = tentative;
          parent[next] = current;
          final heuristic = haversineKm(to, grid.target) * 1000;
          heap.push(next, tentative + heuristic);
        }
      }
    }

    if (!found) return const [];
    final path = <GridCell>[];
    var node = targetIndex;
    while (node != -1) {
      path.add(GridCell(node % cols, node ~/ cols));
      if (node == startIndex) break;
      node = parent[node];
    }
    return path.reversed.toList(growable: false);
  }

  List<GeoPoint> _chaikin(List<GeoPoint> input, int iterations) {
    var points = input;
    for (var pass = 0; pass < iterations; pass++) {
      if (points.length < 3) return points;
      final output = <GeoPoint>[points.first];
      for (var i = 0; i < points.length - 1; i++) {
        final a = points[i];
        final b = points[i + 1];
        output.add(
          GeoPoint(a.lon * 0.75 + b.lon * 0.25, a.lat * 0.75 + b.lat * 0.25),
        );
        output.add(
          GeoPoint(a.lon * 0.25 + b.lon * 0.75, a.lat * 0.25 + b.lat * 0.75),
        );
      }
      output.add(points.last);
      points = output;
    }
    return points;
  }
}

class _MinHeap {
  final List<int> _ids = [];
  final List<double> _scores = [];

  bool get isNotEmpty => _ids.isNotEmpty;

  void push(int id, double score) {
    _ids.add(id);
    _scores.add(score);
    var index = _ids.length - 1;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_scores[parent] <= _scores[index]) break;
      _swap(index, parent);
      index = parent;
    }
  }

  int pop() {
    final top = _ids.first;
    final lastId = _ids.removeLast();
    final lastScore = _scores.removeLast();
    if (_ids.isNotEmpty) {
      _ids[0] = lastId;
      _scores[0] = lastScore;
      var index = 0;
      while (true) {
        final left = index * 2 + 1;
        final right = left + 1;
        var smallest = index;
        if (left < _ids.length && _scores[left] < _scores[smallest]) {
          smallest = left;
        }
        if (right < _ids.length && _scores[right] < _scores[smallest]) {
          smallest = right;
        }
        if (smallest == index) break;
        _swap(index, smallest);
        index = smallest;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final id = _ids[a];
    final score = _scores[a];
    _ids[a] = _ids[b];
    _scores[a] = _scores[b];
    _ids[b] = id;
    _scores[b] = score;
  }
}
