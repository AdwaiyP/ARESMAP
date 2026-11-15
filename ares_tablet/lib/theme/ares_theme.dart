import 'package:flutter/material.dart';

import '../models/ares_models.dart';

abstract final class AresColors {
  // iOS Dark / Crew Dragon Neutral Carbon Palette (matching frontend/styles.css)
  static const bg0 = Color(0xFF09090B);
  static const bg1 = Color(0xFF141417);
  static const bg2 = Color(0xFF1C1C20);
  static const surfaceSolid = Color(0xFF161618);
  static const surfaceGroup = Color(0x0BFFFFFF); // rgba(255, 255, 255, 0.045)
  static const surfaceControl = Color(0x13FFFFFF); // rgba(255, 255, 255, 0.075)
  static const surfaceControlHover = Color(0x1FFFFFFF); // rgba(255, 255, 255, 0.12)
  static const line = Color(0x16FFFFFF); // rgba(255, 255, 255, 0.085)
  static const lineHot = Color(0x26FFFFFF); // rgba(255, 255, 255, 0.15)

  // Typography Colors
  static const text = Color(0xFFF5F5F7);
  static const textSecondary = Color(0xFFA1A1AA);
  static const muted = Color(0xFF8E8E93);
  static const dim = Color(0xFF71717A);

  // Semantic Apple System Colors
  static const blue = Color(0xFF0A84FF);
  static const blueTint = Color(0x290A84FF);
  static const cyan = Color(0xFF0A84FF); // Mapped to system blue for backwards compatibility
  static const green = Color(0xFF30D158);
  static const greenTint = Color(0x2930D158);
  static const amber = Color(0xFFFF9F0A);
  static const amberTint = Color(0x29FF9F0A);
  static const red = Color(0xFFFF453A);
  static const redTint = Color(0x2EFF453A);
  static const violet = Color(0xFFA855F7);
  static const pink = Color(0xFFEC4899);
  static const teal = Color(0xFF06B6D4);
  static const yellow = Color(0xFFEAB308);
}

abstract final class AresType {
  static const display = 'BarlowCondensed';
  static const mono = 'IBMPlexMono';

  static TextStyle label({
    double size = 11.0,
    Color color = AresColors.muted,
    FontWeight weight = FontWeight.w600,
    double spacing = 0.4,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    color: color,
    height: 1.2,
  );

  static TextStyle displayStyle({
    double size = 24,
    Color color = AresColors.text,
    FontWeight weight = FontWeight.w600,
    double spacing = 0.2,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    color: color,
    height: 1.1,
  );

  static TextStyle monoStyle({
    double size = 11.5,
    Color color = AresColors.text,
    FontWeight weight = FontWeight.w500,
    double spacing = 0.0,
  }) => TextStyle(
    fontFamily: mono,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    color: color,
    height: 1.25,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static const body = TextStyle(
    fontSize: 12.5,
    height: 1.45,
    color: AresColors.text,
    letterSpacing: -0.1,
  );

  static const bodyMuted = TextStyle(
    fontSize: 11.5,
    height: 1.45,
    color: AresColors.muted,
    letterSpacing: -0.1,
  );
}

ThemeData buildAresTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: AresColors.blue,
      onPrimary: Colors.white,
      secondary: AresColors.amber,
      onSecondary: AresColors.bg0,
      surface: AresColors.bg1,
      onSurface: AresColors.text,
      error: AresColors.red,
      outline: AresColors.line,
    ),
    scaffoldBackgroundColor: AresColors.bg0,
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      bodyMedium: AresType.body,
      bodySmall: AresType.bodyMuted,
      labelLarge: AresType.label(size: 11.5),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xF0141417),
        border: Border.all(color: AresColors.lineHot),
        borderRadius: BorderRadius.circular(7),
      ),
      textStyle: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        color: AresColors.text,
      ),
      waitDuration: const Duration(milliseconds: 350),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AresColors.blue,
      inactiveTrackColor: Color(0x26FFFFFF),
      thumbColor: Colors.white,
      overlayColor: Color(0x220A84FF),
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AresColors.bg2,
      contentTextStyle: AresType.body,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AresColors.lineHot),
      ),
      width: 460,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(const Color(0x30FFFFFF)),
      thickness: WidgetStateProperty.all(5),
      radius: const Radius.circular(999),
    ),
  );
}

Color provenanceColor(Provenance provenance) => switch (provenance) {
  Provenance.live => AresColors.green,
  Provenance.cached => AresColors.blue,
  Provenance.derived => AresColors.violet,
  Provenance.model => AresColors.amber,
  Provenance.sim => AresColors.amber,
  Provenance.archive => AresColors.muted,
  Provenance.noData => AresColors.red,
};

String provenanceLabel(Provenance provenance) => switch (provenance) {
  Provenance.live => 'LIVE',
  Provenance.cached => 'CACHED',
  Provenance.derived => 'DERIVED',
  Provenance.model => 'MODEL',
  Provenance.sim => 'SIM',
  Provenance.archive => 'ARCHIVE',
  Provenance.noData => 'NO DATA',
};

Color severityColor(AlertSeverity severity) => switch (severity) {
  AlertSeverity.info => AresColors.blue,
  AlertSeverity.caution => AresColors.amber,
  AlertSeverity.warning => AresColors.amber,
  AlertSeverity.critical => AresColors.red,
};
