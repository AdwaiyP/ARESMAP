import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ares_tablet/data/backend_api.dart';
import 'package:ares_tablet/models/ares_models.dart';
import 'package:ares_tablet/util/terrain.dart';
import 'package:flutter_test/flutter_test.dart';

RouteGrid _grid() {
  const cols = 4;
  const rows = 3;
  final elevations = Float64List(cols * rows);
  for (var i = 0; i < elevations.length; i++) {
    elevations[i] = i * 3.0;
  }
  return RouteGrid(
    start: const GeoPoint(137.0, -4.5),
    target: const GeoPoint(137.03, -4.5),
    minLon: 136.99,
    maxLon: 137.04,
    minLat: -4.55,
    maxLat: -4.45,
    cols: cols,
    rows: rows,
    elevations: elevations,
    startX: 0,
    startY: 1,
    goalX: 3,
    goalY: 1,
  );
}

void main() {
  late HttpServer server;
  late AresBackend backend;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    backend = AresBackend(
      baseUrl: 'http://127.0.0.1:${server.port}',
      timeout: const Duration(milliseconds: 800),
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('health probe reports an online backend', () async {
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ok', 'service': 'ARES'}));
      await request.response.close();
    });
    expect(await backend.ping(), isTrue);
  });

  test('route request sends the sampled grid and parses cells', () async {
    Map<String, dynamic>? received;
    server.listen((request) async {
      received = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'status': 'success',
            'route': [
              {'x': 0, 'y': 1},
              {'x': 1, 'y': 1},
              {'x': 2, 'y': 1},
              {'x': 3, 'y': 1},
            ],
            'distance_m': 30.0,
            'elevation_gain_m': 0.0,
            'explored_nodes': 7,
            'terrain_source': 'client_supplied_grid',
            'validated_for_eva_safety': false,
          }),
        );
      await request.response.close();
    });

    final result = await backend.planRoute(_grid());

    expect(received, isNotNull);
    expect(received!['start'], {'x': 0, 'y': 1});
    expect(received!['goal'], {'x': 3, 'y': 1});
    expect((received!['elevation'] as List), hasLength(3));
    expect(((received!['elevation'] as List).first as List), hasLength(4));
    expect(received!['cell_size_m'], greaterThan(0));
    expect(result, isNotNull);
    expect(result!.status, 'success');
    expect(result.hasRoute, isTrue);
    expect(result.cells, hasLength(4));
    expect(result.cells.last.x, 3);
    expect(result.exploredNodes, 7);
  });

  test('no_route keeps the result reachable but without a path', () async {
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'status': 'no_route',
            'route': <Object>[],
            'distance_m': null,
            'elevation_gain_m': null,
            'total_cost': null,
            'explored_nodes': 12,
          }),
        );
      await request.response.close();
    });
    final result = await backend.planRoute(_grid());
    expect(result, isNotNull);
    expect(result!.status, 'no_route');
    expect(result.hasRoute, isFalse);
    expect(result.exploredNodes, 12);
  });

  test('rejected request is reported without dropping the link', () async {
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.unprocessableEntity
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'detail': 'Start or goal is outside the grid'}));
      await request.response.close();
    });
    final result = await backend.planRoute(_grid());
    expect(result, isNotNull);
    expect(result!.status, 'rejected');
    expect(result.hasRoute, isFalse);
  });

  test('unreachable backend fails soft', () async {
    final port = server.port;
    await server.close(force: true);
    final offline = AresBackend(
      baseUrl: 'http://127.0.0.1:$port',
      timeout: const Duration(milliseconds: 500),
    );
    expect(await offline.ping(), isFalse);
    expect(await offline.planRoute(_grid()), isNull);
  });
}
