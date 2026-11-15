import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/exploration_data.dart';
import '../models/ares_models.dart';
import '../state/ares_scope.dart';
import '../theme/ares_theme.dart';
import '../util/astro.dart';
import '../util/globe_projection.dart';
import '../util/terrain.dart';

class AresTerrainModal extends StatefulWidget {
  const AresTerrainModal({
    super.key,
    required this.initialMode,
    required this.title,
    required this.center,
    required this.routeStops,
    required this.catalogFeatures,
    required this.onClose,
    required this.onOpenStreetView,
    required this.onPlanGlobeEva,
  });

  final String initialMode; // 'globe' or 'terrain'
  final String title;
  final GeoPoint center;
  final List<({GeoPoint point, String label})> routeStops;
  final List<SurveyFeature> catalogFeatures;
  final VoidCallback onClose;
  final void Function(GeoPoint point, String label) onOpenStreetView;
  final void Function(GeoPoint start, GeoPoint goal) onPlanGlobeEva;

  @override
  State<AresTerrainModal> createState() => _AresTerrainModalState();
}

class _AresTerrainModalState extends State<AresTerrainModal> {
  late String _mode; // 'globe' | 'terrain'
  String _globeTex = 'viking_red'; // 'viking_red' | 'mola'
  String _colorMode = 'orbital'; // 'orbital' | 'elevation' | 'slope'
  double _exag = 3.0;
  bool _fullscreen = false;

  // Globe state
  double _globeLon = 137.4417;
  double _globeLat = -4.5895;
  double _globeZoom = 1.05;
  double _gestureStartZoom = 1.05;
  SurveyFeature? _selectedFeature;
  GeoPoint? _inspectedPoint;
  bool _planningGlobeEva = false;
  GeoPoint? _globeEvaStart;
  GeoPoint? _globeEvaGoal;

  // Terrain 3D state
  double _yaw = -0.62;
  double _pitch = 0.64;
  double _terrainZoom = 1.0;
  Offset _panOffset = Offset.zero;

  ui.Image? _vikingImg;
  ui.Image? _molaImg;
  ui.Image? _orbitalImg;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _globeLon = widget.center.lon;
    _globeLat = widget.center.lat;
    _loadImages();
  }

  Future<ui.Image> _decodeAsset(String path) async {
    final bytes = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<void> _loadImages() async {
    try {
      final results = await Future.wait([
        _decodeAsset('assets/images/map/mars_global.jpg'),
        _decodeAsset('assets/images/map/mars_mola.jpg'),
        _decodeAsset('assets/images/map/ctx_optical_gale.png'),
      ]);
      if (!mounted) {
        for (final img in results) {
          img.dispose();
        }
        return;
      }
      setState(() {
        _vikingImg = results[0];
        _molaImg = results[1];
        _orbitalImg = results[2];
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _vikingImg?.dispose();
    _molaImg?.dispose();
    _orbitalImg?.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final key = event.logicalKey;
    setState(() {
      if (_mode == 'globe') {
        if (key == LogicalKeyboardKey.keyW || key == LogicalKeyboardKey.arrowUp) {
          _globeLat = (_globeLat + 4 / _globeZoom).clamp(-85.0, 85.0);
        } else if (key == LogicalKeyboardKey.keyS || key == LogicalKeyboardKey.arrowDown) {
          _globeLat = (_globeLat - 4 / _globeZoom).clamp(-85.0, 85.0);
        } else if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.arrowLeft) {
          _globeLon = (_globeLon - 5 / _globeZoom + 540) % 360 - 180;
        } else if (key == LogicalKeyboardKey.keyD || key == LogicalKeyboardKey.arrowRight) {
          _globeLon = (_globeLon + 5 / _globeZoom + 540) % 360 - 180;
        } else if (key == LogicalKeyboardKey.keyE) {
          _globeZoom = (_globeZoom * 1.12).clamp(0.65, 2.8);
        } else if (key == LogicalKeyboardKey.keyQ) {
          _globeZoom = (_globeZoom / 1.12).clamp(0.65, 2.8);
        }
      } else {
        if (key == LogicalKeyboardKey.keyW || key == LogicalKeyboardKey.arrowUp) {
          _panOffset += const Offset(0, 14);
        } else if (key == LogicalKeyboardKey.keyS || key == LogicalKeyboardKey.arrowDown) {
          _panOffset += const Offset(0, -14);
        } else if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.arrowLeft) {
          _yaw -= 0.08;
        } else if (key == LogicalKeyboardKey.keyD || key == LogicalKeyboardKey.arrowRight) {
          _yaw += 0.08;
        } else if (key == LogicalKeyboardKey.keyE) {
          _terrainZoom = (_terrainZoom * 1.1).clamp(0.6, 2.6);
        } else if (key == LogicalKeyboardKey.keyQ) {
          _terrainZoom = (_terrainZoom / 1.1).clamp(0.6, 2.6);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final terrain = state.terrain;
    final sun = state.sun;
    final statsText = _mode == 'globe'
        ? 'IAU:49900 · R=3389.5 km · ${_globeLat.toStringAsFixed(2)}°, ${_globeLon.toStringAsFixed(2)}°'
        : '${widget.title} · 3×3 Chunks (9/9) · Exag ${_exag.toStringAsFixed(1)}×';

    final scaleMeters = (_mode == 'globe'
            ? (2400000 / _globeZoom)
            : (1200 / _terrainZoom))
        .round();
    final scaleText = scaleMeters >= 1000
        ? '${(scaleMeters / 1000).toStringAsFixed(1)} km'
        : '$scaleMeters m';

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Container(
        margin: _fullscreen ? EdgeInsets.zero : EdgeInsets.zero,
        color: AresColors.bg0,
        child: Column(
          children: [
            // Modal Header (.modal-header)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: const BoxDecoration(
                color: Color(0xF0121214),
                border: Border(bottom: BorderSide(color: AresColors.line)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '3D Mars Planet & Terrain',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AresColors.text,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        statsText,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AresColors.muted,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _ModalDropdown<String>(
                        value: _mode,
                        items: const [
                          DropdownMenuItem(
                            value: 'globe',
                            child: Text('3D Mars Globe'),
                          ),
                          DropdownMenuItem(
                            value: 'terrain',
                            child: Text('3D Local Terrain'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _mode = v);
                        },
                      ),
                      if (_mode == 'globe')
                        _ModalDropdown<String>(
                          value: _globeTex,
                          items: const [
                            DropdownMenuItem(
                              value: 'viking_red',
                              child: Text('Viking Red'),
                            ),
                            DropdownMenuItem(
                              value: 'mola',
                              child: Text('MOLA Elevation'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _globeTex = v);
                          },
                        ),
                      if (_mode == 'terrain') ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Exag',
                              style: TextStyle(
                                fontSize: 11,
                                color: AresColors.textSecondary,
                              ),
                            ),
                            SizedBox(
                              width: 84,
                              height: 26,
                              child: Slider(
                                value: _exag,
                                min: 1.0,
                                max: 8.0,
                                divisions: 14,
                                onChanged: (v) => setState(() => _exag = v),
                              ),
                            ),
                          ],
                        ),
                        _ModalDropdown<String>(
                          value: _colorMode,
                          items: const [
                            DropdownMenuItem(
                              value: 'orbital',
                              child: Text('NASA Orbital Photo (CTX/HiRISE)'),
                            ),
                            DropdownMenuItem(
                              value: 'elevation',
                              child: Text('Elevation Heatmap'),
                            ),
                            DropdownMenuItem(
                              value: 'slope',
                              child: Text('Slope Hazard'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _colorMode = v);
                          },
                        ),
                      ],
                      _ModalButton(
                        label: _planningGlobeEva
                            ? (_globeEvaStart == null
                                  ? 'Click Start...'
                                  : 'Click Goal...')
                            : 'Plan EVA Route',
                        active: _planningGlobeEva,
                        onTap: () => setState(() {
                          _planningGlobeEva = !_planningGlobeEva;
                          _globeEvaStart = null;
                          _globeEvaGoal = null;
                        }),
                      ),
                      _ModalButton(
                        icon: _fullscreen
                            ? LucideIcons.minimize2
                            : LucideIcons.maximize2,
                        label: _fullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                        active: _fullscreen,
                        onTap: () => setState(() => _fullscreen = !_fullscreen),
                      ),
                      _ModalButton(
                        icon: LucideIcons.x,
                        label: 'Close 3D',
                        onTap: widget.onClose,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Canvas wrap
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_mode == 'globe')
                    _buildGlobeCanvas()
                  else
                    _buildTerrainCanvas(terrain, sun, state.archiveTrail),

                  // Bottom-left Controls Guide (.controls-guide)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xD1121215),
                          border: Border.all(color: AresColors.line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 11,
                              color: AresColors.textSecondary,
                            ),
                            children: [
                              const TextSpan(
                                text: 'Controls: ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AresColors.text,
                                ),
                              ),
                              const TextSpan(
                                text: 'Drag = Rotate · Scroll/Pinch = Zoom · ',
                              ),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: _CodeTag('W A S D'),
                              ),
                              const TextSpan(text: ' / Arrows = Move · '),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: _CodeTag('E'),
                              ),
                              const TextSpan(text: '/'),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: _CodeTag('Q'),
                              ),
                              const TextSpan(
                                text: ' = Up/Down · Tap Globe = Inspect',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Bottom-right Scale Bar (#t3d-scale-bar)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xD1121215),
                          border: Border.all(color: AresColors.line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 90,
                              height: 5,
                              decoration: const BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: AresColors.text,
                                    width: 1.5,
                                  ),
                                  right: BorderSide(
                                    color: AresColors.text,
                                    width: 1.5,
                                  ),
                                  bottom: BorderSide(
                                    color: AresColors.text,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '90px ≈ $scaleText · 1 Chunk = 4.7 km',
                              style: AresType.monoStyle(
                                size: 10.5,
                                color: AresColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Top-right Globe Info Card (#globe-info-card)
                  if (_inspectedPoint != null)
                    Positioned(
                      top: 12,
                      right: 12,
                      width: 280,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xEB141417),
                          border: Border.all(color: AresColors.lineHot),
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x73000000),
                              blurRadius: 20,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _selectedFeature?.name ??
                                        'Mars Surface Point',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AresColors.text,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => setState(() {
                                    _inspectedPoint = null;
                                    _selectedFeature = null;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AresColors.surfaceControl,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: const Icon(
                                      LucideIcons.x,
                                      size: 12,
                                      color: AresColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Coordinates: ${_inspectedPoint!.lat.toStringAsFixed(4)}°, ${_inspectedPoint!.lon.toStringAsFixed(4)}°\n'
                              'Elevation: ${terrain.elevationAt(_inspectedPoint!.lon, _inspectedPoint!.lat).round()} m\n'
                              '${_selectedFeature?.notes ?? 'IAU:49900 Mars Geoid · Click below to explore in 3D'}',
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.45,
                                color: AresColors.muted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _ModalButton(
                                    icon: LucideIcons.mountain,
                                    label: '3D Terrain',
                                    onTap: () => setState(() {
                                      _mode = 'terrain';
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _ModalButton(
                                    icon: LucideIcons.compass,
                                    label: 'Street View',
                                    primary: true,
                                    onTap: () => widget.onOpenStreetView(
                                      _inspectedPoint!,
                                      _selectedFeature?.name ?? 'Globe Point',
                                    ),
                                  ),
                                ),
                              ],
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
      ),
    );
  }

  Widget _buildGlobeCanvas() {
    final img = _globeTex == 'mola' ? _molaImg : _vikingImg;
    final beacons = widget.catalogFeatures
        .where((f) => f.kind != 'Curiosity' && f.kind != 'Perseverance')
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final radius = size.shortestSide * 0.39 * _globeZoom;
        final center = size.center(Offset.zero);

        return GestureDetector(
          onScaleStart: (_) => _gestureStartZoom = _globeZoom,
          onScaleUpdate: (d) {
            setState(() {
              if (d.pointerCount > 1) {
                _globeZoom = (_gestureStartZoom * d.scale).clamp(0.65, 2.8);
              } else {
                _globeLon =
                    (_globeLon - d.focalPointDelta.dx / _globeZoom * 0.28 + 540) %
                        360 -
                    180;
                _globeLat = (_globeLat + d.focalPointDelta.dy / _globeZoom * 0.28)
                    .clamp(-85.0, 85.0);
              }
            });
          },
          onTapUp: (d) {
            final point = unprojectGlobe(
              (d.localPosition.dx - center.dx) / radius,
              (center.dy - d.localPosition.dy) / radius,
              _globeLon,
              _globeLat,
            );
            if (point == null) return;

            if (_planningGlobeEva) {
              setState(() {
                if (_globeEvaStart == null) {
                  _globeEvaStart = point;
                } else {
                  _globeEvaGoal = point;
                  _planningGlobeEva = false;
                  widget.onPlanGlobeEva(_globeEvaStart!, _globeEvaGoal!);
                }
              });
              return;
            }

            SurveyFeature? hit;
            var bestDist = 20.0;
            for (final f in beacons) {
              final p = projectGlobe(f.point, _globeLon, _globeLat);
              if (p.$3 <= 0) continue;
              final screenPt = Offset(
                center.dx + radius * p.$1,
                center.dy - radius * p.$2,
              );
              final dist = (screenPt - d.localPosition).distance;
              if (dist < bestDist) {
                bestDist = dist;
                hit = f;
              }
            }
            setState(() {
              _selectedFeature = hit;
              _inspectedPoint = hit?.point ?? point;
            });
          },
          child: CustomPaint(
            size: size,
            painter: _MarsGlobe3DPainter(
              image: img,
              longitude: _globeLon,
              latitude: _globeLat,
              zoom: _globeZoom,
              features: beacons,
              routeStops: widget.routeStops,
              evaStart: _globeEvaStart,
              evaGoal: _globeEvaGoal,
              selectedId: _selectedFeature?.id,
              inspectedPoint: _inspectedPoint,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTerrainCanvas(
    TerrainModel terrain,
    SolarPosition sun,
    List<GeoPoint> archiveTrail,
  ) {
    return GestureDetector(
      onDoubleTap: () => setState(() {
        _yaw = -0.62;
        _pitch = 0.64;
        _terrainZoom = 1.0;
        _panOffset = Offset.zero;
      }),
      onScaleStart: (_) => _gestureStartZoom = _terrainZoom,
      onScaleUpdate: (d) {
        setState(() {
          if (d.pointerCount > 1) {
            _terrainZoom = (_gestureStartZoom * d.scale).clamp(0.6, 2.6);
          } else {
            _yaw -= d.focalPointDelta.dx * 0.007;
            _pitch = (_pitch + d.focalPointDelta.dy * 0.004).clamp(0.22, 1.28);
          }
        });
      },
      child: CustomPaint(
        painter: _LocalTerrain3DPainter(
          texture: _colorMode == 'orbital' ? _orbitalImg : null,
          colorMode: _colorMode,
          grid: terrain.displayGrid,
          slopeGrid: terrain.slopeGrid,
          bounds: terrain.bounds,
          routeStops: widget.routeStops,
          archiveTrail: archiveTrail,
          yaw: _yaw,
          pitch: _pitch,
          zoom: _terrainZoom,
          panOffset: _panOffset,
          exaggeration: _exag * 0.55,
          sunAzimuth: sun.azimuthDeg,
          sunElevation: sun.elevationDeg,
        ),
      ),
    );
  }
}

class _MarsGlobe3DPainter extends CustomPainter {
  _MarsGlobe3DPainter({
    required this.image,
    required this.longitude,
    required this.latitude,
    required this.zoom,
    required this.features,
    required this.routeStops,
    required this.evaStart,
    required this.evaGoal,
    required this.selectedId,
    required this.inspectedPoint,
  });

  final ui.Image? image;
  final double longitude;
  final double latitude;
  final double zoom;
  final List<SurveyFeature> features;
  final List<({GeoPoint point, String label})> routeStops;
  final GeoPoint? evaStart;
  final GeoPoint? evaGoal;
  final String? selectedId;
  final GeoPoint? inspectedPoint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF050508),
    );
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.39 * zoom;

    // Subtle atmospheric rim glow
    canvas.drawCircle(
      center,
      radius * 1.03,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0x00D97736),
            const Color(0x28D97736),
            Colors.transparent,
          ],
          stops: const [0.88, 0.96, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 1.04)),
    );

    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF6E3F28));

    if (image != null) {
      final positions = <Offset>[];
      final tex = <Offset>[];
      final indices = <int>[];
      for (var y = 0; y <= 50; y++) {
        for (var x = 0; x <= 100; x++) {
          final p = projectGlobe(
            GeoPoint(x * 3.6 - 180, 90 - y * 3.6),
            longitude,
            latitude,
          );
          positions.add(
            Offset(center.dx + p.$1 * radius, center.dy - p.$2 * radius),
          );
          tex.add(
            Offset(x / 100 * image!.width, y / 50 * image!.height),
          );
          if (x < 100 && y < 50) {
            final mid = projectGlobe(
              GeoPoint(x * 3.6 - 178.2, 88.2 - y * 3.6),
              longitude,
              latitude,
            );
            if (mid.$3 > 0.015) {
              final i = y * 101 + x;
              indices.addAll([i, i + 1, i + 102, i, i + 102, i + 101]);
            }
          }
        }
      }
      final vertices = ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        textureCoordinates: tex,
        indices: indices,
      );
      canvas.drawVertices(
        vertices,
        BlendMode.srcOver,
        Paint()
          ..shader = ImageShader(
            image!,
            TileMode.clamp,
            TileMode.clamp,
            Matrix4.identity().storage,
          )
          ..filterQuality = FilterQuality.medium,
      );
      vertices.dispose();
    }

    // Terminator shading
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: [Colors.transparent, Color(0x22000000), Color(0xAA000000)],
          stops: [0.0, 0.62, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // Features
    final pinScale = (1.0 / math.sqrt(zoom)).clamp(0.55, 1.15);
    for (final f in features) {
      final p = projectGlobe(f.point, longitude, latitude);
      if (p.$3 <= 0.05) continue;
      final at = center + Offset(p.$1 * radius, -p.$2 * radius);
      final color = switch (f.kind) {
        'mineral' => AresColors.yellow,
        'planned' => AresColors.pink,
        _ => AresColors.violet,
      };
      canvas.drawCircle(at, 4.2 * pinScale, Paint()..color = color);
      if (f.id == selectedId) {
        canvas.drawCircle(
          at,
          9.0 * pinScale,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
      }
    }

    // Route Stops & EVA pins
    if (routeStops.length > 1) {
      final path = Path();
      var started = false;
      for (final s in routeStops) {
        final p = projectGlobe(s.point, longitude, latitude);
        if (p.$3 <= 0.02) continue;
        final at = center + Offset(p.$1 * radius, -p.$2 * radius);
        if (!started) {
          path.moveTo(at.dx, at.dy);
          started = true;
        } else {
          path.lineTo(at.dx, at.dy);
        }
      }
      if (started) {
        canvas.drawPath(
          path,
          Paint()
            ..color = AresColors.green
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
      }
    }

    for (final pin in [
      (evaStart ?? (routeStops.isNotEmpty ? routeStops.first.point : null), AresColors.green),
      (evaGoal ?? (routeStops.length > 1 ? routeStops.last.point : null), AresColors.blue),
    ]) {
      if (pin.$1 == null) continue;
      final p = projectGlobe(pin.$1!, longitude, latitude);
      if (p.$3 <= 0.02) continue;
      final at = center + Offset(p.$1 * radius, -p.$2 * radius);
      canvas.drawCircle(at, 5.5 * pinScale, Paint()..color = pin.$2);
      canvas.drawCircle(
        at,
        5.5 * pinScale,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    if (inspectedPoint != null) {
      final p = projectGlobe(inspectedPoint!, longitude, latitude);
      if (p.$3 > 0.02) {
        final at = center + Offset(p.$1 * radius, -p.$2 * radius);
        canvas.drawCircle(
          at,
          8 * pinScale,
          Paint()
            ..color = AresColors.blue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MarsGlobe3DPainter old) => true;
}

class _LocalTerrain3DPainter extends CustomPainter {
  _LocalTerrain3DPainter({
    required this.texture,
    required this.colorMode,
    required this.grid,
    required this.slopeGrid,
    required this.bounds,
    required this.routeStops,
    required this.archiveTrail,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.panOffset,
    required this.exaggeration,
    required this.sunAzimuth,
    required this.sunElevation,
  });

  final ui.Image? texture;
  final String colorMode;
  final List<List<double>> grid;
  final List<List<double>> slopeGrid;
  final MapBounds bounds;
  final List<({GeoPoint point, String label})> routeStops;
  final List<GeoPoint> archiveTrail;
  final double yaw;
  final double pitch;
  final double zoom;
  final Offset panOffset;
  final double exaggeration;
  final double sunAzimuth;
  final double sunElevation;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF140E0B), Color(0xFF08080A)],
        ).createShader(Offset.zero & size),
    );

    final rows = grid.length;
    final cols = grid.first.length;
    var minZ = double.infinity;
    var maxZ = -double.infinity;
    for (final row in grid) {
      for (final z in row) {
        if (z < minZ) minZ = z;
        if (z > maxZ) maxZ = z;
      }
    }
    final range = math.max(maxZ - minZ, 1.0);
    final scale = math.min(size.width, size.height) * 0.42 * zoom;
    final cx = size.width * 0.5 + panOffset.dx;
    final cy = size.height * 0.56 + panOffset.dy;
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final sinPitch = math.sin(pitch);
    final cosPitch = math.cos(pitch);

    Offset project(double nx, double ny, double normZ) {
      final x = nx * 2 - 1;
      final y = ny * 2 - 1;
      final z = (normZ - 0.32) * 0.85 * exaggeration;
      final xr = x * cosYaw - y * sinYaw;
      final yr = x * sinYaw + y * cosYaw;
      return Offset(
        cx + xr * scale,
        cy + (yr * sinPitch - z * cosPitch) * scale,
      );
    }

    double depthOf(double nx, double ny, double normZ) {
      final x = nx * 2 - 1;
      final y = ny * 2 - 1;
      final z = (normZ - 0.32) * 0.85 * exaggeration;
      final yr = x * sinYaw + y * cosYaw;
      return yr * cosPitch + z * sinPitch;
    }

    final faces = <({Path path, double depth, Color color})>[];
    for (var r = 0; r < rows - 1; r++) {
      for (var c = 0; c < cols - 1; c++) {
        final nx0 = c / (cols - 1);
        final nx1 = (c + 1) / (cols - 1);
        final ny0 = r / (rows - 1);
        final ny1 = (r + 1) / (rows - 1);
        final z00 = (grid[r][c] - minZ) / range;
        final z10 = (grid[r][c + 1] - minZ) / range;
        final z11 = (grid[r + 1][c + 1] - minZ) / range;
        final z01 = (grid[r + 1][c] - minZ) / range;

        final p0 = project(nx0, ny0, z00);
        final p1 = project(nx1, ny0, z10);
        final p2 = project(nx1, ny1, z11);
        final p3 = project(nx0, ny1, z01);

        final avgZ = (z00 + z10 + z11 + z01) * 0.25;
        final slope = slopeGrid[r][c];
        final shade = (0.65 + (z10 - z00) * 2.4 - (z01 - z00) * 1.8).clamp(0.4, 1.25);

        Color baseColor;
        if (colorMode == 'slope') {
          baseColor = slope >= 25
              ? AresColors.red
              : slope >= 15
                  ? AresColors.amber
                  : AresColors.green;
        } else if (colorMode == 'elevation') {
          baseColor = Color.lerp(
            const Color(0xFF1E3A8A),
            const Color(0xFFF97316),
            avgZ,
          )!;
        } else {
          baseColor = Color.lerp(
            const Color(0xFF5C3A28),
            const Color(0xFFC2855E),
            avgZ,
          )!;
        }

        final rChan = (baseColor.r * 255 * shade).round().clamp(0, 255);
        final gChan = (baseColor.g * 255 * shade).round().clamp(0, 255);
        final bChan = (baseColor.b * 255 * shade).round().clamp(0, 255);

        faces.add((
          path: Path()
            ..moveTo(p0.dx, p0.dy)
            ..lineTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..lineTo(p3.dx, p3.dy)
            ..close(),
          depth: depthOf((nx0 + nx1) * 0.5, (ny0 + ny1) * 0.5, avgZ),
          color: Color.fromARGB(255, rChan, gChan, bChan),
        ));
      }
    }

    faces.sort((a, b) => a.depth.compareTo(b.depth));
    for (final f in faces) {
      canvas.drawPath(f.path, Paint()..color = f.color);
    }

    // Draw 3D EVA Route & Beacons
    if (routeStops.isNotEmpty) {
      final pts = <Offset>[];
      for (final stop in routeStops) {
        final nx = ((stop.point.lon - bounds.minLon) / bounds.widthDeg).clamp(0.05, 0.95);
        final ny = ((bounds.maxLat - stop.point.lat) / bounds.heightDeg).clamp(0.05, 0.95);
        final r = (ny * (rows - 1)).round().clamp(0, rows - 1);
        final c = (nx * (cols - 1)).round().clamp(0, cols - 1);
        final nz = (grid[r][c] - minZ) / range + 0.015;
        pts.add(project(nx, ny, nz));
      }
      if (pts.length > 1) {
        final routePath = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (var i = 1; i < pts.length; i++) {
          routePath.lineTo(pts[i].dx, pts[i].dy);
        }
        canvas.drawPath(
          routePath,
          Paint()
            ..color = AresColors.green
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0,
        );
      }
      for (var i = 0; i < pts.length; i++) {
        final p = pts[i];
        final isEnd = i == 0 || i == pts.length - 1;
        final color = i == 0
            ? AresColors.green
            : i == pts.length - 1
                ? AresColors.amber
                : AresColors.blue;
        canvas.drawLine(
          p,
          p - const Offset(0, 14),
          Paint()
            ..color = color
            ..strokeWidth = 2,
        );
        canvas.drawCircle(p - const Offset(0, 14), isEnd ? 4.5 : 3.5, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LocalTerrain3DPainter old) => true;
}

class _ModalDropdown<T> extends StatelessWidget {
  const _ModalDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0x52000000),
        border: Border.all(color: AresColors.lineHot),
        borderRadius: BorderRadius.circular(7),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isDense: true,
          dropdownColor: AresColors.bg2,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: AresColors.text,
          ),
        ),
      ),
    );
  }
}

class _ModalButton extends StatelessWidget {
  const _ModalButton({
    this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.primary = false,
  });

  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bg = primary
        ? AresColors.blue
        : active
            ? AresColors.blueTint
            : AresColors.surfaceControl;
    final border = primary
        ? const Color(0x24FFFFFF)
        : active
            ? const Color(0x610A84FF)
            : AresColors.line;
    final fg = primary
        ? Colors.white
        : active
            ? const Color(0xFF64B5F6)
            : AresColors.text;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: primary || active ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeTag extends StatelessWidget {
  const _CodeTag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: AresType.monoStyle(size: 10, color: AresColors.text),
      ),
    );
  }
}

