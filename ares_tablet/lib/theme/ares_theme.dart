import 'package:flutter/material.dart';

import '../models/ares_models.dart';

abstract final class AresColors {
  static const bg0 = Color(0xFF06090C);
  static const bg1 = Color(0xFF0D141B);
  static const bg2 = Color(0xFF131D26);
  static const line = Color(0xFF22333F);
  static const lineHot = Color(0xFF35566A);
  static const text = Color(0xFFE4EDF3);
  static const muted = Color(0xFF9DB2BE);
  static const dim = Color(0xFF7E95A3);
  static const cyan = Color(0xFF38E1FF);
  static const amber = Color(0xFFFFB454);
  static const green = Color(0xFF53E08B);
  static const red = Color(0xFFFF5A5F);
  static const violet = Color(0xFFB58CFF);
}

abstract final class AresType {
  static const display = 'BarlowCondensed';
  static const mono = 'IBMPlexMono';

  static TextStyle label({
    double size = 10.5,
    Color color = AresColors.muted,
    FontWeight weight = FontWeight.w600,
    double spacing = 0.6,
  }) => TextStyle(
    fontFamily: display,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    color: color,
    height: 1.2,
  );

  static TextStyle displayStyle({
    double size = 26,
    Color color = AresColors.text,
    FontWeight weight = FontWeight.w600,
    double spacing = 0.4,
  }) => TextStyle(
    fontFamily: display,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    color: color,
    height: 1.05,
  );

  static TextStyle monoStyle({
    double size = 12,
    Color color = AresColors.text,
    FontWeight weight = FontWeight.w500,
    double spacing = 0.1,
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
    letterSpacing: 0.1,
  );

  static const bodyMuted = TextStyle(
    fontSize: 11.5,
    height: 1.45,
    color: AresColors.muted,
    letterSpacing: 0.1,
  );
}

ThemeData buildAresTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: AresColors.cyan,
      onPrimary: AresColors.bg0,
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
        color: AresColors.bg2,
        border: Border.all(color: AresColors.lineHot),
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: AresType.label(size: 10.5, color: AresColors.text),
      waitDuration: const Duration(milliseconds: 400),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AresColors.cyan,
      inactiveTrackColor: AresColors.line,
      thumbColor: AresColors.cyan,
      overlayColor: Color(0x2238E1FF),
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AresColors.bg2,
      contentTextStyle: AresType.body,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AresColors.lineHot),
      ),
      width: 460,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AresColors.lineHot),
      thickness: WidgetStateProperty.all(4),
      radius: const Radius.circular(2),
    ),
  );
}

Color provenanceColor(Provenance provenance) => switch (provenance) {
  Provenance.live => AresColors.green,
  Provenance.cached => AresColors.cyan,
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
  AlertSeverity.info => AresColors.cyan,
  AlertSeverity.caution => AresColors.amber,
  AlertSeverity.warning => AresColors.amber,
  AlertSeverity.critical => AresColors.red,
};