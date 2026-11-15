import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/ares_models.dart';
import '../theme/ares_theme.dart';

class HudPanel extends StatelessWidget {
  const HudPanel({
    super.key,
    this.title,
    this.code,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 14),
    this.dense = false,
    this.expand = false,
    this.fillChild = false,
  });

  final String? title;
  final String? code;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  final bool dense;
  final bool expand;
  final bool fillChild;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AresColors.bg1,
        border: Border.all(color: AresColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: dense ? const EdgeInsets.fromLTRB(12, 10, 12, 11) : padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (title != null) ...[
              SizedBox(
                height: 24,
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title!,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: AresType.label(
                                size: 11.5,
                                spacing: 0.7,
                                color: AresColors.text,
                              ),
                            ),
                          ),
                          if (code != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                code!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AresType.monoStyle(
                                  size: 9.5,
                                  color: AresColors.dim,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (fillChild) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}

class ProvenancePill extends StatelessWidget {
  const ProvenancePill(
    this.provenance, {
    super.key,
    this.label,
    this.compact = false,
  });

  final Provenance provenance;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = provenanceColor(provenance);
    return Tooltip(
      message: 'Data source: ${provenanceLabel(provenance).toLowerCase()}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 7,
          vertical: compact ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: compact ? 4 : 5),
            Text(
              (label ?? provenanceLabel(provenance)).toUpperCase(),
              style: AresType.label(
                size: compact ? 8.5 : 9.5,
                color: color,
                spacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusDot extends StatefulWidget {
  const StatusDot({
    super.key,
    required this.color,
    this.size = 6,
    this.pulse = false,
  });

  final Color color;
  final double size;
  final bool pulse;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulse) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = 0.45 + _controller.value * 0.55;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

class AresButton extends StatelessWidget {
  const AresButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.active = false,
    this.primary = false,
    this.accent = AresColors.cyan,
    this.expanded = false,
    this.height = 40,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool active;
  final bool primary;
  final Color accent;
  final bool expanded;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final highlighted = enabled && (active || primary);
    final color = enabled ? accent : AresColors.dim;
    return Material(
      color: highlighted
          ? color.withValues(alpha: 0.16)
          : AresColors.bg2,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        splashColor: color.withValues(alpha: 0.12),
        highlightColor: color.withValues(alpha: 0.08),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: highlighted
                  ? color.withValues(alpha: 0.65)
                  : enabled
                  ? AresColors.lineHot
                  : AresColors.line,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AresType.label(
                    size: 11,
                    color: enabled ? color : AresColors.dim,
                    spacing: 0.3,
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

class ChipToggle extends StatelessWidget {
  const ChipToggle({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = AresColors.cyan,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent.withValues(alpha: 0.14) : AresColors.bg2,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        splashColor: accent.withValues(alpha: 0.12),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.6)
                  : AresColors.line,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? accent : AresColors.muted,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: AresType.label(
                  size: 10.5,
                  color: selected ? accent : AresColors.muted,
                  spacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Metric extends StatelessWidget {
  const Metric({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.color = AresColors.text,
    this.size = 20,
    this.note,
  });

  final String label;
  final String value;
  final String? unit;
  final Color color;
  final double size;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AresType.label(size: 10, color: AresColors.muted, spacing: 0.4),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AresType.monoStyle(
                  size: size,
                  color: color,
                  weight: FontWeight.w500,
                ),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(
                unit!,
                style: AresType.label(
                  size: 10,
                  color: AresColors.muted,
                  spacing: 0.3,
                ),
              ),
            ],
          ],
        ),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(
            note!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AresType.monoStyle(size: 9.5, color: AresColors.dim),
          ),
        ],
      ],
    );
  }
}

class GaugeBar extends StatelessWidget {
  const GaugeBar({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.readout,
    this.height = 5,
  });

  final String label;
  final double value;
  final Color color;
  final String? readout;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AresType.label(size: 10, color: AresColors.muted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (readout != null)
              Text(readout!, style: AresType.monoStyle(size: 11, color: color)),
          ],
        ),
        const SizedBox(height: 5),
        LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: AresColors.line,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
                Container(
                  height: height,
                  width: constraints.maxWidth * value.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class RadialGauge extends StatelessWidget {
  const RadialGauge({
    super.key,
    required this.value,
    required this.label,
    required this.color,
    this.size = 86,
    this.unit,
  });

  final double value;
  final String label;
  final Color color;
  final double size;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RadialGaugePainter(value: value, color: color),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(value * 100).round()}',
                style: AresType.monoStyle(
                  size: size * 0.26,
                  color: AresColors.text,
                ),
              ),
              if (unit != null)
                Text(
                  unit!,
                  style: AresType.label(
                    size: 9,
                    color: AresColors.dim,
                    spacing: 0.4,
                  ),
                ),
              const SizedBox(height: 1),
              Text(
                label,
                style: AresType.label(size: 9, color: color, spacing: 0.4),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RadialGaugePainter extends CustomPainter {
  _RadialGaugePainter({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final background = Paint()
      ..color = AresColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final foreground = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, background);
    canvas.drawArc(
      rect,
      start,
      sweep * value.clamp(0.0, 1.0),
      false,
      foreground,
    );
    final tickPaint = Paint()
      ..color = AresColors.dim.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      final angle = start + sweep * (i / 10);
      final inner =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius - 10);
      final outer =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius - 6);
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadialGaugePainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color = AresColors.cyan,
    this.secondaryValues,
    this.secondaryColor = AresColors.amber,
    this.gridLines = 3,
    this.strokeWidth = 1.6,
    this.fill = true,
  });

  final List<double> values;
  final Color color;
  final List<double>? secondaryValues;
  final Color secondaryColor;
  final int gridLines;
  final double strokeWidth;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(
        values: values,
        color: color,
        secondaryValues: secondaryValues,
        secondaryColor: secondaryColor,
        gridLines: gridLines,
        strokeWidth: strokeWidth,
        fill: fill,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.secondaryValues,
    required this.secondaryColor,
    required this.gridLines,
    required this.strokeWidth,
    required this.fill,
  });

  final List<double> values;
  final Color color;
  final List<double>? secondaryValues;
  final Color secondaryColor;
  final int gridLines;
  final double strokeWidth;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final all = [...values, ...?secondaryValues];
    var minV = all.reduce(math.min);
    var maxV = all.reduce(math.max);
    if ((maxV - minV).abs() < 0.0001) {
      minV -= 1;
      maxV += 1;
    }
    final padding = (maxV - minV) * 0.08;
    minV -= padding;
    maxV += padding;

    final gridPaint = Paint()
      ..color = AresColors.line.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    for (var i = 0; i <= gridLines; i++) {
      final y = size.height * (i / gridLines);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    Path buildPath(List<double> series) {
      final path = Path();
      for (var i = 0; i < series.length; i++) {
        final x = size.width * (i / (series.length - 1));
        final y = size.height * (1 - (series[i] - minV) / (maxV - minV));
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    if (secondaryValues != null && secondaryValues!.length > 1) {
      final secondaryPath = buildPath(secondaryValues!);
      canvas.drawPath(
        secondaryPath,
        Paint()
          ..color = secondaryColor.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final path = buildPath(values);
    if (fill) {
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
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );

    final x = size.width;
    final y = size.height * (1 - (values.last - minV) / (maxV - minV));
    canvas.drawCircle(Offset(x, y), 2.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class DataRow extends StatelessWidget {
  const DataRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor = AresColors.text,
    this.provenance,
  });

  final String label;
  final String value;
  final Color valueColor;
  final Provenance? provenance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AresType.label(size: 10.5, color: AresColors.muted),
            ),
          ),
          if (provenance != null) ...[
            ProvenancePill(provenance!, compact: true),
            const SizedBox(width: 6),
          ],
          Text(value, style: AresType.monoStyle(size: 11.5, color: valueColor)),
        ],
      ),
    );
  }
}

class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key, this.color = AresColors.line});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(height: 1, color: color.withValues(alpha: 0.8)),
    );
  }
}

class StarfieldBackground extends StatelessWidget {
  const StarfieldBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BackgroundPainter(), child: child);
  }
}

class _BackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.2, -0.4),
          radius: 1.4,
          colors: [Color(0xFF0A1219), AresColors.bg0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}