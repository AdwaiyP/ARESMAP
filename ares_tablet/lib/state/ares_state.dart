import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/ares_dataset.dart';
import '../data/backend_api.dart';
import '../models/ares_models.dart';
import '../util/astro.dart';
import '../util/terrain.dart';

class MissionObjective {
  const MissionObjective({
    required this.code,
    required this.title,
    required this.detail,
    required this.done,
  });

  final String code;
  final String title;
  final String detail;
  final bool done;
}

class AresState extends ChangeNotifier {
  AresState(this.data, {this.backend}) {
    terrain = TerrainModel(bounds: data.bounds);
    current = const GeoPoint(137.4000, -4.6550);
    buddy = GeoPoint(current.lon + 0.00042, current.lat + 0.00012);
    archiveTrail = data.curiosityTrail;
    focus = focusFromReference(data.references.last);
    _planRouteGrid(
      terrain.buildRouteGrid(current, data.veraRubin.point),
      'VERA RUBIN RIDGE',
    );
    samples = [
      SampleRecord(
        id: 'ARES-001',
        label: 'ARES-001 · FLOAT ROCK',
        context: 'Operator-entered demo record · WP-03 · context from THEMIS thermal stamp.',
        point: const GeoPoint(137.4240, -4.6110),
        mtc: marsClockAt(DateTime.now().toUtc()).mtc,
        provenance: Provenance.sim,
        loggedAt: DateTime.now().toUtc(),
      ),
    ];
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      now = DateTime.now().toUtc();
      notifyListeners();
    });
    if (backend != null) {
      _probeBackend();
      _healthTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _probeBackend(),
      );
    }
  }

  final AresDataset data;
  final AresBackend? backend;
  late final TerrainModel terrain;
  late final GeoPoint current;
  late final GeoPoint buddy;
  late final List<GeoPoint> archiveTrail;

  DateTime now = DateTime.now().toUtc();
  Timer? _timer;
  Timer? _healthTimer;
  bool backendOnline = false;
  bool backendChecked = false;
  bool routeSolvedByBackend = false;
  int backendExploredNodes = 0;
  int _routeEpoch = 0;
  bool _disposed = false;

  int screenIndex = 0;
  int mapLayer = 0;
  bool routeMode = false;
  bool showThemis = true;
  bool showSlope = false;
  bool showPnr = true;
  bool showArchive = true;
  int photoIndex = 2;

  late MapFocus focus;
  TraversePlan? route;
  List<SampleRecord> samples = [];
  final Set<String> acknowledged = {};
  final Set<int> visited = {0};

  static const pnrRadiusKm = 5.0;
  static const _baseWalkSpeedKmh = 1.44;

  AresDataset get dataset => data;
  MapBounds get bounds => data.bounds;
  SurfacePhoto get photo => data.photos[photoIndex];
  List<ThemisStamp> get stamps => data.stamps;
  List<MarsReference> get references => data.references;
  List<MedaRecord> get meda => data.meda;

  MarsClock get marsClock => marsClockAt(now, lonDeg: current.lon);
  SolarPosition get sun => solarPosition(current, marsClock);
  double get owltSeconds => oneWayLightSeconds(now);
  String get earthUtc => formatUtc(now);
  String get earthClock => earthUtc.split(' ').last;
  String get earthDate => earthUtc.split(' ').first;
  String get owltLabel => formatSeconds(owltSeconds);

  double get pnrDistanceKm => haversineKm(current, data.landingSite.point);
  double get pnrBearing => initialBearingDeg(current, data.landingSite.point);
  double get pnrUsage => pnrDistanceKm / pnrRadiusKm;
  Duration get pnrReturnTime => Duration(
    seconds: ((pnrDistanceKm / _baseWalkSpeedKmh) * 3600 + 25 * 60).round(),
  );
  String get pnrStatus => switch (pnrUsage) {
    >= 1.0 => 'OUTSIDE PNR',
    >= 0.8 => 'NEAR LIMIT',
    _ => 'WITHIN PNR',
  };

  double get buddyDistanceM => haversineKm(current, buddy) * 1000;

  int get relayWindowSeconds =>
      2820 - (now.millisecondsSinceEpoch ~/ 1000) % 2820;

  List<double> get airSeries => meda
      .map((r) => r.airTempMean)
      .whereType<double>()
      .toList(growable: false);

  List<double> get groundSeries => meda
      .map((r) => r.groundTempMean)
      .whereType<double>()
      .toList(growable: false);

  List<double> get pressureSeries =>
      meda.map((r) => r.pressurePa).whereType<double>().toList(growable: false);

  List<double?> get opacitySeries =>
      meda.map((r) => r.opacity).toList(growable: false);

  int get invalidOpacityCount =>
      opacitySeries.whereType<double>().where((v) => v < 0.1 || v > 2.0).length;

  double get opacityMedian {
    final values = opacitySeries.whereType<double>().toList()..sort();
    return median(values);
  }

  double get airMin => airSeries.reduce(math.min);
  double get airMax => airSeries.reduce(math.max);
  double get groundMin => groundSeries.reduce(math.min);
  double get groundMax => groundSeries.reduce(math.max);
  double get pressureMin => pressureSeries.reduce(math.min);
  double get pressureMax => pressureSeries.reduce(math.max);

  List<MissionObjective> get objectives => [
    MissionObjective(
      code: 'P1',
      title: 'Plan a safe traverse to Vera Rubin Ridge',
      detail: route?.targetName ?? 'No traverse target set',
      done: route != null,
    ),
    MissionObjective(
      code: 'P2',
      title: 'Review slope and solar load in 3D',
      detail: visited.contains(2)
          ? 'Terrain review complete'
          : 'Open the 3D terrain view',
      done: visited.contains(2),
    ),
    MissionObjective(
      code: 'P3',
      title: 'Review archive surface imagery',
      detail: visited.contains(3)
          ? 'Surface panorama reviewed'
          : 'Open surface imagery',
      done: visited.contains(3),
    ),
    MissionObjective(
      code: 'P4',
      title: 'Log two context-linked samples',
      detail: '${samples.length} of 2 logged',
      done: samples.length >= 2,
    ),
    MissionObjective(
      code: 'P5',
      title: 'Hold PNR and rule-of-two',
      detail:
          '${pnrDistanceKm.toStringAsFixed(1)} km / '
          '${AresState.pnrRadiusKm.toStringAsFixed(1)} km · buddy '
          '${buddyDistanceM.round()} m',
      done: pnrUsage < 1.0 && buddyDistanceM < 50,
    ),
  ];

  int get objectivesDone => objectives.where((o) => o.done).length;

  List<AresAlert> get alerts {
    final relay = formatSeconds(relayWindowSeconds.toDouble());
    final list = <AresAlert>[
      AresAlert(
        id: 'rad',
        severity: AlertSeverity.warning,
        title: 'RAD MONITOR NOT IN ARCHIVE',
        detail:
            'No ionizing-radiation channel exists in the Sol 100 MEDA extract. '
            'Dose is unknown; do not clear EVA on this display.',
        source: 'SUIT / RAD',
        provenance: Provenance.noData,
        acknowledged: acknowledged.contains('rad'),
      ),
      AresAlert(
        id: 'opacity',
        severity: AlertSeverity.caution,
        title: 'OPTICAL DEPTH UNVALIDATED',
        detail:
            '$invalidOpacityCount of ${meda.length} raw opacity samples fall outside '
            'the plausible 0.1–2.0 range. Dust risk is not assessed from this series.',
        source: 'MEDA SOL 100',
        provenance: Provenance.archive,
        acknowledged: acknowledged.contains('opacity'),
      ),
      AresAlert(
        id: 'relay',
        severity: AlertSeverity.info,
        title: 'ORBITER RELAY WINDOW IN $relay',
        detail:
            'Next MRO pass simulated. Store-and-forward queue active; local base '
            'latency 1.8 s, Earth one-way ${formatSeconds(owltSeconds)}.',
        source: 'COMMS',
        provenance: Provenance.sim,
        acknowledged: acknowledged.contains('relay'),
      ),
      AresAlert(
        id: 'slope',
        severity: route != null && route!.maxSlopeDeg > 14
            ? AlertSeverity.caution
            : AlertSeverity.info,
        title: route != null && route!.maxSlopeDeg > 14
            ? 'STEEP SEGMENT ON PLANNED TRAVERSE'
            : 'TRAVERSE SLOPE WITHIN LIMIT',
        detail: route == null
            ? 'No traverse planned.'
            : 'Maximum ${route!.maxSlopeDeg.toStringAsFixed(1)}° across '
                  '${route!.hazardCells} hazard segment(s); slope limit 20°.',
        source: 'TERRAIN',
        provenance: Provenance.derived,
        acknowledged: acknowledged.contains('slope'),
      ),
      AresAlert(
        id: 'pnr',
        severity: pnrUsage >= 0.8 ? AlertSeverity.caution : AlertSeverity.info,
        title: 'PNR $pnrStatus',
        detail:
            '${pnrDistanceKm.toStringAsFixed(2)} km of '
            '${pnrRadiusKm.toStringAsFixed(1)} km from Bradbury Landing. '
            'Return ${formatDuration(pnrReturnTime)} at 1.44 km/h.',
        source: 'PNT',
        provenance: Provenance.derived,
        acknowledged: acknowledged.contains('pnr'),
      ),
      AresAlert(
        id: 'buddy',
        severity: buddyDistanceM > 50
            ? AlertSeverity.warning
            : AlertSeverity.info,
        title: buddyDistanceM > 50 ? 'RULE OF TWO VIOLATION' : 'EVA-2 LINKED',
        detail:
            'Buddy separation ${buddyDistanceM.round()} m, link nominal. '
            'Rule of two requires < 50 m line-of-sight.',
        source: 'EVA',
        provenance: Provenance.sim,
        acknowledged: acknowledged.contains('buddy'),
      ),
    ];
    list.sort((a, b) => _severityRank(b.severity) - _severityRank(a.severity));
    return list;
  }

  List<AresAlert> get unacknowledgedAlerts =>
      alerts.where((a) => !a.acknowledged).toList(growable: false);

  int _severityRank(AlertSeverity severity) => switch (severity) {
    AlertSeverity.critical => 3,
    AlertSeverity.warning => 2,
    AlertSeverity.caution => 1,
    AlertSeverity.info => 0,
  };

  MapFocus focusFromReference(MarsReference ref) => MapFocus(
    id: ref.id,
    name: ref.name,
    kind: ref.category.replaceAll('_', ' ').toUpperCase(),
    detail: ref.notes,
    lon: ref.lon,
    lat: ref.lat,
    provenance: Provenance.archive,
  );

  MapFocus focusFromStamp(ThemisStamp stamp) => MapFocus(
    id: stamp.fileId,
    name: 'THEMIS ${stamp.fileId}',
    kind: stamp.frameType == 'IR' ? 'THERMAL STAMP · IR' : 'VISIBLE STAMP',
    detail: stamp.description.isEmpty
        ? 'THEMIS radiance footprint over Gale Crater.'
        : '${stamp.description} · bands ${stamp.bands}',
    lon: stamp.lon,
    lat: stamp.lat,
    provenance: Provenance.archive,
    tempC: stamp.tempC,
    albedo: stamp.albedo,
    frameType: stamp.frameType,
    stamp: stamp,
  );

  void setScreen(int index) {
    screenIndex = index;
    visited.add(index);
    notifyListeners();
  }

  void setMapLayer(int index) {
    mapLayer = index;
    notifyListeners();
  }

  void toggleRouteMode() {
    routeMode = !routeMode;
    notifyListeners();
  }

  void toggleThemis() {
    showThemis = !showThemis;
    notifyListeners();
  }

  void toggleSlope() {
    showSlope = !showSlope;
    notifyListeners();
  }

  void togglePnr() {
    showPnr = !showPnr;
    notifyListeners();
  }

  void toggleArchive() {
    showArchive = !showArchive;
    notifyListeners();
  }

  void setPhoto(int index) {
    photoIndex = index;
    notifyListeners();
  }

  void selectReference(MarsReference ref) {
    focus = focusFromReference(ref);
    notifyListeners();
  }

  void selectStamp(ThemisStamp stamp) {
    focus = focusFromStamp(stamp);
    notifyListeners();
  }

  void handleMapTap(GeoPoint point) {
    if (routeMode) {
      planRouteTo(point, 'TACTICAL WAYPOINT');
      return;
    }
    _focusNearest(point);
  }

  void _focusNearest(GeoPoint point) {
    MarsReference? nearestRef;
    var nearestRefKm = double.infinity;
    for (final ref in data.references) {
      final d = haversineKm(point, ref.point);
      if (d < nearestRefKm) {
        nearestRefKm = d;
        nearestRef = ref;
      }
    }
    ThemisStamp? nearestStamp;
    var nearestStampKm = double.infinity;
    for (final stamp in data.stamps) {
      final d = haversineKm(point, stamp.point);
      if (d < nearestStampKm) {
        nearestStampKm = d;
        nearestStamp = stamp;
      }
    }
    if (nearestRef != null && nearestRefKm < 18) {
      selectReference(nearestRef);
    } else if (nearestStamp != null && nearestStampKm < 14) {
      selectStamp(nearestStamp);
    } else {
      focus = MapFocus(
        id: 'pick-${point.lon}-${point.lat}',
        name: 'TACTICAL SURFACE POINT',
        kind: 'MAP PICK',
        detail:
            'No catalog feature within 14 km. Position is a map estimate; '
            'no thermal context available.',
        lon: point.lon,
        lat: point.lat,
        provenance: Provenance.sim,
      );
      notifyListeners();
    }
  }

  String get backendStatusLabel {
    if (backend == null) return 'NO LIVE BACKEND';
    if (!backendChecked) return 'BACKEND LINK · PROBING';
    return backendOnline ? 'BACKEND LINK · LIVE' : 'BACKEND LINK · OFFLINE';
  }

  String get routeSolverLabel =>
      routeSolvedByBackend ? 'BACKEND A*' : 'LOCAL A*';

  void _planRouteGrid(RouteGrid grid, String name) {
    route = terrain.planRouteOnGrid(grid, name);
    routeSolvedByBackend = false;
    backendExploredNodes = 0;
    final client = backend;
    if (client == null) return;
    final epoch = ++_routeEpoch;
    unawaited(_tryBackendRoute(client, grid, name, epoch));
  }

  Future<void> _tryBackendRoute(
    AresBackend client,
    RouteGrid grid,
    String name,
    int epoch,
  ) async {
    final result = await client.planRoute(grid);
    if (_disposed || epoch != _routeEpoch) return;
    if (result == null) {
      if (backendOnline || !backendChecked) {
        backendOnline = false;
        backendChecked = true;
        notifyListeners();
      }
      return;
    }
    backendOnline = true;
    backendChecked = true;
    if (result.hasRoute) {
      route = terrain.planRouteFromCells(grid, result.cells, name);
      routeSolvedByBackend = true;
      backendExploredNodes = result.exploredNodes;
    }
    notifyListeners();
  }

  Future<void> _probeBackend() async {
    final client = backend;
    if (client == null) return;
    final online = await client.ping();
    if (_disposed) return;
    final changed = online != backendOnline || !backendChecked;
    backendOnline = online;
    backendChecked = true;
    if (changed) notifyListeners();
  }

  void planRouteTo(GeoPoint target, String name) {
    _planRouteGrid(terrain.buildRouteGrid(current, target), name);
    routeMode = false;
    focus = MapFocus(
      id: 'target-${target.lon}',
      name: name,
      kind: 'TRAVERSE TARGET',
      detail:
          'Waypoint from map pick. Route is a derived A* traverse over a procedural '
          'Gale DEM; validate in the field.',
      lon: target.lon,
      lat: target.lat,
      provenance: Provenance.derived,
    );
    notifyListeners();
  }

  void replanToFocus() {
    _planRouteGrid(terrain.buildRouteGrid(current, focus.point), focus.name);
    notifyListeners();
  }

  void planToVeraRubin() {
    _planRouteGrid(
      terrain.buildRouteGrid(current, data.veraRubin.point),
      'VERA RUBIN RIDGE',
    );
    focus = focusFromReference(data.veraRubin);
    routeMode = false;
    notifyListeners();
  }

  void acknowledge(String id) {
    acknowledged.add(id);
    notifyListeners();
  }

  void acknowledgeAll() {
    acknowledged.addAll(alerts.map((a) => a.id));
    notifyListeners();
  }

  SampleRecord logSample() {
    final clock = marsClock;
    final record = SampleRecord(
      id: 'ARES-${(samples.length + 1).toString().padLeft(3, '0')}',
      label:
          'ARES-${(samples.length + 1).toString().padLeft(3, '0')} · SURFACE SAMPLE',
      context:
          'Operator-entered field record at ${formatCoordinate(current)} · '
          'no lab analysis in demo.',
      point: current,
      mtc: clock.mtc,
      provenance: Provenance.sim,
      loggedAt: now,
    );
    samples = [record, ...samples];
    notifyListeners();
    return record;
  }

  @override
  void dispose() {
    _disposed = true;
    _routeEpoch++;
    _healthTimer?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
