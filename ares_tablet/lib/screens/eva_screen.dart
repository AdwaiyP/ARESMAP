import 'dart:math' as math;

import 'package:flutter/material.dart' hide DataRow;

import '../models/ares_models.dart';
import '../state/ares_scope.dart';
import '../theme/ares_theme.dart';
import '../util/astro.dart';
import '../util/eva_plan.dart';
import '../util/terrain.dart';
import '../widgets/hud.dart';

class EvaScreen extends StatefulWidget {
  const EvaScreen({super.key});
  @override
  State<EvaScreen> createState() => _EvaScreenState();
}

class _EvaScreenState extends State<EvaScreen> {
  GeoPoint? _start, _goal, _eye;
  EvaPlan? _plan;
  String? _message;
  int _stop = 0;
  bool _walk = false;
  double _heading = 0, _pitch = 0;

  void _pick(GeoPoint point) {
    final state = AresScope.of(context);
    setState(() {
      if (_start == null || _goal != null) {
        _start = point;
        _goal = null;
        _plan = null;
        _message = null;
      } else {
        final distance = haversineKm(_start!, point) * 1000;
        if (distance < 30 || distance > 600) {
          _message = 'Choose a goal 30–600 m from the start.';
          return;
        }
        _goal = point;
        _plan = solveEva(
          state.terrain,
          buildEvaGrid(state.terrain, evaBounds(state.current), _start!, point),
        );
        _message = _plan == null
            ? 'No route below the 25° modeled slope limit. Choose a different start and goal.'
            : null;
      }
    });
  }

  void _example() {
    final state = AresScope.of(context);
    final b = evaBounds(state.current);
    setState(() {
      _start = GeoPoint(
        b.minLon + b.widthDeg * 0.2,
        b.minLat + b.heightDeg * 0.2,
      );
      _goal = null;
    });
    _pick(GeoPoint(b.minLon + b.widthDeg * 0.7, b.minLat + b.heightDeg * 0.7));
  }

  void _moveStop(int index) {
    final stops = _plan!.stops;
    setState(() {
      _stop = index.clamp(0, stops.length - 1);
      _eye = stops[_stop];
      if (_stop < stops.length - 1) {
        _heading = initialBearingDeg(_eye!, stops[_stop + 1]);
      }
      _pitch = 0;
    });
  }

  void _step(double meters) {
    final state = AresScope.of(context);
    final b = evaBounds(state.current);
    final a = _heading * math.pi / 180;
    final lat =
        _eye!.lat +
        meters * math.cos(a) / (marsRadiusKm * 1000 * math.pi / 180);
    final lon =
        _eye!.lon +
        meters *
            math.sin(a) /
            (marsRadiusKm *
                1000 *
                math.pi /
                180 *
                math.cos(_eye!.lat * math.pi / 180));
    if (lon < b.minLon || lon > b.maxLon || lat < b.minLat || lat > b.maxLat) {
      setState(
        () => _message = 'Edge of the 500 m rehearsal window. Turn back or select a route stop.',
      );
      return;
    }
    setState(() {
      _eye = GeoPoint(lon, lat);
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final bounds = evaBounds(state.current);
    return Scaffold(
      backgroundColor: AresColors.bg0,
      appBar: AppBar(
        title: Text(_walk ? 'Visor route rehearsal' : 'Local EVA planner'),
        actions: [
          const Center(child: ProvenancePill(Provenance.model)),
          const SizedBox(width: 16),
          if (_walk)
            TextButton.icon(
              onPressed: () => setState(() => _walk = false),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Back to plan'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _walk
                        ? 'Drag to look · use Walk or the stop controls'
                        : _start == null || _goal != null
                        ? 'Tap a start point, then a goal'
                        : 'Now tap a goal 30–600 m away',
                    style: AresType.displayStyle(size: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Procedural terrain · 500 × 500 m window · 10 m sampling, not DEM resolution',
                    style: AresType.monoStyle(
                      size: 11,
                      color: AresColors.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ClipRect(
                      child: ColoredBox(
                        color: const Color(0xFF100E0C),
                        child: LayoutBuilder(
                          builder: (context, c) => GestureDetector(
                            onTapUp: _walk
                                ? null
                                : (d) => _pick(
                                    GeoPoint(
                                      bounds.minLon +
                                          d.localPosition.dx /
                                              c.maxWidth *
                                              bounds.widthDeg,
                                      bounds.maxLat -
                                          d.localPosition.dy /
                                              c.maxHeight *
                                              bounds.heightDeg,
                                    ),
                                  ),
                            onPanUpdate: !_walk
                                ? null
                                : (d) => setState(() {
                                    _heading =
                                        (_heading + d.delta.dx * 0.3 + 360) %
                                        360;
                                    _pitch = (_pitch + d.delta.dy * 0.2).clamp(
                                      -30,
                                      30,
                                    );
                                  }),
                            child: CustomPaint(
                              size: c.biggest,
                              painter: _walk
                                  ? _VisorPainter(
                                      terrain: state.terrain,
                                      eye: _eye!,
                                      heading: _heading,
                                      pitch: _pitch,
                                      stops: _plan!.stops,
                                      activeStop: _stop,
                                    )
                                  : _EvaMapPainter(
                                      terrain: state.terrain,
                                      bounds: bounds,
                                      start: _start,
                                      goal: _goal,
                                      plan: _plan,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _message!,
                        style: AresType.monoStyle(
                          size: 12,
                          color: AresColors.amber,
                        ),
                      ),
                    ),
                  if (_walk)
                    Row(
                      children: [
                        Expanded(
                          child: AresButton(
                            label: 'Previous stop',
                            icon: Icons.skip_previous,
                            onTap: _stop > 0
                                ? () => _moveStop(_stop - 1)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AresButton(
                            label: 'Turn left',
                            icon: Icons.rotate_left,
                            onTap: () => setState(
                              () => _heading = (_heading - 15 + 360) % 360,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AresButton(
                            label: 'Walk 10 m',
                            icon: Icons.directions_walk,
                            onTap: () => _step(10),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AresButton(
                            label: 'Turn right',
                            icon: Icons.rotate_right,
                            onTap: () => setState(
                              () => _heading = (_heading + 15) % 360,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AresButton(
                            label: 'Next stop',
                            icon: Icons.skip_next,
                            onTap: _stop < _plan!.stops.length - 1
                                ? () => _moveStop(_stop + 1)
                                : null,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        AresButton(
                          label: 'Try a 350 m route',
                          icon: Icons.alt_route,
                          onTap: _example,
                        ),
                        const SizedBox(width: 12),
                        AresButton(
                          label: 'Clear plan',
                          icon: Icons.restart_alt,
                          onTap: () => setState(() {
                            _start = null;
                            _goal = null;
                            _plan = null;
                            _message = null;
                          }),
                        ),
                        const Spacer(),
                        Text(
                          'Amber ≥15° · red >25°',
                          style: AresType.monoStyle(
                            size: 11,
                            color: AresColors.amber,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: 290,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _walk ? 'Visor readout' : 'Route assessment',
                      style: AresType.displayStyle(size: 25),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Experimental — not safety clearance',
                      style: AresType.monoStyle(
                        size: 12,
                        color: AresColors.amber,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_plan != null) ...[
                      DataRow(
                        label: 'Distance',
                        value: '${_plan!.distanceM.round()} m',
                      ),
                      DataRow(
                        label: 'Walk at 1.2 m/s',
                        value: '${_plan!.walkMinutes.toStringAsFixed(1)} min',
                      ),
                      DataRow(
                        label: 'Maximum segment slope',
                        value: '${_plan!.maxSlope.toStringAsFixed(1)}°',
                      ),
                      DataRow(
                        label: 'Segments ≥15°',
                        value: '${_plan!.cautionSegments}',
                      ),
                      DataRow(
                        label: 'Visor stops',
                        value: '${_plan!.stops.length}',
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Oxygen budget · simulated',
                        style: AresType.displayStyle(size: 20),
                      ),
                      const SizedBox(height: 8),
                      const DataRow(label: 'Available', value: '252 min'),
                      DataRow(
                        label: 'Return + 30 min reserve',
                        value:
                            '${_plan!.roundTripMinutes.toStringAsFixed(1)} min',
                      ),
                      DataRow(
                        label: 'Budget margin',
                        value:
                            '${_plan!.oxygenMarginMinutes.toStringAsFixed(1)} min',
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Assumes the same path back, constant walking speed and 82% O₂. Does not model fatigue, leaks or terrain uncertainty.',
                        style: AresType.bodyMuted.copyWith(
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (!_walk)
                        AresButton(
                          label: 'Walk route in visor',
                          icon: Icons.view_in_ar,
                          expanded: true,
                          onTap: () {
                            _moveStop(0);
                            setState(() => _walk = true);
                          },
                        ),
                    ] else
                      Text(
                        'The route avoids segments above 25° in the model. No route is shown if A* cannot find a path. Pick two points or try the example.',
                        style: AresType.bodyMuted.copyWith(
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    if (_walk) ...[
                      const SizedBox(height: 16),
                      DataRow(
                        label: 'Route stop',
                        value: '${_stop + 1} / ${_plan!.stops.length}',
                      ),
                      DataRow(
                        label: 'Heading',
                        value:
                            '${_heading.round().toString().padLeft(3, '0')}°',
                      ),
                      DataRow(
                        label: 'Modeled ground slope',
                        value:
                            '${state.terrain.slopeAt(_eye!.lon, _eye!.lat).toStringAsFixed(1)}°',
                      ),
                      DataRow(
                        label: 'Range to start',
                        value:
                            '${(haversineKm(_eye!, _plan!.points.first) * 1000).round()} m',
                      ),
                      const DataRow(
                        label: 'O₂ / battery',
                        value: '82% / 76% SIM',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatCoordinate(_eye!),
                        style: AresType.monoStyle(size: 11),
                      ),
                    ],
                    const SizedBox(height: 22),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      'No survey-grade local DEM or radiation monitor is bundled. The visor is a generated rehearsal, not a NASA panorama or live camera.',
                      style: AresType.bodyMuted.copyWith(
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EvaMapPainter extends CustomPainter {
  _EvaMapPainter({
    required this.terrain,
    required this.bounds,
    required this.start,
    required this.goal,
    required this.plan,
  });
  final TerrainModel terrain;
  final MapBounds bounds;
  final GeoPoint? start, goal;
  final EvaPlan? plan;
  @override
  void paint(Canvas canvas, Size size) {
    const n = 40;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final lon = bounds.minLon + (x + 0.5) / n * bounds.widthDeg,
            lat = bounds.maxLat - (y + 0.5) / n * bounds.heightDeg;
        final slope = terrain.slopeAt(lon, lat);
        final z = terrain.elevationAt(lon, lat);
        final color = slope > 25
            ? AresColors.red
            : slope >= 15
            ? AresColors.amber
            : Color.lerp(
                const Color(0xFF3C3023),
                const Color(0xFF967D56),
                ((z + 4600) / 500).clamp(0, 1),
              )!;
        final rect = Rect.fromLTWH(
          x / n * size.width,
          y / n * size.height,
          size.width / n + 0.5,
          size.height / n + 0.5,
        );
        canvas.drawRect(rect, Paint()..color = color);
        canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.1)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );
      }
    }
    Offset project(GeoPoint p) => Offset(
      (p.lon - bounds.minLon) / bounds.widthDeg * size.width,
      (bounds.maxLat - p.lat) / bounds.heightDeg * size.height,
    );
    if (plan != null) {
      final path = Path();
      for (var i = 0; i < plan!.points.length; i++) {
        final p = project(plan!.points[i]);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AresColors.bg0
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = AresColors.cyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      for (final stop in plan!.stops) {
        canvas.drawCircle(project(stop), 4, Paint()..color = Colors.white);
      }
    }
    for (final entry in [
      (start, 'Start', AresColors.green),
      (goal, 'Goal', AresColors.cyan),
    ]) {
      if (entry.$1 == null) continue;
      final p = project(entry.$1!);
      canvas.drawCircle(p, 7, Paint()..color = entry.$3);
      _paintText(canvas, entry.$2, p + const Offset(10, -20), entry.$3);
    }
    _paintText(canvas, 'N ↑', const Offset(14, 14), Colors.white);
    _paintText(
      canvas,
      '500 m',
      Offset(size.width - 72, size.height - 28),
      Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _EvaMapPainter old) =>
      old.start != start || old.goal != goal || old.plan != plan;
}

class _VisorPainter extends CustomPainter {
  _VisorPainter({
    required this.terrain,
    required this.eye,
    required this.heading,
    required this.pitch,
    required this.stops,
    required this.activeStop,
  });
  final TerrainModel terrain;
  final GeoPoint eye;
  final double heading, pitch;
  final List<GeoPoint> stops;
  final int activeStop;
  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * (0.42 + pitch / 100);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5E4638), Color(0xFFB39376)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRect(
      Rect.fromLTRB(0, horizon, size.width, size.height),
      Paint()..color = const Color(0xFF695440),
    );
    final a = heading * math.pi / 180,
        cosA = math.cos(heading * math.pi / 180),
        sinA = math.sin(heading * math.pi / 180);
    final meters = marsRadiusKm * 1000 * math.pi / 180;
    final eyeZ = terrain.elevationAt(eye.lon, eye.lat) + 1.7;
    final focal = size.width * 0.72;
    (Offset, double) project(double east, double north, double height) {
      final depth = north * cosA + east * sinA;
      final right = east * cosA - north * sinA;
      return (
        Offset(
          size.width / 2 + right / math.max(1, depth) * focal,
          horizon - (height - eyeZ) / math.max(1, depth) * focal,
        ),
        depth,
      );
    }

    final faces = <(Path, double, Color)>[];
    for (var row = 0; row < 40; row++) {
      for (var col = -22; col < 22; col++) {
        final corners = <Offset>[];
        var totalDepth = 0.0;
        var shade = 0.0;
        for (final d in [
          (col, row),
          (col + 1, row),
          (col + 1, row + 1),
          (col, row + 1),
        ]) {
          final forward = d.$2 * 12.0 + 2, right = d.$1 * 12.0;
          final east = forward * math.sin(a) + right * math.cos(a),
              north = forward * math.cos(a) - right * math.sin(a);
          final lon =
                  eye.lon + east / (meters * math.cos(eye.lat * math.pi / 180)),
              lat = eye.lat + north / meters;
          final z = terrain.elevationAt(lon, lat), p = project(east, north, z);
          corners.add(p.$1);
          totalDepth += p.$2;
          shade += z;
        }
        final t = ((shade / 4 - eyeZ + 40) / 80).clamp(0.0, 1.0);
        final color = Color.lerp(
          const Color(0xFF493729),
          const Color(0xFFA38965),
          t,
        )!;
        faces.add((Path()..addPolygon(corners, true), totalDepth / 4, color));
      }
    }
    faces.sort((a, b) => b.$2.compareTo(a.$2));
    for (final f in faces) {
      canvas.drawPath(f.$1, Paint()..color = f.$3);
      canvas.drawPath(
        f.$1,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }
    for (var i = 0; i < stops.length; i++) {
      final p = stops[i],
          east = (p.lon - eye.lon) * meters * math.cos(eye.lat * math.pi / 180),
          north = (p.lat - eye.lat) * meters;
      final projected = project(east, north, terrain.elevationAt(p.lon, p.lat));
      if (projected.$2 < 3) continue;
      final base = projected.$1;
      if (base.dx < -40 || base.dx > size.width + 40) continue;
      final height = (focal * 4 / projected.$2).clamp(20.0, 90.0);
      canvas.drawLine(
        base,
        base - Offset(0, height),
        Paint()
          ..color = AresColors.cyan
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        base - Offset(0, height),
        4,
        Paint()..color = AresColors.cyan,
      );
      if (i == math.min(activeStop + 1, stops.length - 1)) {
        _paintText(
          canvas,
          'Next stop ${i + 1} · ${math.sqrt(east * east + north * north).round()} m',
          base + Offset(7, -height - 22),
          AresColors.text,
          bounds: size,
        );
      }
    }
    canvas.drawLine(
      Offset(size.width / 2 - 10, horizon),
      Offset(size.width / 2 + 10, horizon),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(size.width / 2, horizon - 10),
      Offset(size.width / 2, horizon + 10),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1,
    );
    _paintText(
      canvas,
      '${heading.round().toString().padLeft(3, '0')}°  ${compass16(heading)}',
      Offset(size.width / 2 - 42, 16),
      Colors.white,
    );
    _paintText(
      canvas,
      'GENERATED TERRAIN · REHEARSAL',
      Offset(14, size.height - 30),
      Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _VisorPainter old) =>
      old.eye != eye ||
      old.heading != heading ||
      old.pitch != pitch ||
      old.stops != stops ||
      old.activeStop != activeStop;
}

void _paintText(
  Canvas canvas,
  String text,
  Offset at,
  Color color, {
  Size? bounds,
}) {
  final p = TextPainter(
    text: TextSpan(
      text: text,
      style: AresType.monoStyle(size: 12, color: color),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  if (bounds != null) {
    at = Offset(
      at.dx.clamp(8.0, math.max(8.0, bounds.width - p.width - 8)),
      at.dy.clamp(8.0, math.max(8.0, bounds.height - p.height - 8)),
    );
  }
  canvas.drawRect(
    Rect.fromLTWH(at.dx - 4, at.dy - 3, p.width + 8, p.height + 6),
    Paint()..color = AresColors.bg0.withValues(alpha: 0.75),
  );
  p.paint(canvas, at);
}
