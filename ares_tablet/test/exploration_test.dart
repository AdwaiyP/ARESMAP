import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ares_tablet/data/exploration_data.dart';
import 'package:ares_tablet/models/ares_models.dart';
import 'package:ares_tablet/util/astro.dart';
import 'package:ares_tablet/util/eva_plan.dart';
import 'package:ares_tablet/util/globe_projection.dart';
import 'package:ares_tablet/util/space_edac.dart';
import 'package:ares_tablet/util/terrain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Space EDAC', () {
    test('CRC32 matches independent standard vector', () {
      expect(crc32(utf8.encode('123456789')), 'CBF43926');
      expect(crc32([]), '00000000');
    });
    test('every single-bit error in all byte values is corrected', () {
      for (var byte = 0; byte < 256; byte++) {
        for (var bit = 0; bit < 7; bit++) {
          final words = encodeHamming74([byte]);
          words[0] ^= 1 << bit;
          words[1] ^= 1 << ((bit + 1) % 7);
          final result = decodeHamming74(words);
          expect(result.$1, [byte]);
          expect(result.$2, 2);
        }
      }
    });
    test('clean, UTF8, recoverable and uncorrectable packets', () {
      expect(testSpaceLink('ARES', flips: 0).correctedWords, 0);
      expect(testSpaceLink('Mars — O₂', flips: 8).verified, isTrue);
      expect(testSpaceLink('ARES', doubleError: true).verified, isFalse);
      expect(() => decodeHamming74([1]), throwsArgumentError);
      expect(() => testSpaceLink('ARES', flips: -1), throwsArgumentError);
    });
  });

  group('Globe picking', () {
    test('center and hidden hemisphere', () {
      final p = projectGlobe(const GeoPoint(137.4, -4.6), 137.4, -4.6);
      expect(p.$1, closeTo(0, 1e-8));
      expect(p.$2, closeTo(0, 1e-8));
      expect(p.$3, closeTo(1, 1e-8));
      expect(
        projectGlobe(const GeoPoint(-42.6, 4.6), 137.4, -4.6).$3,
        lessThan(0),
      );
      expect(unprojectGlobe(1.1, 0, 0, 0), isNull);
    });
    test('screen pick round trip across antimeridian and tilt', () {
      for (final point in [
        const GeoPoint(-175, 35),
        const GeoPoint(165, 55),
        const GeoPoint(179, 70),
      ]) {
        final projected = projectGlobe(point, 170, 40);
        final picked = unprojectGlobe(projected.$1, projected.$2, 170, 40)!;
        expect(picked.lon, closeTo(point.lon, 1e-6));
        expect(picked.lat, closeTo(point.lat, 1e-6));
      }
    });
  });

  group('EVA route', () {
    final terrain = TerrainModel(
      bounds: const MapBounds(136.1, -5.8, 138.7, -3.2),
    );
    const center = GeoPoint(137.4, -4.655);
    final bounds = evaBounds(center);
    test('window is 500m, 10m sampling and budget includes return reserve', () {
      final start = GeoPoint(
        bounds.minLon + bounds.widthDeg * .2,
        bounds.minLat + bounds.heightDeg * .2,
      );
      final goal = GeoPoint(
        bounds.minLon + bounds.widthDeg * .7,
        bounds.minLat + bounds.heightDeg * .7,
      );
      final grid = buildEvaGrid(terrain, bounds, start, goal);
      expect(grid.cellSizeM, closeTo(10, 0.01));
      expect(
        haversineKm(
              GeoPoint(bounds.minLon, center.lat),
              GeoPoint(bounds.maxLon, center.lat),
            ) *
            1000,
        closeTo(500, 0.01),
      );
      final result = solveEva(terrain, grid)!;
      expect(result.distanceM, closeTo(353.55, 1));
      expect(result.maxSlope, lessThanOrEqualTo(25));
      expect(result.stops.length, 9);
      expect(
        result.roundTripMinutes,
        closeTo(result.walkMinutes * 2 + 30, 1e-9),
      );
      expect(
        result.oxygenMarginMinutes,
        closeTo(252 - result.roundTripMinutes, 1e-9),
      );
    });
    test('impassable grid returns no route instead of a straight line', () {
      final grid = RouteGrid(
        start: center,
        target: const GeoPoint(137.40002, -4.655),
        minLon: 137.4,
        maxLon: 137.40002,
        minLat: -4.65502,
        maxLat: -4.655,
        cols: 3,
        rows: 3,
        elevations: Float64List.fromList([
          0,
          1000,
          2000,
          0,
          1000,
          2000,
          0,
          1000,
          2000,
        ]),
        startX: 0,
        startY: 0,
        goalX: 2,
        goalY: 0,
      );
      expect(solveEva(terrain, grid), isNull);
    });
  });

  test(
    'planned waypoint writes, replaces and removes without changing catalog',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ares-waypoint-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/waypoints.json');
      final data = ExplorationData([], [], file);
      const point = SurveyFeature(
        id: 'planned-1',
        name: 'Sample site',
        point: GeoPoint(137.4, -4.6),
        kind: 'planned',
        notes: 'Operator entered',
        source: 'Tablet',
      );
      await data.save([point]);
      final decoded = SurveyFeature.fromJson(
        (jsonDecode(await file.readAsString()) as List).single
            as Map<String, dynamic>,
      );
      expect(decoded.name, point.name);
      expect(decoded.point.lon, point.point.lon);
      expect(data.planned.single.id, point.id);
      await data.save([]);
      expect(jsonDecode(await file.readAsString()), isEmpty);
      expect(data.catalog, isEmpty);
    },
  );
}
