import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide DataRow;
import 'package:flutter/services.dart';

import '../data/exploration_data.dart';
import '../models/ares_models.dart';
import '../state/ares_scope.dart';
import '../theme/ares_theme.dart';
import '../util/astro.dart';
import '../util/globe_projection.dart';
import '../widgets/hud.dart';

class ExplorationScreen extends StatefulWidget {
  const ExplorationScreen({super.key});
  @override
  State<ExplorationScreen> createState() => _ExplorationScreenState();
}

class _ExplorationScreenState extends State<ExplorationScreen> {
  ExplorationData? _data;
  String? _error;
  ui.Image? _viking;
  ui.Image? _mola;
  SurveyFeature? _selected;
  GeoPoint? _picked;
  bool _globe = true;
  bool _molaMode = false;
  bool _orbit = true;
  bool _dropping = false;
  bool _saving = false;
  int _region = 0;
  double _lon = 137.4;
  double _lat = -4.6;
  double _zoom = 1;
  double _gestureZoom = 1;
  final _mapController = TransformationController();
  final Set<String> _visible = {
    'landmark',
    'mineral',
    'Curiosity',
    'Perseverance',
    'planned',
  };

  static const _regions = [
    'Whole Mars',
    'Gale Crater',
    'Mount Sharp',
    'Jezero',
  ];
  static const _bounds = [
    MapBounds(-180, -90, 180, 90),
    MapBounds(136.1, -5.8, 138.7, -3.2),
    MapBounds(137.3, -4.9, 137.5, -4.55),
    MapBounds(77.25, 18.3, 77.6, 18.65),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<ui.Image> _image(String name) async {
    final bytes = await rootBundle.load('assets/images/map/$name.jpg');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    return image;
  }

  Future<void> _load() async {
    try {
      final data = await ExplorationData.load();
      final viking = await _image('mars_global');
      final mola = await _image('mars_mola');
      if (!mounted) {
        viking.dispose();
        mola.dispose();
        return;
      }
      setState(() {
        _data = data;
        _viking = viking;
        _mola = mola;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The exploration archive could not be opened. Your saved waypoints have not been changed.',
        );
      }
    }
  }

  @override
  void dispose() {
    _viking?.dispose();
    _mola?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  List<SurveyFeature> get _features => [
    ...?_data?.catalog,
    ...?_data?.planned,
  ].where((f) => _visible.contains(f.kind)).toList();

  void _jump(int region) {
    setState(() {
      _region = region;
      _selected = null;
      _picked = null;
      _mapController.value = Matrix4.identity();
      final b = _bounds[region];
      if (region != 0) {
        _lon = (b.minLon + b.maxLon) / 2;
        _lat = (b.minLat + b.maxLat) / 2;
      }
      _zoom = region == 0 ? 1 : 1.15;
      _dropping = false;
    });
  }

  Future<void> _savePoint(GeoPoint point) async {
    final data = _data!;
    final controller = TextEditingController(
      text: 'Waypoint ${data.planned.length + 1}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save planned waypoint'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatCoordinate(point)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLength: 60,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Waypoint name'),
              ),
              const Text('Stored on this tablet, not uploaded to MongoDB.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Wait for the dialog exit animation before disposing its field controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (!mounted || name == null) return;
    setState(() => _saving = true);
    final feature = SurveyFeature(
      id: 'planned-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      point: point,
      kind: 'planned',
      notes: 'Operator-planned location. Not a surveyed landmark.',
      source: 'Saved on this tablet',
    );
    try {
      await data.save([...data.planned, feature]);
      if (mounted) {
        setState(() {
          _selected = feature;
          _picked = point;
          _dropping = false;
          _visible.add('planned');
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Waypoint not saved. Check available device storage.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final feature = _selected!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${feature.name}?'),
        content: const Text('This removes the waypoint saved on this tablet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _data!.save(
        _data!.planned.where((f) => f.id != feature.id).toList(),
      );
      if (mounted) setState(() => _selected = null);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove waypoint. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _pick(GeoPoint point, SurveyFeature? feature) {
    if (_saving) return;
    if (_dropping) {
      _savePoint(point);
      return;
    }
    setState(() {
      _selected = feature;
      _picked = feature?.point ?? point;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AresColors.bg0,
      appBar: AppBar(
        title: const Text('Explore Mars'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() {
              _globe = !_globe;
              _dropping = false;
            }),
            icon: Icon(_globe ? Icons.map_outlined : Icons.public),
            label: Text(_globe ? 'Regional map' : '3D globe'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : _data == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < _regions.length; i++) ...[
                        Expanded(
                          child: ChipToggle(
                            label: _regions[i],
                            selected: _region == i,
                            onTap: () => _jump(i),
                          ),
                        ),
                        if (i < _regions.length - 1) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRect(
                            child: ColoredBox(
                              color: const Color(0xFF040709),
                              child: _globe ? _globeView() : _mapView(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(width: 302, child: _inspector()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _globeView() => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final radius = size.shortestSide * 0.39 * _zoom;
      final center = size.center(Offset.zero);
      final beacons = _features
          .where((f) => f.kind != 'Curiosity' && f.kind != 'Perseverance')
          .toList();
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onScaleStart: (_) => _gestureZoom = _zoom,
              onScaleUpdate: (d) => setState(() {
                if (d.pointerCount > 1) {
                  _zoom = (_gestureZoom * d.scale).clamp(0.7, 2.2);
                } else {
                  _lon =
                      (_lon - d.focalPointDelta.dx / _zoom * 0.3 + 540) % 360 -
                      180;
                  _lat = (_lat + d.focalPointDelta.dy / _zoom * 0.3).clamp(
                    -85,
                    85,
                  );
                }
              }),
              onTapUp: (d) {
                SurveyFeature? feature;
                var nearest = 22.0;
                for (final f in beacons) {
                  final p = projectGlobe(f.point, _lon, _lat);
                  if (p.$3 < 0) continue;
                  final distance =
                      (Offset(
                                center.dx + radius * p.$1,
                                center.dy - radius * p.$2,
                              ) -
                              d.localPosition)
                          .distance;
                  if (distance < nearest) {
                    nearest = distance;
                    feature = f;
                  }
                }
                final point = unprojectGlobe(
                  (d.localPosition.dx - center.dx) / radius,
                  (center.dy - d.localPosition.dy) / radius,
                  _lon,
                  _lat,
                );
                if (point != null) _pick(point, feature);
              },
              child: CustomPaint(
                painter: _GlobePainter(
                  image: (_molaMode ? _mola : _viking)!,
                  longitude: _lon,
                  latitude: _lat,
                  zoom: _zoom,
                  features: beacons,
                  selected: _selected?.id,
                  orbit: _orbit,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: 12,
            child: Text(
              'NASA ${_molaMode ? 'MOLA shaded elevation' : 'Viking mosaic'} · IAU:49900\nDrag to rotate · pinch to zoom · tap a beacon',
              style: AresType.monoStyle(size: 11, color: AresColors.muted),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 8,
            child: Row(
              children: [
                const Icon(Icons.zoom_out, size: 18),
                Expanded(
                  child: Slider(
                    value: _zoom,
                    min: 0.7,
                    max: 2.2,
                    onChanged: (v) => setState(() => _zoom = v),
                  ),
                ),
                const Icon(Icons.zoom_in, size: 18),
                const SizedBox(width: 20),
                Text(
                  _orbit ? 'MRO orbit schematic · SIM' : 'Orbit hidden',
                  style: AresType.monoStyle(size: 11),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _mapView() {
    final bounds = _bounds[_region];
    final asset = _region == 0
        ? 'assets/images/map/${_molaMode ? 'mars_mola' : 'mars_global'}.jpg'
        : _region == 3
        ? 'assets/images/map/jezero_orbital.jpg'
        : _region == 2
        ? 'assets/images/map/mount_sharp_orbital.jpg'
        : 'assets/images/map/ctx_optical_gale.png';
    return LayoutBuilder(
      builder: (context, c) {
        final aspect = bounds.widthDeg / bounds.heightDeg;
        final width = math.min(c.maxWidth, c.maxHeight * aspect);
        final rect = Rect.fromCenter(
          center: c.biggest.center(Offset.zero),
          width: width,
          height: width / aspect,
        );
        Offset project(GeoPoint p) => Offset(
          rect.left + (p.lon - bounds.minLon) / bounds.widthDeg * rect.width,
          rect.top + (bounds.maxLat - p.lat) / bounds.heightDeg * rect.height,
        );
        final features = _features;
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _mapController,
                minScale: 1,
                maxScale: 12,
                child: GestureDetector(
                  onTapUp: (d) {
                    if (!rect.contains(d.localPosition)) return;
                    final point = GeoPoint(
                      bounds.minLon +
                          (d.localPosition.dx - rect.left) /
                              rect.width *
                              bounds.widthDeg,
                      bounds.maxLat -
                          (d.localPosition.dy - rect.top) /
                              rect.height *
                              bounds.heightDeg,
                    );
                    SurveyFeature? nearest;
                    var distance =
                        20 / _mapController.value.getMaxScaleOnAxis();
                    for (final f in features) {
                      final delta =
                          (project(f.point) - d.localPosition).distance;
                      if (delta < distance) {
                        distance = delta;
                        nearest = f;
                      }
                    }
                    _pick(point, nearest);
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fromRect(
                        rect: rect,
                        child: ClipRect(
                          child: Image.asset(
                            asset,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter: _FeatureMapPainter(
                          rect: rect,
                          bounds: bounds,
                          features: features,
                          selected: _selected?.id,
                          picked: _picked,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Text(
                _dropping
                    ? 'Tap the map to save a waypoint'
                    : 'Pinch to zoom · tap a feature to inspect',
                style: AresType.monoStyle(
                  size: 12,
                  color: _dropping ? AresColors.amber : AresColors.text,
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 10,
              child: Text(
                'Archive imagery · ${_regions[_region]} · offline',
                style: AresType.monoStyle(size: 11),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 8,
              child: IconButton(
                tooltip: 'Reset map zoom',
                onPressed: () => _mapController.value = Matrix4.identity(),
                icon: const Icon(Icons.fit_screen),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _inspector() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Map layers', style: AresType.displayStyle(size: 23)),
        if (_globe || _region == 0) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('MOLA elevation'),
            value: _molaMode,
            onChanged: (v) => setState(() => _molaMode = v),
          ),
          if (_globe)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('MRO orbit schematic'),
              value: _orbit,
              onChanged: (v) => setState(() => _orbit = v),
            ),
        ],
        for (final kind in [
          'landmark',
          'mineral',
          'Curiosity',
          'Perseverance',
          'planned',
        ])
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              '${switch (kind) {
                'landmark' => 'Landmarks',
                'mineral' => 'Mineral targets',
                'planned' => 'Planned waypoints',
                _ => kind,
              }} (${[..._data!.catalog, ..._data!.planned].where((f) => f.kind == kind).length})',
              style: AresType.monoStyle(size: 11),
            ),
            value: _visible.contains(kind),
            onChanged: (_) => setState(() {
              if (!_visible.remove(kind)) _visible.add(kind);
            }),
          ),
        const SizedBox(height: 8),
        AresButton(
          label: _dropping
              ? 'Cancel waypoint placement'
              : 'Drop planned waypoint',
          icon: Icons.add_location_alt_outlined,
          expanded: true,
          onTap: _saving
              ? null
              : () => setState(() {
                  _globe = false;
                  _dropping = !_dropping;
                }),
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        Text(
          _selected?.name ??
              (_picked == null ? 'Site inspector' : 'Surface point'),
          style: AresType.displayStyle(size: 23),
        ),
        const SizedBox(height: 8),
        if (_picked != null)
          Text(formatCoordinate(_picked!), style: AresType.monoStyle(size: 12)),
        const SizedBox(height: 10),
        Text(
          _selected?.notes ?? 'Tap a landmark, mineral target or rover waypoint. Globe beacons show landmarks and planned stops; rover traverses appear in regional maps.',
          style: AresType.bodyMuted.copyWith(fontSize: 13, height: 1.5),
        ),
        if (_selected != null) ...[
          const SizedBox(height: 10),
          Text(
            _selected!.kind == 'mineral' || _selected!.kind == 'landmark'
                ? 'Team seed catalog · approximate location'
                : _selected!.kind == 'planned'
                ? 'Saved locally · operator entered'
                : 'NASA MMGIS rover archive',
            style: AresType.monoStyle(size: 10, color: AresColors.amber),
          ),
          if (_selected!.elevation != null)
            DataRow(
              label: 'Catalog elevation',
              value: '${_selected!.elevation!.round()} m',
            ),
          if (_selected!.kind == 'planned')
            TextButton.icon(
              onPressed: _saving ? null : _remove,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove waypoint'),
            ),
        ],
        if (_picked != null &&
            _picked!.lon > 136.1 &&
            _picked!.lon < 138.7 &&
            _picked!.lat > -5.8 &&
            _picked!.lat < -3.2) ...[
          const SizedBox(height: 12),
          AresButton(
            label: 'Route here on Gale map',
            icon: Icons.alt_route,
            expanded: true,
            onTap: () {
              final state = AresScope.of(context);
              state.planRouteTo(
                _picked!,
                _selected?.name ?? 'Planned location',
              );
              Navigator.pop(context);
            },
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Radiation: no data. Archive and model views cannot establish EVA safety.',
          style: AresType.bodyMuted.copyWith(fontSize: 12),
        ),
      ],
    ),
  );
}

Color _featureColor(String kind) => switch (kind) {
  'mineral' => AresColors.amber,
  'Curiosity' => AresColors.green,
  'Perseverance' => AresColors.cyan,
  'planned' => AresColors.violet,
  _ => AresColors.text,
};

class _FeatureMapPainter extends CustomPainter {
  _FeatureMapPainter({
    required this.rect,
    required this.bounds,
    required this.features,
    required this.selected,
    required this.picked,
  });
  final Rect rect;
  final MapBounds bounds;
  final List<SurveyFeature> features;
  final String? selected;
  final GeoPoint? picked;
  @override
  void paint(Canvas canvas, Size size) {
    Offset project(GeoPoint p) => Offset(
      rect.left + (p.lon - bounds.minLon) / bounds.widthDeg * rect.width,
      rect.top + (bounds.maxLat - p.lat) / bounds.heightDeg * rect.height,
    );
    canvas.save();
    canvas.clipRect(rect);
    for (final kind in ['Curiosity', 'Perseverance']) {
      final points = features.where((f) => f.kind == kind).toList();
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final p = project(points[i].point);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = _featureColor(kind)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    for (final f in features) {
      final p = project(f.point);
      if (!rect.contains(p)) continue;
      final rover = f.kind == 'Curiosity' || f.kind == 'Perseverance';
      canvas.drawCircle(
        p,
        rover ? 2 : 5,
        Paint()..color = _featureColor(f.kind),
      );
      if (f.id == selected) {
        canvas.drawCircle(
          p,
          10,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    if (picked != null && selected == null) {
      canvas.drawCircle(
        project(picked!),
        8,
        Paint()
          ..color = AresColors.cyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FeatureMapPainter oldDelegate) => true;
}

class _GlobePainter extends CustomPainter {
  _GlobePainter({
    required this.image,
    required this.longitude,
    required this.latitude,
    required this.zoom,
    required this.features,
    required this.selected,
    required this.orbit,
  });
  final ui.Image image;
  final double longitude, latitude, zoom;
  final List<SurveyFeature> features;
  final String? selected;
  final bool orbit;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.39 * zoom;
    final positions = <Offset>[];
    final tex = <Offset>[];
    final indices = <int>[];
    for (var y = 0; y <= 60; y++) {
      for (var x = 0; x <= 120; x++) {
        final p = projectGlobe(
          GeoPoint(x * 3 - 180, 90 - y * 3),
          longitude,
          latitude,
        );
        positions.add(
          Offset(center.dx + p.$1 * radius, center.dy - p.$2 * radius),
        );
        tex.add(Offset(x / 120 * image.width, y / 60 * image.height));
        if (x < 120 && y < 60) {
          final mid = projectGlobe(
            GeoPoint(x * 3 - 178.5, 88.5 - y * 3),
            longitude,
            latitude,
          );
          if (mid.$3 > 0.015) {
            final i = y * 121 + x;
            indices.addAll([i, i + 1, i + 122, i, i + 122, i + 121]);
          }
        }
      }
    }
    void drawOrbit(bool front) {
      final path = Path();
      var drawing = false;
      for (var i = 0; i <= 180; i++) {
        final a = i * math.pi / 90;
        final depth = math.cos(a) * 0.6;
        final point =
            center +
            Offset(math.cos(a) * radius * 0.48, math.sin(a) * radius * 1.17);
        if ((depth >= 0) == front) {
          if (!drawing) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
          drawing = true;
        } else {
          drawing = false;
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AresColors.cyan.withValues(alpha: front ? 0.65 : 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    if (orbit) drawOrbit(false);
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF5D3725));
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
          image,
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity().storage,
        )
        ..filterQuality = FilterQuality.medium,
    );
    vertices.dispose();
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 1,
          colors: [Colors.transparent, Color(0x22000000), Color(0xAA000000)],
          stops: [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    if (orbit) {
      drawOrbit(true);
      canvas.drawCircle(
        center + Offset(radius * 0.34, -radius * 0.82),
        5,
        Paint()..color = AresColors.cyan,
      );
    }
    for (final f in features) {
      final p = projectGlobe(f.point, longitude, latitude);
      if (p.$3 <= 0.05) continue;
      final at = center + Offset(p.$1 * radius, -p.$2 * radius);
      canvas.drawCircle(at, 4, Paint()..color = _featureColor(f.kind));
      if (f.id == selected) {
        canvas.drawCircle(
          at,
          9,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) =>
      old.longitude != longitude ||
      old.latitude != latitude ||
      old.zoom != zoom ||
      old.image != image ||
      old.orbit != orbit ||
      old.selected != selected ||
      old.features != features;
}
