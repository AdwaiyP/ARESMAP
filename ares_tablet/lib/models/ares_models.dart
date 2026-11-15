enum Provenance { live, cached, derived, model, sim, archive, noData }

class GeoPoint {
  const GeoPoint(this.lon, this.lat);

  final double lon;
  final double lat;

  @override
  String toString() => '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°';
}

class MapBounds {
  const MapBounds(this.minLon, this.minLat, this.maxLon, this.maxLat);

  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;

  double get widthDeg => maxLon - minLon;
  double get heightDeg => maxLat - minLat;
}

class MarsReference {
  const MarsReference({
    required this.id,
    required this.name,
    required this.category,
    required this.lon,
    required this.lat,
    required this.notes,
  });

  final String id;
  final String name;
  final String category;
  final double lon;
  final double lat;
  final String notes;

  GeoPoint get point => GeoPoint(lon, lat);
}

class ThemisStamp {
  const ThemisStamp({
    required this.fileId,
    required this.frameType,
    required this.lon,
    required this.lat,
    required this.tempK,
    required this.tempC,
    required this.albedo,
    required this.bands,
    required this.description,
    required this.tempStatus,
  });

  final String fileId;
  final String frameType;
  final double lon;
  final double lat;
  final double? tempK;
  final double? tempC;
  final double? albedo;
  final String bands;
  final String description;
  final String tempStatus;

  GeoPoint get point => GeoPoint(lon, lat);
}

class MedaRecord {
  const MedaRecord({
    required this.bucket,
    required this.airTempMean,
    required this.groundTempMean,
    required this.pressurePa,
    required this.opacity,
    required this.solarZenithDeg,
    required this.windValidFraction,
    required this.safetyState,
  });

  final String bucket;
  final double? airTempMean;
  final double? groundTempMean;
  final double? pressurePa;
  final double? opacity;
  final double? solarZenithDeg;
  final double windValidFraction;
  final String safetyState;
}

class SurfacePhoto {
  const SurfacePhoto({
    required this.asset,
    required this.title,
    required this.nasaId,
    required this.credit,
    required this.released,
    required this.location,
    required this.lon,
    required this.lat,
    required this.aspect,
    required this.note,
  });

  final String asset;
  final String title;
  final String nasaId;
  final String credit;
  final String released;
  final String location;
  final double lon;
  final double lat;
  final double aspect;
  final String note;

  GeoPoint get point => GeoPoint(lon, lat);
}

class MapFocus {
  const MapFocus({
    required this.id,
    required this.name,
    required this.kind,
    required this.detail,
    required this.lon,
    required this.lat,
    required this.provenance,
    this.tempC,
    this.albedo,
    this.frameType,
    this.stamp,
  });

  final String id;
  final String name;
  final String kind;
  final String detail;
  final double lon;
  final double lat;
  final Provenance provenance;
  final double? tempC;
  final double? albedo;
  final String? frameType;
  final ThemisStamp? stamp;

  GeoPoint get point => GeoPoint(lon, lat);
}

class TraversePlan {
  const TraversePlan({
    required this.points,
    required this.elevations,
    required this.distanceKm,
    required this.elevationGainM,
    required this.maxSlopeDeg,
    required this.duration,
    required this.targetName,
    required this.target,
    required this.cellSizeM,
    required this.hazardCells,
  });

  final List<GeoPoint> points;
  final List<double> elevations;
  final double distanceKm;
  final double elevationGainM;
  final double maxSlopeDeg;
  final Duration duration;
  final String targetName;
  final GeoPoint target;
  final double cellSizeM;
  final int hazardCells;

  String get durationLabel {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    return '${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m';
  }
}

class SampleRecord {
  const SampleRecord({
    required this.id,
    required this.label,
    required this.context,
    required this.point,
    required this.mtc,
    required this.provenance,
    required this.loggedAt,
  });

  final String id;
  final String label;
  final String context;
  final GeoPoint point;
  final String mtc;
  final Provenance provenance;
  final DateTime loggedAt;
}

enum AlertSeverity { info, caution, warning, critical }

class AresAlert {
  const AresAlert({
    required this.id,
    required this.severity,
    required this.title,
    required this.detail,
    required this.source,
    required this.provenance,
    this.acknowledged = false,
  });

  final String id;
  final AlertSeverity severity;
  final String title;
  final String detail;
  final String source;
  final Provenance provenance;
  final bool acknowledged;

  AresAlert copyWith({bool? acknowledged}) => AresAlert(
    id: id,
    severity: severity,
    title: title,
    detail: detail,
    source: source,
    provenance: provenance,
    acknowledged: acknowledged ?? this.acknowledged,
  );
}
