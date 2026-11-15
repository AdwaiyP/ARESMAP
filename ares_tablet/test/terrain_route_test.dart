import 'package:ares_tablet/models/ares_models.dart';
import 'package:ares_tablet/util/terrain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final terrain = TerrainModel(
    bounds: const MapBounds(137.2, -5.0, 138.1, -4.3),
  );
  const start = GeoPoint(137.4, -4.655);
  const target = GeoPoint(137.65, -4.6);

  test('on-device solve builds a route over the sampled grid', () {
    final grid = terrain.buildRouteGrid(start, target);
    final plan = terrain.planRouteOnGrid(grid, 'TEST TARGET');

    expect(plan.points.length, greaterThanOrEqualTo(2));
    expect(plan.distanceKm, greaterThan(0));
    expect(plan.targetName, 'TEST TARGET');
    expect(plan.target.lon, target.lon);
    expect(plan.points.first.lon, closeTo(start.lon, 1e-9));
    expect(plan.points.last.lon, closeTo(target.lon, 1e-9));
  });

  test('backend cells assemble a plan over the same grid', () {
    final grid = terrain.buildRouteGrid(start, target);
    final midX = (grid.startX + grid.goalX) ~/ 2;
    final midY = (grid.startY + grid.goalY) ~/ 2;
    final plan = terrain.planRouteFromCells(grid, [
      GridCell(grid.startX, grid.startY),
      GridCell(midX, midY),
      GridCell(grid.goalX, grid.goalY),
    ], 'REMOTE TARGET');

    expect(plan.points.length, greaterThan(2));
    expect(plan.distanceKm, greaterThan(0));
    expect(plan.targetName, 'REMOTE TARGET');
    expect(plan.points.first.lon, closeTo(start.lon, 1e-9));
    expect(plan.points.last.lon, closeTo(target.lon, 1e-9));
  });

  test('out-of-bounds backend cells fall back to the local solve', () {
    final grid = terrain.buildRouteGrid(start, target);
    final plan = terrain.planRouteFromCells(grid, [
      const GridCell(-1, 0),
      GridCell(grid.goalX, grid.goalY),
    ], 'FALLBACK');

    expect(plan.points.length, greaterThanOrEqualTo(2));
    expect(plan.distanceKm, greaterThan(0));
  });
}
