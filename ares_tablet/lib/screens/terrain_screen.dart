import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:flutter/material.dart' hide DataRow;

import '../models/ares_models.dart';
import '../state/ares_scope.dart';
import '../theme/ares_theme.dart';
import '../util/astro.dart';
import '../widgets/hud.dart';

class TerrainScreen extends StatefulWidget {
  const TerrainScreen({super.key});

  @override
  State<TerrainScreen> createState() => _TerrainScreenState();
}

class _TerrainScreenState extends State<TerrainScreen> {
  double _yaw = -0.55;
  double _pitch = 0.6;
  double _exaggeration = 1.5;
  bool _slopeMode = false;
  bool _showRoute = true;
  bool _wireframe = false;
  bool _orbital = true;
  ui.Image? _texture;
  String? _textureError;

  @override
  void initState() {
    super.initState();
    _loadTexture();
  }

  Future<void> _loadTexture() async {
    try {
      final bytes = await rootBundle.load(
        'assets/images/map/ctx_optical_gale.png',
      );
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _texture = image);
    } catch (_) {
      if (mounted) setState(() => _textureError = 'Orbital image unavailable');
    }
  }

  @override
  void dispose() {
    _texture?.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _yaw = -0.55;
      _pitch = 0.6;
      _exaggeration = 1.5;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final terrain = state.terrain;
    final sun = state.sun;
    final maxSlope = _maxSlope(terrain.slopeGrid);
    final steepCells = _countSteep(terrain.slopeGrid, 20);
    final relief = terrain.maxElevation - terrain.minElevation;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '3D TERRAIN',
                    style: AresType.displayStyle(size: 25, spacing: 0.8),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Aeolis Mons · elevation, slope and sunlight',
                    style: AresType.label(
                      size: 9.5,
                      color: AresColors.muted,
                      spacing: 0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              const ProvenancePill(Provenance.model),
              const SizedBox(width: 5),
              const ProvenancePill(Provenance.derived),
              const Spacer(),
              Text(
                'Drag to orbit · double-tap to reset',
                style: AresType.label(
                  size: 9.5,
                  color: AresColors.dim,
                  spacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 258,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        HudPanel(
                          title: 'DISPLAY',
                          trailing: const ProvenancePill(
                            Provenance.model,
                            compact: true,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: ChipToggle(
                                      label: 'Elevation',
                                      selected: !_slopeMode && !_orbital,
                                      onTap: () => setState(() {
                                        _slopeMode = false;
                                        _orbital = false;
                                      }),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: ChipToggle(
                                      label: 'Slope',
                                      selected: _slopeMode,
                                      accent: AresColors.amber,
                                      onTap: () => setState(() {
                                        _slopeMode = true;
                                        _orbital = false;
                                      }),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ChipToggle(
                                label: 'NASA orbital photo',
                                selected: _orbital,
                                onTap: () => setState(() {
                                  _orbital = true;
                                  _slopeMode = false;
                                }),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _textureError ?? 'CTX archive draped on modeled relief, not a measured DEM.',
                                style: AresType.bodyMuted.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Text(
                                    'Height exaggeration',
                                    style: AresType.label(
                                      size: 9.5,
                                      color: AresColors.dim,
                                      spacing: 0.3,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${_exaggeration.toStringAsFixed(1)}×',
                                    style: AresType.monoStyle(
                                      size: 11,
                                      color: AresColors.cyan,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: _exaggeration,
                                min: 0.5,
                                max: 3,
                                divisions: 25,
                                onChanged: (v) =>
                                    setState(() => _exaggeration = v),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: ChipToggle(
                                      label: 'Route',
                                      icon: Icons.alt_route,
                                      selected: _showRoute,
                                      onTap: () => setState(
                                        () => _showRoute = !_showRoute,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: ChipToggle(
                                      label: 'Mesh',
                                      icon: Icons.grid_4x4,
                                      selected: _wireframe,
                                      onTap: () => setState(
                                        () => _wireframe = !_wireframe,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              AresButton(
                                label: 'Reset view',
                                icon: Icons.restart_alt,
                                expanded: true,
                                onTap: _reset,
                              ),
                              const SizedBox(height: 7),
                              Text(
                                'Shading follows the computed sun direction, '
                                'kept at least 8° above the horizon so slopes '
                                'stay readable.',
                                style: AresType.bodyMuted.copyWith(
                                  fontSize: 10,
                                  height: 1.35,
                                  color: AresColors.dim,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        HudPanel(
                          title: 'SITE STATS',
                          code: 'GALE',
                          trailing: const ProvenancePill(
                            Provenance.model,
                            compact: true,
                          ),
                          child: Column(
                            children: [
                              DataRow(
                                label: 'Relief',
                                value: '${relief.round()} m',
                              ),
                              DataRow(
                                label: 'Peak',
                                value: '${terrain.maxElevation.round()} m',
                              ),
                              DataRow(
                                label: 'Floor',
                                value: '${terrain.minElevation.round()} m',
                              ),
                              DataRow(
                                label: 'Grid',
                                value:
                                    '${terrain.displayGrid.first.length} × ${terrain.displayGrid.length}',
                              ),
                              DataRow(
                                label: 'Max slope',
                                value: '${maxSlope.toStringAsFixed(1)}°',
                                valueColor: maxSlope > 20
                                    ? AresColors.amber
                                    : AresColors.text,
                                provenance: Provenance.derived,
                              ),
                              DataRow(
                                label: 'Steep cells > 20°',
                                value: '$steepCells',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        HudPanel(
                          title: 'SUNLIGHT',
                          trailing: const ProvenancePill(
                            Provenance.model,
                            compact: true,
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.wb_sunny_outlined,
                                    size: 20,
                                    color: AresColors.amber,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Metric(
                                      label: 'Azimuth',
                                      value:
                                          '${sun.azimuthDeg.round().toString().padLeft(3, '0')}°',
                                      note: compass16(sun.azimuthDeg),
                                      size: 19,
                                      color: AresColors.amber,
                                    ),
                                  ),
                                  Expanded(
                                    child: Metric(
                                      label: 'Elevation',
                                      value:
                                          '${sun.elevationDeg.toStringAsFixed(1)}°',
                                      note: sun.isUp
                                          ? 'Sun up'
                                          : 'Below horizon',
                                      size: 19,
                                      color: sun.isUp
                                          ? AresColors.text
                                          : AresColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                'Local solar time '
                                '${state.marsClock.localSolarHours.toStringAsFixed(2)} h',
                                style: AresType.monoStyle(
                                  size: 9.5,
                                  color: AresColors.dim,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Mars clock ${state.marsClock.mtc}',
                                style: AresType.monoStyle(
                                  size: 9.5,
                                  color: AresColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF06090C),
                      border: Border.all(color: AresColors.line),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          GestureDetector(
                            onDoubleTap: _reset,
                            onPanUpdate: (details) {
                              setState(() {
                                _yaw -= details.delta.dx * 0.007;
                                _pitch = (_pitch + details.delta.dy * 0.004)
                                    .clamp(0.22, 1.28);
                              });
                            },
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: CustomPaint(
                                painter: _TerrainPainter(
                                  texture: _orbital ? _texture : null,
                                  archiveTrail: _showRoute
                                      ? state.archiveTrail
                                      : const [],
                                  grid: terrain.displayGrid,
                                  slopeGrid: terrain.slopeGrid,
                                  bounds: state.bounds,
                                  route: _showRoute ? state.route : null,
                                  yaw: _yaw,
                                  pitch: _pitch,
                                  exaggeration: _exaggeration,
                                  slopeMode: _slopeMode,
                                  wireframe: _wireframe,
                                  sunAzimuth: sun.azimuthDeg,
                                  sunElevation: sun.elevationDeg,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            top: 10,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Aeolis Mons',
                                  style: AresType.label(
                                    size: 11,
                                    color: AresColors.text,
                                    spacing: 0.4,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _orbital
                                      ? 'NASA CTX photo · green: Curiosity archive traverse'
                                      : _slopeMode
                                      ? 'Slope 0–25° · green to red'
                                      : 'Elevation ${terrain.minElevation.round()} to '
                                            '${terrain.maxElevation.round()} m',
                                  style: AresType.monoStyle(
                                    size: 9.5,
                                    color: AresColors.dim,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: _orbital
                                ? const SizedBox.shrink()
                                : _VerticalLegend(slopeMode: _slopeMode),
                          ),
                          Positioned(
                            left: 12,
                            bottom: 10,
                            child: Text(
                              'Yaw ${(_yaw * 180 / math.pi).round().abs()}° · '
                              'pitch ${(_pitch * 180 / math.pi).round()}° · '
                              'height ${_exaggeration.toStringAsFixed(1)}× · '
                              'grid ${terrain.displayGrid.first.length}²',
                              style: AresType.monoStyle(
                                size: 9.5,
                                color: AresColors.muted,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Text(
                              'Illustrative model · not for navigation',
                              style: AresType.label(
                                size: 9,
                                color: AresColors.amber,
                                spacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 300,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const _RouteProfilePanel(),
                        const SizedBox(height: 10),
                        _HazardPanel(steeper: steepCells, maxSlope: maxSlope),
                        const SizedBox(height: 10),
                        HudPanel(
                          title: 'FIELD NOTE',
                          trailing: const ProvenancePill(
                            Provenance.sim,
                            compact: true,
                          ),
                          child: Text(
                            'Confirm break-over angles and drop-offs on foot. '
                            'This 3D view exaggerates relief and cannot resolve '
                            'meter-scale hazards or loose regolith under the '
                            'wheels.',
                            style: AresType.bodyMuted.copyWith(
                              fontSize: 11,
                              height: 1.4,
                            ),
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

  double _maxSlope(List<List<double>> grid) {
    var maxValue = 0.0;
    for (final row in grid) {
      for (final value in row) {
        if (value > maxValue) maxValue = value;
      }
    }
    return maxValue;
  }

  int _countSteep(List<List<double>> grid, double threshold) {
    var count = 0;
    for (final row in grid) {
      for (final value in row) {
        if (value > threshold) count++;
      }
    }
    return count;
  }
}

class _VerticalLegend extends StatelessWidget {
  const _VerticalLegend({required this.slopeMode});

  final bool slopeMode;

  @override
  Widget build(BuildContext context) {
    final colors = slopeMode
        ? const [AresColors.red, AresColors.amber, AresColors.green]
        : const [
            Color(0xFFE3D3B3),
            AresColors.amber,
            Color(0xFF14616A),
            Color(0xFF0B2733),
          ];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AresColors.bg0.withValues(alpha: 0.75),
        border: Border.all(color: AresColors.line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                slopeMode ? '25°' : 'Peak',
                style: AresType.monoStyle(size: 9, color: AresColors.dim),
              ),
              Container(
                width: 6,
                height: 68,
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: colors,
                  ),
                ),
              ),
              Text(
                slopeMode ? '0°' : 'Floor',
                style: AresType.monoStyle(size: 9, color: AresColors.dim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteProfilePanel extends StatelessWidget {
  const _RouteProfilePanel();

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final route = state.route;
    return HudPanel(
      title: 'ROUTE PROFILE',
      code: route?.targetName,
      trailing: const ProvenancePill(Provenance.derived, compact: true),
      child: route == null
          ? Text(
              'No traverse yet. Plan a route from the map to see its '
              'elevation profile here.',
              style: AresType.bodyMuted.copyWith(fontSize: 11, height: 1.4),
            )
          : Column(
              children: [
                SizedBox(
                  height: 130,
                  child: CustomPaint(
                    painter: _ProfilePainter(elevations: route.elevations),
                    child: const SizedBox.expand(),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${route.elevations.first.round()} m',
                      style: AresType.monoStyle(
                        size: 9.5,
                        color: AresColors.dim,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${route.elevations.last.round()} m',
                      style: AresType.monoStyle(
                        size: 9.5,
                        color: AresColors.amber,
                      ),
                    ),
                  ],
                ),
                const SectionDivider(),
                Row(
                  children: [
                    Expanded(
                      child: Metric(
                        label: 'Distance',
                        value: route.distanceKm.toStringAsFixed(2),
                        unit: 'km',
                        size: 16,
                      ),
                    ),
                    Expanded(
                      child: Metric(
                        label: 'Ascent',
                        value: '${route.elevationGainM.round()}',
                        unit: 'm',
                        size: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Metric(
                        label: 'ETA',
                        value: route.durationLabel,
                        size: 16,
                        color: AresColors.cyan,
                      ),
                    ),
                    Expanded(
                      child: Metric(
                        label: 'Max slope',
                        value: route.maxSlopeDeg.toStringAsFixed(1),
                        unit: '°',
                        size: 16,
                        color: route.maxSlopeDeg > 14
                            ? AresColors.amber
                            : AresColors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  'Computed on device over a modeled elevation grid at '
                  '${route.cellSizeM.round()} m cells. ETA assumes 0.4 m/s '
                  'with slope derating.',
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

class _ProfilePainter extends CustomPainter {
  _ProfilePainter({required this.elevations});

  final List<double> elevations;

  @override
  void paint(Canvas canvas, Size size) {
    if (elevations.length < 2) return;
    final minValue = elevations.reduce(math.min);
    final maxValue = elevations.reduce(math.max);
    final range = math.max(maxValue - minValue, 1.0);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()..color = AresColors.bg0.withValues(alpha: 0.45),
    );
    final grid = Paint()
      ..color = AresColors.line.withValues(alpha: 0.6)
      ..strokeWidth = 0.7;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = 0; i <= 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final path = Path();
    for (var i = 0; i < elevations.length; i++) {
      final x = size.width * i / (elevations.length - 1);
      final y =
          size.height -
          4 -
          (elevations[i] - minValue) / range * (size.height - 8);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AresColors.cyan.withValues(alpha: 0.22),
            AresColors.cyan.withValues(alpha: 0.02),
          ],
        ).createShader(rect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AresColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final lastX = size.width;
    final lastY =
        size.height -
        4 -
        (elevations.last - minValue) / range * (size.height - 8);
    canvas.drawCircle(
      Offset(lastX, lastY),
      2.5,
      Paint()..color = AresColors.amber,
    );
  }

  @override
  bool shouldRepaint(covariant _ProfilePainter oldDelegate) =>
      oldDelegate.elevations != elevations;
}

class _HazardPanel extends StatelessWidget {
  const _HazardPanel({required this.steeper, required this.maxSlope});

  final int steeper;
  final double maxSlope;

  @override
  Widget build(BuildContext context) {
    return HudPanel(
      title: 'SURFACE HAZARDS',
      trailing: const ProvenancePill(Provenance.model, compact: true),
      child: Column(
        children: [
          DataRow(
            label: 'Drop-off risk',
            value: maxSlope > 20 ? 'Elevated' : 'Moderate',
            valueColor: maxSlope > 20 ? AresColors.amber : AresColors.muted,
            provenance: Provenance.derived,
          ),
          DataRow(label: 'Steep cells', value: '$steeper > 20°'),
          DataRow(
            label: 'Regolith slip',
            value: 'Moderate',
            provenance: Provenance.sim,
          ),
          DataRow(
            label: 'Rock abundance',
            value: 'No data',
            valueColor: AresColors.red,
            provenance: Provenance.noData,
          ),
          DataRow(label: 'Slope limit', value: '20°'),
        ],
      ),
    );
  }
}

class _TerrainPainter extends CustomPainter {
  _TerrainPainter({
    required this.texture,
    required this.archiveTrail,
    required this.grid,
    required this.slopeGrid,
    required this.bounds,
    required this.route,
    required this.yaw,
    required this.pitch,
    required this.exaggeration,
    required this.slopeMode,
    required this.wireframe,
    required this.sunAzimuth,
    required this.sunElevation,
  });

  final ui.Image? texture;
  final List<GeoPoint> archiveTrail;
  final List<List<double>> grid;
  final List<List<double>> slopeGrid;
  final MapBounds bounds;
  final TraversePlan? route;
  final double yaw;
  final double pitch;
  final double exaggeration;
  final bool slopeMode;
  final bool wireframe;
  final double sunAzimuth;
  final double sunElevation;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackdrop(canvas, size);

    final rows = grid.length;
    final cols = grid.first.length;
    var minValue = double.infinity;
    var maxValue = -double.infinity;
    for (final row in grid) {
      for (final value in row) {
        if (value < minValue) minValue = value;
        if (value > maxValue) maxValue = value;
      }
    }
    final range = math.max(maxValue - minValue, 1.0);

    final scale = math.min(size.width, size.height) * 0.4;
    final cx = size.width * 0.5;
    final cy = size.height * 0.55;
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final sinPitch = math.sin(pitch);
    final cosPitch = math.cos(pitch);

    Offset project(double nx, double ny, double normZ) {
      final x = nx * 2 - 1;
      final y = ny * 2 - 1;
      final z = (normZ - 0.32) * 0.9 * exaggeration;
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
      final z = (normZ - 0.32) * 0.9 * exaggeration;
      final yr = x * sinYaw + y * cosYaw;
      return yr * cosPitch + z * sinPitch;
    }

    final sunAz = sunAzimuth * math.pi / 180;
    final sunEl = math.max(sunElevation, 8.0) * math.pi / 180;
    final light = (
      math.cos(sunEl) * math.sin(sunAz),
      math.cos(sunEl) * math.cos(sunAz),
      math.sin(sunEl),
    );

    final faces = <_Face>[];
    for (var y = 0; y < rows - 1; y++) {
      for (var x = 0; x < cols - 1; x++) {
        final h = grid[y][x];
        final normZ = (h - minValue) / range;
        final hx =
            (grid[y][math.min(x + 1, cols - 1)] - grid[y][math.max(x - 1, 0)]) /
            (2 * 2100);
        final hy =
            (grid[math.min(y + 1, rows - 1)][x] - grid[math.max(y - 1, 0)][x]) /
            (2 * 2100);
        final nxWorld = -hx * 6;
        final nyWorld = -hy * 6;
        final normalLength = math.sqrt(
          nxWorld * nxWorld + nyWorld * nyWorld + 1,
        );
        final dot =
            ((nxWorld / normalLength) * light.$1 +
                    (nyWorld / normalLength) * light.$2 +
                    (1 / normalLength) * light.$3)
                .clamp(-1.0, 1.0);
        final lit = 0.48 + (dot + 1) / 2 * 0.62;
        final centerNx = (x + 0.5) / (cols - 1);
        final centerNy = (y + 0.5) / (rows - 1);
        final centerZ =
            (grid[y][x] +
                grid[y + 1][x] +
                grid[y][x + 1] +
                grid[y + 1][x + 1]) /
            4;
        final depth = depthOf(centerNx, centerNy, (centerZ - minValue) / range);

        final slopeNorm = slopeMode
            ? (_slopeAt(centerNx, centerNy) / 25).clamp(0.0, 1.0)
            : 0.0;
        var baseColor = slopeMode
            ? _slopeColor(slopeNorm)
            : _elevationColor(normZ);
        if (lit < 0.75) {
          baseColor = Color.lerp(baseColor, Colors.black, (0.75 - lit) * 0.8)!;
        } else {
          baseColor = Color.lerp(baseColor, Colors.white, (lit - 0.75) * 0.35)!;
        }

        final p00 = project(
          x / (cols - 1),
          y / (rows - 1),
          (grid[y][x] - minValue) / range,
        );
        final p10 = project(
          (x + 1) / (cols - 1),
          y / (rows - 1),
          (grid[y][x + 1] - minValue) / range,
        );
        final p11 = project(
          (x + 1) / (cols - 1),
          (y + 1) / (rows - 1),
          (grid[y + 1][x + 1] - minValue) / range,
        );
        final p01 = project(
          x / (cols - 1),
          (y + 1) / (rows - 1),
          (grid[y + 1][x] - minValue) / range,
        );
        faces.add(
          _Face(
            path: Path()
              ..moveTo(p00.dx, p00.dy)
              ..lineTo(p10.dx, p10.dy)
              ..lineTo(p11.dx, p11.dy)
              ..lineTo(p01.dx, p01.dy)
              ..close(),
            color: baseColor,
            depth: depth,
            col: x,
            points: [p00, p10, p11, p01],
            row: y,
          ),
        );
      }
    }
    faces.sort((a, b) => a.depth.compareTo(b.depth));

    final edgePaint = Paint()
      ..color = AresColors.cyan.withValues(alpha: wireframe ? 0.16 : 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.45;
    final photo = texture;
    final texturePaint = photo == null
        ? null
        : (Paint()
            ..shader = ui.ImageShader(
              photo,
              TileMode.clamp,
              TileMode.clamp,
              Matrix4.identity().storage,
            )
            ..filterQuality = FilterQuality.medium);
    for (final face in faces) {
      if (photo != null) {
        final x = face.col, y = face.row;
        final uv = [
          Offset(x / (cols - 1) * photo.width, y / (rows - 1) * photo.height),
          Offset(
            (x + 1) / (cols - 1) * photo.width,
            y / (rows - 1) * photo.height,
          ),
          Offset(
            (x + 1) / (cols - 1) * photo.width,
            (y + 1) / (rows - 1) * photo.height,
          ),
          Offset(
            x / (cols - 1) * photo.width,
            (y + 1) / (rows - 1) * photo.height,
          ),
        ];
        final vertices = ui.Vertices(
          ui.VertexMode.triangles,
          face.points,
          textureCoordinates: uv,
          indices: [0, 1, 2, 0, 2, 3],
        );
        canvas.drawVertices(vertices, BlendMode.srcOver, texturePaint!);
        vertices.dispose();
      } else {
        canvas.drawPath(
          face.path,
          Paint()..color = face.color.withValues(alpha: 0.94),
        );
      }
      if (wireframe || face.col % 4 == 0) {
        canvas.drawPath(face.path, edgePaint);
      }
    }

    final archivePath = Path();
    var firstArchivePoint = true;
    for (final point in archiveTrail) {
      final nx = (point.lon - bounds.minLon) / bounds.widthDeg;
      final ny = (bounds.maxLat - point.lat) / bounds.heightDeg;
      if (nx < 0 || nx > 1 || ny < 0 || ny > 1) {
        firstArchivePoint = true;
        continue;
      }
      final x = (nx * (cols - 1)).round(), y = (ny * (rows - 1)).round();
      final p = project(nx, ny, (grid[y][x] - minValue) / range + 0.015);
      if (firstArchivePoint) {
        archivePath.moveTo(p.dx, p.dy);
        firstArchivePoint = false;
      } else {
        archivePath.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      archivePath,
      Paint()
        ..color = AresColors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (route != null) {
      _drawRoute(canvas, project, range, minValue);
    }

    _drawPeakLabel(canvas, project, range, minValue);
    _drawSunGlyph(canvas, size);
  }

  void _drawBackdrop(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.1,
          colors: [Color(0xFF0A1219), Color(0xFF06090C)],
        ).createShader(rect),
    );
  }

  Color _elevationColor(double norm) {
    if (norm < 0.45) {
      return Color.lerp(
        const Color(0xFF0B2733),
        const Color(0xFF14616A),
        norm / 0.45,
      )!;
    }
    if (norm < 0.72) {
      return Color.lerp(
        const Color(0xFF14616A),
        const Color(0xFF9B7448),
        (norm - 0.45) / 0.27,
      )!;
    }
    return Color.lerp(
      const Color(0xFF9B7448),
      const Color(0xFFE3D3B3),
      (norm - 0.72) / 0.28,
    )!;
  }

  Color _slopeColor(double norm) {
    if (norm < 0.5) {
      return Color.lerp(AresColors.green, AresColors.amber, norm / 0.5)!;
    }
    return Color.lerp(AresColors.amber, AresColors.red, (norm - 0.5) / 0.5)!;
  }

  double _slopeAt(double nx, double ny) {
    final rows = slopeGrid.length;
    final cols = slopeGrid.first.length;
    final x = (nx * (cols - 1)).round().clamp(0, cols - 1);
    final y = (ny * (rows - 1)).round().clamp(0, rows - 1);
    return slopeGrid[y][x];
  }

  void _drawRoute(
    Canvas canvas,
    Offset Function(double, double, double) project,
    double range,
    double minValue,
  ) {
    final plan = route!;
    if (plan.points.length < 2) return;
    final path = Path();
    for (var i = 0; i < plan.points.length; i++) {
      final point = plan.points[i];
      final nx = (point.lon - bounds.minLon) / bounds.widthDeg;
      final ny = (bounds.maxLat - point.lat) / bounds.heightDeg;
      final norm = ((plan.elevations[i] - minValue) / range).clamp(0.0, 1.0);
      final offset = project(nx, ny, norm + 0.02);
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AresColors.cyan.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AresColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    final first = plan.points.first;
    final last = plan.points.last;
    final startOffset = project(
      (first.lon - bounds.minLon) / bounds.widthDeg,
      (bounds.maxLat - first.lat) / bounds.heightDeg,
      ((plan.elevations.first - minValue) / range) + 0.02,
    );
    final endOffset = project(
      (last.lon - bounds.minLon) / bounds.widthDeg,
      (bounds.maxLat - last.lat) / bounds.heightDeg,
      ((plan.elevations.last - minValue) / range) + 0.02,
    );
    canvas.drawCircle(startOffset, 4, Paint()..color = AresColors.cyan);
    canvas.drawCircle(
      endOffset,
      4,
      Paint()
        ..color = AresColors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  void _drawPeakLabel(
    Canvas canvas,
    Offset Function(double, double, double) project,
    double range,
    double minValue,
  ) {
    var peakX = 0;
    var peakY = 0;
    var peak = -double.infinity;
    for (var y = 0; y < grid.length; y++) {
      for (var x = 0; x < grid.first.length; x++) {
        if (grid[y][x] > peak) {
          peak = grid[y][x];
          peakX = x;
          peakY = y;
        }
      }
    }
    final offset = project(
      peakX / (grid.first.length - 1),
      peakY / (grid.length - 1),
      (peak - minValue) / range,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: 'Aeolis Mons summit',
        style: AresType.label(size: 9.5, color: AresColors.amber, spacing: 0.3),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset + const Offset(8, -18));
    canvas.drawLine(
      offset + const Offset(0, -4),
      offset + const Offset(8, -13),
      Paint()
        ..color = AresColors.amber.withValues(alpha: 0.7)
        ..strokeWidth = 0.8,
    );
  }

  void _drawSunGlyph(Canvas canvas, Size size) {
    final center = Offset(size.width - 38, 42);
    final position =
        center +
        Offset(
          math.sin(sunAzimuth * math.pi / 180) * 12,
          -math.cos(sunAzimuth * math.pi / 180) * 12,
        );
    canvas.drawCircle(position, 3, Paint()..color = AresColors.amber);
    canvas.drawCircle(
      center,
      18,
      Paint()
        ..color = AresColors.amber.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(covariant _TerrainPainter oldDelegate) {
    return oldDelegate.texture != texture ||
        oldDelegate.archiveTrail != archiveTrail ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.exaggeration != exaggeration ||
        oldDelegate.slopeMode != slopeMode ||
        oldDelegate.wireframe != wireframe ||
        oldDelegate.route != route ||
        oldDelegate.sunAzimuth != sunAzimuth ||
        oldDelegate.sunElevation != sunElevation;
  }
}

class _Face {
  const _Face({
    required this.path,
    required this.color,
    required this.depth,
    required this.col,
    required this.row,
    required this.points,
  });

  final int row;
  final List<Offset> points;
  final Path path;
  final Color color;
  final double depth;
  final int col;
}
