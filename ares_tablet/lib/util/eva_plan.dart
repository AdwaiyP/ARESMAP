import 'dart:math' as math;
import 'dart:typed_data';

import '../models/ares_models.dart';
import 'astro.dart';
import 'terrain.dart';

class EvaPlan {
  EvaPlan(this.points, this.distanceM, this.maxSlope, this.cautionSegments);
  final List<GeoPoint> points;
  final double distanceM;
  final double maxSlope;
  final int cautionSegments;
  double get walkMinutes => distanceM / 1.2 / 60;
  double get roundTripMinutes => walkMinutes * 2 + 30;
  double get oxygenMarginMinutes => 252 - roundTripMinutes;
  List<GeoPoint> get stops {
    final count = math.min(9, points.length);
    return List.generate(
      count,
      (i) => points[(i * (points.length - 1) / (count - 1)).round()],
    );
  }
}

MapBounds evaBounds(GeoPoint center) {
  final latHalf = 0.25 / (marsRadiusKm * math.pi / 180);
  final lonHalf = latHalf / math.cos(center.lat * math.pi / 180);
  return MapBounds(
    center.lon - lonHalf,
    center.lat - latHalf,
    center.lon + lonHalf,
    center.lat + latHalf,
  );
}

RouteGrid buildEvaGrid(
  TerrainModel terrain,
  MapBounds bounds,
  GeoPoint start,
  GeoPoint goal,
) {
  const n = 51;
  final heights = Float64List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      heights[y * n + x] = terrain.elevationAt(
        bounds.minLon + x / (n - 1) * bounds.widthDeg,
        bounds.maxLat - y / (n - 1) * bounds.heightDeg,
      );
    }
  }
  int col(GeoPoint p) => ((p.lon - bounds.minLon) / bounds.widthDeg * (n - 1))
      .round()
      .clamp(0, n - 1);
  int row(GeoPoint p) => ((bounds.maxLat - p.lat) / bounds.heightDeg * (n - 1))
      .round()
      .clamp(0, n - 1);
  return RouteGrid(
    start: start,
    target: goal,
    minLon: bounds.minLon,
    maxLon: bounds.maxLon,
    minLat: bounds.minLat,
    maxLat: bounds.maxLat,
    cols: n,
    rows: n,
    elevations: heights,
    startX: col(start),
    startY: row(start),
    goalX: col(goal),
    goalY: row(goal),
  );
}

EvaPlan? solveEva(TerrainModel terrain, RouteGrid grid) {
  final cells = terrain.solveLocalGrid(grid, maxSlopeDeg: 25);
  if (cells.length < 2) return null;
  // Keep the grid path unsmoothed so the displayed path cannot cut across rejected slopes.
  final points = cells.map((c) => grid.pointFor(c.x, c.y)).toList();
  var distance = 0.0, maxSlope = 0.0;
  var caution = 0;
  for (var i = 1; i < points.length; i++) {
    final length = haversineKm(points[i - 1], points[i]) * 1000;
    final rise =
        grid.elevationAt(cells[i].x, cells[i].y) -
        grid.elevationAt(cells[i - 1].x, cells[i - 1].y);
    final slope = math.atan2(rise.abs(), length) * 180 / math.pi;
    distance += length;
    maxSlope = math.max(maxSlope, slope);
    if (slope >= 15) caution++;
  }
  return EvaPlan(points, distance, maxSlope, caution);
}
