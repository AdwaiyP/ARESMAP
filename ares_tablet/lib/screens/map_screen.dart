import 'package:flutter/material.dart' hide DataRow;

import '../models/ares_models.dart';
import '../state/ares_scope.dart';
import '../theme/ares_theme.dart';
import '../util/astro.dart';
import '../widgets/hud.dart';
import '../widgets/mars_map.dart';
import '../widgets/panels.dart';
import 'exploration_screen.dart';
import 'eva_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final TransformationController _controller = TransformationController();
  Size _viewport = Size.zero;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final current = _controller.value.getMaxScaleOnAxis();
    final scale = (current * factor).clamp(1.0, 4.5);
    if (scale == 1) {
      _controller.value = Matrix4.identity();
      return;
    }
    final center = _viewport.center(Offset.zero);
    _controller.value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            Positioned.fill(
              child: MouseRegion(
                cursor: state.routeMode
                    ? SystemMouseCursors.precise
                    : SystemMouseCursors.basic,
                child: MarsMap(
                  rightInset: 318,
                  controller: _controller,
                  onTapGeo: state.handleMapTap,
                ),
              ),
            ),
            Positioned(left: 86, top: 12, width: 470, child: _MapHeader()),
            Positioned(left: 16, top: 104, child: _MapTools()),
            Positioned(
              left: 16,
              bottom: 16,
              child: _ZoomControls(
                onZoomIn: () => _zoom(1.35),
                onZoomOut: () => _zoom(1 / 1.35),
                onFit: () => _controller.value = Matrix4.identity(),
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              bottom: 12,
              width: 300,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _FocusInspector(
                      onCenter: () => _controller.value = Matrix4.identity(),
                    ),
                    const SizedBox(height: 10),
                    const TraverseCard(showActions: false, dense: true),
                    const SizedBox(height: 10),
                    const _MapStatusPanel(),
                  ],
                ),
              ),
            ),
            Positioned(left: 86, top: 172, width: 470, child: _MapHint()),
          ],
        );
      },
    );
  }
}

class _MapHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      decoration: BoxDecoration(
        color: AresColors.bg0.withValues(alpha: 0.92),
        border: Border.all(color: AresColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SURFACE MAP',
                style: AresType.displayStyle(size: 23, spacing: 0.8),
              ),
              const Spacer(),
              const ProvenancePill(Provenance.archive, compact: true),
              const SizedBox(width: 5),
              const ProvenancePill(Provenance.derived, compact: true),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Gale Crater · Aeolis Palus · tap a feature to inspect it',
            style: AresType.monoStyle(size: 9.5, color: AresColors.dim),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: AresButton(
                  label: 'Explore Mars',
                  icon: Icons.public,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ExplorationScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AresButton(
                  label: 'Local EVA planner',
                  icon: Icons.directions_walk,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const EvaScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              for (var i = 0; i < marsMapLayers.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                ChipToggle(
                  label: marsMapLayers[i].shortTitle,
                  selected: state.mapLayer == i,
                  onTap: () => state.setMapLayer(i),
                ),
              ],
              const Spacer(),
              if (state.routeMode)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AresColors.amber.withValues(alpha: 0.12),
                    border: Border.all(
                      color: AresColors.amber.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'Pick a destination',
                    style: AresType.label(
                      size: 9.5,
                      color: AresColors.amber,
                      spacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapTools extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AresColors.bg0.withValues(alpha: 0.92),
        border: Border.all(color: AresColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          _MapTool(
            icon: Icons.alt_route,
            tooltip: 'Plan a route: tap the map to set a destination',
            active: state.routeMode,
            accent: AresColors.amber,
            onTap: state.toggleRouteMode,
          ),
          const SizedBox(height: 4),
          _MapTool(
            icon: Icons.center_focus_weak,
            tooltip: 'Inspect features: tap a landmark or thermal stamp',
            active: !state.routeMode,
            onTap: () {
              if (state.routeMode) state.toggleRouteMode();
            },
          ),
          const SizedBox(height: 4),
          Container(width: 24, height: 1, color: AresColors.line),
          const SizedBox(height: 4),
          _MapTool(
            icon: Icons.grain,
            tooltip: 'THEMIS thermal stamps',
            active: state.showThemis,
            onTap: state.toggleThemis,
          ),
          const SizedBox(height: 4),
          _MapTool(
            icon: Icons.warning_amber_rounded,
            tooltip: 'Slope overlay',
            active: state.showSlope,
            accent: AresColors.amber,
            onTap: state.toggleSlope,
          ),
          const SizedBox(height: 4),
          _MapTool(
            icon: Icons.radar,
            tooltip: 'Return-limit (PNR) ring',
            active: state.showPnr,
            accent: AresColors.amber,
            onTap: state.togglePnr,
          ),
          const SizedBox(height: 4),
          _MapTool(
            icon: Icons.history,
            tooltip: 'Archive traverse',
            active: state.showArchive,
            accent: AresColors.amber,
            onTap: state.toggleArchive,
          ),
        ],
      ),
    );
  }
}

class _MapTool extends StatelessWidget {
  const _MapTool({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.accent = AresColors.cyan,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: active
                    ? accent.withValues(alpha: 0.55)
                    : AresColors.line,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: active ? accent : AresColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusInspector extends StatelessWidget {
  const _FocusInspector({required this.onCenter});

  final VoidCallback onCenter;

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final focus = state.focus;
    return HudPanel(
      title: 'TARGET INSPECTOR',
      trailing: ProvenancePill(focus.provenance, compact: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            focus.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AresType.displayStyle(size: 18, spacing: 0.3),
          ),
          const SizedBox(height: 3),
          Text(
            formatCoordinate(GeoPoint(focus.lon, focus.lat)),
            style: AresType.monoStyle(size: 10, color: AresColors.muted),
          ),
          const SizedBox(height: 8),
          if (focus.tempC != null || focus.albedo != null)
            Row(
              children: [
                Expanded(
                  child: Metric(
                    label: 'Surface temp',
                    value: focus.tempC?.toStringAsFixed(1) ?? '—',
                    unit: '°C',
                    color: AresColors.amber,
                    size: 17,
                  ),
                ),
                Expanded(
                  child: Metric(
                    label: 'Albedo',
                    value: focus.albedo?.toStringAsFixed(3) ?? '—',
                    size: 17,
                  ),
                ),
                Expanded(
                  child: Metric(
                    label: 'Frame',
                    value: focus.frameType ?? '—',
                    size: 17,
                    color: AresColors.cyan,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: DataRow(
                    label: 'Category',
                    value: focus.kind,
                    provenance: Provenance.archive,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 7),
          Text(
            focus.detail,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AresType.bodyMuted.copyWith(fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: AresButton(
                  label: 'Route to target',
                  icon: Icons.alt_route,
                  primary: true,
                  expanded: true,
                  onTap: () {
                    state.replanToFocus();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Route planned to ${focus.name} · '
                          '${state.route!.distanceKm.toStringAsFixed(2)} km · '
                          'computed on device',
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              AresButton(
                label: 'Center',
                icon: Icons.filter_center_focus,
                onTap: onCenter,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Tap a thermal dot or landmark to inspect it. Colors show surface '
            'temperature from −110 to +10 °C (archived THEMIS data).',
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

class _MapStatusPanel extends StatelessWidget {
  const _MapStatusPanel();

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return HudPanel(
      title: 'MAP STATUS',
      trailing: const ProvenancePill(Provenance.archive, compact: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataRow(label: 'Thermal stamps', value: '${state.stamps.length}'),
          DataRow(label: 'Landmarks', value: '${state.references.length}'),
          DataRow(
            label: 'Elevation grid',
            value:
                '${state.terrain.displayGrid.first.length} × '
                '${state.terrain.displayGrid.length}',
            provenance: Provenance.model,
          ),
          DataRow(
            label: 'Route cell size',
            value: state.route == null
                ? '—'
                : '${state.route!.cellSizeM.round()} m',
            provenance: Provenance.derived,
          ),
          DataRow(
            label: 'Route solver',
            value: state.routeSolverLabel,
            provenance: state.routeSolvedByBackend
                ? Provenance.live
                : Provenance.derived,
          ),
          DataRow(
            label: 'Backend link',
            value: state.backend == null
                ? 'NOT LINKED'
                : state.backendOnline
                ? 'ONLINE'
                : state.backendChecked
                ? 'OFFLINE'
                : 'CHECKING',
            provenance: state.backendOnline
                ? Provenance.live
                : Provenance.noData,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '−110°C',
                style: AresType.monoStyle(size: 9.5, color: AresColors.dim),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF2F6BFF),
                        AresColors.cyan,
                        AresColors.amber,
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '+10°C',
                style: AresType.monoStyle(size: 9.5, color: AresColors.dim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AresColors.bg0.withValues(alpha: 0.92),
        border: Border.all(color: AresColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(icon: Icons.add, tooltip: 'Zoom in', onTap: onZoomIn),
          _ZoomButton(
            icon: Icons.remove,
            tooltip: 'Zoom out',
            onTap: onZoomOut,
          ),
          _ZoomButton(
            icon: Icons.center_focus_strong,
            tooltip: 'Fit map',
            onTap: onFit,
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 18, color: AresColors.muted),
          ),
        ),
      ),
    );
  }
}

class _MapHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final route = state.route;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AresColors.bg0.withValues(alpha: 0.9),
        border: Border.all(color: AresColors.line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          StatusDot(
            color: state.routeMode ? AresColors.amber : AresColors.cyan,
            size: 6,
            pulse: state.routeMode,
          ),
          const SizedBox(width: 7),
          Text(
            state.routeMode
                ? 'Route mode · tap map to set destination'
                : 'Inspect mode · tap a feature',
            style: AresType.label(
              size: 10,
              color: state.routeMode ? AresColors.amber : AresColors.cyan,
              spacing: 0.3,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              route == null
                  ? 'No active traverse'
                  : '${route.distanceKm.toStringAsFixed(2)} km · '
                        '${route.durationLabel} · max slope '
                        '${route.maxSlopeDeg.toStringAsFixed(1)}°',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AresType.monoStyle(size: 10, color: AresColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
