import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/ares_scope.dart';
import '../theme/ares_theme.dart';
import '../util/astro.dart';
import 'hud.dart';

class AresTopBar extends StatelessWidget {
  const AresTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final unacked = state.unacknowledgedAlerts;
    final warningCount = unacked
        .where(
          (a) => a.severity.name == 'warning' || a.severity.name == 'critical',
        )
        .length;
    final linkColor = state.backend == null
        ? AresColors.amber
        : state.backendOnline
        ? AresColors.green
        : state.backendChecked
        ? AresColors.amber
        : AresColors.cyan;
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: AresColors.bg0,
        border: Border(bottom: BorderSide(color: AresColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const _AresMark(),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ARES',
                  style: AresType.displayStyle(
                    size: 19,
                    spacing: 2.6,
                    color: AresColors.text,
                  ),
                ),
                Text(
                  'MARS SURFACE OPERATIONS',
                  style: AresType.label(
                    size: 8.5,
                    color: AresColors.muted,
                    spacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 18),
            Container(width: 1, height: 28, color: AresColors.line),
            const SizedBox(width: 16),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const StatusDot(color: AresColors.amber, size: 5),
                    const SizedBox(width: 6),
                    Text(
                      'MSL-CURIOSITY',
                      style: AresType.label(
                        size: 10,
                        color: AresColors.text,
                        spacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'GALE CRATER · AEOLIS PALUS',
                  style: AresType.label(
                    size: 9,
                    color: AresColors.dim,
                    spacing: 0.8,
                  ),
                ),
              ],
            ),
            const Spacer(),
            _ClockBlock(
              label: 'EARTH UTC',
              value: state.earthClock,
              sub: state.earthDate,
            ),
            const _TopDivider(),
            _ClockBlock(
              label: 'MARS MTC',
              value: state.marsClock.mtc,
              sub:
                  'MSD ${state.marsClock.msdLabel} · LON '
                  '${state.current.lon.toStringAsFixed(1)}°E',
              accent: AresColors.cyan,
              tooltip: 'Mars Coordinated Time at the rover',
            ),
            const _TopDivider(),
            _ClockBlock(
              label: 'SIGNAL DELAY',
              value: state.owltLabel,
              sub: 'ROUND TRIP ${formatSeconds(state.owltSeconds * 2)}',
              width: 118,
              tooltip: 'One-way light time between Mars and Earth',
            ),
            const _TopDivider(),
            Tooltip(
              message: state.backendOnline
                  ? 'Connected to the ARES route-planning API'
                  : 'Using bundled archive data; routes computed on-device',
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      StatusDot(color: linkColor, size: 6),
                      const SizedBox(width: 6),
                      Text(
                        state.backendOnline ? 'LIVE API LINK' : 'ARCHIVE MODE',
                        style: AresType.label(
                          size: 10,
                          color: linkColor,
                          spacing: 0.7,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.backendStatusLabel,
                    style: AresType.monoStyle(size: 9, color: AresColors.dim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Tooltip(
              message: '$unacked.length unacknowledged alerts',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: warningCount > 0
                      ? AresColors.amber.withValues(alpha: 0.1)
                      : AresColors.bg1,
                  border: Border.all(
                    color: warningCount > 0
                        ? AresColors.amber.withValues(alpha: 0.5)
                        : AresColors.line,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      warningCount > 0
                          ? Icons.warning_amber_rounded
                          : Icons.notifications_none,
                      size: 15,
                      color: warningCount > 0
                          ? AresColors.amber
                          : AresColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      unacked.length.toString().padLeft(2, '0'),
                      style: AresType.monoStyle(
                        size: 12,
                        color: warningCount > 0
                            ? AresColors.amber
                            : AresColors.muted,
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
  }
}

class _TopDivider extends StatelessWidget {
  const _TopDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Container(width: 1, height: 28, color: AresColors.line),
  );
}

class _ClockBlock extends StatelessWidget {
  const _ClockBlock({
    required this.label,
    required this.value,
    required this.sub,
    this.accent = AresColors.text,
    this.width = 132,
    this.tooltip,
  });

  final String label;
  final String value;
  final String sub;
  final Color accent;
  final double width;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final block = SizedBox(
      width: width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AresType.label(size: 9, color: AresColors.dim, spacing: 0.8),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AresType.monoStyle(
              size: 13,
              color: accent,
              weight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AresType.monoStyle(size: 9, color: AresColors.dim),
          ),
        ],
      ),
    );
    if (tooltip == null) return block;
    return Tooltip(message: tooltip!, child: block);
  }
}

class _AresMark extends StatelessWidget {
  const _AresMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: CustomPaint(
        painter: _MarkPainter(),
        child: Center(
          child: Text(
            'A',
            style: AresType.displayStyle(
              size: 15,
              color: AresColors.cyan,
              spacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      final offset = Offset(
        center.dx + size.width * 0.44 * math.cos(angle),
        center.dy + size.height * 0.44 * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = AresColors.cyan.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AresNavRail extends StatelessWidget {
  const AresNavRail({super.key});

  static const _items = [
    (Icons.grid_view_rounded, 'MISSION', 'Mission overview and alerts'),
    (Icons.map_outlined, 'MAP', 'Surface map and route planning'),
    (Icons.terrain_outlined, 'TERRAIN', '3D relief and slope view'),
    (Icons.panorama_horizontal_outlined, 'SURFACE', 'Panorama image archive'),
    (Icons.science_outlined, 'SCIENCE', 'Weather charts and sample log'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return Container(
      width: 84,
      decoration: const BoxDecoration(
        color: AresColors.bg0,
        border: Border(right: BorderSide(color: AresColors.line)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          for (var i = 0; i < _items.length; i++)
            _NavItem(
              icon: _items[i].$1,
              label: _items[i].$2,
              tooltip: _items[i].$3,
              active: state.screenIndex == i,
              onTap: () => state.setScreen(i),
            ),
          const Spacer(),
          const _SideStatus(
            label: 'NAV',
            value: 'OK',
            color: AresColors.green,
            tooltip: 'Position fix is good',
          ),
          const _SideStatus(
            label: 'COMMS',
            value: 'SIM',
            color: AresColors.amber,
            tooltip: 'Relay link is simulated',
          ),
          const _SideStatus(
            label: 'SUIT O₂',
            value: '82%',
            color: AresColors.cyan,
            tooltip: 'Suit oxygen remaining · simulated',
          ),
          const SizedBox(height: 12),
          Container(width: 1, height: 20, color: AresColors.line),
          const SizedBox(height: 8),
          Text(
            'v1.0',
            style: AresType.monoStyle(size: 8.5, color: AresColors.dim),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Material(
          color: active
              ? AresColors.cyan.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            splashColor: AresColors.cyan.withValues(alpha: 0.12),
            child: SizedBox(
              height: 62,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: active ? AresColors.cyan : AresColors.muted,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    style: AresType.label(
                      size: 9.5,
                      color: active ? AresColors.cyan : AresColors.dim,
                      spacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideStatus extends StatelessWidget {
  const _SideStatus({
    required this.label,
    required this.value,
    required this.color,
    required this.tooltip,
  });

  final String label;
  final String value;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          children: [
            Text(
              label,
              style: AresType.label(
                size: 8.5,
                color: AresColors.dim,
                spacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(value, style: AresType.monoStyle(size: 10.5, color: color)),
          ],
        ),
      ),
    );
  }
}

class AresBottomBar extends StatelessWidget {
  const AresBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: AresColors.bg0,
        border: Border(top: BorderSide(color: AresColors.line)),
      ),
      child: Row(
        children: [
          Text(
            formatCoordinate(state.current),
            style: AresType.monoStyle(size: 9.5, color: AresColors.muted),
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 12, color: AresColors.line),
          const SizedBox(width: 14),
          Text(
            'Gale Crater · ${state.bounds.minLon} to ${state.bounds.maxLon}°E',
            style: AresType.monoStyle(size: 9.5, color: AresColors.dim),
          ),
          const Spacer(),
          Text(
            'DATA: NASA / THEMIS / MEDA · BUNDLED',
            style: AresType.label(size: 9, color: AresColors.dim, spacing: 0.7),
          ),
          const SizedBox(width: 14),
          Text(
            'TABLET BUILD 1.0.0',
            style: AresType.monoStyle(size: 9, color: AresColors.dim),
          ),
        ],
      ),
    );
  }
}
