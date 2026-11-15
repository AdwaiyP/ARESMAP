import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../util/terrain.dart';

class BackendRouteResult {
  const BackendRouteResult({
    required this.status,
    this.cells = const [],
    this.distanceM,
    this.elevationGainM,
    this.exploredNodes = 0,
    this.terrainSource = 'client_supplied_grid',
  });

  final String status;
  final List<GridCell> cells;
  final double? distanceM;
  final double? elevationGainM;
  final int exploredNodes;
  final String terrainSource;

  bool get hasRoute => status == 'success' && cells.length > 1;
}

class _BackendResponse {
  const _BackendResponse(this.statusCode, this.json);

  final int statusCode;
  final Map<String, dynamic>? json;
}

/// Optional link to the ARES FastAPI backend. Every call fails soft: the
/// tablet keeps operating on its bundled archive and procedural DEM.
class AresBackend {
  AresBackend({String? baseUrl, this.timeout = const Duration(seconds: 3)})
    : baseUrl = baseUrl ?? defaultBaseUrl;

  static const defaultBaseUrl = String.fromEnvironment(
    'ARES_API_BASE',
    defaultValue: 'http://10.0.2.2:8006',
  );

  final String baseUrl;
  final Duration timeout;

  Future<bool> ping() async {
    final response = await _send('GET', '/api/v1/health');
    return response != null &&
        response.statusCode == HttpStatus.ok &&
        response.json?['status'] == 'ok';
  }

  /// Solves the traverse on the backend over the exact grid sampled on-device.
  /// Returns null when the backend cannot be reached.
  Future<BackendRouteResult?> planRoute(
    RouteGrid grid, {
    double maxSlopeDeg = 30,
    double slopeWeight = 2,
    double riskWeight = 5,
  }) async {
    final elevationRows = List<List<double>>.generate(
      grid.rows,
      (y) => List<double>.generate(
        grid.cols,
        (x) => grid.elevationAt(x, y),
        growable: false,
      ),
      growable: false,
    );
    final response = await _send(
      'POST',
      '/api/v1/routes/plan',
      body: {
        'start': {'x': grid.startX, 'y': grid.startY},
        'goal': {'x': grid.goalX, 'y': grid.goalY},
        'elevation': elevationRows,
        'cell_size_m': grid.meanCellSizeM,
        'max_slope_deg': maxSlopeDeg,
        'slope_weight': slopeWeight,
        'risk_weight': riskWeight,
      },
    );
    if (response == null) return null;
    final json = response.json;
    if (response.statusCode != HttpStatus.ok || json == null) {
      return const BackendRouteResult(status: 'rejected');
    }
    final status = json['status'];
    if (status is! String) {
      return const BackendRouteResult(status: 'rejected');
    }
    final cells = <GridCell>[];
    final route = json['route'];
    if (route is List) {
      for (final item in route) {
        if (item is Map) {
          final x = item['x'];
          final y = item['y'];
          if (x is num && y is num) {
            cells.add(GridCell(x.toInt(), y.toInt()));
          }
        }
      }
    }
    return BackendRouteResult(
      status: status,
      cells: cells,
      distanceM: (json['distance_m'] as num?)?.toDouble(),
      elevationGainM: (json['elevation_gain_m'] as num?)?.toDouble(),
      exploredNodes: (json['explored_nodes'] as num?)?.toInt() ?? 0,
      terrainSource:
          json['terrain_source'] as String? ?? 'client_supplied_grid',
    );
  }

  Future<Uint8List?> fetchRegionalTextureBytes({
    required String bbox,
    String style = 'viking_red',
    int size = 1024,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final uri = Uri.parse(
        '$baseUrl/api/v1/map/regional-texture?bbox=${Uri.encodeQueryComponent(bbox)}&style=${Uri.encodeQueryComponent(style)}&size=$size',
      );
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } on Exception {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<_BackendResponse?> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .openUrl(method, Uri.parse('$baseUrl$path'))
          .timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final decoded = text.isEmpty ? null : jsonDecode(text);
      return _BackendResponse(
        response.statusCode,
        decoded is Map<String, dynamic> ? decoded : null,
      );
    } on Exception {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
