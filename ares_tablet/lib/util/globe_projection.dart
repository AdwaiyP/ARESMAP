import 'dart:math' as math;

import '../models/ares_models.dart';

(double, double, double) projectGlobe(
  GeoPoint point,
  double longitude,
  double latitude,
) {
  final lon = (point.lon - longitude) * math.pi / 180;
  final lat = point.lat * math.pi / 180;
  final tilt = latitude * math.pi / 180;
  final x = math.cos(lat) * math.sin(lon);
  final y = math.sin(lat);
  final z = math.cos(lat) * math.cos(lon);
  return (
    x,
    y * math.cos(tilt) - z * math.sin(tilt),
    y * math.sin(tilt) + z * math.cos(tilt),
  );
}

GeoPoint? unprojectGlobe(
  double x,
  double y,
  double longitude,
  double latitude,
) {
  final r = x * x + y * y;
  if (r > 1) return null;
  final z = math.sqrt(1 - r);
  final tilt = latitude * math.pi / 180;
  final worldY = y * math.cos(tilt) + z * math.sin(tilt);
  final worldZ = -y * math.sin(tilt) + z * math.cos(tilt);
  return GeoPoint(
    (longitude + math.atan2(x, worldZ) * 180 / math.pi + 540) % 360 - 180,
    math.asin(worldY.clamp(-1.0, 1.0)) * 180 / math.pi,
  );
}
