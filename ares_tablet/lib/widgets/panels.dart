import 'package:flutter/material.dart' hide DataRow;

import '../models/ares_models.dart';
import '../state/ares_scope.dart';
import '../state/ares_state.dart';
import '../theme/ares_theme.dart';
import '../util/astro.dart';
import 'hud.dart';
import 'edac_dialog.dart';

class PlssPanel extends StatelessWidget {
  const PlssPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return HudPanel(
      title: 'SUIT SYSTEMS',
      code: 'EVA-2',
      trailing: const ProvenancePill(Provenance.sim, compact: true),
      child: Column(
        children: [
          Row(
            children: [
              const RadialGauge(
                value: 0.82,
                label: 'O₂',
                unit: '%',
                color: AresColors.cyan,
                size: 88,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: [
                    const GaugeBar(
                      label: 'Battery',
                      value: 0.76,
                      color: AresColors.green,
                      readout: '76%',
                    ),
                    const SizedBox(height: 10),
                    const GaugeBar(
                      label: 'CO₂ scrubber',
                      value: 0.84,
                      color: AresColors.cyan,
                      readout: '84%',
                    ),
                    const SizedBox(height: 10),
                    const GaugeBar(
                      label: 'Water',
                      value: 0.51,
                      color: AresColors.cyan,
                      readout: '51%',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SectionDivider(),
          Row(
            children: const [
              Expanded(
                child: Metric(
                  label: 'Suit pressure',
                  value: '29.8',
                  unit: 'kPa',
                  size: 15,
                ),
              ),
              Expanded(
                child: Metric(
                  label: 'Suit temp',
                  value: '18.6',
                  unit: '°C',
                  size: 15,
                ),
              ),
              Expanded(
                child: Metric(
                  label: 'Runtime left',
                  value: '04h 12m',
                  size: 15,
                  color: AresColors.cyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const DataRow(label: 'ppCO₂', value: '1.8 mmHg'),
          const DataRow(label: 'Metabolic load', value: '310 W'),
          const DataRow(label: 'Cooling water', value: '3.2 L'),
          DataRow(
            label: 'Buddy EVA-2',
            value:
                '${state.buddyDistanceM.round()} m @ ${initialBearingDeg(state.current, state.buddy).round().toString().padLeft(3, '0')}°',
          ),
        ],
      ),
    );
  }
}

class WeatherPanel extends StatelessWidget {
  const WeatherPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return HudPanel(
      title: 'WEATHER · MEDA',
      code: 'SOL 100',
      trailing: const ProvenancePill(Provenance.archive, compact: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Metric(
                  label: 'Air max',
                  value: state.airMax.toStringAsFixed(1),
                  unit: '°C',
                  size: 17,
                  color: AresColors.cyan,
                ),
              ),
              Expanded(
                child: Metric(
                  label: 'Ground max',
                  value: state.groundMax.toStringAsFixed(1),
                  unit: '°C',
                  size: 17,
                  color: AresColors.amber,
                ),
              ),
              Expanded(
                child: Metric(
                  label: 'Pressure',
                  value: ((state.pressureMin + state.pressureMax) / 2)
                      .toStringAsFixed(0),
                  unit: 'Pa',
                  size: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: Sparkline(
              values: state.airSeries,
              secondaryValues: state.groundSeries,
              color: AresColors.cyan,
              secondaryColor: AresColors.amber,
              gridLines: 2,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const _Legend(color: AresColors.cyan, label: 'Air'),
              const SizedBox(width: 12),
              const _Legend(color: AresColors.amber, label: 'Ground IR'),
              const Spacer(),
              Text(
                '${state.meda.length} readings · 15 min',
                style: AresType.monoStyle(size: 9, color: AresColors.dim),
              ),
            ],
          ),
          const SectionDivider(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: AresColors.amber,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Wind sensor offline · optical depth '
                  '${state.invalidOpacityCount}/${state.meda.length} out of range',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AresType.label(
                    size: 9.5,
                    color: AresColors.amber,
                    spacing: 0.3,
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

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 2, color: color),
        const SizedBox(width: 5),
        Text(label, style: AresType.label(size: 9.5, color: AresColors.muted)),
      ],
    );
  }
}

class CommsPanel extends StatelessWidget {
  const CommsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return HudPanel(
      title: 'COMMUNICATIONS',
      code: 'DSN-43',
      trailing: const ProvenancePill(Provenance.sim, compact: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataRow(
            label: 'Signal delay to Earth',
            value: state.owltLabel,
            provenance: Provenance.derived,
          ),
          DataRow(
            label: 'Local base latency',
            value: '1.8 s',
            provenance: Provenance.sim,
          ),
          DataRow(
            label: 'Next orbiter pass',
            value: formatSeconds(state.relayWindowSeconds.toDouble()),
            valueColor: AresColors.cyan,
            provenance: Provenance.sim,
          ),
          const SizedBox(height: 8),
          _RelayTimeline(progress: 1 - state.relayWindowSeconds / 2820),
          const SizedBox(height: 7),
          Row(
            children: [
              const StatusDot(color: AresColors.green, size: 5),
              const SizedBox(width: 6),
              Text(
                'Line of sight clear',
                style: AresType.label(
                  size: 9.5,
                  color: AresColors.green,
                  spacing: 0.4,
                ),
              ),
              const Spacer(),
              Text(
                '3 packets queued',
                style: AresType.monoStyle(size: 9, color: AresColors.dim),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const DataRow(
            label: 'Map storage',
            value: 'Bundled offline archive',
            provenance: Provenance.cached,
          ),
          AresButton(
            label: 'Test bit-flip recovery',
            icon: Icons.verified_user_outlined,
            expanded: true,
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const EdacDialog(),
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayTimeline extends StatelessWidget {
  const _RelayTimeline({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final clamped = progress.clamp(0.0, 1.0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: AresColors.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Positioned(
              left: constraints.maxWidth * 0.62,
              width: constraints.maxWidth * 0.18,
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: AresColors.green.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Positioned(
              left: constraints.maxWidth * clamped - 1,
              top: -2,
              bottom: -2,
              child: Container(width: 2, color: AresColors.cyan),
            ),
          ],
        );
      },
    );
  }
}

class AlertPanel extends StatelessWidget {
  const AlertPanel({super.key, this.limit = 3});

  final int limit;

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final alerts = state.alerts.take(limit).toList();
    return HudPanel(
      title: 'ALERTS',
      code: '${state.unacknowledgedAlerts.length} OPEN',
      trailing: AresButton(
        label: 'Ack all',
        icon: Icons.done_all,
        height: 32,
        onTap: state.acknowledgeAll,
      ),
      child: Column(
        children: [
          for (var i = 0; i < alerts.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _AlertRow(alert: alerts[i]),
          ],
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final AresAlert alert;

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final color = severityColor(alert.severity);
    return Material(
      color: color.withValues(alpha: alert.acknowledged ? 0.03 : 0.07),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: alert.acknowledged ? null : () => state.acknowledge(alert.id),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 7, 8, 7),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            alert.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AresType.label(
                              size: 10.5,
                              color: color,
                              spacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        ProvenancePill(alert.provenance, compact: true),
                        const Spacer(),
                        if (alert.acknowledged)
                          Text(
                            'ACKED',
                            style: AresType.monoStyle(
                              size: 8.5,
                              color: AresColors.dim,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      alert.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AresType.bodyMuted.copyWith(
                        fontSize: 10.5,
                        height: 1.3,
                        color: AresColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                alert.acknowledged
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
                size: 16,
                color: alert.acknowledged ? AresColors.dim : color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AlertTicker extends StatelessWidget {
  const AlertTicker({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final alerts = state.unacknowledgedAlerts;
    final alert = alerts.isEmpty ? null : alerts.first;
    final color = alert == null
        ? AresColors.green
        : severityColor(alert.severity);
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          StatusDot(color: color, size: 6, pulse: alert != null),
          const SizedBox(width: 8),
          Text(
            alert == null ? 'ALL ALERTS ACKNOWLEDGED' : alert.title,
            style: AresType.label(size: 10.5, color: color, spacing: 0.4),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              alert?.detail ?? 'No open items on the alert stack.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AresType.bodyMuted.copyWith(fontSize: 10.5),
            ),
          ),
          if (alert != null)
            AresButton(
              label: 'Ack',
              height: 28,
              onTap: () => state.acknowledge(alert.id),
              accent: color,
            ),
          const SizedBox(width: 10),
          Text(
            '${alerts.length.toString().padLeft(2, '0')} OPEN',
            style: AresType.monoStyle(size: 9.5, color: AresColors.dim),
          ),
        ],
      ),
    );
  }
}

class PnrPanel extends StatelessWidget {
  const PnrPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final usage = state.pnrUsage;
    final statusColor = usage >= 1
        ? AresColors.red
        : usage >= 0.8
        ? AresColors.amber
        : AresColors.green;
    return HudPanel(
      title: 'RETURN RANGE',
      code: 'PNR',
      trailing: const ProvenancePill(Provenance.derived, compact: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      state.pnrDistanceKm.toStringAsFixed(2),
                      style: AresType.monoStyle(
                        size: 27,
                        color: AresColors.text,
                        weight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'km from lander',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AresType.label(
                            size: 9.5,
                            color: AresColors.dim,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  state.pnrStatus,
                  style: AresType.label(
                    size: 9.5,
                    color: statusColor,
                    spacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GaugeBar(
            label:
                'Return radius ${AresState.pnrRadiusKm.toStringAsFixed(1)} km',
            value: usage,
            color: statusColor,
            height: 5,
            readout: '${(usage * 100).round()}%',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Bearing to lander',
                  value:
                      '${state.pnrBearing.round().toString().padLeft(3, '0')}° '
                      '${compass16(state.pnrBearing)}',
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Return at 1.44 km/h',
                  value: formatDuration(state.pnrReturnTime),
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: AresColors.line),
              borderRadius: BorderRadius.circular(4),
              color: AresColors.bg0.withValues(alpha: 0.4),
            ),
            child: Row(
              children: [
                const StatusDot(color: AresColors.green, size: 5),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'EVA-2 buddy',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AresType.label(
                      size: 9.5,
                      color: AresColors.green,
                      spacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${state.buddyDistanceM.round()} m · link OK',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AresType.monoStyle(size: 10, color: AresColors.text),
                ),
                const SizedBox(width: 7),
                const ProvenancePill(Provenance.sim, compact: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.color = AresColors.text,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AresType.label(size: 9.5, color: AresColors.dim),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AresType.monoStyle(size: 11.5, color: color),
        ),
      ],
    );
  }
}

class MissionObjectivesPanel extends StatelessWidget {
  const MissionObjectivesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final objectives = state.objectives;
    return HudPanel(
      title: 'MISSION OBJECTIVES',
      trailing: Text(
        '${state.objectivesDone}/${objectives.length}',
        style: AresType.monoStyle(size: 12, color: AresColors.cyan),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Traverse to Vera Rubin Ridge with validated slope, thermal and '
            'sample context while holding PNR and the rule of two.',
            style: AresType.bodyMuted.copyWith(fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 9),
          GaugeBar(
            label: 'Mission progress',
            value: state.objectivesDone / objectives.length,
            color: AresColors.cyan,
            readout:
                '${(state.objectivesDone / objectives.length * 100).round()}%',
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < objectives.length; i++) ...[
            if (i > 0) const SizedBox(height: 7),
            _ObjectiveRow(objective: objectives[i]),
          ],
        ],
      ),
    );
  }
}

class _ObjectiveRow extends StatelessWidget {
  const _ObjectiveRow({required this.objective});

  final MissionObjective objective;

  @override
  Widget build(BuildContext context) {
    final color = objective.done ? AresColors.green : AresColors.lineHot;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: objective.done
                ? AresColors.green.withValues(alpha: 0.14)
                : Colors.transparent,
            border: Border.all(color: color),
          ),
          child: objective.done
              ? const Icon(Icons.check, size: 10, color: AresColors.green)
              : Center(
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                      color: AresColors.lineHot,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                objective.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AresType.body.copyWith(
                  fontSize: 11,
                  height: 1.25,
                  color: objective.done ? AresColors.text : AresColors.muted,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                objective.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AresType.monoStyle(size: 9, color: AresColors.dim),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          objective.code,
          style: AresType.monoStyle(
            size: 9,
            color: objective.done ? AresColors.green : AresColors.dim,
          ),
        ),
      ],
    );
  }
}

class TraverseCard extends StatelessWidget {
  const TraverseCard({super.key, this.showActions = true, this.dense = false});

  final bool showActions;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final plan = state.route;
    return HudPanel(
      title: 'TRAVERSE PLAN',
      code: plan?.targetName,
      trailing: const ProvenancePill(Provenance.derived, compact: true),
      child: plan == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No traverse planned. Activate ROUTE on the map and pick a destination.',
                style: AresType.bodyMuted.copyWith(fontSize: 11),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      plan.distanceKm.toStringAsFixed(2),
                      style: AresType.monoStyle(
                        size: dense ? 22 : 26,
                        color: AresColors.text,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        'km',
                        style: AresType.label(size: 10, color: AresColors.dim),
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          plan.durationLabel,
                          style: AresType.monoStyle(
                            size: dense ? 13 : 15,
                            color: AresColors.cyan,
                          ),
                        ),
                        Text(
                          'ETA at 0.4 m/s',
                          style: AresType.label(
                            size: 9,
                            color: AresColors.dim,
                            spacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: dense ? 28 : 36,
                  child: Sparkline(
                    values: plan.elevations,
                    color: AresColors.cyan,
                    gridLines: 2,
                    secondaryColor: AresColors.amber,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _TraverseStat(
                      label: 'Max slope',
                      value: '${plan.maxSlopeDeg.toStringAsFixed(1)}°',
                      color: plan.maxSlopeDeg > 14
                          ? AresColors.amber
                          : AresColors.green,
                    ),
                    _TraverseStat(
                      label: 'Ascent',
                      value: '${plan.elevationGainM.round()} m',
                    ),
                    _TraverseStat(
                      label: 'Hazard cells',
                      value: '${plan.hazardCells}',
                      color: plan.hazardCells > 0
                          ? AresColors.amber
                          : AresColors.green,
                    ),
                    _TraverseStat(
                      label: 'Grid cell',
                      value: '${plan.cellSizeM.round()} m',
                    ),
                  ],
                ),
                if (showActions) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: AresButton(
                          label: 'Open map',
                          icon: Icons.map_outlined,
                          onTap: () => state.setScreen(1),
                          expanded: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AresButton(
                          label: 'Replan',
                          icon: Icons.alt_route,
                          onTap: () {
                            state.setScreen(1);
                            if (!state.routeMode) state.toggleRouteMode();
                          },
                          expanded: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _TraverseStat extends StatelessWidget {
  const _TraverseStat({
    required this.label,
    required this.value,
    this.color = AresColors.text,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AresType.label(size: 9.5, color: AresColors.dim),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AresType.monoStyle(size: 11, color: color),
          ),
        ],
      ),
    );
  }
}

class QuickActions extends StatelessWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.alt_route,
            title: 'Plan route',
            subtitle: 'Pick a target on the map',
            onTap: () {
              state.setScreen(1);
              if (!state.routeMode) state.toggleRouteMode();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.terrain,
            title: '3D terrain',
            subtitle: 'Slope and relief view',
            onTap: () => state.setScreen(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.panorama_horizontal,
            title: 'Surface camera',
            subtitle: 'NASA panorama archive',
            onTap: () => state.setScreen(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.biotech_outlined,
            title: 'Log sample',
            subtitle: '${state.samples.length} on record',
            onTap: () {
              final sample = state.logSample();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${sample.label} logged at ${formatCoordinate(sample.point)} · SIM',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AresColors.bg1,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        splashColor: AresColors.cyan.withValues(alpha: 0.1),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AresColors.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AresColors.cyan),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AresType.label(
                        size: 11,
                        color: AresColors.text,
                        spacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AresType.monoStyle(size: 9, color: AresColors.dim),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EnvironmentStrip extends StatelessWidget {
  const EnvironmentStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final sun = state.sun;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AresColors.bg1,
        border: Border.all(color: AresColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wb_sunny_outlined,
            size: 16,
            color: AresColors.amber,
          ),
          const SizedBox(width: 7),
          Text(
            'Sun ${sun.azimuthDeg.round().toString().padLeft(3, '0')}° · '
            'el ${sun.elevationDeg.toStringAsFixed(1)}°',
            style: AresType.monoStyle(size: 10.5, color: AresColors.text),
          ),
          const SizedBox(width: 9),
          const ProvenancePill(Provenance.model, compact: true),
          const Spacer(),
          _EnvItem(
            label: 'Local solar',
            value: '${state.marsClock.localSolarHours.toStringAsFixed(2)} h',
          ),
          const SizedBox(width: 16),
          _EnvItem(
            label: 'Slip risk',
            value: 'MODERATE',
            color: AresColors.amber,
          ),
          const SizedBox(width: 16),
          _EnvItem(label: 'Gravity', value: '3.71 m/s²'),
        ],
      ),
    );
  }
}

class _EnvItem extends StatelessWidget {
  const _EnvItem({
    required this.label,
    required this.value,
    this.color = AresColors.text,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label ',
          style: AresType.label(size: 9.5, color: AresColors.dim),
        ),
        Text(value, style: AresType.monoStyle(size: 10.5, color: color)),
      ],
    );
  }
}
