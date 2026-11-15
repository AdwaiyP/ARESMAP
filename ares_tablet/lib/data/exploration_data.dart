import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ares_models.dart';

class SurveyFeature {
  const SurveyFeature({
    required this.id,
    required this.name,
    required this.point,
    required this.kind,
    required this.notes,
    required this.source,
    this.elevation,
  });

  final String id;
  final String name;
  final GeoPoint point;
  final String kind;
  final String notes;
  final String source;
  final double? elevation;

  factory SurveyFeature.fromJson(Map<String, dynamic> json) => SurveyFeature(
    id: json['id'] as String,
    name: json['name'] as String,
    point: GeoPoint(
      (json['lon'] as num).toDouble(),
      (json['lat'] as num).toDouble(),
    ),
    kind: json['kind'] as String,
    notes: json['notes'] as String,
    source: json['source'] as String,
    elevation: (json['elevation'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lon': point.lon,
    'lat': point.lat,
    'kind': kind,
    'notes': notes,
    'source': source,
    if (elevation != null) 'elevation': elevation,
  };
}

class ExplorationData {
  ExplorationData(this.catalog, this.planned, this.storage);
  final List<SurveyFeature> catalog;
  final List<SurveyFeature> planned;
  final File storage;

  static Future<ExplorationData> load() async {
    final raw = jsonDecode(
      await rootBundle.loadString('assets/data/exploration.json'),
    ) as List;
    final directory = await getApplicationSupportDirectory();
    final storage = File('${directory.path}/planned_waypoints.json');
    final planned = await storage.exists()
        ? (jsonDecode(await storage.readAsString()) as List)
              .map((e) => SurveyFeature.fromJson(e as Map<String, dynamic>))
              .toList()
        : <SurveyFeature>[];
    return ExplorationData(
      raw
          .map((e) => SurveyFeature.fromJson(e as Map<String, dynamic>))
          .toList(),
      planned,
      storage,
    );
  }

  Future<void> save(List<SurveyFeature> points) async {
    await storage.parent.create(recursive: true);
    final pending = File('${storage.path}.pending');
    await pending.writeAsString(
      jsonEncode(points.map((e) => e.toJson()).toList()),
      flush: true,
    );
    await pending.rename(storage.path);
    planned
      ..clear()
      ..addAll(points);
  }
}
