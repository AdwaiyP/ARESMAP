import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/ares_models.dart';

class AresDataset {
  AresDataset({
    required this.region,
    required this.crs,
    required this.bounds,
    required this.references,
    required this.stamps,
    required this.meda,
    required this.photos,
    this.curiosityTrail = const [],
  });

  final String region;
  final String crs;
  final MapBounds bounds;
  final List<MarsReference> references;
  final List<ThemisStamp> stamps;
  final List<MedaRecord> meda;
  final List<SurfacePhoto> photos;
  final List<GeoPoint> curiosityTrail;

  MarsReference get landingSite => references.firstWhere(
    (r) => r.id == 'bradbury_landing',
    orElse: () => references.first,
  );

  MarsReference get veraRubin => references.firstWhere(
    (r) => r.id == 'vera_rubin_ridge',
    orElse: () => references.first,
  );

  static Future<AresDataset> load() async {
    final gale = jsonDecode(
      await rootBundle.loadString('assets/data/gale_spatial_bundle.json'),
    ) as Map<String, dynamic>;
    final geojson = jsonDecode(
      await rootBundle.loadString('assets/data/themis_stamps.geojson'),
    ) as Map<String, dynamic>;
    final meda = jsonDecode(
      await rootBundle.loadString('assets/data/telemetry_15min_sol100.json'),
    ) as Map<String, dynamic>;

    final bbox = (gale['bbox_lon_lat'] as List).cast<num>();
    final bounds = MapBounds(
      bbox[0].toDouble(),
      bbox[1].toDouble(),
      bbox[2].toDouble(),
      bbox[3].toDouble(),
    );

    final references = (gale['reference_locations'] as List)
        .map((raw) {
          final map = raw as Map<String, dynamic>;
          return MarsReference(
            id: map['id'] as String,
            name: map['name'] as String,
            category: map['category'] as String,
            lon: (map['lon_deg'] as num).toDouble(),
            lat: (map['lat_deg'] as num).toDouble(),
            notes: map['notes'] as String,
          );
        })
        .toList(growable: false);

    final stamps = (geojson['features'] as List)
        .map((raw) {
          final p =
              (raw as Map<String, dynamic>)['properties']
                  as Map<String, dynamic>;
          return ThemisStamp(
            fileId: p['file_id'] as String,
            frameType: p['frame_type'] as String,
            lon: (p['lon_deg'] as num).toDouble(),
            lat: (p['lat_deg'] as num).toDouble(),
            tempK: _nullableDouble(p['surf_temp_k']),
            tempC: _nullableDouble(p['surf_temp_c']),
            albedo: _nullableDouble(p['alb_avg']),
            bands: '${p['bands']}',
            description: (p['description'] as String?) ?? '',
            tempStatus: '${p['temp_status']}',
          );
        })
        .toList(growable: false);

    final records = (meda['records'] as List)
        .map((raw) {
          final r = raw as Map<String, dynamic>;
          return MedaRecord(
            bucket: r['lmst_bucket'] as String,
            airTempMean: _nullableDouble(r['air_temp_c_mean']),
            groundTempMean: _nullableDouble(r['ground_ir_temp_c_mean']),
            pressurePa: _nullableDouble(r['pressure_barocap1_pa_mean']),
            opacity: _nullableDouble(r['optical_rds_top7_mean']),
            solarZenithDeg: _nullableDouble(r['solar_zenith_deg_mean']),
            windValidFraction:
                (r['wind_valid_fraction'] as num?)?.toDouble() ?? 0,
            safetyState: '${r['safety_state']}',
          );
        })
        .toList(growable: false);

    final exploration = jsonDecode(
      await rootBundle.loadString('assets/data/exploration.json'),
    ) as List;
    final curiosity = exploration
        .where((f) => f['kind'] == 'Curiosity')
        .map(
          (f) => GeoPoint(
            (f['lon'] as num).toDouble(),
            (f['lat'] as num).toDouble(),
          ),
        )
        .toList();
    return AresDataset(
      curiosityTrail: curiosity,
      region: '${gale['region']}',
      crs: '${gale['crs']}',
      bounds: bounds,
      references: references,
      stamps: stamps,
      meda: records,
      photos: _photos,
    );
  }
}

double? _nullableDouble(Object? value) =>
    value == null ? null : (value as num).toDouble();

const _photos = [
  SurfacePhoto(
    asset: 'assets/images/surface/pia16101_mount_sharp_pan.jpg',
    title: 'Landing Site Panorama, with the Heights of Mount Sharp',
    nasaId: 'PIA16101',
    credit: 'NASA / JPL-Caltech',
    released: '2012-08-27',
    location: 'BRADBURY LANDING · AEOLIS PALUS',
    lon: 137.4417,
    lat: -4.5895,
    aspect: 1919 / 471,
    note: 'Mosaic from Curiosity looking south toward the base of Aeolis Mons. Real NASA archive imagery.',
  ),
  SurfacePhoto(
    asset: 'assets/images/surface/pia21268_full_circle_dune.jpg',
    title: 'Full-Circle Vista With a Linear Shaped Martian Sand Dune',
    nasaId: 'PIA21268',
    credit: 'NASA / JPL-Caltech',
    released: '2017-02-27',
    location: 'BAGNOLD DUNES · GALE CRATER',
    lon: 137.42,
    lat: -4.75,
    aspect: 1280 / 277,
    note: 'Panorama near the Bagnold dune field. Surface coordinates for the overlay are approximate (SIM).',
  ),
  SurfacePhoto(
    asset: 'assets/images/surface/pia19803_geology_ahead.jpg',
    title: 'Curiosity Rover View of Alluring Martian Geology Ahead',
    nasaId: 'PIA19803',
    credit: 'NASA / JPL-Caltech',
    released: '2015-08-05',
    location: 'MARIAS PASS · GALE CRATER',
    lon: 137.39,
    lat: -4.8,
    aspect: 1920 / 494,
    note: 'View toward the foothills of Mount Sharp. Real NASA archive image; heading overlay simulated.',
  ),
  SurfacePhoto(
    asset: 'assets/images/surface/pia21717_vera_rubin.jpg',
    title: "Wide 'Vera Rubin Ridge' Ahead of Curiosity Mars Rover",
    nasaId: 'PIA21717',
    credit: 'NASA / JPL-Caltech',
    released: '2017-07-11',
    location: 'VERA RUBIN RIDGE · MOUNT SHARP',
    lon: 137.35,
    lat: -4.69,
    aspect: 10000 / 727,
    note: '180-degree Mastcam panorama of the hematite-bearing ridge. Real NASA archive image.',
  ),
];
