import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/exploration_data.dart';
import '../models/ares_models.dart';
import '../state/ares_scope.dart';
import '../theme/ares_theme.dart';
import '../util/astro.dart';
import '../util/terrain.dart';

class AresStreetViewModal extends StatefulWidget {
  const AresStreetViewModal({
    super.key,
    required this.initialPoint,
    required this.initialLabel,
    required this.routeStops,
    required this.catalogFeatures,
    required this.customJumps,
    required this.landingSite,
    required this.plssInitO2,
    required this.plssInitBat,
    required this.plssMetabolicW,
    required this.onWalkedChanged,
    required this.onSetLandingSite,
    required this.onAddCustomJump,
    required this.onClose,
  });

  final GeoPoint initialPoint;
  final String initialLabel;
  final List<({GeoPoint point, String label})> routeStops;
  final List<SurveyFeature> catalogFeatures;
  final List<({String id, String name, GeoPoint point})> customJumps;
  final GeoPoint landingSite;
  final double plssInitO2;
  final double plssInitBat;
  final double plssMetabolicW;
  final ValueChanged<double> onWalkedChanged;
  final ValueChanged<GeoPoint> onSetLandingSite;
  final void Function(String name, GeoPoint point) onAddCustomJump;
  final VoidCallback onClose;

  @override
  State<AresStreetViewModal> createState() => _AresStreetViewModalState();
}

class _AresStreetViewModalState extends State<AresStreetViewModal> {
  late List<({GeoPoint point, String label})> _stops;
  int _activeStopIdx = 0;
  late GeoPoint _playerGeo;
  late GeoPoint _landerGeo;
  late String _currentLabel;

  String _viewMode = 'drone'; // 'drone' | 'astronaut' | 'rover' | 'overview'
  bool _fogEnabled = true;
  bool _fullscreen = false;
  double _yawDeg = 35.0;
  double _pitchDeg = -18.0;
  double _droneAltM = 45.0;
  double _walkedMeters = 0.0;

  SurfacePhoto? _selectedPhoto;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentLabel = widget.initialLabel;
    _landerGeo = widget.landingSite;
    if (widget.routeStops.isNotEmpty) {
      _stops = List.of(widget.routeStops);
      _activeStopIdx = 0;
    } else {
      _stops = _buildLocalTraverseStops(
        widget.initialPoint.lon,
        widget.initialPoint.lat,
        widget.initialLabel,
      );
      _activeStopIdx = 0;
    }
    _loadStop(0, notifyWalk: false);
  }

  List<({GeoPoint point, String label})> _buildLocalTraverseStops(
    double lon,
    double lat,
    String baseLabel,
  ) {
    final cosLat = math.max(0.2, math.cos(lat * math.pi / 180));
    final offsets = [
      (0.0, 0.0, '$baseLabel Start'),
      (25.0, 65.0, 'Ridge Check'),
      (60.0, 125.0, 'Regolith Sample'),
      (35.0, 195.0, 'Outcrop Scan'),
      (80.0, 260.0, 'EVA Goal'),
    ];
    return offsets
        .map(
          (o) => (
            point: GeoPoint(
              lon + o.$1 / (59274 * cosLat),
              lat + o.$2 / 59274,
            ),
            label: o.$3,
          ),
        )
        .toList();
  }

  void _loadStop(int idx, {bool notifyWalk = true}) {
    if (_stops.isEmpty) return;
    final clamped = idx.clamp(0, _stops.length - 1);
    final stop = _stops[clamped];
    double nextYaw = _yawDeg;
    if (clamped + 1 < _stops.length) {
      final nxt = _stops[clamped + 1].point;
      final dLon = (nxt.lon - stop.point.lon) *
          math.cos(stop.point.lat * math.pi / 180);
      final dLat = nxt.lat - stop.point.lat;
      nextYaw = (math.atan2(dLon, dLat) * 180 / math.pi + 360) % 360;
    }
    setState(() {
      _activeStopIdx = clamped;
      _playerGeo = stop.point;
      _currentLabel = stop.label;
      _yawDeg = nextYaw;
    });
    if (notifyWalk) {
      widget.onWalkedChanged(_walkedMeters);
    }
  }

  void _setViewMode(String mode) {
    setState(() {
      _viewMode = mode;
      if (mode == 'overview') {
        _droneAltM = 550.0;
        _pitchDeg = -58.0;
        if (_stops.length > 1) {
          final midLon =
              _stops.fold<double>(0, (s, e) => s + e.point.lon) / _stops.length;
          final midLat =
              _stops.fold<double>(0, (s, e) => s + e.point.lat) / _stops.length;
          _playerGeo = GeoPoint(midLon, midLat);
        }
      } else if (mode == 'astronaut' || mode == 'rover') {
        _droneAltM = mode == 'astronaut' ? 2.4 : 2.8;
        _pitchDeg = -14.0;
      } else {
        _droneAltM = 45.0;
        _pitchDeg = -22.0;
      }
    });
  }

  void _movePlayer(double forwardSign, double rightSign, {double altDelta = 0}) {
    final isGrounded = _viewMode == 'astronaut' || _viewMode == 'rover';
    final stepMeters = _viewMode == 'overview'
        ? 45.0
        : _viewMode == 'drone'
            ? 18.0
            : _viewMode == 'rover'
                ? 9.0
                : 5.5;
    final az = _yawDeg * math.pi / 180;
    final eastM = (math.sin(az) * forwardSign + math.cos(az) * rightSign) *
        stepMeters;
    final northM = (math.cos(az) * forwardSign - math.sin(az) * rightSign) *
        stepMeters;
    final cosLat = math.max(0.2, math.cos(_playerGeo.lat * math.pi / 180));
    final newLon = _playerGeo.lon + eastM / (59274 * cosLat);
    final newLat = (_playerGeo.lat + northM / 59274).clamp(-85.0, 85.0);
    final movedM = math.sqrt(eastM * eastM + northM * northM);

    setState(() {
      _playerGeo = GeoPoint(newLon, newLat);
      if (!isGrounded && altDelta != 0) {
        _droneAltM = (_droneAltM + altDelta).clamp(4.0, 900.0);
      }
      if (movedM > 0 && (_viewMode == 'drone' || isGrounded)) {
        _walkedMeters += movedM;
      }
      // Auto-advance activeStopIdx when Astronaut/Rover/Drone reaches a forward waypoint (<= 22m)
      if (_stops.length > 1 && _activeStopIdx < _stops.length - 1) {
        for (var j = _activeStopIdx + 1; j < _stops.length; j++) {
          final st = _stops[j].point;
          final sLatM = (st.lat - _playerGeo.lat) * 59274;
          final sLonM = (st.lon - _playerGeo.lon) * 59274 * cosLat;
          final distM = math.sqrt(sLatM * sLatM + sLonM * sLonM);
          if (distM <= 22.0) {
            _activeStopIdx = j;
            _currentLabel = _stops[j].label;
          } else {
            break;
          }
        }
      }
    });
    widget.onWalkedChanged(_walkedMeters);
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.keyW || k == LogicalKeyboardKey.arrowUp) {
      _movePlayer(1, 0);
    } else if (k == LogicalKeyboardKey.keyS || k == LogicalKeyboardKey.arrowDown) {
      _movePlayer(-1, 0);
    } else if (k == LogicalKeyboardKey.keyD || k == LogicalKeyboardKey.arrowRight) {
      _movePlayer(0, 1);
    } else if (k == LogicalKeyboardKey.keyA || k == LogicalKeyboardKey.arrowLeft) {
      _movePlayer(0, -1);
    } else if (k == LogicalKeyboardKey.keyE || k == LogicalKeyboardKey.space) {
      _movePlayer(0, 0, altDelta: 12);
    } else if (k == LogicalKeyboardKey.keyQ || k == LogicalKeyboardKey.shiftLeft) {
      _movePlayer(0, 0, altDelta: -12);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final terrain = state.terrain;
    final photos = state.data.photos;

    final hereSlope = terrain.slopeAt(_playerGeo.lon, _playerGeo.lat);
    final hdgInt = ((_yawDeg.round() % 360) + 360) % 360;
    final hdgCard = compass16(_yawDeg);

    final totalWps = math.max(1, _stops.length);
    final currentWpNum = math.min(totalWps, _activeStopIdx + 1);
    final remainingWps = math.max(0, totalWps - currentWpNum);
    final curStopLabel = _stops.isNotEmpty
        ? _stops[_activeStopIdx].label
        : _currentLabel;
    final isComplete = remainingWps == 0 && totalWps > 1;

    // Next stop / Lander navigation
    final routeTarget =
        (_activeStopIdx + 1 < _stops.length) ? _stops[_activeStopIdx + 1] : null;
    final navTargetPoint = routeTarget?.point ?? _landerGeo;
    final navPrefix = routeTarget != null ? 'WP ${currentWpNum + 1}' : 'LANDER';
    final cosLat = math.max(0.2, math.cos(_playerGeo.lat * math.pi / 180));
    final dLatM = (navTargetPoint.lat - _playerGeo.lat) * 59274;
    final dLonM = (navTargetPoint.lon - _playerGeo.lon) * 59274 * cosLat;
    final navDistM = math.sqrt(dLatM * dLatM + dLonM * dLonM);
    final navBrg = ((math.atan2(dLonM, dLatM) * 180 / math.pi) + 360) % 360;
    final navRel = ((navBrg - _yawDeg + 540) % 360) - 180;
    final navAligned = navRel.abs() < 20;

    // Lander distance/bearing
    final lLatM = (_landerGeo.lat - _playerGeo.lat) * 59274;
    final lLonM = (_landerGeo.lon - _playerGeo.lon) * 59274 * cosLat;
    final landerDistM = math.sqrt(lLatM * lLatM + lLonM * lLonM).round();
    final landerBrg =
        (((math.atan2(lLonM, lLatM) * 180 / math.pi) + 360) % 360).round();

    // PLSS simulation
    final workFactor = math.max(0.4, widget.plssMetabolicW / 310.0);
    final o2 = math.max(0.0, widget.plssInitO2 - _walkedMeters * 0.012 * workFactor);
    final bat = math.max(0.0, widget.plssInitBat - _walkedMeters * 0.01 * workFactor);
    final pnrOk = o2 > 35 && bat > 30;

    // Nearby features within 35 km
    final nearby = widget.catalogFeatures
        .where((f) => f.kind != 'Curiosity' && f.kind != 'Perseverance')
        .map((f) {
          final fLatM = (f.point.lat - _playerGeo.lat) * 59274;
          final fLonM = (f.point.lon - _playerGeo.lon) * 59274 * cosLat;
          final dist = math.sqrt(fLatM * fLatM + fLonM * fLonM);
          final brg = ((math.atan2(fLonM, fLatM) * 180 / math.pi) + 360) % 360;
          return (feature: f, distM: dist, bearing: brg);
        })
        .toList()
      ..sort((a, b) => a.distM.compareTo(b.distM));
    final topNearby = nearby.take(4).toList();

    final modeAction = _viewMode == 'astronaut'
        ? 'WASD walk'
        : _viewMode == 'rover'
            ? 'WASD drive'
            : 'WASD fly';
    final metaString =
        '$_currentLabel ($currentWpNum/$totalWps) · ${_playerGeo.lat.toStringAsFixed(4)}°, ${_playerGeo.lon.toStringAsFixed(4)}° · 5×5 Chunks: 25/25 · $modeAction';

    final altM = (_viewMode == 'astronaut' || _viewMode == 'rover')
        ? 2.6
        : _droneAltM;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Container(
        color: AresColors.bg0,
        child: Column(
          children: [
            // Street View Header (.modal-header)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: const BoxDecoration(
                color: Color(0xF0121214),
                border: Border(bottom: BorderSide(color: AresColors.line)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  // .modal-title-group
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      const Text(
                        'Mars 360° Street View',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AresColors.text,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AresColors.surfaceControl,
                          border: Border.all(color: AresColors.line),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'HDG ${hdgInt.toString().padLeft(3, '0')}° $hdgCard',
                          style: AresType.monoStyle(
                            size: 10.5,
                            color: AresColors.textSecondary,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // #sv-wp-badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AresColors.greenTint,
                          border: Border.all(
                            color: const Color(0x4D30D158),
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.mapPin,
                              size: 12,
                              color: AresColors.green,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isComplete
                                  ? 'WP $currentWpNum / $totalWps · COMPLETE'
                                  : 'WP $currentWpNum / $totalWps · $remainingWps Left',
                              style: AresType.monoStyle(
                                size: 10.5,
                                color: AresColors.green,
                                weight: FontWeight.w600,
                              ),
                            ),
                            if (isComplete) ...[
                              const SizedBox(width: 3),
                              const Icon(
                                LucideIcons.check,
                                size: 11,
                                color: AresColors.green,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        metaString,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AresColors.muted,
                        ),
                      ),
                    ],
                  ),
                  // .modal-controls
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      // iOS Segmented Group: Drone | Astronaut | Rover | Overview
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0x0EFFFFFF),
                          border: Border.all(color: AresColors.line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SegButton(
                              icon: LucideIcons.plane,
                              label: 'Drone',
                              active: _viewMode == 'drone',
                              onTap: () => _setViewMode('drone'),
                            ),
                            _SegButton(
                              icon: LucideIcons.userRound,
                              label: 'Astronaut',
                              active: _viewMode == 'astronaut',
                              onTap: () => _setViewMode('astronaut'),
                            ),
                            _SegButton(
                              icon: LucideIcons.carFront,
                              label: 'Rover',
                              active: _viewMode == 'rover',
                              onTap: () => _setViewMode('rover'),
                            ),
                            _SegButton(
                              icon: LucideIcons.map,
                              label: 'Overview',
                              active: _viewMode == 'overview',
                              onTap: () => _setViewMode('overview'),
                            ),
                          ],
                        ),
                      ),
                      _SvHeaderButton(
                        icon: LucideIcons.cloudFog,
                        label: _fogEnabled ? 'Dust Fog: ON' : 'Dust Fog: OFF',
                        active: _fogEnabled,
                        onTap: () => setState(() => _fogEnabled = !_fogEnabled),
                      ),
                      _SvHeaderButton(
                        icon: LucideIcons.rocket,
                        label: 'Set Landing Site',
                        onTap: () {
                          setState(() => _landerGeo = _playerGeo);
                          widget.onSetLandingSite(_playerGeo);
                        },
                      ),
                      // Prev / Next Segmented Group
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0x0EFFFFFF),
                          border: Border.all(color: AresColors.line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SegButton(
                              icon: LucideIcons.chevronLeft,
                              label: 'Prev',
                              active: false,
                              onTap: () => _loadStop(_activeStopIdx - 1),
                            ),
                            _SegButton(
                              icon: LucideIcons.chevronRight,
                              label: 'Next',
                              iconRight: true,
                              active: false,
                              onTap: () => _loadStop(_activeStopIdx + 1),
                            ),
                          ],
                        ),
                      ),
                      _SvHeaderButton(
                        label: '+ Mark',
                        onTap: () => widget.onAddCustomJump(
                          'SV Stop ${_stops.length + 1}',
                          _playerGeo,
                        ),
                      ),
                      _SvHeaderButton(
                        icon: _fullscreen
                            ? LucideIcons.minimize2
                            : LucideIcons.maximize2,
                        label: _fullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                        active: _fullscreen,
                        onTap: () => setState(() => _fullscreen = !_fullscreen),
                      ),
                      _SvHeaderButton(
                        icon: LucideIcons.x,
                        label: 'Close',
                        onTap: widget.onClose,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 3D Canvas & HUD Overlays (.modal-canvas-wrap)
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 3D Street View Surface Painter
                  GestureDetector(
                    onPanUpdate: (d) {
                      setState(() {
                        _yawDeg = (_yawDeg + d.delta.dx * 0.28 + 360) % 360;
                        _pitchDeg = (_pitchDeg - d.delta.dy * 0.22).clamp(
                          -68.0,
                          35.0,
                        );
                      });
                    },
                    child: CustomPaint(
                      painter: _MarsStreetView3DPainter(
                        terrain: terrain,
                        playerGeo: _playerGeo,
                        landerGeo: _landerGeo,
                        stops: _stops,
                        activeStopIdx: _activeStopIdx,
                        nearbyFeatures: topNearby,
                        yawDeg: _yawDeg,
                        pitchDeg: _pitchDeg,
                        altitudeM: altM,
                        viewMode: _viewMode,
                        fogEnabled: _fogEnabled,
                      ),
                    ),
                  ),

                  // Top-Center 3D Compass Navigation Pill (#sv-nav-arrow)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xE0121215),
                            border: Border.all(color: AresColors.lineHot),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x73000000),
                                blurRadius: 16,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.rotate(
                                angle: navRel * math.pi / 180,
                                child: Icon(
                                  LucideIcons.navigation2,
                                  size: 15,
                                  color: navAligned
                                      ? AresColors.green
                                      : AresColors.amber,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                navAligned
                                    ? '$navPrefix AHEAD · ${navDistM.round()} m'
                                    : '$navPrefix ${navRel > 0 ? 'RIGHT' : 'LEFT'} ${navRel.abs().round()}° · ${navDistM.round()} m',
                                style: AresType.monoStyle(
                                  size: 11,
                                  color: AresColors.text,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Top-Left Visor HUD (#sv-visor-hud)
                  Positioned(
                    top: 12,
                    left: 12,
                    width: 248,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 540),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xD6121215),
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
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // EVA SAFETY
                              _VisorRow(
                                label: 'EVA SAFETY',
                                trailing: _StatusPill(
                                  label: hereSlope >= 25
                                      ? 'HAZARD · ${hereSlope.toStringAsFixed(1)}°'
                                      : hereSlope >= 15
                                          ? 'CAUTION · ${hereSlope.toStringAsFixed(1)}°'
                                          : 'NOMINAL · ${hereSlope.toStringAsFixed(1)}°',
                                  tone: hereSlope >= 25
                                      ? _PillTone.hazard
                                      : hereSlope >= 15
                                          ? _PillTone.caution
                                          : _PillTone.ok,
                                ),
                              ),
                              // CURRENT WP
                              _VisorRow(
                                label: 'CURRENT WP',
                                value:
                                    'WP $currentWpNum / $totalWps · $curStopLabel',
                              ),
                              // WAYPOINTS LEFT
                              _VisorRow(
                                label: 'WAYPOINTS LEFT',
                                trailing: _StatusPill(
                                  label: isComplete
                                      ? '0 Remaining · Complete ✓'
                                      : '$remainingWps Remaining',
                                  tone: remainingWps > 0
                                      ? _PillTone.caution
                                      : _PillTone.ok,
                                ),
                              ),
                              // #visor-wp-progress (Progress Bar + Clickable Chips)
                              Container(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x0AFFFFFF),
                                  border: Border.all(color: AresColors.line),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: totalWps > 1
                                            ? currentWpNum / totalWps
                                            : 1.0,
                                        minHeight: 4,
                                        backgroundColor:
                                            const Color(0x1FFFFFFF),
                                        color: AresColors.green,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: [
                                        for (var i = 0;
                                            i < _stops.length;
                                            i++)
                                          _WpChipButton(
                                            index: i,
                                            activeStopIdx: _activeStopIdx,
                                            tooltip:
                                                'Jump to WP ${i + 1}: ${_stops[i].label}',
                                            onTap: () => _loadStop(i),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // NEXT STOP
                              _VisorRow(
                                label: 'NEXT STOP',
                                value: routeTarget != null
                                    ? 'WP ${currentWpNum + 1} · ${navDistM.round()} m @ ${navBrg.round().toString().padLeft(3, '0')}°'
                                    : totalWps > 1
                                        ? 'All Waypoints Reached ✓'
                                        : 'Free Roam',
                              ),
                              // PLSS O2 / BAT
                              _VisorRow(
                                label: 'PLSS O₂ / BAT',
                                value:
                                    '${o2.toStringAsFixed(0)}% · ${bat.toStringAsFixed(0)}%',
                              ),
                              // WALKED / PNR
                              _VisorRow(
                                label: 'WALKED / PNR',
                                value:
                                    '${_walkedMeters.round()} m · ${pnrOk ? 'PNR OK' : 'RETURN NOW'}',
                              ),
                              // ROCKET LANDER
                              _VisorRow(
                                label: 'ROCKET LANDER',
                                value:
                                    '$landerDistM m @ ${landerBrg.toString().padLeft(3, '0')}°',
                              ),
                              // NEARBY AREA INTEL
                              if (topNearby.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.only(top: 6),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: AresColors.line),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'NEARBY AREA INTEL (${nearby.length})',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.4,
                                          color: AresColors.muted,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      for (final nf in topNearby)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 4),
                                          child: InkWell(
                                            onTap: () => setState(() {
                                              _yawDeg = nf.bearing;
                                              _pitchDeg = -10.0;
                                            }),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    const Color(0x0BFFFFFF),
                                                border: Border.all(
                                                  color: AresColors.line,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Row(
                                                      children: [
                                                        const Icon(
                                                          LucideIcons.camera,
                                                          size: 11,
                                                          color: AresColors
                                                              .textSecondary,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            nf.feature.name,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize:
                                                                      10.5,
                                                                  color:
                                                                      AresColors
                                                                          .text,
                                                                ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    '${nf.distM < 1000 ? '${nf.distM.round()}m' : '${(nf.distM / 1000).toStringAsFixed(1)}km'} @ ${nf.bearing.round()}°',
                                                    style: AresType.monoStyle(
                                                      size: 10,
                                                      color: AresColors.muted,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Top-Right Photo Preview (#sv-photo-preview)
                  if (_selectedPhoto != null)
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
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '360° Panorama · ${_selectedPhoto!.nasaId} · ${_selectedPhoto!.location}',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AresColors.muted,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                InkWell(
                                  onTap: () =>
                                      setState(() => _selectedPhoto = null),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AresColors.surfaceControl,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: const Text(
                                      'Hide',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AresColors.text,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.asset(
                                _selectedPhoto!.asset,
                                height: 118,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Bottom-Left Controls Guide + Touch Walk Pad
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xD1121215),
                            border: Border.all(color: AresColors.line),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Controls: Drag = Look Around · W A S D / Arrows = Move · E/Q = Up/Down',
                            style: TextStyle(
                              fontSize: 11,
                              color: AresColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Tablet Touch Walk Buttons
                        _SvHeaderButton(
                          icon: LucideIcons.arrowUp,
                          label: 'Forward',
                          onTap: () => _movePlayer(1, 0),
                        ),
                        const SizedBox(width: 4),
                        _SvHeaderButton(
                          icon: LucideIcons.arrowDown,
                          label: 'Back',
                          onTap: () => _movePlayer(-1, 0),
                        ),
                      ],
                    ),
                  ),

                  // Bottom-Right Scale Bar (#sv-scale-bar)
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
                              '90px ≈ ${(altM * 1.4).round()} m · ALT ${altM.toStringAsFixed(1)} m · 1 Chunk = 4.7 km',
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
                ],
              ),
            ),

            // Bottom Filmstrip (#sv-filmstrip)
            Container(
              height: 92,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF0C0C0E),
                border: Border(top: BorderSide(color: AresColors.line)),
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final p = photos[i];
                  final az = (95 + i * 68) % 360;
                  return InkWell(
                    onTap: () => setState(() {
                      _selectedPhoto = p;
                      _yawDeg = az.toDouble();
                      _pitchDeg = -8.0;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 132,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AresColors.surfaceControl,
                        border: Border.all(
                          color: _selectedPhoto?.nasaId == p.nasaId
                              ? AresColors.blue
                              : AresColors.line,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: Image.asset(
                                p.asset,
                                width: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '360° PANO · ${p.nasaId} · $az°',
                            style: AresType.monoStyle(
                              size: 9.5,
                              color: AresColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarsStreetView3DPainter extends CustomPainter {
  _MarsStreetView3DPainter({
    required this.terrain,
    required this.playerGeo,
    required this.landerGeo,
    required this.stops,
    required this.activeStopIdx,
    required this.nearbyFeatures,
    required this.yawDeg,
    required this.pitchDeg,
    required this.altitudeM,
    required this.viewMode,
    required this.fogEnabled,
  });

  final TerrainModel terrain;
  final GeoPoint playerGeo;
  final GeoPoint landerGeo;
  final List<({GeoPoint point, String label})> stops;
  final int activeStopIdx;
  final List<({SurveyFeature feature, double distM, double bearing})>
      nearbyFeatures;
  final double yawDeg;
  final double pitchDeg;
  final double altitudeM;
  final String viewMode;
  final bool fogEnabled;

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = (size.height * (0.44 - pitchDeg / 95.0)).clamp(
      size.height * 0.12,
      size.height * 0.85,
    );

    // Martian Sky & Dust Haze Gradient
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: fogEnabled
              ? const [Color(0xFF23140E), Color(0xFF7D4B34), Color(0xFFB57756)]
              : const [Color(0xFF0E0908), Color(0xFF3A2218), Color(0xFF6B422E)],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Offset.zero & size),
    );

    // Ground base below horizon
    canvas.drawRect(
      Rect.fromLTRB(0, horizon, size.width, size.height),
      Paint()..color = const Color(0xFF5D3928),
    );

    final az = yawDeg * math.pi / 180;
    final cosA = math.cos(az);
    final sinA = math.sin(az);
    final cosLat = math.max(0.2, math.cos(playerGeo.lat * math.pi / 180));
    final eyeGroundZ = terrain.elevationAt(playerGeo.lon, playerGeo.lat);
    final eyeZ = eyeGroundZ + altitudeM;
    final focal = size.width * 0.72;

    (Offset, double) project3D(double eastM, double northM, double z) {
      final depth = northM * cosA + eastM * sinA;
      final right = eastM * cosA - northM * sinA;
      final d = math.max(1.5, depth);
      return (
        Offset(
          size.width * 0.5 + (right / d) * focal,
          horizon - ((z - eyeZ) / d) * focal,
        ),
        depth,
      );
    }

    // 3D Terrain Mesh Tiles
    final stepM = viewMode == 'overview' ? 32.0 : 12.0;
    final faces = <({Path path, double depth, Color color})>[];
    for (var row = 1; row < 32; row++) {
      for (var col = -18; col < 18; col++) {
        final corners = <Offset>[];
        var sumDepth = 0.0;
        var sumZ = 0.0;
        for (final d in [
          (col, row),
          (col + 1, row),
          (col + 1, row + 1),
          (col, row + 1),
        ]) {
          final fwd = d.$2 * stepM;
          final rgt = d.$1 * stepM;
          final eastM = fwd * sinA + rgt * cosA;
          final northM = fwd * cosA - rgt * sinA;
          final lon = playerGeo.lon + eastM / (59274 * cosLat);
          final lat = playerGeo.lat + northM / 59274;
          final z = terrain.elevationAt(lon, lat);
          final p = project3D(eastM, northM, z);
          corners.add(p.$1);
          sumDepth += p.$2;
          sumZ += z;
        }
        final avgDepth = sumDepth * 0.25;
        final relZ = ((sumZ * 0.25 - eyeGroundZ + 35) / 70).clamp(0.0, 1.0);
        var tileColor = Color.lerp(
          const Color(0xFF4F2E1E),
          const Color(0xFFA66B49),
          relZ,
        )!;
        if (fogEnabled) {
          final fogFactor = (avgDepth / (stepM * 34)).clamp(0.0, 0.72);
          tileColor = Color.lerp(tileColor, const Color(0xFF9E6447), fogFactor)!;
        }
        final path = Path()..addPolygon(corners, true);
        faces.add((path: path, depth: avgDepth, color: tileColor));
      }
    }

    faces.sort((a, b) => b.depth.compareTo(a.depth));
    for (final f in faces) {
      canvas.drawPath(f.path, Paint()..color = f.color);
      canvas.drawPath(
        f.path,
        Paint()
          ..color = const Color(0x16000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }

    // 3D Green EVA Route Path + Flush Yellow Directional Cones + Waypoint Beacons
    if (stops.isNotEmpty) {
      final projectedStops = <({Offset screen, double depth, int idx})>[];
      for (var i = 0; i < stops.length; i++) {
        final s = stops[i].point;
        final eastM = (s.lon - playerGeo.lon) * 59274 * cosLat;
        final northM = (s.lat - playerGeo.lat) * 59274;
        final z = terrain.elevationAt(s.lon, s.lat) + 0.35;
        final p = project3D(eastM, northM, z);
        projectedStops.add((screen: p.$1, depth: p.$2, idx: i));
      }

      // Route Tube
      for (var i = 0; i < projectedStops.length - 1; i++) {
        final a = projectedStops[i];
        final b = projectedStops[i + 1];
        if (a.depth < 2 && b.depth < 2) continue;
        canvas.drawLine(
          a.screen,
          b.screen,
          Paint()
            ..color = const Color(0xFF14532D)
            ..strokeWidth = 6.0
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawLine(
          a.screen,
          b.screen,
          Paint()
            ..color = AresColors.green
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round,
        );

        // Flush yellow directional cone on route tube midpoint (matching chunks3d.js fix)
        final mid = Offset.lerp(a.screen, b.screen, 0.5)!;
        final dir = b.screen - a.screen;
        final len = dir.distance;
        if (len > 18) {
          final u = dir / len;
          final perp = Offset(-u.dy, u.dx);
          final cone = Path()
            ..moveTo(mid.dx + u.dx * 7, mid.dy + u.dy * 7)
            ..lineTo(
              mid.dx - u.dx * 5 + perp.dx * 4.5,
              mid.dy - u.dy * 5 + perp.dy * 4.5,
            )
            ..lineTo(
              mid.dx - u.dx * 5 - perp.dx * 4.5,
              mid.dy - u.dy * 5 - perp.dy * 4.5,
            )
            ..close();
          canvas.drawPath(cone, Paint()..color = const Color(0xFFFACC15));
        }
      }

      // Waypoint Vertical Beacons
      for (final ps in projectedStops) {
        if (ps.depth < 2.5) continue;
        if (ps.screen.dx < -40 || ps.screen.dx > size.width + 40) continue;
        final h = (focal * 4.2 / ps.depth).clamp(16.0, 68.0);
        final color = ps.idx == 0
            ? AresColors.green
            : ps.idx == stops.length - 1
                ? AresColors.amber
                : ps.idx == activeStopIdx
                    ? Colors.white
                    : AresColors.blue;
        final top = ps.screen - Offset(0, h);
        canvas.drawLine(
          ps.screen,
          top,
          Paint()
            ..color = color
            ..strokeWidth = 2.2,
        );
        canvas.drawCircle(top, 4.5, Paint()..color = color);
      }
    }

    // 3D Rocket Lander Beacon
    {
      final eastM = (landerGeo.lon - playerGeo.lon) * 59274 * cosLat;
      final northM = (landerGeo.lat - playerGeo.lat) * 59274;
      final z = terrain.elevationAt(landerGeo.lon, landerGeo.lat);
      final p = project3D(eastM, northM, z);
      if (p.$2 > 3 && p.$1.dx > 0 && p.$1.dx < size.width) {
        final h = (focal * 9.0 / p.$2).clamp(24.0, 88.0);
        canvas.drawLine(
          p.$1,
          p.$1 - Offset(0, h),
          Paint()
            ..color = const Color(0xFFF87171)
            ..strokeWidth = 2.5,
        );
        canvas.drawCircle(
          p.$1 - Offset(0, h),
          5.5,
          Paint()..color = AresColors.amber,
        );
      }
    }

    // 3D Avatar in Astronaut or Rover Third-Person Mode
    if (viewMode == 'astronaut' || viewMode == 'rover') {
      final avatarPos = Offset(size.width * 0.5, size.height * 0.78);
      if (viewMode == 'astronaut') {
        // Clean Astronaut Suit Silhouette
        canvas.drawCircle(
          avatarPos + const Offset(0, 18),
          18,
          Paint()..color = const Color(0x55000000),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: avatarPos, width: 22, height: 30),
            const Radius.circular(6),
          ),
          Paint()..color = const Color(0xFFE2E8F0),
        );
        canvas.drawCircle(
          avatarPos - const Offset(0, 22),
          10,
          Paint()..color = const Color(0xFFF8FAFC),
        );
        canvas.drawCircle(
          avatarPos - const Offset(0, 22),
          6.5,
          Paint()..color = const Color(0xFFD97706),
        );
      } else {
        // 6-Wheel Mars Rover Chassis
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: avatarPos, width: 48, height: 22),
            const Radius.circular(5),
          ),
          Paint()..color = const Color(0xFFE2E8F0),
        );
        for (final dx in [-22.0, 0.0, 22.0]) {
          canvas.drawCircle(
            avatarPos + Offset(dx, 14),
            6,
            Paint()..color = const Color(0xFF27272A),
          );
        }
        canvas.drawLine(
          avatarPos - const Offset(-10, 11),
          avatarPos - const Offset(-10, 28),
          Paint()
            ..color = const Color(0xFFFACC15)
            ..strokeWidth = 2.5,
        );
        canvas.drawCircle(
          avatarPos - const Offset(-10, 29),
          4.5,
          Paint()..color = AresColors.blue,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MarsStreetView3DPainter old) => true;
}

class _VisorRow extends StatelessWidget {
  const _VisorRow({required this.label, this.value, this.trailing});

  final String label;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: AresColors.muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (trailing != null)
            Flexible(child: trailing!)
          else
            Flexible(
              child: Text(
                value ?? '--',
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: AresType.monoStyle(
                  size: 11,
                  color: AresColors.text,
                  weight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _PillTone { ok, caution, hazard }

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final _PillTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (tone) {
      _PillTone.ok => (
        AresColors.greenTint,
        AresColors.green,
        const Color(0x4730D158),
      ),
      _PillTone.caution => (
        AresColors.amberTint,
        AresColors.amber,
        const Color(0x4DFF9F0A),
      ),
      _PillTone.hazard => (
        AresColors.redTint,
        AresColors.red,
        const Color(0x59FF453A),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _WpChipButton extends StatelessWidget {
  const _WpChipButton({
    required this.index,
    required this.activeStopIdx,
    required this.tooltip,
    required this.onTap,
  });

  final int index;
  final int activeStopIdx;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDone = index < activeStopIdx;
    final isCurrent = index == activeStopIdx;
    final bg = isCurrent
        ? AresColors.blueTint
        : isDone
            ? AresColors.greenTint
            : const Color(0x0DFFFFFF);
    final border = isCurrent
        ? const Color(0x800A84FF)
        : isDone
            ? const Color(0x5930D158)
            : AresColors.line;
    final fg = isCurrent
        ? Colors.white
        : isDone
            ? AresColors.green
            : AresColors.textSecondary;
    final icon = isDone
        ? LucideIcons.check
        : isCurrent
            ? LucideIcons.circleDot
            : LucideIcons.circle;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 10, color: fg),
              const SizedBox(width: 3),
              Text(
                'WP${index + 1}',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
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

class _SegButton extends StatelessWidget {
  const _SegButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.iconRight = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool iconRight;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : AresColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0x29FFFFFF) : Colors.transparent,
          border: Border.all(
            color: active ? const Color(0x1FFFFFFF) : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!iconRight) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
            if (iconRight) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 13, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}

class _SvHeaderButton extends StatelessWidget {
  const _SvHeaderButton({
    this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bg = active ? AresColors.blueTint : AresColors.surfaceControl;
    final border = active ? const Color(0x610A84FF) : AresColors.line;
    final fg = active ? const Color(0xFF64B5F6) : AresColors.text;

    return InkWell(
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
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

