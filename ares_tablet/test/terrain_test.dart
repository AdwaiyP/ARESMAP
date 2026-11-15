import 'package:ares_tablet/models/ares_models.dart';
import 'package:ares_tablet/util/astro.dart';
import 'package:ares_tablet/util/terrain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bounds = MapBounds(136.1, -5.8, 138.7, -3.2);
  const landing = GeoPoint(137.44, -4.59);
  const veraRubin = GeoPoint(137.35, -4.69);

  group('Procedural Gale terrain', () {
    test('Aeolis Mons is well above the crater floor', () {
      final terrain = TerrainModel(bounds: bounds);
      final summit = terrain.elevationAt(137.85, -5.08);
      final floor = terrain.elevationAt(137.45, -4.59);
      expect(summit, greaterThan(floor + 3000));
      expect(terrain.maxElevation, greaterThan(terrain.minElevation));
      expect(terrain.displayGrid.length, 72);
      expect(terrain.displayGrid.first.length, 72);
      expect(terrain.slopeGrid.length, 64);
    });

    test('slopes are finite and non-negative', () {
      final terrain = TerrainModel(bounds: bounds);
      final slopes = terrain.slopeGrid.expand((row) => row);
      expect(slopes.every((value) => value.isFinite), isTrue);
      expect(slopes.every((value) => value >= 0), isTrue);
      expect(terrain.slopeAt(137.85, -5.08), greaterThan(0));
    });
  });

  group('A* traverse planner', () {
    test('route connects start and target with finite metrics', () {
      final terrain = TerrainModel(bounds: bounds);
      final plan = terrain.planRoute(landing, veraRubin, 'VERA RUBIN RIDGE');
      expect(plan.points.length, greaterThanOrEqualTo(2));
      expect(plan.elevations.length, plan.points.length);
      expect(plan.points.first.lon, closeTo(landing.lon, 1e-9));
      expect(plan.points.first.lat, closeTo(landing.lat, 1e-9));
      expect(plan.points.last.lon, closeTo(veraRubin.lon, 1e-9));
      expect(plan.points.last.lat, closeTo(veraRubin.lat, 1e-9));
      expect(plan.distanceKm, greaterThan(0.5));
      expect(plan.distanceKm, lessThan(30));
      expect(plan.duration.inSeconds, greaterThan(0));
      expect(plan.elevationGainM, greaterThanOrEqualTo(0));
      expect(plan.maxSlopeDeg.isFinite, isTrue);
      expect(plan.hazardCells, greaterThanOrEqualTo(0));
      expect(plan.cellSizeM, greaterThan(0));
      expect(plan.cellSizeM, lessThan(1000));
      expect(plan.targetName, 'VERA RUBIN RIDGE');
      expect(plan.durationLabel, matches(RegExp(r'^\d{2}h \d{2}m$')));
    });

    test('route distance is at least the direct separation', () {
      final terrain = TerrainModel(bounds: bounds);
      final plan = terrain.planRoute(landing, veraRubin, 'VRR');
      final direct = haversineKm(landing, veraRubin);
      expect(plan.distanceKm, greaterThanOrEqualTo(direct - 0.01));
    });
  });
}
