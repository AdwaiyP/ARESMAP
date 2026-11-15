import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/ares_models.dart';
import '../state/ares_scope.dart';
import '../theme/ares_theme.dart';
import '../util/astro.dart';
import '../widgets/hud.dart';

enum _CatalogFilter { all, ir, vis, warm, albedo }

class ScienceScreen extends StatefulWidget {
  const ScienceScreen({super.key});

  @override
  State<ScienceScreen> createState() => _ScienceScreenState();
}

class _ScienceScreenState extends State<ScienceScreen> {
  final TextEditingController _search = TextEditingController();
  _CatalogFilter _filter = _CatalogFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ThemisStamp> _filtered(List<ThemisStamp> stamps) {
    final query = _search.text.trim().toLowerCase();
    return stamps
        .where((stamp) {
          final matchesQuery =
              query.isEmpty ||
              stamp.fileId.toLowerCase().contains(query) ||
              stamp.description.toLowerCase().contains(query);
          if (!matchesQuery) return false;
          return switch (_filter) {
            _CatalogFilter.all => true,
            _CatalogFilter.ir => stamp.frameType == 'IR',
            _CatalogFilter.vis => stamp.frameType == 'VIS',
            _CatalogFilter.warm => stamp.tempC != null && stamp.tempC! >= -60,
            _CatalogFilter.albedo => stamp.albedo != null,
          };
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final filtered = _filtered(state.stamps);
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
                      'SCIENCE / SAMPLE LOG',
                      style: AresType.displayStyle(size: 25, spacing: 0.8),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Thermal context · MEDA weather archive · THEMIS catalog',
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
                  '${state.samples.length} '
                  '${state.samples.length == 1 ? 'sample' : 'samples'} · '
                  '${state.stamps.length} stamps',
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
                SizedBox(
                  width: 320,
                  child: Column(
                    children: [
                      Expanded(
                        child: HudPanel(
                          title: 'SAMPLE LOG',
                          code:
                              '${state.samples.length} '
                              '${state.samples.length == 1 ? 'record' : 'records'}',
                          trailing: const ProvenancePill(
                            Provenance.sim,
                            compact: true,
                          ),
                          expand: true,
                          fillChild: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AresButton(
                                label: 'Log sample at current position',
                                icon: Icons.add_location_alt_outlined,
                                primary: true,
                                expanded: true,
                                onTap: () {
                                  final sample = state.logSample();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${sample.label} logged · ${formatCoordinate(sample.point)} · simulated',
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: state.samples.isEmpty
                                    ? Center(
                                        child: Text(
                                          'No samples logged.',
                                          style: AresType.bodyMuted,
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: state.samples.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(height: 6),
                                        itemBuilder: (context, index) =>
                                            _SampleCard(
                                              sample: state.samples[index],
                                            ),
                                      ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Field entries are operator-authored demo '
                                'records. No lab analysis is included.',
                                style: AresType.bodyMuted.copyWith(
                                  fontSize: 10,
                                  height: 1.35,
                                  color: AresColors.dim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const _DataQualityPanel(),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const _MedaKpiPanel(),
                        const SizedBox(height: 10),
                        HudPanel(
                          title: 'AIR / GROUND TEMPERATURE',
                          code: '63 readings',
                          trailing: const ProvenancePill(
                            Provenance.archive,
                            compact: true,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 240,
                                child: CustomPaint(
                                  painter: _MultiSeriesPainter(
                                    series: [
                                      _ChartSeries(
                                        label: 'AIR',
                                        color: AresColors.cyan,
                                        values: state.airSeries,
                                        fill: true,
                                      ),
                                      _ChartSeries(
                                        label: 'GROUND IR',
                                        color: AresColors.amber,
                                        values: state.groundSeries,
                                      ),
                                    ],
                                    unit: '°C',
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: const [
                                  _ChartLegend(
                                    color: AresColors.cyan,
                                    label: 'Air temp',
                                  ),
                                  SizedBox(width: 10),
                                  _ChartLegend(
                                    color: AresColors.amber,
                                    label: 'Ground IR',
                                  ),
                                  Spacer(),
                                  Text(
                                    'Local time 00:00–23:00',
                                    style: TextStyle(
                                      fontFamily: AresType.mono,
                                      fontSize: 9.5,
                                      color: AresColors.dim,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _PressurePanel(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 330,
                  child: HudPanel(
                    title: 'THERMAL CATALOG',
                    code: '${filtered.length} / ${state.stamps.length}',
                    trailing: const ProvenancePill(
                      Provenance.archive,
                      compact: true,
                    ),
                    expand: true,
                    fillChild: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          style: AresType.monoStyle(
                            size: 11,
                            color: AresColors.text,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: AresColors.bg0.withValues(alpha: 0.6),
                            hintText: 'Search file ID or description',
                            hintStyle: AresType.label(
                              size: 9.5,
                              color: AresColors.dim,
                              spacing: 0.3,
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              size: 16,
                              color: AresColors.dim,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 30,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 9,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                color: AresColors.line,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                color: AresColors.cyan,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final filter in _CatalogFilter.values)
                              ChipToggle(
                                label: _filterLabel(filter),
                                selected: _filter == filter,
                                onTap: () => setState(() => _filter = filter),
                              ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Text(
                                    'No stamps match this filter.',
                                    style: AresType.bodyMuted,
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final stamp = filtered[index];
                                    return _CatalogRow(
                                      stamp: stamp,
                                      selected: state.focus.id == stamp.fileId,
                                      onTap: () => state.selectStamp(stamp),
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                state.focus.stamp == null
                                    ? 'No stamp selected'
                                    : state.focus.id,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AresType.monoStyle(
                                  size: 9.5,
                                  color: AresColors.muted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            AresButton(
                              label: 'View on map',
                              icon: Icons.map_outlined,
                              onTap: () => state.setScreen(1),
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
    );
  }

  String _filterLabel(_CatalogFilter filter) => switch (filter) {
    _CatalogFilter.all => 'All',
    _CatalogFilter.ir => 'IR',
    _CatalogFilter.vis => 'VIS',
    _CatalogFilter.warm => 'Warm ≥−60°',
    _CatalogFilter.albedo => 'Albedo',
  };
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.sample});

  final SampleRecord sample;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
      decoration: BoxDecoration(
        color: AresColors.bg0.withValues(alpha: 0.35),
        border: Border.all(color: AresColors.line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sample.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AresType.label(
                    size: 10.5,
                    color: AresColors.text,
                    spacing: 0.3,
                  ),
                ),
              ),
              const ProvenancePill(Provenance.sim, compact: true),
              const SizedBox(width: 5),
              Text(
                sample.mtc,
                style: AresType.monoStyle(size: 9.5, color: AresColors.dim),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            formatCoordinate(sample.point),
            style: AresType.monoStyle(size: 10, color: AresColors.cyan),
          ),
          const SizedBox(height: 3),
          Text(
            sample.context,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AresType.bodyMuted.copyWith(fontSize: 10.5, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _DataQualityPanel extends StatelessWidget {
  const _DataQualityPanel();

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return HudPanel(
      title: 'DATA QUALITY',
      trailing: const ProvenancePill(Provenance.noData, compact: true),
      child: Column(
        children: [
          _QualityRow(
            label: 'Ionizing radiation',
            value: 'Missing',
            color: AresColors.red,
          ),
          _QualityRow(
            label: 'Wind sensor',
            value: 'Offline',
            color: AresColors.amber,
          ),
          _QualityRow(
            label: 'Optical depth',
            value: '${state.invalidOpacityCount}/63 bad',
            color: AresColors.amber,
          ),
          _QualityRow(
            label: 'Humidity uncertainty',
            value: 'Unreported',
            color: AresColors.amber,
          ),
          _QualityRow(
            label: 'Pressure uncertainty',
            value: 'Unreported',
            color: AresColors.amber,
          ),
          const SizedBox(height: 6),
          Text(
            'Missing channels stay visibly missing. ARES does not substitute '
            'synthetic values into sensor slots.',
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

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AresType.label(
                size: 10,
                color: AresColors.muted,
                spacing: 0.2,
              ),
            ),
          ),
          Text(value, style: AresType.monoStyle(size: 9.5, color: color)),
        ],
      ),
    );
  }
}

class _MedaKpiPanel extends StatelessWidget {
  const _MedaKpiPanel();

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final pressureMean =
        state.pressureSeries.reduce((a, b) => a + b) /
        state.pressureSeries.length;
    return HudPanel(
      title: 'MEDA · SOL 100',
      code: '63 × 15 min',
      trailing: const ProvenancePill(Provenance.archive, compact: true),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Metric(
                  label: 'Air min',
                  value: state.airMin.toStringAsFixed(1),
                  unit: '°C',
                  size: 18,
                  color: AresColors.cyan,
                ),
              ),
              Expanded(
                child: Metric(
                  label: 'Air max',
                  value: state.airMax.toStringAsFixed(1),
                  unit: '°C',
                  size: 18,
                  color: AresColors.cyan,
                ),
              ),
              Expanded(
                child: Metric(
                  label: 'Pressure mean',
                  value: pressureMean.toStringAsFixed(0),
                  unit: 'Pa',
                  size: 18,
                ),
              ),
              Expanded(
                child: Metric(
                  label: 'Opacity median',
                  value: state.opacityMedian.toStringAsFixed(2),
                  unit: 'τ',
                  size: 18,
                  color: AresColors.amber,
                  note: '${state.invalidOpacityCount} out of range',
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 13, color: AresColors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Archived Curiosity MEDA extract. It is not a live weather '
                  'feed; optical-depth values are raw and unvalidated.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AresType.bodyMuted.copyWith(
                    fontSize: 10,
                    height: 1.35,
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

class _PressurePanel extends StatelessWidget {
  const _PressurePanel();

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final zenith = state.meda
        .map((r) => r.solarZenithDeg)
        .whereType<double>()
        .toList(growable: false);
    final zenithMin = zenith.reduce(math.min);
    final zenithMax = zenith.reduce(math.max);
    return HudPanel(
      title: 'PRESSURE / ATMOSPHERE',
      trailing: const ProvenancePill(Provenance.archive, compact: true),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Metric(
                  label: 'Minimum',
                  value: state.pressureMin.toStringAsFixed(1),
                  unit: 'Pa',
                  size: 15,
                ),
              ),
              Expanded(
                child: Metric(
                  label: 'Maximum',
                  value: state.pressureMax.toStringAsFixed(1),
                  unit: 'Pa',
                  size: 15,
                ),
              ),
              Expanded(
                child: Metric(
                  label: 'Wind',
                  value: 'Offline',
                  size: 13,
                  color: AresColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 54,
            child: CustomPaint(
              painter: _MultiSeriesPainter(
                series: [
                  _ChartSeries(
                    label: 'PRESSURE',
                    color: AresColors.text,
                    values: state.pressureSeries,
                    fill: true,
                  ),
                ],
                unit: 'Pa',
                dense: true,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Safety state · ${state.meda.last.safetyState}',
                style: AresType.monoStyle(size: 9.5, color: AresColors.amber),
              ),
              const Spacer(),
              Text(
                'Solar zenith ${zenithMin.toStringAsFixed(1)}°–'
                '${zenithMax.toStringAsFixed(1)}°',
                style: AresType.monoStyle(size: 9.5, color: AresColors.dim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.stamp,
    required this.selected,
    required this.onTap,
  });

  final ThemisStamp stamp;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? AresColors.amber.withValues(alpha: 0.07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: selected
                    ? AresColors.amber.withValues(alpha: 0.55)
                    : AresColors.line,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            stamp.fileId,
                            style: AresType.monoStyle(
                              size: 10,
                              color: selected
                                  ? AresColors.amber
                                  : AresColors.cyan,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            stamp.frameType,
                            style: AresType.label(
                              size: 9,
                              color: AresColors.dim,
                              spacing: 0.3,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            stamp.tempC == null
                                ? (stamp.albedo == null
                                      ? '—'
                                      : 'albedo ${stamp.albedo!.toStringAsFixed(3)}')
                                : '${stamp.tempC!.toStringAsFixed(1)}°C',
                            style: AresType.monoStyle(
                              size: 10,
                              color: stamp.tempC == null
                                  ? AresColors.muted
                                  : _tempColor(stamp.tempC!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${stamp.description.isEmpty ? 'Gale Crater' : stamp.description} · '
                        '${stamp.lat.toStringAsFixed(3)}, ${stamp.lon.toStringAsFixed(3)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AresType.monoStyle(
                          size: 9.5,
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
      ),
    );
  }

  Color _tempColor(double temp) {
    final t = ((temp + 110) / 120).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFF3B74FF), AresColors.amber, t)!;
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 3, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: AresType.label(
            size: 9.5,
            color: AresColors.muted,
            spacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _ChartSeries {
  const _ChartSeries({
    required this.label,
    required this.color,
    required this.values,
    this.fill = false,
  });

  final String label;
  final Color color;
  final List<double> values;
  final bool fill;
}

class _MultiSeriesPainter extends CustomPainter {
  _MultiSeriesPainter({
    required this.series,
    required this.unit,
    this.dense = false,
  });

  final List<_ChartSeries> series;
  final String unit;
  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || series.first.values.length < 2) return;
    final all = series.expand((s) => s.values).toList();
    var minValue = all.reduce(math.min);
    var maxValue = all.reduce(math.max);
    if ((maxValue - minValue).abs() < 0.01) {
      minValue -= 1;
      maxValue += 1;
    }
    final padding = (maxValue - minValue) * 0.1;
    minValue -= padding;
    maxValue += padding;

    final grid = Paint()
      ..color = AresColors.line.withValues(alpha: 0.65)
      ..strokeWidth = 0.7;
    const leftPad = 38.0;
    const bottomPad = 16.0;
    final plot = Rect.fromLTWH(
      leftPad,
      4,
      size.width - leftPad - 4,
      size.height - bottomPad - 8,
    );
    final rows = size.height < 90 ? 2 : 4;
    for (var i = 0; i <= rows; i++) {
      final y = plot.top + plot.height * i / rows;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final value = maxValue - (maxValue - minValue) * i / rows;
      _label(
        canvas,
        value.toStringAsFixed(dense ? 1 : 0),
        Offset(0, y - 5),
        AresColors.dim,
        9,
      );
    }
    for (var i = 0; i <= 5; i++) {
      final x = plot.left + plot.width * i / 5;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
    }
    _label(
      canvas,
      '00:00',
      Offset(plot.left, plot.bottom + 3),
      AresColors.dim,
      9,
    );
    final end = TextPainter(
      text: TextSpan(
        text: '23:00',
        style: AresType.monoStyle(size: 9, color: AresColors.dim),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    end.paint(canvas, Offset(plot.right - end.width, plot.bottom + 3));
    _label(canvas, unit, Offset(0, plot.top - 2), AresColors.muted, 9);

    for (final line in series) {
      if (line.values.length < 2) continue;
      final path = Path();
      for (var i = 0; i < line.values.length; i++) {
        final x = plot.left + plot.width * i / (line.values.length - 1);
        final y =
            plot.bottom -
            (line.values[i] - minValue) / (maxValue - minValue) * plot.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      if (line.fill) {
        final fillPath = Path.from(path)
          ..lineTo(plot.right, plot.bottom)
          ..lineTo(plot.left, plot.bottom)
          ..close();
        canvas.drawPath(
          fillPath,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                line.color.withValues(alpha: 0.18),
                line.color.withValues(alpha: 0.01),
              ],
            ).createShader(plot),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = dense ? 1.1 : 1.5
          ..strokeJoin = StrokeJoin.round,
      );
      final lastX = plot.right;
      final lastY =
          plot.bottom -
          (line.values.last - minValue) / (maxValue - minValue) * plot.height;
      canvas.drawCircle(Offset(lastX, lastY), 2, Paint()..color = line.color);
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset anchor,
    Color color,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AresType.monoStyle(size: size, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, anchor);
  }

  @override
  bool shouldRepaint(covariant _MultiSeriesPainter oldDelegate) =>
      oldDelegate.series != series;
}
