import 'dart:math' as math;

import '../models/ares_models.dart';

const _unixJ2000 = 946728000.0;
const _solSeconds = 88775.244;
const marsRadiusKm = 3389.5;

class MarsClock {
  const MarsClock({
    required this.msd,
    required this.mtc,
    required this.mtcSeconds,
    required this.localSolarHours,
  });

  final double msd;
  final String mtc;
  final int mtcSeconds;
  final double localSolarHours;

  String get msdLabel => msd.toStringAsFixed(3);
  String get solLabel => msd.floor().toString();
}

MarsClock marsClockAt(DateTime utc, {double lonDeg = 137.4}) {
  final deltaS = utc.millisecondsSinceEpoch / 1000.0 - _unixJ2000;
  final msd = (deltaS / _solSeconds) + 44796.0 - 0.00096;
  final frac = msd - msd.floorToDouble();
  final mtcSec = (frac * 86400).floor();
  final hh = mtcSec ~/ 3600;
  final mm = (mtcSec % 3600) ~/ 60;
  final ss = mtcSec % 60;
  final mtcHours = mtcSec / 3600.0;
  final local = (mtcHours + lonDeg / 15.0) % 24.0;
  return MarsClock(
    msd: msd,
    mtc: '${_two(hh)}:${_two(mm)}:${_two(ss)}',
    mtcSeconds: mtcSec,
    localSolarHours: local,
  );
}

String _two(int value) => value.toString().padLeft(2, '0');

/// Low-precision one-way light time using circular heliocentric orbits.
/// Accurate to minutes, not suitable for commanding.
double oneWayLightSeconds(DateTime utc) {
  final days = utc.millisecondsSinceEpoch / 86400000.0 + 2440587.5 - 2451545.0;
  final earthLon = _rad(100.464 + 0.9856091199 * days);
  final marsLon = _rad(355.453 + 0.5240207766 * days);
  const auKm = 149597870.7;
  const earthR = 1.00000011;
  const marsR = 1.52371034;
  final ex = earthR * math.cos(earthLon);
  final ey = earthR * math.sin(earthLon);
  final mx = marsR * math.cos(marsLon);
  final my = marsR * math.sin(marsLon);
  final distanceKm =
      math.sqrt(math.pow(ex - mx, 2) + math.pow(ey - my, 2)) * auKm;
  return distanceKm / 299792.458;
}

double _rad(double deg) => deg * math.pi / 180.0;

class SolarPosition {
  const SolarPosition({required this.azimuthDeg, required this.elevationDeg});

  final double azimuthDeg;
  final double elevationDeg;

  bool get isUp => elevationDeg > 0;
}

/// Approximate solar geometry at Gale Crater for the current Mars season.
SolarPosition solarPosition(GeoPoint point, MarsClock clock) {
  final season = ((clock.msd - 44796.0) / 668.6) * 2 * math.pi;
  final declination = _rad(25.2) * math.sin(season);
  final hourAngle = _rad((clock.localSolarHours - 12.0) * 15.0);
  final lat = _rad(point.lat);
  final sinElevation =
      math.sin(lat) * math.sin(declination) +
      math.cos(lat) * math.cos(declination) * math.cos(hourAngle);
  final elevation = math.asin(sinElevation.clamp(-1.0, 1.0));
  final azimuth =
      math.atan2(
        math.sin(hourAngle),
        math.cos(hourAngle) * math.sin(lat) -
            math.tan(declination) * math.cos(lat),
      ) +
      math.pi;
  return SolarPosition(
    azimuthDeg: (azimuth * 180.0 / math.pi + 360.0) % 360.0,
    elevationDeg: elevation * 180.0 / math.pi,
  );
}

double haversineKm(GeoPoint a, GeoPoint b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final lat1 = _rad(a.lat);
  final lat2 = _rad(b.lat);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
  return 2 * marsRadiusKm * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
}

double initialBearingDeg(GeoPoint from, GeoPoint to) {
  final lat1 = _rad(from.lat);
  final lat2 = _rad(to.lat);
  final dLon = _rad(to.lon - from.lon);
  final y = math.sin(dLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
}

String compass16(double bearing) {
  const names = [
    'N',
    'NNE',
    'NE',
    'ENE',
    'E',
    'ESE',
    'SE',
    'SSE',
    'S',
    'SSW',
    'SW',
    'WSW',
    'W',
    'WNW',
    'NW',
    'NNW',
  ];
  return names[((bearing / 22.5).round() % 16)];
}

String formatDuration(Duration duration) {
  final h = duration.inHours;
  final m = duration.inMinutes.remainder(60);
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m';
  }
  return '${m}m ${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}s';
}

String formatSeconds(double seconds) {
  final d = Duration(seconds: seconds.round());
  return formatDuration(d);
}

String formatCoordinate(GeoPoint point) {
  final lat = point.lat.abs().toStringAsFixed(4);
  final lon = point.lon.abs().toStringAsFixed(4);
  return '$lat°${point.lat >= 0 ? 'N' : 'S'}  $lon°${point.lon >= 0 ? 'E' : 'W'}';
}

String formatUtc(DateTime utc) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
}

double median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}
