import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/ares_models.dart';
import '../state/ares_scope.dart';
import '../theme/ares_theme.dart';

class MarsMapLayer {
  const MarsMapLayer({
    required this.title,
    required this.shortTitle,
    required this.asset,
    required this.note,
  });

  final String title;
  final String shortTitle;
  final String asset;
  final String note;
}

const marsMapLayers = [
  MarsMapLayer(
    title: 'THEMIS DAY INFRARED',
    shortTitle: 'THEMIS DAY IR',
    asset: 'assets/images/map/themis_day_ir.png',
    note: 'THEMIS daytime infrared radiance. Thermal stamps are drawn on top.',
  ),
  MarsMapLayer(
    title: 'CTX OPTICAL MOSAIC',
    shortTitle: 'CTX MOSAIC',
    asset: 'assets/images/map/ctx_optical_gale.png',
    note: 'Context Camera optical mosaic aligned to the Gale bounding box.',
  ),
  MarsMapLayer(
    title: 'MOLA + THEMIS FALSE COLOR',
    shortTitle: 'MOLA COLOR',
    asset: 'assets/images/map/mola_themis_blend.png',
    note:
        'False-color MOLA elevation blended with THEMIS; green/blue encode '
        'elevation, not surface color.',
  ),
];

const _marsTint = ColorFilter.matrix(<double>[
  1.10,
  0.05,
  0.00,
  0,
  8,
  0.82,
  0.05,
  0.00,
  0,
  0,
  0.62,
  0.03,
  0.00,
  0,
  -8,
  0,
  0,
  0,
  1,
  0,
]);

class MarsMap extends StatelessWidget {
  const MarsMap({
    super.key,
    this.rightInset = 0,
    this.compact = false,
    this.cover = false,
    this.interactive = true,
    this.onTapGeo,
    this.controller,
  });

  final double rightInset;
  final bool compact;
  final bool cover;
  final bool interactive;
  final ValueChanged<GeoPoint>? onTapGeo;
  final TransformationController? controller;

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final layer = marsMapLayers[state.mapLayer];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final availableWidth = math.max(160.0, width - rightInset);
        final side = cover
            ? math.max(availableWidth, height)
            : math.min(availableWidth, height);
        final left = cover ? (width - side) / 2 : (availableWidth - side) / 2;
        final top = (height - side) / 2;
        final imageRect = Rect.fromLTWH(left, top, side, side);

        final stack = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: interactive && onTapGeo != null
              ? (details) {
                  if (!imageRect.contains(details.localPosition)) return;
                  onTapGeo!(
                    _projectInverse(
                      details.localPosition,
                      imageRect,
                      state.bounds,
                    ),
                  );
                }
              : null,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const CustomPaint(painter: _MapBackdropPainter()),
                Positioned.fromRect(
                  rect: imageRect,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: ColorFiltered(
                      key: ValueKey(layer.asset),
                      colorFilter: _marsTint,
                      child: Image.asset(
                        layer.asset,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
                CustomPaint(
                  size: Size(width, height),
                  painter: _MarsOverlayPainter(
                    imageRect: imageRect,
                    bounds: state.bounds,
                    stamps: state.stamps,
                    references: state.references,
                    route: state.route,
                    archiveTrail: state.archiveTrail,
                    current: state.current,
                    pnrAnchor: state.data.landingSite.point,
                    pnrRadiusKm: AresStateConstants.pnrRadiusKm,
                    focus: state.focus,
                    showThemis: state.showThemis,
                    showSlope: state.showSlope,
                    showPnr: state.showPnr,
                    showArchive: state.showArchive,
                    slopeGrid: state.terrain.slopeGrid,
                    compact: compact,
                    dashPhase: (state.now.millisecondsSinceEpoch / 55.0) % 22,
                  ),
                ),
              ],
            ),
          ),
        );

        if (!interactive) return stack;
        return InteractiveViewer(
          transformationController: controller,
          minScale: 1,
          maxScale: 4.5,
          boundaryMargin: const EdgeInsets.all(160),
          clipBehavior: Clip.hardEdge,
          child: stack,
        );
      },
    );
  }
}

abstract final class AresStateConstants {
  static const pnrRadiusKm = 5.0;
}

GeoPoint _projectInverse(Offset local, Rect rect, MapBounds bounds) {
  final nx = (local.dx - rect.left) / rect.width;
  final ny = (local.dy - rect.top) / rect.height;
  return GeoPoint(
    bounds.minLon + nx * bounds.widthDeg,
    bounds.maxLat - ny * bounds.heightDeg,
  );
}

class _Projector {
  _Projector(this.rect, this.bounds);

  final Rect rect;
  final MapBounds bounds;

  Offset call(GeoPoint point) => Offset(
    rect.left + (point.lon - bounds.minLon) / bounds.widthDeg * rect.width,
    rect.top + (bounds.maxLat - point.lat) / bounds.heightDeg * rect.height,
  );
}

class _MapBackdropPainter extends CustomPainter {
  const _MapBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF091117), Color(0xFF05080B)],
        ).createShader(rect),
    );
    final paint = Paint()
      ..color = AresColors.cyan.withValues(alpha: 0.035)
      ..strokeWidth = 0.7;
    for (var x = 0.0; x < size.width; x += 36) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    canvas.drawCircle(
      Offset(size.width * 0.42, size.height * 0.5),
      size.shortestSide * 0.55,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                AresColors.cyan.withValues(alpha: 0.03),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(
                center: Offset(size.width * 0.42, size.height * 0.5),
                radius: size.shortestSide * 0.55,
              ),
            ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MarsOverlayPainter extends CustomPainter {
  _MarsOverlayPainter({
    required this.imageRect,
    required this.bounds,
    required this.stamps,
    required this.references,
    required this.route,
    required this.archiveTrail,
    required this.current,
    required this.pnrAnchor,
    required this.pnrRadiusKm,
    required this.focus,
    required this.showThemis,
    required this.showSlope,
    required this.showPnr,
    required this.showArchive,
    required this.slopeGrid,
    required this.compact,
    required this.dashPhase,
  });

  final Rect imageRect;
  final MapBounds bounds;
  final List<ThemisStamp> stamps;
  final List<MarsReference> references;
  final TraversePlan? route;
  final List<GeoPoint> archiveTrail;
  final GeoPoint current;
  final GeoPoint pnrAnchor;
  final double pnrRadiusKm;
  final MapFocus focus;
  final bool showThemis;
  final bool showSlope;
  final bool showPnr;
  final bool showArchive;
  final List<List<double>> slopeGrid;
  final bool compact;
  final double dashPhase;

  @override
  void paint(Canvas canvas, Size size) {
    final project = _Projector(imageRect, bounds);

    if (showSlope) _paintSlope(canvas, project);
    _paintGraticule(canvas, project);
    if (showPnr) _paintPnr(canvas, project);
    if (showThemis) _paintStamps(canvas, project);
    if (showArchive) _paintArchive(canvas, project);
    if (route != null) _paintRoute(canvas, project);
    _paintReferences(canvas, project);
    _paintFocus(canvas, project);
    _paintRover(canvas, project);
    if (!compact) {
      _paintCompass(canvas, project);
      _paintScaleBar(canvas);
    }
  }

  void _paintSlope(Canvas canvas, _Projector project) {
    final rows = slopeGrid.length;
    final cols = slopeGrid.first.length;
    final cellW = imageRect.width / cols;
    final cellH = imageRect.height / rows;
    canvas.save();
    canvas.clipRect(imageRect);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final slope = slopeGrid[y][x];
        if (slope < 8) continue;
        final norm = ((slope - 8) / 22).clamp(0.0, 1.0);
        final color = norm > 0.7
            ? AresColors.red
            : Color.lerp(AresColors.green, AresColors.amber, norm)!;
        canvas.drawRect(
          Rect.fromLTWH(
            imageRect.left + x * cellW,
            imageRect.top + y * cellH,
            cellW + 0.5,
            cellH + 0.5,
          ),
          Paint()..color = color.withValues(alpha: 0.10 + norm * 0.26),
        );
      }
    }
    canvas.restore();
  }

  void _paintGraticule(Canvas canvas, _Projector project) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: compact ? 0.035 : 0.06)
      ..strokeWidth = 0.6;
    for (
      var lon = (bounds.minLon * 2).ceil() / 2;
      lon <= bounds.maxLon;
      lon += 0.5
    ) {
      final start = project(GeoPoint(lon, bounds.minLat));
      final end = project(GeoPoint(lon, bounds.maxLat));
      canvas.drawLine(start, end, paint);
      if (!compact) {
        _text(
          canvas,
          '${lon.toStringAsFixed(1)}°E',
          Offset(start.dx + 3, imageRect.top + 5),
          color: Colors.white.withValues(alpha: 0.5),
          size: 9,
        );
      }
    }
    for (
      var lat = (bounds.minLat * 2).ceil() / 2;
      lat <= bounds.maxLat;
      lat += 0.5
    ) {
      final start = project(GeoPoint(bounds.minLon, lat));
      final end = project(GeoPoint(bounds.maxLon, lat));
      canvas.drawLine(start, end, paint);
      if (!compact) {
        _text(
          canvas,
          '${lat.toStringAsFixed(1)}°',
          Offset(imageRect.left + 5, start.dy + 1),
          color: Colors.white.withValues(alpha: 0.5),
          size: 9,
        );
      }
    }
    canvas.drawRect(
      imageRect,
      Paint()
        ..color = AresColors.lineHot.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _paintPnr(Canvas canvas, _Projector project) {
    final points = <Offset>[];
    const segments = 96;
    final anchor = project(pnrAnchor);
    final kmPerDegLat = 59.16;
    final radiusDegLat = pnrRadiusKm / kmPerDegLat;
    final cosLat = math
        .cos(pnrAnchor.lat * math.pi / 180)
        .abs()
        .clamp(0.1, 1.0);
    final radiusDegLon = radiusDegLat / cosLat;
    for (var i = 0; i <= segments; i++) {
      final angle = i / segments * math.pi * 2;
      points.add(
        project(
          GeoPoint(
            pnrAnchor.lon + math.cos(angle) * radiusDegLon,
            pnrAnchor.lat + math.sin(angle) * radiusDegLat,
          ),
        ),
      );
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.save();
    canvas.clipRect(imageRect);
    _dashedPath(
      canvas,
      path,
      Paint()
        ..color = AresColors.amber.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
      dash: 5,
      gap: 5,
      phase: dashPhase,
    );
    canvas.drawCircle(
      anchor,
      3,
      Paint()
        ..color = AresColors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawCircle(anchor, 1, Paint()..color = AresColors.amber);
    _label(
      canvas,
      'Return limit ${pnrRadiusKm.toStringAsFixed(1)} km',
      anchor + const Offset(-8, -24),
      color: AresColors.amber,
      alignEnd: true,
    );
    canvas.restore();
  }

  void _paintStamps(Canvas canvas, _Projector project) {
    canvas.save();
    canvas.clipRect(imageRect);
    for (final stamp in stamps) {
      final offset = project(stamp.point);
      final color = _thermalColor(stamp.tempC);
      final selected = focus.stamp?.fileId == stamp.fileId;
      canvas.drawCircle(
        offset,
        selected ? 4.2 : (compact ? 1.0 : 1.45),
        Paint()..color = color.withValues(alpha: selected ? 1 : 0.72),
      );
      if (selected) {
        canvas.drawCircle(
          offset,
          7,
          Paint()
            ..color = AresColors.amber
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }
    canvas.restore();
  }

  Color _thermalColor(double? tempC) {
    if (tempC == null) return AresColors.dim;
    final t = ((tempC + 110) / 120).clamp(0.0, 1.0);
    if (t < 0.55) {
      return Color.lerp(const Color(0xFF2F6BFF), AresColors.cyan, t / 0.55)!;
    }
    return Color.lerp(AresColors.cyan, AresColors.amber, (t - 0.55) / 0.45)!;
  }

  void _paintArchive(Canvas canvas, _Projector project) {
    if (archiveTrail.length < 2) return;
    final path = Path();
    final first = project(archiveTrail.first);
    path.moveTo(first.dx, first.dy);
    for (final point in archiveTrail.skip(1)) {
      final offset = project(point);
      path.lineTo(offset.dx, offset.dy);
    }
    canvas.save();
    canvas.clipRect(imageRect);
    _dashedPath(
      canvas,
      path,
      Paint()
        ..color = AresColors.amber.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 0.9 : 1.2,
      dash: 3,
      gap: 4,
      phase: dashPhase,
    );
    canvas.restore();
  }

  void _paintRoute(Canvas canvas, _Projector project) {
    final plan = route!;
    if (plan.points.length < 2) return;
    final path = Path();
    final first = project(plan.points.first);
    path.moveTo(first.dx, first.dy);
    for (final point in plan.points.skip(1)) {
      final offset = project(point);
      path.lineTo(offset.dx, offset.dy);
    }

    canvas.save();
    canvas.clipRect(imageRect);
    canvas.drawPath(
      path,
      Paint()
        ..color = AresColors.bg0.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 3.5 : 5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AresColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 1.5 : 2.4
        ..strokeJoin = StrokeJoin.round,
    );

    final arrowIndices = [
      (plan.points.length * 0.25).round(),
      (plan.points.length * 0.55).round(),
      (plan.points.length * 0.82).round(),
    ];
    for (final index in arrowIndices) {
      if (index <= 0 || index >= plan.points.length - 1) continue;
      _chevron(
        canvas,
        project(plan.points[index]),
        project(plan.points[index + 1]),
      );
    }

    final target = project(plan.target);
    final diamond = Path()
      ..moveTo(target.dx, target.dy - 6)
      ..lineTo(target.dx + 6, target.dy)
      ..lineTo(target.dx, target.dy + 6)
      ..lineTo(target.dx - 6, target.dy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = AresColors.bg0);
    canvas.drawPath(
      diamond,
      Paint()
        ..color = AresColors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawCircle(target, 1.5, Paint()..color = AresColors.amber);
    canvas.restore();
  }

  void _chevron(Canvas canvas, Offset from, Offset to) {
    final vector = to - from;
    if (vector.distance < 0.1) return;
    final direction = vector / vector.distance;
    final normal = Offset(-direction.dy, direction.dx);
    final tip = from;
    final back = tip - direction * 6;
    final paint = Paint()
      ..color = AresColors.bg0
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final core = Paint()
      ..color = AresColors.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final p in [paint, core]) {
      canvas.drawLine(tip, back + normal * 3.5, p);
      canvas.drawLine(tip, back - normal * 3.5, p);
    }
  }

  void _paintReferences(Canvas canvas, _Projector project) {
    for (var i = 0; i < references.length; i++) {
      final ref = references[i];
      final point = project(ref.point);
      final isFocused = focus.id == ref.id;
      final color = isFocused ? AresColors.amber : AresColors.cyan;
      final diamond = Path()
        ..moveTo(point.dx, point.dy - 5)
        ..lineTo(point.dx + 5, point.dy)
        ..lineTo(point.dx, point.dy + 5)
        ..lineTo(point.dx - 5, point.dy)
        ..close();
      canvas.drawPath(
        diamond,
        Paint()..color = AresColors.bg0.withValues(alpha: 0.85),
      );
      canvas.drawPath(
        diamond,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      canvas.drawCircle(point, 1.2, Paint()..color = color);
      if (!compact || i == 3) {
        final labels = {
          'bradbury_landing': 'Bradbury Landing',
          'vera_rubin_ridge': 'Vera Rubin Ridge',
          'gale_crater_center': 'Gale Crater center',
          'mount_sharp_summit': 'Mount Sharp',
        };
        final label = labels[ref.id] ?? ref.name;
        _label(canvas, label, point + const Offset(7, -6), color: color);
      }
    }
  }

  void _paintFocus(Canvas canvas, _Projector project) {
    if (focus.stamp != null) return;
    final point = project(GeoPoint(focus.lon, focus.lat));
    final isRef = references.any((r) => r.id == focus.id);
    if (isRef) return;
    final paint = Paint()
      ..color = AresColors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const arm = 7.0;
    canvas.drawCircle(point, 8, paint);
    for (final delta in [
      const Offset(-1, -1),
      const Offset(1, -1),
      const Offset(-1, 1),
      const Offset(1, 1),
    ]) {
      canvas.drawLine(
        point + Offset(delta.dx * 10, delta.dy * 10),
        point + Offset(delta.dx * (10 + arm), delta.dy * (10 + arm)),
        paint,
      );
    }
  }

  void _paintRover(Canvas canvas, _Projector project) {
    final point = project(current);
    canvas.drawCircle(
      point,
      10,
      Paint()..color = AresColors.cyan.withValues(alpha: 0.12),
    );
    canvas.drawCircle(
      point,
      7,
      Paint()
        ..color = AresColors.cyan.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(point, 4, Paint()..color = AresColors.bg0);
    canvas.drawCircle(
      point,
      4,
      Paint()
        ..color = AresColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(point, 1.4, Paint()..color = AresColors.cyan);
    if (!compact) {
      _label(
        canvas,
        'Rover',
        point + const Offset(-12, -18),
        color: AresColors.cyan,
        alignEnd: true,
      );
    }
  }

  void _paintCompass(Canvas canvas, _Projector project) {
    final bottom = imageRect.bottom - 20;
    final center = Offset(imageRect.left + 26, bottom - 12);
    final paint = Paint()
      ..color = AresColors.muted.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    canvas.drawCircle(center, 14, paint);
    final arrow = Path()
      ..moveTo(center.dx, center.dy - 11)
      ..lineTo(center.dx + 3.5, center.dy + 3)
      ..lineTo(center.dx, center.dy + 0.5)
      ..lineTo(center.dx - 3.5, center.dy + 3)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()..color = AresColors.cyan.withValues(alpha: 0.85),
    );
    _text(
      canvas,
      'N',
      Offset(center.dx - 3, center.dy + 15),
      color: AresColors.text,
      size: 9,
    );
  }

  void _paintScaleBar(Canvas canvas) {
    final totalKm =
        bounds.widthDeg *
        59.16 *
        math.cos((bounds.minLat + bounds.maxLat) / 2 * math.pi / 180);
    final pxPerKm = imageRect.width / totalKm;
    final candidates = [2.0, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0];
    final desired = 90 / pxPerKm;
    final distanceKm = candidates.firstWhere(
      (value) => value >= desired,
      orElse: () => 100,
    );
    final width = distanceKm * pxPerKm;
    final y = imageRect.bottom - 24;
    final x = imageRect.right - width - 18;
    final paint = Paint()
      ..color = AresColors.text.withValues(alpha: 0.65)
      ..strokeWidth = 1.1;
    canvas.drawLine(Offset(x, y), Offset(x + width, y), paint);
    canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), paint);
    canvas.drawLine(Offset(x + width, y - 3), Offset(x + width, y + 3), paint);
    _text(
      canvas,
      '${distanceKm.toStringAsFixed(0)} km',
      Offset(x + width / 2 - 12, y - 16),
      color: AresColors.text,
      size: 9.5,
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset anchor, {
    required Color color,
    bool alignEnd = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AresType.label(size: 10, color: color, spacing: 0.3),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var x = alignEnd ? anchor.dx - painter.width : anchor.dx;
    var y = anchor.dy;
    if (x + painter.width + 8 > imageRect.right) {
      x = imageRect.right - painter.width - 8;
    }
    x = math.max(imageRect.left + 4, x);
    y = y.clamp(imageRect.top + 4, imageRect.bottom - 18);
    canvas.drawRect(
      Rect.fromLTWH(x - 3, y - 2, painter.width + 6, painter.height + 4),
      Paint()..color = AresColors.bg0.withValues(alpha: 0.72),
    );
    painter.paint(canvas, Offset(x, y));
  }

  void _text(
    Canvas canvas,
    String text,
    Offset anchor, {
    required Color color,
    required double size,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AresType.monoStyle(size: size, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, anchor);
  }

  void _dashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dash,
    required double gap,
    required double phase,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = -phase % (dash + gap);
      while (distance < metric.length) {
        final start = math.max(distance, 0.0);
        final end = math.min(distance + dash, metric.length);
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), paint);
        }
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MarsOverlayPainter oldDelegate) {
    return oldDelegate.route != route ||
        oldDelegate.focus != focus ||
        oldDelegate.showThemis != showThemis ||
        oldDelegate.showSlope != showSlope ||
        oldDelegate.showPnr != showPnr ||
        oldDelegate.showArchive != showArchive ||
        oldDelegate.imageRect != imageRect ||
        oldDelegate.dashPhase != dashPhase;
  }
}
