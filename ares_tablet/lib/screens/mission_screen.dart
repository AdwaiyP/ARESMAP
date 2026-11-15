import 'package:flutter/material.dart';

import '../models/ares_models.dart';
import '../state/ares_scope.dart';
import '../theme/ares_theme.dart';
import '../util/astro.dart';
import '../widgets/hud.dart';
import '../widgets/mars_map.dart';
import '../widgets/panels.dart';

class MissionScreen extends StatelessWidget {
  const MissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        children: [
          _MissionHeader(),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 292,
                  child: SingleChildScrollView(
                    child: Column(
                      children: const [
                        MissionObjectivesPanel(),
                        SizedBox(height: 10),
                        PnrPanel(),
                        SizedBox(height: 10),
                        AlertPanel(limit: 3),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _MapPreviewCard()),
                      const SizedBox(height: 10),
                      const TraverseCard(),
                      const SizedBox(height: 10),
                      const QuickActions(),
                      const SizedBox(height: 10),
                      const EnvironmentStrip(),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 302,
                  child: SingleChildScrollView(
                    child: Column(
                      children: const [
                        PlssPanel(),
                        SizedBox(height: 10),
                        WeatherPanel(),
                        SizedBox(height: 10),
                        CommsPanel(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const AlertTicker(),
        ],
      ),
    );
  }
}

class _MissionHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return SizedBox(
      height: 42,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'MISSION CONTROL',
                style: AresType.displayStyle(size: 25, spacing: 0.8),
              ),
              const SizedBox(height: 2),
              Text(
                'Gale Crater · Aeolis Palus · MSL Curiosity',
                style: AresType.label(
                  size: 9.5,
                  color: AresColors.muted,
                  spacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              border: Border.all(color: AresColors.cyan.withValues(alpha: 0.4)),
              color: AresColors.cyan.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              'SURFACE OPS · EVA WINDOW',
              style: AresType.label(
                size: 9,
                color: AresColors.cyan,
                spacing: 0.5,
              ),
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'SITREP · ${state.marsClock.mtc} MTC',
                style: AresType.monoStyle(size: 11, color: AresColors.text),
              ),
              const SizedBox(height: 2),
              Text(
                'Sun ${state.sun.azimuthDeg.round().toString().padLeft(3, '0')}° / '
                'el ${state.sun.elevationDeg.toStringAsFixed(0)}° · '
                '${formatCoordinate(state.current)}',
                style: AresType.monoStyle(size: 9.5, color: AresColors.dim),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 26, color: AresColors.line),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'CREW 03',
                style: AresType.label(
                  size: 9.5,
                  color: AresColors.dim,
                  spacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: const [
                  StatusDot(color: AresColors.green, size: 5),
                  SizedBox(width: 5),
                  StatusDot(color: AresColors.green, size: 5),
                  SizedBox(width: 5),
                  StatusDot(color: AresColors.green, size: 5),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapPreviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final layer = marsMapLayers[state.mapLayer];
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => state.setScreen(1),
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AresColors.line),
            borderRadius: BorderRadius.circular(6),
            color: AresColors.bg1,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const MarsMap(compact: true, cover: true, interactive: false),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Container(
                    height: 54,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AresColors.bg0.withValues(alpha: 0.9),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tactical overview',
                              style: AresType.label(
                                size: 11.5,
                                color: AresColors.text,
                                spacing: 0.7,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${layer.shortTitle} · archive imagery',
                              style: AresType.monoStyle(
                                size: 9.5,
                                color: AresColors.muted,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const ProvenancePill(Provenance.archive, compact: true),
                        const SizedBox(width: 5),
                        const ProvenancePill(Provenance.derived, compact: true),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          AresColors.bg0.withValues(alpha: 0.95),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        const StatusDot(color: AresColors.cyan, size: 5),
                        const SizedBox(width: 6),
                        Text(
                          'WP-04 · AEOLIS PALUS',
                          style: AresType.label(
                            size: 9.5,
                            color: AresColors.cyan,
                            spacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            state.route == null
                                ? 'No active traverse'
                                : '${state.route!.distanceKm.toStringAsFixed(2)} km → '
                                      '${state.route!.targetName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AresType.monoStyle(
                              size: 10,
                              color: AresColors.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Open map',
                          style: AresType.label(
                            size: 9.5,
                            color: AresColors.muted,
                            spacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward,
                          size: 13,
                          color: AresColors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 60,
                  right: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _LayerDot(label: 'THEMIS', active: state.showThemis),
                      const SizedBox(height: 4),
                      _LayerDot(label: 'SLOPE', active: state.showSlope),
                      const SizedBox(height: 4),
                      _LayerDot(label: 'PNR', active: state.showPnr),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LayerDot extends StatelessWidget {
  const _LayerDot({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AresColors.bg0.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: active ? AresColors.cyan : AresColors.dim,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AresType.label(
              size: 8.5,
              color: active ? AresColors.muted : AresColors.dim,
              spacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}