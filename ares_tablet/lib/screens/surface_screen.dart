import 'dart:math' as math;

import 'package:flutter/material.dart' hide DataRow;

import '../models/ares_models.dart';
import '../state/ares_scope.dart';
import '../theme/ares_theme.dart';
import '../util/astro.dart';
import '../widgets/hud.dart';

class SurfaceScreen extends StatefulWidget {
  const SurfaceScreen({super.key});

  @override
  State<SurfaceScreen> createState() => _SurfaceScreenState();
}

class _SurfaceScreenState extends State<SurfaceScreen> {
  double _offsetX = 0;
  double _offsetY = 0;
  double _viewportWidth = 1;
  double _renderWidth = 1;

  double get _maxOffsetX => math.max(0, _renderWidth - _viewportWidth);

  double get _panFraction =>
      _maxOffsetX <= 0 ? 0.5 : (_offsetX / _maxOffsetX).clamp(0.0, 1.0);

  double get _heading {
    final state = AresScope.read(context);
    final base = 150 + state.photoIndex * 53;
    return (base + (_panFraction - 0.5) * 110 + 360) % 360;
  }

  double get _pitch => -_offsetY * 0.16;

  void _selectPhoto(int index) {
    final state = AresScope.read(context);
    state.setPhoto(index);
    setState(() {
      _offsetX = 0;
      _offsetY = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final photo = state.photo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'SURFACE IMAGERY',
                      style: AresType.displayStyle(size: 25, spacing: 0.8),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Panorama archive · drag to look around',
                      style: AresType.label(
                        size: 9.5,
                        color: AresColors.muted,
                        spacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                const ProvenancePill(Provenance.archive),
                const SizedBox(width: 5),
                const ProvenancePill(Provenance.sim),
                const Spacer(),
                Text(
                  'NASA image library · ${state.data.photos.length} frames',
                  style: AresType.monoStyle(size: 9.5, color: AresColors.dim),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: _PanoramaViewer(
                          heading: _heading,
                          pitch: _pitch,
                          offsetX: _offsetX,
                          offsetY: _offsetY,
                          onLayout: (viewportWidth, renderWidth) {
                            _viewportWidth = viewportWidth;
                            _renderWidth = renderWidth;
                            if (_offsetX > _maxOffsetX) {
                              _offsetX = _maxOffsetX;
                            }
                          },
                          onPan: (delta) {
                            setState(() {
                              _offsetX = (_offsetX - delta.dx).clamp(
                                0.0,
                                _maxOffsetX,
                              );
                              _offsetY = (_offsetY - delta.dy).clamp(
                                -35.0,
                                35.0,
                              );
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      HudPanel(
                        title: 'PANORAMA ARCHIVE',
                        code:
                            '${state.photoIndex + 1} / '
                            '${state.data.photos.length}',
                        dense: true,
                        trailing: const ProvenancePill(
                          Provenance.archive,
                          compact: true,
                        ),
                        child: SizedBox(
                          height: 56,
                          child: Row(
                            children: [
                              for (
                                var i = 0;
                                i < state.data.photos.length;
                                i++
                              ) ...[
                                if (i > 0) const SizedBox(width: 6),
                                Expanded(
                                  child: _FilmFrame(
                                    photo: state.data.photos[i],
                                    selected: i == state.photoIndex,
                                    onTap: () => _selectPhoto(i),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 300,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _MetadataPanel(photo: photo),
                        const SizedBox(height: 10),
                        HudPanel(
                          title: 'CAMERA VIEW',
                          trailing: const ProvenancePill(
                            Provenance.sim,
                            compact: true,
                          ),
                          child: Column(
                            children: [
                              DataRow(
                                label: 'Heading',
                                value:
                                    '${_heading.round().toString().padLeft(3, '0')}° ${compass16(_heading)}',
                              ),
                              DataRow(
                                label: 'Pitch',
                                value: '${_pitch.toStringAsFixed(1)}°',
                              ),
                              DataRow(
                                label: 'Field of view',
                                value: '110° horizontal',
                              ),
                              DataRow(
                                label: 'Pan position',
                                value: '${(_panFraction * 100).round()}%',
                              ),
                              const SectionDivider(),
                              Text(
                                'The compass tape and pitch scale are simulated '
                                'overlays, not camera instrument data.',
                                style: AresType.bodyMuted.copyWith(
                                  fontSize: 10,
                                  height: 1.35,
                                  color: AresColors.dim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanoramaViewer extends StatelessWidget {
  const _PanoramaViewer({
    required this.heading,
    required this.pitch,
    required this.offsetX,
    required this.offsetY,
    required this.onLayout,
    required this.onPan,
  });

  final double heading;
  final double pitch;
  final double offsetX;
  final double offsetY;
  final void Function(double viewportWidth, double renderWidth) onLayout;
  final ValueChanged<Offset> onPan;

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final photo = state.photo;
    return Container(
      decoration: BoxDecoration(
        color: AresColors.bg1,
        border: Border.all(color: AresColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final viewportWidth = constraints.maxWidth;
            var renderHeight = height;
            var renderWidth = renderHeight * photo.aspect;
            if (renderWidth < viewportWidth) {
              renderWidth = viewportWidth;
              renderHeight = renderWidth / photo.aspect;
            }
            onLayout(viewportWidth, renderWidth);
            return GestureDetector(
              onPanUpdate: (details) => onPan(details.delta),
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: -offsetX,
                      top: -offsetY - (renderHeight - height) / 2,
                      width: renderWidth,
                      height: renderHeight,
                      child: Image.asset(
                        photo.asset,
                        fit: BoxFit.fill,
                        cacheWidth: 6000,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 64,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.72),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 12,
                      child: Row(
                        children: [
                          const StatusDot(color: AresColors.amber, size: 6),
                          const SizedBox(width: 6),
                          Text(
                            'Surface camera · archive',
                            style: AresType.label(
                              size: 10,
                              color: AresColors.text,
                              spacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 12,
                      child: Row(
                        children: const [
                          ProvenancePill(Provenance.archive, compact: true),
                          SizedBox(width: 4),
                          ProvenancePill(Provenance.sim, compact: true),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 32,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: SizedBox(
                          width: 430,
                          height: 38,
                          child: CustomPaint(
                            painter: _CompassTapePainter(heading: heading),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 92,
                      bottom: 96,
                      child: SizedBox(
                        width: 38,
                        child: CustomPaint(
                          painter: _PitchTapePainter(pitch: pitch),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _ReticlePainter()),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 10,
                      child: _GeoTag(photo: photo),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AresColors.bg0.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Heading ${heading.round().toString().padLeft(3, '0')}° · '
                              'pitch ${pitch.toStringAsFixed(1)}° · FOV 110°',
                              style: AresType.monoStyle(
                                size: 9.5,
                                color: AresColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Drag to pan · simulated overlay',
                              style: AresType.label(
                                size: 9.5,
                                color: AresColors.muted,
                                spacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      top: 34,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AresColors.bg0.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'NASA ${photo.nasaId}',
                              style: AresType.monoStyle(
                                size: 9.5,
                                color: AresColors.text,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 1,
                              height: 10,
                              color: AresColors.line,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Released ${photo.released}',
                              style: AresType.monoStyle(
                                size: 9.5,
                                color: AresColors.muted,
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
          },
        ),
      ),
    );
  }
}

class _GeoTag extends StatelessWidget {
  const _GeoTag({required this.photo});

  final SurfacePhoto photo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: AresColors.bg0.withValues(alpha: 0.82),
        border: Border.all(color: AresColors.line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.place_outlined,
                size: 13,
                color: AresColors.cyan,
              ),
              const SizedBox(width: 5),
              Text(
                photo.location,
                style: AresType.label(
                  size: 9.5,
                  color: AresColors.text,
                  spacing: 0.3,
                ),
              ),
              const SizedBox(width: 6),
              const ProvenancePill(Provenance.sim, compact: true),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            formatCoordinate(photo.point),
            style: AresType.monoStyle(size: 10, color: AresColors.cyan),
          ),
        ],
      ),
    );
  }
}

class _CompassTapePainter extends CustomPainter {
  _CompassTapePainter({required this.heading});

  final double heading;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(1)),
      Paint()..color = AresColors.bg0.withValues(alpha: 0.62),
    );
    final center = size.width / 2;
    final tick = Paint()
      ..color = AresColors.text.withValues(alpha: 0.5)
      ..strokeWidth = 0.8;
    final start = ((heading - 30) / 5).floor() * 5;
    final end = ((heading + 30) / 5).ceil() * 5;
    for (var degrees = start; degrees <= end; degrees += 5) {
      final x = center + (degrees - heading) / 60 * size.width;
      if (x < 0 || x > size.width) continue;
      final normalized = ((degrees % 360) + 360) % 360;
      final isMajor = normalized % 30 == 0;
      canvas.drawLine(
        Offset(x, size.height - (isMajor ? 12 : 6)),
        Offset(x, size.height),
        tick,
      );
      if (isMajor) {
        final label = switch (normalized) {
          0 => 'N',
          90 => 'E',
          180 => 'S',
          270 => 'W',
          _ => normalized.toString().padLeft(3, '0'),
        };
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: AresType.label(
              size: 9,
              color: normalized % 90 == 0 ? AresColors.cyan : AresColors.muted,
              spacing: 0.3,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(x - painter.width / 2, size.height - 26));
      }
    }
    final centerPaint = Paint()
      ..color = AresColors.amber
      ..strokeWidth = 1.4;
    canvas.drawLine(
      Offset(center, size.height - 12),
      Offset(center, size.height),
      centerPaint,
    );
    final diamond = Path()
      ..moveTo(center, size.height - 13)
      ..lineTo(center + 3, size.height - 17)
      ..lineTo(center, size.height - 21)
      ..lineTo(center - 3, size.height - 17)
      ..close();
    canvas.drawPath(diamond, Paint()..color = AresColors.amber);
  }

  @override
  bool shouldRepaint(covariant _CompassTapePainter oldDelegate) =>
      oldDelegate.heading != heading;
}

class _PitchTapePainter extends CustomPainter {
  _PitchTapePainter({required this.pitch});

  final double pitch;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AresColors.bg0.withValues(alpha: 0.5),
    );
    final center = size.height / 2;
    final paint = Paint()
      ..color = AresColors.text.withValues(alpha: 0.45)
      ..strokeWidth = 0.8;
    for (var deg = -12; deg <= 12; deg += 2) {
      final y = center - (deg - pitch) / 24 * size.height;
      final major = deg % 6 == 0;
      canvas.drawLine(
        Offset(size.width - (major ? 10 : 5), y),
        Offset(size.width, y),
        paint,
      );
    }
    final markerPaint = Paint()
      ..color = AresColors.amber
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(0, center), Offset(size.width, center), markerPaint);
    final text = TextPainter(
      text: TextSpan(
        text: '${pitch.toStringAsFixed(1)}°',
        style: AresType.monoStyle(size: 9, color: AresColors.amber),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(2, center - 14));
  }

  @override
  bool shouldRepaint(covariant _PitchTapePainter oldDelegate) =>
      oldDelegate.pitch != pitch;
}

class _ReticlePainter extends CustomPainter {
  const _ReticlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = AresColors.cyan.withValues(alpha: 0.5)
      ..strokeWidth = 0.9;
    canvas.drawCircle(center, 16, paint);
    canvas.drawLine(
      center + const Offset(-26, 0),
      center + const Offset(-9, 0),
      paint,
    );
    canvas.drawLine(
      center + const Offset(9, 0),
      center + const Offset(26, 0),
      paint,
    );
    canvas.drawLine(
      center + const Offset(0, -26),
      center + const Offset(0, -9),
      paint,
    );
    canvas.drawLine(
      center + const Offset(0, 9),
      center + const Offset(0, 26),
      paint,
    );
    canvas.drawCircle(
      center,
      1.6,
      Paint()..color = AresColors.cyan.withValues(alpha: 0.85),
    );
    final horizon = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 0.7;
    canvas.drawLine(
      Offset(0, size.height * 0.54),
      Offset(size.width, size.height * 0.54),
      horizon,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FilmFrame extends StatelessWidget {
  const _FilmFrame({
    required this.photo,
    required this.selected,
    required this.onTap,
  });

  final SurfacePhoto photo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AresColors.amber : AresColors.line;
    return Material(
      color: AresColors.bg0,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.8) : color,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 78,
                height: 54,
                child: Image.asset(
                  photo.asset,
                  fit: BoxFit.cover,
                  cacheWidth: 240,
                  errorBuilder: (context, error, stack) => ColoredBox(
                    color: AresColors.bg2,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 14,
                      color: AresColors.dim,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        photo.nasaId,
                        style: AresType.monoStyle(
                          size: 9.5,
                          color: selected ? AresColors.amber : AresColors.cyan,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        photo.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AresType.bodyMuted.copyWith(
                          fontSize: 9.5,
                          height: 1.2,
                          color: selected ? AresColors.text : AresColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataPanel extends StatelessWidget {
  const _MetadataPanel({required this.photo});

  final SurfacePhoto photo;

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return HudPanel(
      title: 'IMAGE METADATA',
      code: photo.nasaId,
      trailing: const ProvenancePill(Provenance.archive, compact: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            photo.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AresType.displayStyle(size: 17, spacing: 0.2),
          ),
          const SizedBox(height: 5),
          Text(
            photo.location,
            style: AresType.label(
              size: 9.5,
              color: AresColors.cyan,
              spacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          DataRow(label: 'NASA ID', value: photo.nasaId),
          DataRow(label: 'Credit', value: photo.credit),
          DataRow(label: 'Released', value: photo.released),
          DataRow(
            label: 'Geo-tag',
            value: formatCoordinate(photo.point),
            provenance: Provenance.sim,
          ),
          const SizedBox(height: 7),
          Text(
            photo.note,
            style: AresType.bodyMuted.copyWith(fontSize: 11, height: 1.4),
          ),
          const SectionDivider(),
          Row(
            children: [
              Expanded(
                child: AresButton(
                  label: 'Tag waypoint',
                  icon: Icons.place_outlined,
                  primary: true,
                  expanded: true,
                  onTap: () {
                    state.planRouteTo(photo.point, photo.location);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Waypoint tagged at ${photo.nasaId} · '
                          'route ${state.route!.distanceKm.toStringAsFixed(2)} km',
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              AresButton(
                label: 'Map',
                icon: Icons.map_outlined,
                onTap: () => state.setScreen(1),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'The location tag is approximate (simulated). The photo is real '
            'NASA archive imagery — not for navigation.',
            style: AresType.bodyMuted.copyWith(
              fontSize: 10,
              height: 1.35,
              color: AresColors.dim,
            ),
          ),
        ],
      ),
    );
  }
}
