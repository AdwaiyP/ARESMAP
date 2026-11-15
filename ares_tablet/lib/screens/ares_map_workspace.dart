import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/exploration_data.dart';
import '../models/ares_models.dart';
import '../state/ares_scope.dart';
import '../state/ares_state.dart';
import '../theme/ares_theme.dart';
import '../util/astro.dart';
import 'ares_streetview_modal.dart';
import 'ares_terrain_modal.dart';

class _JumpPreset {
  const _JumpPreset({
    required this.id,
    required this.label,
    required this.title,
    required this.lon,
    required this.lat,
    required this.zoom,
  });

  final String id;
  final String label;
  final String title;
  final double lon;
  final double lat;
  final double zoom;
}

class _MineralSite {
  const _MineralSite({
    required this.id,
    required this.name,
    required this.mineral,
    required this.hydrationPct,
    required this.instrument,
    required this.lon,
    required this.lat,
    required this.notes,
  });

  final String id;
  final String name;
  final String mineral;
  final double hydrationPct;
  final String instrument;
  final double lon;
  final double lat;
  final String notes;
}

class _GlobalLandmark {
  const _GlobalLandmark({
    required this.id,
    required this.name,
    required this.category,
    required this.diameterKm,
    required this.lon,
    required this.lat,
    required this.notes,
  });

  final String id;
  final String name;
  final String category;
  final double diameterKm;
  final double lon;
  final double lat;
  final String notes;
}

class _SafetyCheck {
  const _SafetyCheck({
    required this.label,
    required this.value,
    required this.status, // 'GO' | 'CAUTION' | 'NO-GO'
  });

  final String label;
  final String value;
  final String status;
}

class _TourStep {
  const _TourStep({
    required this.title,
    required this.body,
    required this.openLeftDrawer,
    required this.openRightDrawer,
  });

  final String title;
  final String body;
  final bool openLeftDrawer;
  final bool openRightDrawer;
}

class AresMapWorkspace extends StatefulWidget {
  const AresMapWorkspace({super.key});

  @override
  State<AresMapWorkspace> createState() => _AresMapWorkspaceState();
}

class _AresMapWorkspaceState extends State<AresMapWorkspace> {
  static const List<_JumpPreset> _jumpPresets = [
    _JumpPreset(
      id: 'global',
      label: 'Whole Mars',
      title: 'Whole Mars Global Mosaic',
      lon: 137.4,
      lat: -4.6,
      zoom: 1.0,
    ),
    _JumpPreset(
      id: 'mount_sharp',
      label: 'Mount Sharp',
      title: 'Mount Sharp (Aeolis Mons)',
      lon: 137.85,
      lat: -5.08,
      zoom: 14.0,
    ),
    _JumpPreset(
      id: 'gale',
      label: 'Gale Crater',
      title: 'Gale Crater · Bradbury Landing',
      lon: 137.4417,
      lat: -4.5895,
      zoom: 28.0,
    ),
    _JumpPreset(
      id: 'jezero',
      label: 'Jezero (M20)',
      title: 'Jezero Crater · Perseverance',
      lon: 77.4509,
      lat: 18.4446,
      zoom: 26.0,
    ),
    _JumpPreset(
      id: 'ares_vallis',
      label: 'Ares Vallis',
      title: 'Ares Vallis · Pathfinder',
      lon: -33.22,
      lat: 19.13,
      zoom: 12.0,
    ),
    _JumpPreset(
      id: 'gusev',
      label: 'Gusev Crater',
      title: 'Gusev Crater · Spirit',
      lon: 175.47,
      lat: -14.57,
      zoom: 12.0,
    ),
    _JumpPreset(
      id: 'meridiani',
      label: 'Meridiani Planum',
      title: 'Meridiani Planum · Opportunity',
      lon: -5.53,
      lat: -1.95,
      zoom: 12.0,
    ),
    _JumpPreset(
      id: 'valles',
      label: 'Valles Marineris',
      title: 'Valles Marineris Canyon System',
      lon: -59.2,
      lat: -13.9,
      zoom: 4.5,
    ),
  ];

  static const List<_MineralSite> _mineralSites = [
    _MineralSite(
      id: 'min_1',
      name: 'Glen Torridon Clay Unit',
      mineral: 'Fe/Mg Smectite (Phyllosilicate)',
      hydrationPct: 8.4,
      instrument: 'CRISM + CheMin',
      lon: 137.392,
      lat: -4.722,
      notes: 'High-priority hydrated clay horizon indicating sustained neutral-pH lacustrine groundwater.',
    ),
    _MineralSite(
      id: 'min_2',
      name: 'Vera Rubin Hematite Crest',
      mineral: 'Crystalline Gray Hematite (Fe₂O₃)',
      hydrationPct: 4.2,
      instrument: 'CRISM FRT0000B6F',
      lon: 137.405,
      lat: -4.710,
      notes: 'Erosion-resistant diagenetic ridge enriched in ferric oxide nodules.',
    ),
    _MineralSite(
      id: 'min_3',
      name: 'Marker Band Sulfate Transition',
      mineral: 'Mg-Sulfate (Kieserite / Starkeyite)',
      hydrationPct: 9.8,
      instrument: 'CRISM + ChemCam',
      lon: 137.418,
      lat: -4.785,
      notes: 'Polyhydrated and monohydrated magnesium sulfates recording evaporative drying of Gale lake.',
    ),
    _MineralSite(
      id: 'min_4',
      name: 'Gediz Vallis Hydrated Fan',
      mineral: 'Hydrated Silica & Phyllosilicates',
      hydrationPct: 11.2,
      instrument: 'CRISM + Mastcam-Z',
      lon: 137.435,
      lat: -4.812,
      notes: 'Late-stage debris flow deposit carrying opal-A / hydrated silica clasts from upper Mount Sharp.',
    ),
    _MineralSite(
      id: 'min_5',
      name: 'Jezero Marginal Carbonate Unit',
      mineral: 'Mg-Fe Carbonate + Olivine',
      hydrationPct: 7.6,
      instrument: 'CRISM + PIXL',
      lon: 77.412,
      lat: 18.458,
      notes: 'Ancient lakeshore littoral carbonate beach deposit with high biosignature preservation potential.',
    ),
    _MineralSite(
      id: 'min_6',
      name: 'Neretva Vallis Bright Angel',
      mineral: 'Ca-Sulfate Veins & Clay Matrix',
      hydrationPct: 10.5,
      instrument: 'SHERLOC + PIXL',
      lon: 77.388,
      lat: 18.469,
      notes: 'Fine-grained mudstone hosting organic-carbon-bearing redox reaction fronts (Cheyava Falls).',
    ),
  ];

  static const List<_GlobalLandmark> _globalLandmarks = [
    _GlobalLandmark(
      id: 'lm_olympus',
      name: 'Olympus Mons',
      category: 'Mons (Shield Volcano)',
      diameterKm: 610.0,
      lon: -133.8,
      lat: 18.65,
      notes: 'Tallest planetary mountain in the Solar System (+21.9 km above MOLA datum).',
    ),
    _GlobalLandmark(
      id: 'lm_valles',
      name: 'Valles Marineris',
      category: 'Vallis (Tectonic Canyon)',
      diameterKm: 3770.0,
      lon: -59.2,
      lat: -13.9,
      notes: 'Vast tectonic rift canyon system spanning 4,000 km along the Martian equator.',
    ),
    _GlobalLandmark(
      id: 'lm_gale',
      name: 'Gale Crater',
      category: 'Crater · MSL Curiosity Site',
      diameterKm: 154.0,
      lon: 137.8,
      lat: -5.4,
      notes: '154 km impact basin with 5.5 km central sedimentary mound (Aeolis Mons / Mount Sharp).',
    ),
    _GlobalLandmark(
      id: 'lm_jezero',
      name: 'Jezero Crater',
      category: 'Crater · Mars 2020 Site',
      diameterKm: 45.0,
      lon: 77.58,
      lat: 18.38,
      notes: 'Noachian paleolake basin with preserved western river delta fan.',
    ),
    _GlobalLandmark(
      id: 'lm_ares',
      name: 'Ares Vallis',
      category: 'Vallis · Pathfinder Site',
      diameterKm: 1700.0,
      lon: -33.22,
      lat: 19.13,
      notes: 'Catastrophic outflow channel debouching into Chryse Planitia.',
    ),
    _GlobalLandmark(
      id: 'lm_gusev',
      name: 'Gusev Crater',
      category: 'Crater · MER-A Spirit Site',
      diameterKm: 166.0,
      lon: 175.47,
      lat: -14.57,
      notes: 'Impact crater entered by Ma\'adim Vallis hosting the Columbia Hills hydrothermal silica deposits.',
    ),
    _GlobalLandmark(
      id: 'lm_meridiani',
      name: 'Meridiani Planum',
      category: 'Planum · MER-B Opportunity Site',
      diameterKm: 1100.0,
      lon: -5.53,
      lat: -1.95,
      notes: 'Equatorial plains rich in crystalline hematite ("blueberries") and jarosite evaporites.',
    ),
    _GlobalLandmark(
      id: 'lm_hellas',
      name: 'Hellas Planitia',
      category: 'Planitia (Impact Basin)',
      diameterKm: 2300.0,
      lon: 70.0,
      lat: -42.4,
      notes: 'Deepest impact basin on Mars (-7,152 m MOLA datum) with highest surface atmospheric pressure.',
    ),
    _GlobalLandmark(
      id: 'lm_elysium',
      name: 'Elysium Planitia',
      category: 'Planitia · InSight Site',
      diameterKm: 3000.0,
      lon: 135.62,
      lat: 4.5,
      notes: 'Smooth volcanic plains straddling the equator; landing site of the InSight geophysical lander.',
    ),
    _GlobalLandmark(
      id: 'lm_syrtis',
      name: 'Syrtis Major Planum',
      category: 'Planum (Volcanic Shield)',
      diameterKm: 1350.0,
      lon: 69.5,
      lat: 8.4,
      notes: 'Classic low-albedo basaltic shield bordering western Isidis Planitia.',
    ),
    _GlobalLandmark(
      id: 'lm_utopia',
      name: 'Utopia Planitia',
      category: 'Planitia · Viking 2 & Zhurong',
      diameterKm: 3300.0,
      lon: 110.0,
      lat: 46.7,
      notes: 'Northern lowland basin underlain by massive scalloped periglacial water-ice deposits.',
    ),
    _GlobalLandmark(
      id: 'lm_alba',
      name: 'Alba Mons',
      category: 'Mons (Volcano)',
      diameterKm: 1600.0,
      lon: -109.9,
      lat: 40.5,
      notes: 'Broadest volcanic edifice on Mars surrounded by concentric graben fossae.',
    ),
  ];

  static const List<_TourStep> _tourSteps = [
    _TourStep(
      title: '1 / 11 · Welcome to ARES MAP',
      body: 'ARES MAP is a Mission-Grade Mars EVA Tactical GIS & 3D Surface Simulation System built for astronauts and mission controllers. Let\'s take a quick tour of every tool.',
      openLeftDrawer: false,
      openRightDrawer: false,
    ),
    _TourStep(
      title: '2 / 11 · Live Mars Chronometer & Telemetry Strip',
      body: 'The top status bar tracks real-time Mars Season (MY / Ls), Mars Sol Date (MSD), Coordinated Mars Time (MTC), Local Mean Solar Time (LMST) at Gale Crater, Earth UTC, One-Way Light Time (OWLT), and cursor coordinates in IAU:49900.',
      openLeftDrawer: false,
      openRightDrawer: false,
    ),
    _TourStep(
      title: '3 / 11 · Quick Jump & Custom Bookmarks',
      body: 'Instantly fly between Whole Mars, Mount Sharp, Gale Crater, Jezero (M20), Ares Vallis, Gusev, Meridiani, and Valles Marineris — or save your own custom Quick Jump coordinates.',
      openLeftDrawer: true,
      openRightDrawer: false,
    ),
    _TourStep(
      title: '4 / 11 · 3D Mars Globe & Regional DEM Terrain',
      body: 'Open the interactive 3D Mars Globe (with Viking True Color & MOLA Elevation textures) or the 3D Regional Terrain mesh with adjustable vertical exaggeration and direct EVA route plotting.',
      openLeftDrawer: true,
      openRightDrawer: false,
    ),
    _TourStep(
      title: '5 / 11 · Immersive 360° Mars Street View & Visor HUD',
      body: 'Launch Mars Street View to walk the Martian surface in 360° with real NASA Curiosity & Perseverance panoramas, Drone/Astronaut/Rover/Overview modes, and live waypoint navigation.',
      openLeftDrawer: true,
      openRightDrawer: false,
    ),
    _TourStep(
      title: '6 / 11 · A* & Theta* Safe EVA Path Planner',
      body: 'Configure distance budget, max slope, suit O₂, and dust storm conditions, then click "Plan Safe EVA Route" and pick two points on the map to compute a terrain-aware traverse.',
      openLeftDrawer: true,
      openRightDrawer: false,
    ),
    _TourStep(
      title: '7 / 11 · Multi-Layer Planetary GIS & Vector Overlays',
      body: 'Switch between 4 global planetary base maps, 4 high-resolution regional orbital overlays, and 8 vector layers including CRISM Mineral Signatures, 730 THEMIS Thermal Stamps, and Rover Waypoints.',
      openLeftDrawer: true,
      openRightDrawer: false,
    ),
    _TourStep(
      title: '8 / 11 · PLSS Life Support Simulator (EVA-1)',
      body: 'Monitor real-time astronaut O₂ pressure, battery, cooling water, and metabolic load. Adjust initial reserves or metabolic workload to stress-test EVA safety margins.',
      openLeftDrawer: false,
      openRightDrawer: true,
    ),
    _TourStep(
      title: '9 / 11 · Orbital Relay & EDAC Bit-Flip Fault Injection',
      body: 'Track Odyssey/MRO UHF relay passes and test radiation-hardened packet integrity using the "Test Bit-Flip EDAC" single-event-upset simulator.',
      openLeftDrawer: false,
      openRightDrawer: true,
    ),
    _TourStep(
      title: '10 / 11 · MEDA / REMS Climate & RAD Dosimetry',
      body: 'Explore diurnal Sol 100 weather buckets or 14 years of Curiosity REMS temperature curves, alongside live RAD galactic cosmic ray & solar energetic particle dosimetry.',
      openLeftDrawer: false,
      openRightDrawer: true,
    ),
    _TourStep(
      title: '11 / 11 · Feature Inspector & 7-Check Safety Dashboard',
      body: 'Click any waypoint, mineral outcrop, thermal stamp, or planned EVA route to inspect metadata, view rover camera frames, verify the 7-Check Astronaut Safety Dashboard, and walk the EVA in Street View.',
      openLeftDrawer: false,
      openRightDrawer: true,
    ),
  ];

  // Drawers
  bool _leftDrawerOpen = false;
  bool _rightDrawerOpen = false;

  // Map viewport state
  double _centerLon = 137.4417;
  double _centerLat = -4.5895;
  double _zoom = 24.0; // 1.0 = whole Mars (360° wide), 28.0 = ~1.2° wide
  String _activeJumpId = 'gale';
  GeoPoint _cursorGeo = const GeoPoint(137.4417, -4.5895);

  // Custom Quick Jumps
  final List<({String id, String name, GeoPoint point})> _customJumps = [];

  // Base layer & overlays
  String _baseLayer = 'viking_color'; // 'viking_color' | 'mola_color' | 'themis_ir_global' | 'ctx_global'
  bool _ovMountSharp = true;
  bool _ovJezero = true;
  bool _ovCtxGale = true;
  bool _ovBlendGale = false;

  // Vector layers
  bool _vecMinerals = true;
  bool _vecPlannedWaypoints = true;
  bool _vecEvaTactical = true;
  bool _vecLandmarks = true;
  bool _vecRoverWaypoints = true;
  bool _vecThemisStamps = true;
  bool _vecPerseverance = true;
  bool _vecAoiBounds = true;

  // Planner config & state
  String _plannerAlgo = 'theta_star'; // 'astar' | 'theta_star'
  double _cfgMaxDistM = 1500;
  double _cfgMaxSlopeDeg = 25;
  double _cfgSuitO2Pct = 88;
  double _cfgO2ReservePct = 25;
  String _cfgEnvMode = 'auto'; // 'auto' | 'clear' | 'storm'

  String _interactionMode = 'none'; // 'none' | 'plan_eva' | 'drop_waypoint'
  GeoPoint? _evaStartPoint;
  GeoPoint? _evaGoalPoint;
  String _plannerHint = 'Idle — click button to start.';
  List<({GeoPoint point, String label})> _plannedRouteStops = [];
  TraversePlan? _activeEvaPlan;
  List<_SafetyCheck> _safetyChecks = [];
  bool _evaOverallGo = true;
  double _evaEstO2UsedPct = 0.0;

  // Planned waypoints
  final List<SurveyFeature> _plannedWaypoints = [
    const SurveyFeature(
      id: 'wp_hab_alpha',
      name: 'ARES HABITAT ALPHA',
      point: GeoPoint(137.4417, -4.5895),
      kind: 'habitat',
      notes: 'Primary surface habitat & pressurized rover dock at Bradbury Landing.',
      source: 'ARES EVA Plan',
      elevation: -4462.0,
    ),
    const SurveyFeature(
      id: 'wp_drill_1',
      name: 'YELLOWKNIFE BAY DRILL TARGET',
      point: GeoPoint(137.4485, -4.5842),
      kind: 'sample',
      notes: 'Sheepbed mudstone astrobiology core target.',
      source: 'ARES EVA Plan',
      elevation: -4478.0,
    ),
  ];

  // Landing site for PNR / Street View
  GeoPoint _landingSite = const GeoPoint(137.4417, -4.5895);

  // PLSS Simulator state
  double _plssInitO2 = 100.0;
  double _plssInitBat = 100.0;
  double _plssInitH2O = 100.0;
  double _plssWorkW = 260.0;
  double _plssPressKpa = 29.6;
  double _walkedDistM = 0.0;
  int _plssResetEpochSec = 0;

  // Comms & Orbital Relay state
  int _edacFixedCount = 0;
  String _edacLastWordHex = '0x4F9A2C01';
  double _relayPeriodMin = 47.0;
  double _relayOffsetSec = 0.0;

  // Weather / REMS duration selector
  String _weatherRange = 'sol100'; // 'sol100' | 'rems_30' | 'rems_90' | 'rems_365' | 'rems_668' | 'rems_all' | 'custom'
  String _customStartSol = '1';
  String _customEndSol = '500';

  // Inspector selection
  String _inspectorBadge = 'IDLE';
  String _inspectorKind = 'idle'; // 'idle' | 'waypoint' | 'eva_route' | 'stamp' | 'landmark' | 'mineral'
  SurveyFeature? _selectedFeature;
  ThemisStamp? _selectedStamp;
  _GlobalLandmark? _selectedLandmark;
  _MineralSite? _selectedMineral;

  // Modals
  bool _terrainModalOpen = false;
  String _terrainModalInitialMode = 'globe';
  String _terrainModalTitle = 'Gale Crater Regional DEM';
  bool _streetViewModalOpen = false;
  GeoPoint _streetViewPoint = const GeoPoint(137.4417, -4.5895);
  String _streetViewLabel = 'Bradbury Landing · Gale Crater';

  // Interactive Tour
  int? _tourStepIndex;

  // Cached decoded raster images for fast CustomPainter rendering
  final Map<String, ui.Image> _loadedImages = {};

  @override
  void initState() {
    super.initState();
    _plssResetEpochSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _loadMapImages();
  }

  Future<void> _loadMapImages() async {
    const assets = {
      'mars_global': 'assets/images/map/mars_global.jpg',
      'mars_mola': 'assets/images/map/mars_mola.jpg',
      'mount_sharp_orbital': 'assets/images/map/mount_sharp_orbital.jpg',
      'jezero_orbital': 'assets/images/map/jezero_orbital.jpg',
      'ctx_optical_gale': 'assets/images/map/ctx_optical_gale.png',
      'mola_themis_blend': 'assets/images/map/mola_themis_blend.png',
      'themis_day_ir': 'assets/images/map/themis_day_ir.png',
    };
    for (final entry in assets.entries) {
      try {
        final data = await rootBundle.load(entry.value);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        if (!mounted) return;
        setState(() {
          _loadedImages[entry.key] = frame.image;
        });
      } catch (_) {}
    }
  }

  List<SurveyFeature> _curiosityFeatures(AresState state) {
    final list = <SurveyFeature>[];
    for (final ref in state.references) {
      list.add(
        SurveyFeature(
          id: ref.id,
          name: ref.name,
          point: ref.point,
          kind: ref.category,
          notes: ref.notes,
          source: 'Curiosity Gale Reference',
          elevation: state.terrain.elevationAt(ref.lon, ref.lat),
        ),
      );
    }
    for (final item in state.data.catalogFeatures) {
      final isJezero = item.point.lon > 75 && item.point.lon < 79 && item.point.lat > 17 && item.point.lat < 20;
      if (!isJezero) {
        list.add(item);
      }
    }
    return list;
  }

  List<SurveyFeature> _perseveranceFeatures(AresState state) {
    final list = <SurveyFeature>[];
    for (final item in state.data.catalogFeatures) {
      final isJezero = item.point.lon > 75 && item.point.lon < 79 && item.point.lat > 17 && item.point.lat < 20;
      if (isJezero) {
        list.add(item);
      }
    }
    if (list.isEmpty) {
      list.addAll(const [
        SurveyFeature(
          id: 'm20_octavia',
          name: 'Octavia E. Butler Landing',
          point: GeoPoint(77.4509, 18.4446),
          kind: 'landing',
          notes: 'Mars 2020 Perseverance touchdown site & Ingenuity Wright Brothers Field.',
          source: 'Mars 2020',
          elevation: -2570.0,
        ),
        SurveyFeature(
          id: 'm20_three_forks',
          name: 'Three Forks Sample Depot',
          point: GeoPoint(77.4310, 18.4485),
          kind: 'depot',
          notes: 'First titanium sample tube cache depot placed on another planet (10 tubes).',
          source: 'Mars 2020',
          elevation: -2545.0,
        ),
        SurveyFeature(
          id: 'm20_belva',
          name: 'Belva Crater Rim Overlook',
          point: GeoPoint(77.4195, 18.4612),
          kind: 'crater',
          notes: 'Exposed delta foreset beds inside a 0.9 km impact crater on the western fan.',
          source: 'Mars 2020',
          elevation: -2490.0,
        ),
        SurveyFeature(
          id: 'm20_neretva',
          name: 'Bright Angel · Cheyava Falls',
          point: GeoPoint(77.3880, 18.4690),
          kind: 'biosignature',
          notes: 'Neretva Vallis mudstone with leopard-spot iron-phosphate/sulfide reaction rims.',
          source: 'Mars 2020',
          elevation: -2435.0,
        ),
      ]);
    }
    return list;
  }

  void _jumpToPreset(_JumpPreset preset) {
    setState(() {
      _activeJumpId = preset.id;
      _centerLon = preset.lon;
      _centerLat = preset.lat;
      _zoom = preset.zoom;
      _cursorGeo = GeoPoint(preset.lon, preset.lat);
      _terrainModalTitle = preset.title;
    });
  }

  void _addCustomJumpAtCenter() {
    final idx = _customJumps.length + 1;
    final pt = GeoPoint(_centerLon, _centerLat);
    setState(() {
      _customJumps.add((
        id: 'cust_$idx',
        name: 'Site $idx (${pt.lat.toStringAsFixed(2)}°, ${pt.lon.toStringAsFixed(2)}°)',
        point: pt,
      ));
    });
  }

  void _executeEvaPlan(AresState state, GeoPoint start, GeoPoint goal) {
    final plan = state.terrain.planRoute(start, goal, 'EVA TARGET');
    final distM = plan.distanceKm * 1000.0;
    final maxSlope = plan.maxSlopeDeg;
    final durHours = math.max(distM / 1000.0 / 1.44, 0.15);
    final o2UsedPct = (durHours * (_plssWorkW / 260.0) * 16.5).clamp(1.0, 99.0);
    final remO2Pct = (_cfgSuitO2Pct - o2UsedPct).clamp(0.0, 100.0);
    final pnrDistKm = haversineKm(goal, _landingSite);
    final isDustStorm = _cfgEnvMode == 'storm' ||
        (_cfgEnvMode == 'auto' && (state.meda.last.opacity ?? 0.5) > 1.2);
    final evaDoseMsv = (durHours / 24.0) * 0.242 * (isDustStorm ? 1.15 : 1.0);

    final checks = <_SafetyCheck>[
      _SafetyCheck(
        label: '1. Suit O₂ Reserve (≥ ${_cfgO2ReservePct.round()}%)',
        value: '${remO2Pct.toStringAsFixed(1)}% rem (${o2UsedPct.toStringAsFixed(1)}% used)',
        status: remO2Pct >= _cfgO2ReservePct
            ? 'GO'
            : (remO2Pct >= _cfgO2ReservePct * 0.7 ? 'CAUTION' : 'NO-GO'),
      ),
      _SafetyCheck(
        label: '2. Max Terrain Slope (≤ ${_cfgMaxSlopeDeg.round()}°)',
        value: '${maxSlope.toStringAsFixed(1)}° peak grade',
        status: maxSlope <= _cfgMaxSlopeDeg
            ? 'GO'
            : (maxSlope <= _cfgMaxSlopeDeg + 5 ? 'CAUTION' : 'NO-GO'),
      ),
      _SafetyCheck(
        label: '3. Traverse Distance Budget (≤ ${_cfgMaxDistM.round()} m)',
        value: '${distM.round()} m total',
        status: distM <= _cfgMaxDistM
            ? 'GO'
            : (distM <= _cfgMaxDistM * 1.25 ? 'CAUTION' : 'NO-GO'),
      ),
      _SafetyCheck(
        label: '4. Point-of-No-Return (≤ 5.0 km Hab Radius)',
        value: '${pnrDistKm.toStringAsFixed(2)} km from Hab',
        status: pnrDistKm <= 5.0
            ? 'GO'
            : (pnrDistKm <= 6.5 ? 'CAUTION' : 'NO-GO'),
      ),
      _SafetyCheck(
        label: '5. Atmospheric Optical Depth & Wind (MEDA)',
        value: isDustStorm ? 'Tau 1.50 (Dust Storm)' : 'Tau 0.52 (Clear Sky)',
        status: isDustStorm ? 'CAUTION' : 'GO',
      ),
      _SafetyCheck(
        label: '6. Radiation Dose Limit (RAD ≤ 0.50 mSv)',
        value: '${evaDoseMsv.toStringAsFixed(3)} mSv est.',
        status: evaDoseMsv <= 0.50 ? 'GO' : 'CAUTION',
      ),
      const _SafetyCheck(
        label: '7. UHF Hab Line-of-Sight & Relay Link',
        value: '401.6 MHz Locked · CRC32 OK',
        status: 'GO',
      ),
    ];

    final stops = <({GeoPoint point, String label})>[];
    final step = math.max(1, plan.points.length ~/ 6);
    for (var i = 0; i < plan.points.length; i += step) {
      final pt = plan.points[i];
      stops.add((
        point: pt,
        label: i == 0
            ? 'EVA START'
            : 'WP${stops.length} (${pt.lat.toStringAsFixed(3)}°, ${pt.lon.toStringAsFixed(3)}°)',
      ));
    }
    if (stops.isEmpty || stops.last.point != plan.points.last) {
      stops.add((point: plan.points.last, label: 'EVA GOAL'));
    }

    final hasNoGo = checks.any((c) => c.status == 'NO-GO');

    setState(() {
      _activeEvaPlan = plan;
      _plannedRouteStops = stops;
      _safetyChecks = checks;
      _evaOverallGo = !hasNoGo;
      _evaEstO2UsedPct = o2UsedPct;
      _interactionMode = 'none';
      _plannerHint =
          'Solved via ${_plannerAlgo == 'theta_star' ? 'Theta*' : 'A*'} · ${distM.round()} m · ${stops.length} waypoints.';
      _inspectorBadge = hasNoGo ? 'CAUTION / NO-GO' : 'EVA ROUTE GO';
      _inspectorKind = 'eva_route';
      _rightDrawerOpen = true;
    });
  }

  void _handleMapTap(AresState state, GeoPoint tapped, Size mapSize) {
    setState(() {
      _cursorGeo = tapped;
    });

    if (_interactionMode == 'plan_eva') {
      if (_evaStartPoint == null) {
        setState(() {
          _evaStartPoint = tapped;
          _plannerHint =
              'Start set (${tapped.lat.toStringAsFixed(3)}°, ${tapped.lon.toStringAsFixed(3)}°). Click Goal on map.';
        });
      } else {
        final start = _evaStartPoint!;
        _evaGoalPoint = tapped;
        _executeEvaPlan(state, start, tapped);
      }
      return;
    }

    if (_interactionMode == 'drop_waypoint') {
      _showDropWaypointDialog(state, tapped);
      return;
    }

    // Check if user tapped near an existing feature on the map
    final degThreshold = (360.0 / _zoom) * (22.0 / math.max(mapSize.width, 300.0));

    if (_vecPlannedWaypoints) {
      for (final wp in _plannedWaypoints) {
        if (_degDist(tapped, wp.point) <= degThreshold) {
          setState(() {
            _selectedFeature = wp;
            _inspectorKind = 'waypoint';
            _inspectorBadge = 'PLANNED WP';
            _rightDrawerOpen = true;
          });
          return;
        }
      }
    }

    if (_vecMinerals) {
      for (final m in _mineralSites) {
        if (_degDist(tapped, GeoPoint(m.lon, m.lat)) <= degThreshold) {
          setState(() {
            _selectedMineral = m;
            _inspectorKind = 'mineral';
            _inspectorBadge = 'CRISM MINERAL';
            _rightDrawerOpen = true;
          });
          return;
        }
      }
    }

    if (_vecRoverWaypoints) {
      for (final wp in _curiosityFeatures(state)) {
        if (_degDist(tapped, wp.point) <= degThreshold) {
          setState(() {
            _selectedFeature = wp;
            _inspectorKind = 'waypoint';
            _inspectorBadge = 'MSL WAYPOINT';
            _rightDrawerOpen = true;
          });
          return;
        }
      }
    }

    if (_vecPerseverance) {
      for (final wp in _perseveranceFeatures(state)) {
        if (_degDist(tapped, wp.point) <= degThreshold) {
          setState(() {
            _selectedFeature = wp;
            _inspectorKind = 'waypoint';
            _inspectorBadge = 'M20 WAYPOINT';
            _rightDrawerOpen = true;
          });
          return;
        }
      }
    }

    if (_vecLandmarks) {
      for (final lm in _globalLandmarks) {
        if (_degDist(tapped, GeoPoint(lm.lon, lm.lat)) <= degThreshold * 1.4) {
          setState(() {
            _selectedLandmark = lm;
            _inspectorKind = 'landmark';
            _inspectorBadge = 'IAU LANDMARK';
            _rightDrawerOpen = true;
          });
          return;
        }
      }
    }

    if (_vecThemisStamps) {
      for (final st in state.stamps.take(180)) {
        if (_degDist(tapped, st.point) <= degThreshold * 0.9) {
          setState(() {
            _selectedStamp = st;
            _inspectorKind = 'stamp';
            _inspectorBadge = 'THEMIS STAMP';
            _rightDrawerOpen = true;
          });
          return;
        }
      }
    }

    // Default site inspection at clicked coordinate
    final elev = state.terrain.elevationAt(tapped.lon, tapped.lat);
    setState(() {
      _selectedFeature = SurveyFeature(
        id: 'site_probe',
        name: 'Surface Coordinate Probe',
        point: tapped,
        kind: 'terrain_probe',
        notes: 'Direct MOLA / HiRISE surface terrain probe at clicked IAU:49900 coordinate.',
        source: 'IAU:49900 Probe',
        elevation: elev,
      );
      _inspectorKind = 'waypoint';
      _inspectorBadge = 'SITE PROBE';
      _rightDrawerOpen = true;
    });
  }

  double _degDist(GeoPoint a, GeoPoint b) {
    final dx = a.lon - b.lon;
    final dy = a.lat - b.lat;
    return math.sqrt(dx * dx + dy * dy);
  }

  Future<void> _showDropWaypointDialog(AresState state, GeoPoint pt) async {
    final nameCtrl = TextEditingController(
      text: 'EVA WP-${_plannedWaypoints.length + 1}',
    );
    final notesCtrl = TextEditingController(
      text: 'Field sample & stratigraphy target logged on tactical map.',
    );
    String kind = 'sample';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              backgroundColor: const Color(0xF5141418),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0x28FFFFFF)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NEW PLANNED WAYPOINT',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Color(0xFFF4F4F6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Lat: ${pt.lat.toStringAsFixed(5)}° · Lon: ${pt.lon.toStringAsFixed(5)}°',
                        style: AresType.monoStyle(
                          size: 11,
                          color: const Color(0xFF0A84FF),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Waypoint Name',
                        style: TextStyle(fontSize: 11, color: Color(0xFF9898A0)),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFF1C1C21),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(color: Color(0x22FFFFFF)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Target Type',
                        style: TextStyle(fontSize: 11, color: Color(0xFF9898A0)),
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: kind,
                        dropdownColor: const Color(0xFF1C1C21),
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFF1C1C21),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'sample', child: Text('Core / Sample Target')),
                          DropdownMenuItem(value: 'hazard', child: Text('Slope / Obstacle Hazard')),
                          DropdownMenuItem(value: 'shelter', child: Text('Emergency Radiation Shelter')),
                          DropdownMenuItem(value: 'comms', child: Text('UHF Comms Relay Beacon')),
                        ],
                        onChanged: (v) {
                          if (v != null) setModalState(() => kind = v);
                        },
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Mission Notes',
                        style: TextStyle(fontSize: 11, color: Color(0xFF9898A0)),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFF1C1C21),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0A84FF),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Save Waypoint'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      final wp = SurveyFeature(
        id: 'wp_${DateTime.now().millisecondsSinceEpoch}',
        name: nameCtrl.text.trim().isEmpty ? 'EVA WAYPOINT' : nameCtrl.text.trim(),
        point: pt,
        kind: kind,
        notes: notesCtrl.text.trim(),
        source: 'Planned EVA Waypoint',
        elevation: state.terrain.elevationAt(pt.lon, pt.lat),
      );
      setState(() {
        _plannedWaypoints.add(wp);
        _selectedFeature = wp;
        _inspectorKind = 'waypoint';
        _inspectorBadge = 'PLANNED WP';
        _interactionMode = 'none';
        _plannerHint = 'Saved waypoint "${wp.name}".';
        _rightDrawerOpen = true;
      });
    } else if (mounted) {
      setState(() {
        _interactionMode = 'none';
        _plannerHint = 'Idle — click button to start.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AresScope.of(context);
    final clock = state.marsClock;
    final modalActive = _terrainModalOpen || _streetViewModalOpen;

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopStatusBar(state, clock),
            Expanded(
              child: Stack(
                children: [
                  // Full-bleed 2D Mars Map Canvas
                  Positioned.fill(
                    child: _buildInteractive2DMap(state),
                  ),

                  // Top-left zoom controls (+ / -) when left drawer is closed
                  if (!_leftDrawerOpen && !modalActive)
                    Positioned(
                      left: 12,
                      top: 56,
                      child: _buildZoomControls(),
                    ),

                  // Bottom-right scale & attribution pill
                  if (!modalActive)
                    Positioned(
                      right: 12,
                      bottom: 10,
                      child: _buildMapAttributionPill(),
                    ),

                  // Floating drawer trigger buttons
                  if (!_leftDrawerOpen && !modalActive)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _buildDrawerTriggerButton(
                        icon: LucideIcons.slidersHorizontal,
                        label: 'Controls & Layers',
                        onTap: () => setState(() => _leftDrawerOpen = true),
                      ),
                    ),
                  if (!_rightDrawerOpen && !modalActive)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _buildDrawerTriggerButton(
                        icon: LucideIcons.radio,
                        label: 'Telemetry & Inspector',
                        onTap: () => setState(() => _rightDrawerOpen = true),
                      ),
                    ),

                  // Left Collapsible Frosted-Glass Drawer
                  if (_leftDrawerOpen && !modalActive)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 0,
                      width: 276,
                      child: _buildLeftDrawer(state),
                    ),

                  // Right Collapsible Frosted-Glass Drawer
                  if (_rightDrawerOpen && !modalActive)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      width: 340,
                      child: _buildRightDrawer(state),
                    ),

                  // 3D Mars Globe & Local Terrain Modal
                  if (_terrainModalOpen)
                    Positioned.fill(
                      child: AresTerrainModal(
                        initialMode: _terrainModalInitialMode,
                        title: _terrainModalTitle,
                        center: GeoPoint(_centerLon, _centerLat),
                        routeStops: _plannedRouteStops,
                        catalogFeatures: [
                          ..._curiosityFeatures(state),
                          ..._perseveranceFeatures(state),
                          ..._plannedWaypoints,
                        ],
                        onClose: () => setState(() => _terrainModalOpen = false),
                        onOpenStreetView: (pt, label) {
                          setState(() {
                            _terrainModalOpen = false;
                            _streetViewPoint = pt;
                            _streetViewLabel = label;
                            _streetViewModalOpen = true;
                          });
                        },
                        onPlanGlobeEva: (start, goal) {
                          _executeEvaPlan(state, start, goal);
                        },
                      ),
                    ),

                  // 360° Mars Street View Modal
                  if (_streetViewModalOpen)
                    Positioned.fill(
                      child: AresStreetViewModal(
                        initialPoint: _streetViewPoint,
                        initialLabel: _streetViewLabel,
                        routeStops: _plannedRouteStops,
                        catalogFeatures: [
                          ..._curiosityFeatures(state),
                          ..._perseveranceFeatures(state),
                          ..._plannedWaypoints,
                        ],
                        customJumps: _customJumps,
                        landingSite: _landingSite,
                        plssInitO2: _plssInitO2,
                        plssInitBat: _plssInitBat,
                        plssMetabolicW: _plssWorkW,
                        onWalkedChanged: (walkedM) {
                          setState(() => _walkedDistM = walkedM);
                        },
                        onSetLandingSite: (pt) {
                          setState(() => _landingSite = pt);
                        },
                        onAddCustomJump: (name, pt) {
                          setState(() {
                            _customJumps.add((
                              id: 'sv_${_customJumps.length + 1}',
                              name: name,
                              point: pt,
                            ));
                          });
                        },
                        onClose: () => setState(() => _streetViewModalOpen = false),
                      ),
                    ),

                  // 11-step Interactive Guide Tour Overlay
                  if (_tourStepIndex != null)
                    Positioned.fill(
                      child: _buildTourOverlay(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopStatusBar(AresState state, MarsClock clock) {
    final solsSinceMsl = (clock.msd - 49269.25).floor();
    final lmstSec = (clock.localSolarHours * 3600).floor();
    final lH = (lmstSec ~/ 3600).toString().padLeft(2, '0');
    final lM = ((lmstSec % 3600) ~/ 60).toString().padLeft(2, '0');
    final lS = (lmstSec % 60).toString().padLeft(2, '0');
    final marsYear = 39;
    final lsDeg = (((clock.msd - 44796.0) % 668.6) / 668.6 * 360.0);
    final seasonLabel = lsDeg < 90
        ? 'N. Spring'
        : (lsDeg < 180 ? 'N. Summer' : (lsDeg < 270 ? 'N. Autumn' : 'N. Winter'));

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xEB0E0E11),
        border: Border(
          bottom: BorderSide(color: Color(0x14FFFFFF), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Brand
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF30D158),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x5930D158), blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'ARES MAP',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.84,
                  color: Color(0xFFF4F4F6),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'MARS EVA TACTICAL MAP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF9898A0),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Telemetry strip
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _telemetryKv(
                    'MARS:',
                    'MY $marsYear · Ls ${lsDeg.toStringAsFixed(1)}° ($seasonLabel)',
                    const Color(0xFF64D2FF),
                  ),
                  _telemetryDivider(),
                  _telemetryKv('MSD:', clock.msd.toStringAsFixed(4), const Color(0xFFF4F4F6)),
                  _telemetryDivider(),
                  _telemetryKv('MTC:', clock.mtc, const Color(0xFFF4F4F6)),
                  _telemetryDivider(),
                  _telemetryKv(
                    'LMST (137.4°E):',
                    'Sol $solsSinceMsl $lH:$lM:$lS',
                    const Color(0xFFFF9F0A),
                  ),
                  _telemetryDivider(),
                  _telemetryKv('UTC:', state.earthUtc, const Color(0xFF9898A0)),
                  _telemetryDivider(),
                  _telemetryKv('OWLT:', state.owltLabel, const Color(0xFF9898A0)),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x0AFFFFFF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0x14FFFFFF)),
                    ),
                    child: Text(
                      'IAU:49900  ${_cursorGeo.lat.toStringAsFixed(4)}°, ${_cursorGeo.lon.toStringAsFixed(4)}°',
                      style: AresType.monoStyle(
                        size: 11,
                        color: const Color(0xFF64D2FF),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      setState(() {
                        _tourStepIndex = 0;
                        _leftDrawerOpen = false;
                        _rightDrawerOpen = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x240A84FF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0x590A84FF)),
                      ),
                      child: const Text(
                        '? Guide',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64D2FF),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _telemetryKv(String label, String value, Color valueColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Color(0xFF63636B),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          value,
          style: AresType.monoStyle(
            size: 11,
            color: valueColor,
            weight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _telemetryDivider() {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0x14FFFFFF),
    );
  }

  Widget _buildDrawerTriggerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xE016161A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x24FFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: const Color(0xFF0A84FF)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF4F4F6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoomControls() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xEB141418),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              setState(() => _zoom = (_zoom * 1.45).clamp(1.0, 90.0));
            },
            child: const SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: Text(
                  '+',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF4F4F6),
                  ),
                ),
              ),
            ),
          ),
          Container(width: 30, height: 1, color: const Color(0x14FFFFFF)),
          InkWell(
            onTap: () {
              setState(() => _zoom = (_zoom / 1.45).clamp(1.0, 90.0));
            },
            child: const SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: Text(
                  '−',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF4F4F6),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapAttributionPill() {
    final spanKm = (360.0 / _zoom) * 59.16 * 0.12;
    final scaleLabel = spanKm >= 10
        ? '${spanKm.round()} km'
        : '${(spanKm * 1000).round()} m';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xCC0E0E11),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0x24FFFFFF)),
          ),
          child: Text(
            scaleLabel,
            style: AresType.monoStyle(size: 10, color: const Color(0xFFF4F4F6)),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xBF09090B),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'NASA/JPL/USGS MOLA · THEMIS · CTX · HiRISE (IAU:49900)',
            style: TextStyle(fontSize: 10, color: Color(0xFF9898A0)),
          ),
        ),
      ],
    );
  }

  Widget _buildInteractive2DMap(AresState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleUpdate: (details) {
            setState(() {
              if ((details.scale - 1.0).abs() > 0.01) {
                _zoom = (_zoom * details.scale.clamp(0.92, 1.08)).clamp(1.0, 90.0);
              }
              final lonSpan = 360.0 / _zoom;
              final latSpan = lonSpan * (size.height / math.max(size.width, 1.0));
              _centerLon = (_centerLon - details.focalPointDelta.dx / size.width * lonSpan)
                  .clamp(-180.0, 180.0);
              _centerLat = (_centerLat + details.focalPointDelta.dy / size.height * latSpan)
                  .clamp(-85.0, 85.0);
              _cursorGeo = GeoPoint(_centerLon, _centerLat);
            });
          },
          onTapUp: (details) {
            final lonSpan = 360.0 / _zoom;
            final latSpan = lonSpan * (size.height / math.max(size.width, 1.0));
            final lon = _centerLon + (details.localPosition.dx / size.width - 0.5) * lonSpan;
            final lat = _centerLat - (details.localPosition.dy / size.height - 0.5) * latSpan;
            _handleMapTap(
              state,
              GeoPoint(lon.clamp(-180.0, 180.0), lat.clamp(-85.0, 85.0)),
              size,
            );
          },
          child: CustomPaint(
            size: size,
            painter: _Ares2DMapPainter(
              centerLon: _centerLon,
              centerLat: _centerLat,
              zoom: _zoom,
              baseLayer: _baseLayer,
              ovMountSharp: _ovMountSharp,
              ovJezero: _ovJezero,
              ovCtxGale: _ovCtxGale,
              ovBlendGale: _ovBlendGale,
              vecMinerals: _vecMinerals,
              vecPlannedWaypoints: _vecPlannedWaypoints,
              vecEvaTactical: _vecEvaTactical,
              vecLandmarks: _vecLandmarks,
              vecRoverWaypoints: _vecRoverWaypoints,
              vecThemisStamps: _vecThemisStamps,
              vecPerseverance: _vecPerseverance,
              vecAoiBounds: _vecAoiBounds,
              loadedImages: _loadedImages,
              minerals: _mineralSites,
              landmarks: _globalLandmarks,
              plannedWaypoints: _plannedWaypoints,
              curiosityWaypoints: _curiosityFeatures(state),
              perseveranceWaypoints: _perseveranceFeatures(state),
              curiosityTrail: state.archiveTrail,
              stamps: state.stamps,
              landingSite: _landingSite,
              buddyPoint: state.buddy,
              evaStartPoint: _evaStartPoint,
              evaGoalPoint: _evaGoalPoint,
              activeEvaPlan: _activeEvaPlan,
              plannedRouteStops: _plannedRouteStops,
              selectedFeature: _selectedFeature,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeftDrawer(AresState state) {
    final curiosityList = _curiosityFeatures(state);
    final perseveranceList = _perseveranceFeatures(state);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xEB121216),
        border: Border(
          right: BorderSide(color: Color(0x14FFFFFF), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 32,
            offset: Offset(10, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drawer Header
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              color: Color(0x05FFFFFF),
              border: Border(
                bottom: BorderSide(color: Color(0x14FFFFFF), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'MAP CONTROLS & LAYERS',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.77,
                      color: Color(0xFF9898A0),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _leftDrawerOpen = false),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0x0FFFFFFF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      LucideIcons.x,
                      size: 14,
                      color: Color(0xFF9898A0),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                // 1. QUICK JUMP SECTION
                _drawerSection(
                  title: 'Quick Jump',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 3.1,
                        children: _jumpPresets.map((preset) {
                          final active = _activeJumpId == preset.id;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _jumpToPreset(preset),
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: active
                                    ? const Color(0x380A84FF)
                                    : const Color(0x0DFFFFFF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: active
                                      ? const Color(0x8C0A84FF)
                                      : const Color(0x14FFFFFF),
                                ),
                              ),
                              child: Text(
                                preset.label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: active
                                      ? Colors.white
                                      : const Color(0xFFF4F4F6),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (_customJumps.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _customJumps.map((cj) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x1A0A84FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0x400A84FF)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _centerLon = cj.point.lon;
                                        _centerLat = cj.point.lat;
                                        _zoom = 24.0;
                                      });
                                    },
                                    child: Text(
                                      cj.name,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF64D2FF),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _customJumps.removeWhere((e) => e.id == cj.id);
                                      });
                                    },
                                    child: const Icon(
                                      LucideIcons.x,
                                      size: 11,
                                      color: Color(0xFFFF453A),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 6),
                      _actionButton(
                        label: '+ Mark Quick Jump Here',
                        dashed: true,
                        onTap: _addCustomJumpAtCenter,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _actionButton(
                              icon: LucideIcons.globe,
                              label: '3D Mars Globe',
                              primary: true,
                              onTap: () {
                                setState(() {
                                  _terrainModalInitialMode = 'globe';
                                  _terrainModalOpen = true;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _actionButton(
                              icon: LucideIcons.mountain,
                              label: '3D Regional Terrain',
                              primary: true,
                              onTap: () {
                                setState(() {
                                  _terrainModalInitialMode = 'terrain';
                                  _terrainModalOpen = true;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _actionButton(
                        icon: LucideIcons.compass,
                        label: 'Launch Mars Street View',
                        primary: true,
                        onTap: () {
                          setState(() {
                            _streetViewPoint = GeoPoint(_centerLon, _centerLat);
                            _streetViewLabel = _terrainModalTitle;
                            _streetViewModalOpen = true;
                          });
                        },
                      ),
                    ],
                  ),
                ),

                // 2. PLANNER SECTION
                _drawerSection(
                  title: 'Planner',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Segmented control: A* (Grid) | Theta* (Any-Angle)
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0x0FFFFFFF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0x14FFFFFF)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _segButton(
                                label: 'A* (Grid)',
                                active: _plannerAlgo == 'astar',
                                onTap: () => setState(() => _plannerAlgo = 'astar'),
                              ),
                            ),
                            Expanded(
                              child: _segButton(
                                label: 'Theta* (Any-Angle)',
                                active: _plannerAlgo == 'theta_star',
                                onTap: () => setState(() => _plannerAlgo = 'theta_star'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Planner safety config grid
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0x06FFFFFF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0x14FFFFFF)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _miniNumericControl(
                                    label: 'Budget (m)',
                                    value: '${_cfgMaxDistM.round()}',
                                    onDelta: (d) => setState(
                                      () => _cfgMaxDistM = (_cfgMaxDistM + d * 250).clamp(200, 20000),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _miniNumericControl(
                                    label: 'Max Slope (°)',
                                    value: '${_cfgMaxSlopeDeg.round()}',
                                    onDelta: (d) => setState(
                                      () => _cfgMaxSlopeDeg = (_cfgMaxSlopeDeg + d * 2).clamp(5, 45),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: _miniNumericControl(
                                    label: 'Suit O₂ (%)',
                                    value: '${_cfgSuitO2Pct.round()}',
                                    onDelta: (d) => setState(
                                      () => _cfgSuitO2Pct = (_cfgSuitO2Pct + d * 5).clamp(20, 100),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _miniNumericControl(
                                    label: 'Reserve (%)',
                                    value: '${_cfgO2ReservePct.round()}',
                                    onDelta: (d) => setState(
                                      () => _cfgO2ReservePct = (_cfgO2ReservePct + d * 5).clamp(10, 50),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Text(
                                  'Environment',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF9898A0),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _cfgEnvMode,
                                      isDense: true,
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF1C1C21),
                                      style: AresType.monoStyle(
                                        size: 10,
                                        color: const Color(0xFFF4F4F6),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'auto',
                                          child: Text(
                                            'Auto (MEDA Sensor)',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 'clear',
                                          child: Text(
                                            'Force Clear Sky',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 'storm',
                                          child: Text(
                                            'Force Dust Storm (Tau 1.5)',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) setState(() => _cfgEnvMode = v);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      _actionButton(
                        icon: LucideIcons.route,
                        label: _interactionMode == 'plan_eva'
                            ? 'Cancel EVA Route Mode'
                            : 'Plan Safe EVA Route',
                        primary: true,
                        active: _interactionMode == 'plan_eva',
                        onTap: () {
                          setState(() {
                            if (_interactionMode == 'plan_eva') {
                              _interactionMode = 'none';
                              _evaStartPoint = null;
                              _plannerHint = 'Idle — click button to start.';
                            } else {
                              _interactionMode = 'plan_eva';
                              _evaStartPoint = null;
                              _plannerHint = 'Click map to set EVA START point...';
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      _actionButton(
                        icon: LucideIcons.mapPinPlus,
                        label: _interactionMode == 'drop_waypoint'
                            ? 'Cancel Drop Waypoint'
                            : 'Drop Planned Waypoint',
                        active: _interactionMode == 'drop_waypoint',
                        onTap: () {
                          setState(() {
                            if (_interactionMode == 'drop_waypoint') {
                              _interactionMode = 'none';
                              _plannerHint = 'Idle — click button to start.';
                            } else {
                              _interactionMode = 'drop_waypoint';
                              _plannerHint = 'Click anywhere on map to drop waypoint...';
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _plannerHint,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF63636B),
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. GLOBAL BASE LAYER
                _drawerSection(
                  title: 'Global Base Layer',
                  child: Column(
                    children: [
                      _radioLayerRow(
                        label: 'Viking MDIM 2.1 True Color',
                        value: 'viking_color',
                        groupValue: _baseLayer,
                        onChanged: (v) => setState(() => _baseLayer = v),
                      ),
                      _radioLayerRow(
                        label: 'MOLA Colorized Elevation',
                        value: 'mola_color',
                        groupValue: _baseLayer,
                        onChanged: (v) => setState(() => _baseLayer = v),
                      ),
                      _radioLayerRow(
                        label: 'THEMIS Day IR Global (100m)',
                        value: 'themis_ir_global',
                        groupValue: _baseLayer,
                        onChanged: (v) => setState(() => _baseLayer = v),
                      ),
                      _radioLayerRow(
                        label: 'CTX Global Mosaic Beta (5m)',
                        value: 'ctx_global',
                        groupValue: _baseLayer,
                        onChanged: (v) => setState(() => _baseLayer = v),
                      ),
                    ],
                  ),
                ),

                // 4. HIGH-RES REGIONAL OVERLAYS
                _drawerSection(
                  title: 'High-Res Regional Overlays',
                  child: Column(
                    children: [
                      _checkboxLayerRow(
                        label: 'Mount Sharp & Gale Orbital',
                        value: _ovMountSharp,
                        onChanged: (v) => setState(() => _ovMountSharp = v),
                      ),
                      _checkboxLayerRow(
                        label: 'Jezero Crater Perseverance',
                        value: _ovJezero,
                        onChanged: (v) => setState(() => _ovJezero = v),
                      ),
                      _checkboxLayerRow(
                        label: 'Gale CTX Optical (5m)',
                        value: _ovCtxGale,
                        onChanged: (v) => setState(() => _ovCtxGale = v),
                      ),
                      _checkboxLayerRow(
                        label: 'Gale MOLA + THEMIS Blend',
                        value: _ovBlendGale,
                        onChanged: (v) => setState(() => _ovBlendGale = v),
                      ),
                    ],
                  ),
                ),

                // 5. MONGODB VECTOR LAYERS
                _drawerSection(
                  title: 'MongoDB Vector Layers',
                  child: Column(
                    children: [
                      _checkboxLayerRow(
                        label: 'Mineral Signatures',
                        count: '${_mineralSites.length}',
                        value: _vecMinerals,
                        onChanged: (v) => setState(() => _vecMinerals = v),
                      ),
                      _checkboxLayerRow(
                        label: 'Planned Waypoints',
                        count: '${_plannedWaypoints.length}',
                        value: _vecPlannedWaypoints,
                        onChanged: (v) => setState(() => _vecPlannedWaypoints = v),
                      ),
                      _checkboxLayerRow(
                        label: 'EVA Tactical (PNR / Buddy)',
                        count: '2',
                        value: _vecEvaTactical,
                        onChanged: (v) => setState(() => _vecEvaTactical = v),
                      ),
                      _checkboxLayerRow(
                        label: 'Global Mars Landmarks',
                        count: '${_globalLandmarks.length}',
                        value: _vecLandmarks,
                        onChanged: (v) => setState(() => _vecLandmarks = v),
                      ),
                      _checkboxLayerRow(
                        label: 'Curiosity Gale Waypoints',
                        count: '${curiosityList.length}',
                        value: _vecRoverWaypoints,
                        onChanged: (v) => setState(() => _vecRoverWaypoints = v),
                      ),
                      _checkboxLayerRow(
                        label: 'THEMIS Stamps',
                        count: '${state.stamps.length}',
                        value: _vecThemisStamps,
                        onChanged: (v) => setState(() => _vecThemisStamps = v),
                      ),
                      _checkboxLayerRow(
                        label: 'Perseverance Waypoints',
                        count: '${perseveranceList.length}',
                        value: _vecPerseverance,
                        onChanged: (v) => setState(() => _vecPerseverance = v),
                      ),
                      _checkboxLayerRow(
                        label: 'Mount Sharp & Gale AOI',
                        value: _vecAoiBounds,
                        onChanged: (v) => setState(() => _vecAoiBounds = v),
                      ),
                    ],
                  ),
                ),

                // 6. LEGEND
                _drawerSection(
                  title: 'Legend',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _legendRow(const Color(0xFF00E5FF), 'CRISM/TES Hydrated Minerals'),
                      _legendRow(const Color(0xFFFFD60A), 'Planned EVA Waypoint'),
                      _legendRow(const Color(0xFF28CD41), 'PNR Safe Boundary & EVA-1'),
                      _legendRow(const Color(0xFF38BDF8), 'Global Landmark (Mons/Crater)'),
                      _legendRow(const Color(0xFFFF4D4D), 'Landing Site'),
                      _legendRow(const Color(0xFFFF9F1C), 'Curiosity Waypoint'),
                      _legendRow(const Color(0xFFA855F7), 'Perseverance (M20)'),
                      _legendRow(const Color(0xFF2EC4B6), 'THEMIS IR Stamp'),
                      _legendRow(const Color(0xFFE71D36), 'THEMIS VIS Stamp'),
                    ],
                  ),
                ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightDrawer(AresState state) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final elapsedMin = math.max(0.0, (nowSec - _plssResetEpochSec) / 60.0);
    final workFactor = _plssWorkW / 260.0;
    final distKm = _walkedDistM / 1000.0;

    final o2Pct = (_plssInitO2 - elapsedMin * 0.18 * workFactor - distKm * 6.5)
        .clamp(0.0, 100.0);
    final o2Psi = (o2Pct / 100.0 * 3000.0).round();
    final batPct = (_plssInitBat - elapsedMin * 0.14 * workFactor - distKm * 4.8)
        .clamp(0.0, 100.0);
    final h2oPct = (_plssInitH2O - elapsedMin * 0.12 * workFactor - distKm * 4.2)
        .clamp(0.0, 100.0);
    final co2MmHg = (1.1 + workFactor * 0.45).toStringAsFixed(1);
    final plssNominal = o2Pct >= 30 && batPct >= 25;

    // Relay pass countdown
    final periodSec = (_relayPeriodMin * 60).round().clamp(300, 14400);
    final remRelaySec =
        periodSec - ((nowSec + _relayOffsetSec.round()) % periodSec);
    final relayMin = (remRelaySec ~/ 60).toString().padLeft(2, '0');
    final relaySec = (remRelaySec % 60).toString().padLeft(2, '0');

    // Weather / MEDA / REMS telemetry
    final latestMeda = state.meda.isNotEmpty
        ? state.meda.last
        : const MedaRecord(
            bucket: 'Sol 100 12:00',
            airTempMean: -22.8,
            groundTempMean: -8.3,
            pressurePa: 742.0,
            opacity: 0.52,
            solarZenithDeg: 28.4,
            windValidFraction: 1.0,
            safetyState: 'NOMINAL',
          );

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xEB121216),
        border: Border(
          left: BorderSide(color: Color(0x14FFFFFF), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 32,
            offset: Offset(-10, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drawer Header
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              color: Color(0x05FFFFFF),
              border: Border(
                bottom: BorderSide(color: Color(0x14FFFFFF), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'TELEMETRY & INSPECTOR',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.77,
                      color: Color(0xFF9898A0),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _rightDrawerOpen = false),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0x0FFFFFFF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      LucideIcons.x,
                      size: 14,
                      color: Color(0xFF9898A0),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                // 1. PLSS Life Support (EVA-1)
                _telemetryCard(
                  title: 'PLSS Life Support (EVA-1)',
                  badge: plssNominal ? 'NOMINAL' : 'CAUTION',
                  badgeColor: plssNominal
                      ? const Color(0xFF30D158)
                      : const Color(0xFFFF9F0A),
                  child: Column(
                    children: [
                      _weatherGrid6([
                        ('O₂ Pressure', '$o2Psi psi (${o2Pct.round()}%)'),
                        ('Suit / CO₂', '${_plssPressKpa.toStringAsFixed(1)} kPa · $co2MmHg mmHg'),
                        ('Battery', '${batPct.round()}% · 28.2 V'),
                        ('Cooling H₂O', '${h2oPct.round()}% · 18.4°C'),
                        ('Metabolic', '${_plssWorkW.round()} W (EVA Walk)'),
                        ('Traverse', '${_walkedDistM.round()} m walked'),
                      ]),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _miniNumericControl(
                                    label: 'Init O₂ %',
                                    value: '${_plssInitO2.round()}',
                                    onDelta: (d) => setState(
                                      () => _plssInitO2 = (_plssInitO2 + d * 5).clamp(20, 100),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: _miniNumericControl(
                                    label: 'Init Bat %',
                                    value: '${_plssInitBat.round()}',
                                    onDelta: (d) => setState(
                                      () => _plssInitBat = (_plssInitBat + d * 5).clamp(20, 100),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: _miniNumericControl(
                                    label: 'H₂O %',
                                    value: '${_plssInitH2O.round()}',
                                    onDelta: (d) => setState(
                                      () => _plssInitH2O = (_plssInitH2O + d * 5).clamp(20, 100),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: _miniNumericControl(
                                    label: 'Work (W)',
                                    value: '${_plssWorkW.round()}',
                                    onDelta: (d) => setState(
                                      () => _plssWorkW = (_plssWorkW + d * 25).clamp(120, 600),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: _miniNumericControl(
                                    label: 'Press kPa',
                                    value: _plssPressKpa.toStringAsFixed(1),
                                    onDelta: (d) => setState(
                                      () => _plssPressKpa = (_plssPressKpa + d * 0.5).clamp(24.0, 34.0),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: _actionButton(
                                    label: 'Reset Sim',
                                    onTap: () {
                                      setState(() {
                                        _plssInitO2 = 100;
                                        _plssInitBat = 100;
                                        _plssInitH2O = 100;
                                        _walkedDistM = 0;
                                        _plssResetEpochSec =
                                            DateTime.now().millisecondsSinceEpoch ~/ 1000;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Comms & Orbital Relay
                _telemetryCard(
                  title: 'Comms & Orbital Relay',
                  badge: _edacFixedCount == 0
                      ? 'CRC32 OK'
                      : 'EDAC FIXED ($_edacFixedCount)',
                  badgeColor: _edacFixedCount == 0
                      ? const Color(0xFF30D158)
                      : const Color(0xFFFF9F0A),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _weatherGrid4([
                        ('Hab UHF', 'LOCKED · 401.6 MHz'),
                        ('Relay Pass', 'Odyssey in $relayMin:$relaySec'),
                        ('Cache', 'IndexedDB Ready'),
                        (
                          'EDAC Log',
                          _edacFixedCount == 0
                              ? '0 Bit-Flips'
                              : '$_edacLastWordHex Corrected',
                        ),
                      ]),
                      const SizedBox(height: 6),
                      _actionButton(
                        label: 'Test Bit-Flip EDAC',
                        onTap: () {
                          setState(() {
                            _edacFixedCount++;
                            final randHex = (0x4F9A0000 + (_edacFixedCount * 137))
                                .toRadixString(16)
                                .toUpperCase();
                            _edacLastWordHex = '0x$randHex';
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _miniNumericControl(
                              label: 'Orbit (m)',
                              value: '${_relayPeriodMin.round()}',
                              onDelta: (d) => setState(
                                () => _relayPeriodMin = (_relayPeriodMin + d * 5).clamp(10, 180),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _miniNumericControl(
                              label: 'Offset (s)',
                              value: '${_relayOffsetSec.round()}',
                              onDelta: (d) => setState(
                                () => _relayOffsetSec = _relayOffsetSec + d * 60,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _actionButton(
                              label: 'Sat Nearby',
                              onTap: () {
                                setState(() {
                                  _relayOffsetSec = (periodSec - nowSec % periodSec - 45)
                                      .toDouble();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 3. Space Weather / MEDA
                _telemetryCard(
                  title: 'Space Weather / MEDA',
                  badge: _weatherRange == 'sol100'
                      ? 'SOL 100'
                      : _weatherRange.toUpperCase(),
                  badgeColor: const Color(0xFF30D158),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Duration:',
                            style: TextStyle(fontSize: 10, color: Color(0xFF9898A0)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _weatherRange,
                                isDense: true,
                                isExpanded: true,
                                dropdownColor: const Color(0xFF1C1C21),
                                style: AresType.monoStyle(
                                  size: 10,
                                  color: const Color(0xFFF4F4F6),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'sol100',
                                    child: Text(
                                      'MEDA Sol 100 (15m)',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'rems_30',
                                    child: Text(
                                      'REMS (Last 30 Sols)',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'rems_90',
                                    child: Text(
                                      'REMS (Last 90 Sols)',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'rems_365',
                                    child: Text(
                                      'REMS (1 Earth Year)',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'rems_668',
                                    child: Text(
                                      'REMS (1 Mars Year / 668 Sols)',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'rems_all',
                                    child: Text(
                                      'REMS Archive (All 14 Years)',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'custom',
                                    child: Text(
                                      'Custom Sol / Date Range',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) setState(() => _weatherRange = v);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_weatherRange == 'custom') ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _miniNumericControl(
                                label: 'Start Sol',
                                value: _customStartSol,
                                onDelta: (d) {
                                  final v = (int.tryParse(_customStartSol) ?? 1) + d * 25;
                                  setState(() => _customStartSol = '${v.clamp(1, 4500)}');
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _miniNumericControl(
                                label: 'End Sol',
                                value: _customEndSol,
                                onDelta: (d) {
                                  final v = (int.tryParse(_customEndSol) ?? 500) + d * 25;
                                  setState(() => _customEndSol = '${v.clamp(50, 4858)}');
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      _weatherGrid6([
                        (
                          'Air Temp',
                          '${(latestMeda.airTempMean ?? -22.8).toStringAsFixed(1)} °C',
                        ),
                        (
                          'Ground IR',
                          '${(latestMeda.groundTempMean ?? -8.3).toStringAsFixed(1)} °C',
                        ),
                        (
                          'Pressure',
                          '${(latestMeda.pressurePa ?? 742.0).toStringAsFixed(1)} Pa',
                        ),
                        (
                          'Dust Tau',
                          (latestMeda.opacity ?? 0.52).toStringAsFixed(2),
                        ),
                        (
                          'Solar Zenith',
                          '${(latestMeda.solarZenithDeg ?? 28.4).toStringAsFixed(1)}°',
                        ),
                        ('UV Index', 'MODERATE (2.4)'),
                      ]),
                      const SizedBox(height: 8),
                      Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0x80000000),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0x14FFFFFF)),
                        ),
                        child: CustomPaint(
                          painter: _WeatherSparklinePainter(
                            meda: state.meda,
                            rangeMode: _weatherRange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 4. Radiation & Space Weather (RAD)
                _telemetryCard(
                  title: 'Radiation & Space Weather (RAD)',
                  badge: _cfgEnvMode == 'storm' ? 'SEP WATCH' : 'NOMINAL',
                  badgeColor: _cfgEnvMode == 'storm'
                      ? const Color(0xFFFF9F0A)
                      : const Color(0xFF30D158),
                  child: _weatherGrid6([
                    ('Dose Rate', '242 µGy/day'),
                    ('Daily GCR', '0.68 mSv/sol'),
                    ('4h EVA Dose', '0.11 mSv'),
                    ('SEP Storm', _cfgEnvMode == 'storm' ? 'ELEVATED' : 'QUIET (G0)'),
                    ('Shielding', 'Regolith + Hab'),
                    ('Source', 'MSL RAD + DONKI'),
                  ]),
                ),

                // 5. Feature & Site Inspector Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0x05FFFFFF),
                    border: Border(
                      bottom: BorderSide(color: Color(0x14FFFFFF), width: 1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'FEATURE & SITE INSPECTOR',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.77,
                            color: Color(0xFF9898A0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0x1F0A84FF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _inspectorBadge,
                          style: AresType.monoStyle(
                            size: 10,
                            color: const Color(0xFF64D2FF),
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 6. Feature & Site Inspector Body
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _buildInspectorBody(state),
                ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorBody(AresState state) {
    if (_inspectorKind == 'eva_route' && _activeEvaPlan != null) {
      final plan = _activeEvaPlan!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kvTable([
            ('Algorithm', _plannerAlgo == 'theta_star' ? 'Theta* Any-Angle' : 'A* 8-Connected Grid'),
            ('Total Distance', '${(plan.distanceKm * 1000).round()} m (${plan.distanceKm.toStringAsFixed(2)} km)'),
            ('Waypoints', '${_plannedRouteStops.length} nodes (${plan.points.length} vertices)'),
            ('Max Slope', '${plan.maxSlopeDeg.toStringAsFixed(1)}° (Limit ${_cfgMaxSlopeDeg.round()}°)'),
            ('Elevation Gain', '+${plan.elevationGainM.round()} m'),
            ('Est. Duration', plan.durationLabel),
            ('Est. Suit O₂ Used', '${_evaEstO2UsedPct.toStringAsFixed(1)}% (Init ${_cfgSuitO2Pct.round()}%)'),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0x0AFFFFFF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _evaOverallGo
                    ? const Color(0x4D30D158)
                    : const Color(0x4DFF453A),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.shieldCheck,
                          size: 14,
                          color: _evaOverallGo
                              ? const Color(0xFF30D158)
                              : const Color(0xFFFF453A),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'ASTRONAUT SAFETY DASHBOARD',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Color(0xFFF4F4F6),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _evaOverallGo
                            ? const Color(0x2630D158)
                            : const Color(0x26FF453A),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _evaOverallGo ? 'EVA GO' : 'NO-GO / CAUTION',
                        style: AresType.monoStyle(
                          size: 9.5,
                          weight: FontWeight.w700,
                          color: _evaOverallGo
                              ? const Color(0xFF30D158)
                              : const Color(0xFFFF453A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._safetyChecks.map((chk) {
                  final color = chk.status == 'GO'
                      ? const Color(0xFF30D158)
                      : (chk.status == 'CAUTION'
                          ? const Color(0xFFFF9F0A)
                          : const Color(0xFFFF453A));
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            chk.label,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF9898A0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${chk.value} · ${chk.status}',
                          style: AresType.monoStyle(
                            size: 10,
                            weight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _actionButton(
            icon: LucideIcons.compass,
            label: 'Walk EVA in Visor Street View',
            primary: true,
            onTap: () {
              final startPt = _plannedRouteStops.isNotEmpty
                  ? _plannedRouteStops.first.point
                  : plan.points.first;
              setState(() {
                _streetViewPoint = startPt;
                _streetViewLabel = 'EVA Traverse · WP 1 / ${_plannedRouteStops.length}';
                _streetViewModalOpen = true;
              });
            },
          ),
        ],
      );
    }

    if (_inspectorKind == 'mineral' && _selectedMineral != null) {
      final m = _selectedMineral!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kvTable([
            ('Outcrop Name', m.name),
            ('Dominant Phase', m.mineral),
            ('Hydration Index', '${m.hydrationPct.toStringAsFixed(1)} wt% H₂O/OH'),
            ('Instrument', m.instrument),
            ('Coordinates', '${m.lat.toStringAsFixed(4)}°, ${m.lon.toStringAsFixed(4)}°'),
            ('Geologic Context', m.notes),
          ]),
          const SizedBox(height: 10),
          _actionButton(
            icon: LucideIcons.compass,
            label: 'Inspect Outcrop in 360° Street View',
            primary: true,
            onTap: () {
              setState(() {
                _streetViewPoint = GeoPoint(m.lon, m.lat);
                _streetViewLabel = m.name;
                _streetViewModalOpen = true;
              });
            },
          ),
        ],
      );
    }

    if (_inspectorKind == 'landmark' && _selectedLandmark != null) {
      final lm = _selectedLandmark!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kvTable([
            ('Landmark Name', lm.name),
            ('IAU Feature Type', lm.category),
            ('Extent / Diameter', '${lm.diameterKm.toStringAsFixed(0)} km'),
            ('Coordinates', '${lm.lat.toStringAsFixed(3)}°, ${lm.lon.toStringAsFixed(3)}°'),
            ('Description', lm.notes),
          ]),
          const SizedBox(height: 10),
          _actionButton(
            icon: LucideIcons.compass,
            label: 'Open 360° Street View Here',
            primary: true,
            onTap: () {
              setState(() {
                _streetViewPoint = GeoPoint(lm.lon, lm.lat);
                _streetViewLabel = lm.name;
                _streetViewModalOpen = true;
              });
            },
          ),
        ],
      );
    }

    if (_inspectorKind == 'stamp' && _selectedStamp != null) {
      final st = _selectedStamp!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kvTable([
            ('Product ID', st.fileId),
            ('Instrument Mode', 'THEMIS ${st.frameType} (${st.bands} bands)'),
            ('Coordinates', '${st.lat.toStringAsFixed(4)}°, ${st.lon.toStringAsFixed(4)}°'),
            ('Surface Temp', st.tempC != null ? '${st.tempC!.toStringAsFixed(1)} °C (${st.tempK?.toStringAsFixed(1)} K)' : 'N/A'),
            ('Bolometric Albedo', st.albedo?.toStringAsFixed(3) ?? '0.185'),
            ('Calibration Status', st.tempStatus),
          ]),
          const SizedBox(height: 10),
          _actionButton(
            icon: LucideIcons.compass,
            label: 'Open 360° Street View Here',
            primary: true,
            onTap: () {
              setState(() {
                _streetViewPoint = st.point;
                _streetViewLabel = 'THEMIS ${st.fileId}';
                _streetViewModalOpen = true;
              });
            },
          ),
        ],
      );
    }

    if (_inspectorKind == 'waypoint' && _selectedFeature != null) {
      final f = _selectedFeature!;
      final elev = f.elevation ?? state.terrain.elevationAt(f.point.lon, f.point.lat);
      final slope = state.terrain.slopeAt(f.point.lon, f.point.lat);
      final isPlanned = _plannedWaypoints.any((w) => w.id == f.id);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kvTable([
            ('Site Name', f.name),
            ('Category', f.kind.toUpperCase()),
            ('Source', f.source),
            ('Coordinates', '${f.point.lat.toStringAsFixed(4)}°, ${f.point.lon.toStringAsFixed(4)}°'),
            ('MOLA Elevation', '${elev.round()} m'),
            ('Local Slope', '${slope.toStringAsFixed(1)}°'),
            ('Field Notes', f.notes),
          ]),
          const SizedBox(height: 10),
          _actionButton(
            icon: LucideIcons.compass,
            label: 'Open 360° Street View Here',
            primary: true,
            onTap: () {
              setState(() {
                _streetViewPoint = f.point;
                _streetViewLabel = f.name;
                _streetViewModalOpen = true;
              });
            },
          ),
          if (isPlanned) ...[
            const SizedBox(height: 6),
            _actionButton(
              icon: LucideIcons.x,
              label: 'Delete Planned Waypoint',
              onTap: () {
                setState(() {
                  _plannedWaypoints.removeWhere((w) => w.id == f.id);
                  _selectedFeature = null;
                  _inspectorKind = 'idle';
                  _inspectorBadge = 'IDLE';
                });
              },
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            '360° SURFACE PANORAMA & ROVER CAMERAS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Color(0xFF9898A0),
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 110,
              child: Image.asset(
                state.data.photos.first.asset,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.45,
            children: state.data.photos.take(4).map((photo) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _streetViewPoint = f.point;
                    _streetViewLabel = '${f.name} · ${photo.title}';
                    _streetViewModalOpen = true;
                  });
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(photo.asset, fit: BoxFit.cover),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          color: const Color(0xBF000000),
                          child: Text(
                            photo.nasaId,
                            overflow: TextOverflow.ellipsis,
                            style: AresType.monoStyle(
                              size: 9,
                              color: const Color(0xFFF4F4F6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
      alignment: Alignment.center,
      child: const Text(
        'Click any waypoint, mineral outcrop, thermal stamp, or planned EVA route on the map to inspect NASA PDS metadata and surface imagery.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: Color(0xFF63636B),
        ),
      ),
    );
  }

  Widget _buildTourOverlay() {
    final idx = _tourStepIndex ?? 0;
    final step = _tourSteps[idx.clamp(0, _tourSteps.length - 1)];

    return Container(
      color: const Color(0x88000000),
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xF5141418),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x4D0A84FF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 32,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    step.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64D2FF),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _tourStepIndex = null),
                    child: const Icon(
                      LucideIcons.x,
                      size: 15,
                      color: Color(0xFF9898A0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                step.body,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: Color(0xFFF4F4F6),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _tourStepIndex = null),
                    child: const Text(
                      'Skip Tour',
                      style: TextStyle(fontSize: 11, color: Color(0xFF9898A0)),
                    ),
                  ),
                  Row(
                    children: [
                      if (idx > 0)
                        OutlinedButton(
                          onPressed: () {
                            final prev = idx - 1;
                            setState(() {
                              _tourStepIndex = prev;
                              _leftDrawerOpen = _tourSteps[prev].openLeftDrawer;
                              _rightDrawerOpen = _tourSteps[prev].openRightDrawer;
                            });
                          },
                          child: const Text('Prev', style: TextStyle(fontSize: 11)),
                        ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0A84FF),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          if (idx + 1 < _tourSteps.length) {
                            final next = idx + 1;
                            setState(() {
                              _tourStepIndex = next;
                              _leftDrawerOpen = _tourSteps[next].openLeftDrawer;
                              _rightDrawerOpen = _tourSteps[next].openRightDrawer;
                            });
                          } else {
                            setState(() => _tourStepIndex = null);
                          }
                        },
                        child: Text(
                          idx + 1 < _tourSteps.length ? 'Next' : 'Finish',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerSection({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x14FFFFFF), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: Color(0xFF63636B),
            ),
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }

  Widget _telemetryCard({
    required String title,
    required String badge,
    required Color badgeColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0x04FFFFFF),
        border: Border(
          bottom: BorderSide(color: Color(0x14FFFFFF), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: Color(0xFF9898A0),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  badge,
                  style: AresType.monoStyle(
                    size: 9.5,
                    weight: FontWeight.w600,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _weatherGrid6(List<(String, String)> items) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 5,
      crossAxisSpacing: 5,
      childAspectRatio: 2.05,
      children: items.map((item) => _weatherCell(item.$1, item.$2)).toList(),
    );
  }

  Widget _weatherGrid4(List<(String, String)> items) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 5,
      crossAxisSpacing: 5,
      childAspectRatio: 3.1,
      children: items.map((item) => _weatherCell(item.$1, item.$2)).toList(),
    );
  }

  Widget _weatherCell(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 8.5,
              letterSpacing: 0.25,
              color: Color(0xFF63636B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: AresType.monoStyle(
              size: 10.5,
              weight: FontWeight.w600,
              color: const Color(0xFFF4F4F6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvTable(List<(String, String)> rows) {
    return Column(
      children: rows.map((r) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 108,
                child: Text(
                  r.$1,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF63636B),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  r.$2,
                  style: AresType.monoStyle(
                    size: 11,
                    color: const Color(0xFFF4F4F6),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _actionButton({
    IconData? icon,
    required String label,
    bool primary = false,
    bool active = false,
    bool dashed = false,
    required VoidCallback onTap,
  }) {
    final bg = active
        ? const Color(0x400A84FF)
        : (primary ? const Color(0x240A84FF) : const Color(0x0DFFFFFF));
    final border = active
        ? const Color(0xFF0A84FF)
        : (primary ? const Color(0x660A84FF) : const Color(0x14FFFFFF));
    final fg = (primary || active) ? const Color(0xFF64D2FF) : const Color(0xFFF4F4F6);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: dashed ? const Color(0x4D0A84FF) : border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: dashed ? const Color(0xFF64D2FF) : fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0x470A84FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFF9898A0),
          ),
        ),
      ),
    );
  }

  Widget _miniNumericControl({
    required String label,
    required String value,
    required ValueChanged<int> onDelta,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x8C000000),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Color(0xFF9898A0)),
                ),
                Text(
                  value,
                  style: AresType.monoStyle(
                    size: 10.5,
                    weight: FontWeight.w600,
                    color: const Color(0xFFF4F4F6),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => onDelta(-1),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  child: Text('−', style: TextStyle(fontSize: 12, color: Color(0xFF9898A0))),
                ),
              ),
              InkWell(
                onTap: () => onDelta(1),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  child: Text('+', style: TextStyle(fontSize: 12, color: Color(0xFF64D2FF))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _radioLayerRow({
    required String label,
    required String value,
    required String groupValue,
    required ValueChanged<String> onChanged,
  }) {
    final selected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.circleDot : LucideIcons.circle,
              size: 14,
              color: selected ? const Color(0xFF0A84FF) : const Color(0xFF63636B),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFF4F4F6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkboxLayerRow({
    required String label,
    String? count,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: value ? const Color(0xFF0A84FF) : Colors.transparent,
                borderRadius: BorderRadius.circular(3.5),
                border: Border.all(
                  color: value ? const Color(0xFF0A84FF) : const Color(0xFF63636B),
                ),
              ),
              child: value
                  ? const Icon(LucideIcons.check, size: 10, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFF4F4F6),
                ),
              ),
            ),
            if (count != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0x12FFFFFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count,
                  style: AresType.monoStyle(
                    size: 10,
                    color: const Color(0xFF9898A0),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _legendRow(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9898A0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ares2DMapPainter extends CustomPainter {
  _Ares2DMapPainter({
    required this.centerLon,
    required this.centerLat,
    required this.zoom,
    required this.baseLayer,
    required this.ovMountSharp,
    required this.ovJezero,
    required this.ovCtxGale,
    required this.ovBlendGale,
    required this.vecMinerals,
    required this.vecPlannedWaypoints,
    required this.vecEvaTactical,
    required this.vecLandmarks,
    required this.vecRoverWaypoints,
    required this.vecThemisStamps,
    required this.vecPerseverance,
    required this.vecAoiBounds,
    required this.loadedImages,
    required this.minerals,
    required this.landmarks,
    required this.plannedWaypoints,
    required this.curiosityWaypoints,
    required this.perseveranceWaypoints,
    required this.curiosityTrail,
    required this.stamps,
    required this.landingSite,
    required this.buddyPoint,
    required this.evaStartPoint,
    required this.evaGoalPoint,
    required this.activeEvaPlan,
    required this.plannedRouteStops,
    required this.selectedFeature,
  });

  final double centerLon;
  final double centerLat;
  final double zoom;
  final String baseLayer;
  final bool ovMountSharp;
  final bool ovJezero;
  final bool ovCtxGale;
  final bool ovBlendGale;
  final bool vecMinerals;
  final bool vecPlannedWaypoints;
  final bool vecEvaTactical;
  final bool vecLandmarks;
  final bool vecRoverWaypoints;
  final bool vecThemisStamps;
  final bool vecPerseverance;
  final bool vecAoiBounds;
  final Map<String, ui.Image> loadedImages;
  final List<_MineralSite> minerals;
  final List<_GlobalLandmark> landmarks;
  final List<SurveyFeature> plannedWaypoints;
  final List<SurveyFeature> curiosityWaypoints;
  final List<SurveyFeature> perseveranceWaypoints;
  final List<GeoPoint> curiosityTrail;
  final List<ThemisStamp> stamps;
  final GeoPoint landingSite;
  final GeoPoint buddyPoint;
  final GeoPoint? evaStartPoint;
  final GeoPoint? evaGoalPoint;
  final TraversePlan? activeEvaPlan;
  final List<({GeoPoint point, String label})> plannedRouteStops;
  final SurveyFeature? selectedFeature;

  Offset _geoToScreen(double lon, double lat, Size size) {
    final lonSpan = 360.0 / zoom;
    final latSpan = lonSpan * (size.height / math.max(size.width, 1.0));
    final x = ((lon - centerLon) / lonSpan + 0.5) * size.width;
    final y = ((centerLat - lat) / latSpan + 0.5) * size.height;
    return Offset(x, y);
  }

  Rect _bboxToRect(
    double minLon,
    double minLat,
    double maxLon,
    double maxLat,
    Size size,
  ) {
    final tl = _geoToScreen(minLon, maxLat, size);
    final br = _geoToScreen(maxLon, minLat, size);
    return Rect.fromPoints(tl, br);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // 1. Background fill
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF140D0A),
    );

    // 2. Global Base Layer raster
    final globalKey = baseLayer == 'mola_color' ? 'mars_mola' : 'mars_global';
    final globalImg = loadedImages[globalKey];
    if (globalImg != null) {
      final dst = _bboxToRect(-180, -90, 180, 90, size);
      final paint = Paint()..filterQuality = FilterQuality.medium;
      if (baseLayer == 'themis_ir_global') {
        paint.colorFilter = const ColorFilter.matrix(<double>[
          0.35, 0.50, 0.15, 0, 10,
          0.30, 0.45, 0.15, 0, 5,
          0.35, 0.55, 0.25, 0, 22,
          0, 0, 0, 1, 0,
        ]);
      } else if (baseLayer == 'ctx_global') {
        paint.colorFilter = const ColorFilter.matrix(<double>[
          0.33, 0.59, 0.11, 0, 0,
          0.33, 0.59, 0.11, 0, 0,
          0.33, 0.59, 0.11, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      }
      canvas.drawImageRect(
        globalImg,
        Rect.fromLTWH(0, 0, globalImg.width.toDouble(), globalImg.height.toDouble()),
        dst,
        paint,
      );
    }

    // 3. Regional Overlays
    if (ovMountSharp && loadedImages['mount_sharp_orbital'] != null) {
      final img = loadedImages['mount_sharp_orbital']!;
      final dst = _bboxToRect(137.15, -5.35, 138.10, -4.45, size);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        Paint()..color = const Color(0xD9FFFFFF),
      );
    }

    if (ovBlendGale && loadedImages['mola_themis_blend'] != null) {
      final img = loadedImages['mola_themis_blend']!;
      final dst = _bboxToRect(137.25, -4.95, 137.70, -4.48, size);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        Paint()..color = const Color(0xCCFFFFFF),
      );
    }

    if (ovCtxGale && loadedImages['ctx_optical_gale'] != null) {
      final img = loadedImages['ctx_optical_gale']!;
      final dst = _bboxToRect(137.33, -4.78, 137.55, -4.52, size);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        Paint()..color = const Color(0xD9FFFFFF),
      );
    }

    if (ovJezero && loadedImages['jezero_orbital'] != null) {
      final img = loadedImages['jezero_orbital']!;
      final dst = _bboxToRect(77.25, 18.25, 77.70, 18.62, size);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        Paint()..color = const Color(0xE6FFFFFF),
      );
    }

    // 4. Coordinate Graticule Grid
    final gridPaint = Paint()
      ..color = const Color(0x18FFFFFF)
      ..strokeWidth = 1;
    final stepDeg = zoom < 3
        ? 30.0
        : (zoom < 10 ? 5.0 : (zoom < 22 ? 0.5 : 0.05));
    final lonSpan = 360.0 / zoom;
    final minLonVis = (centerLon - lonSpan * 0.6).floorToDouble();
    final maxLonVis = (centerLon + lonSpan * 0.6).ceilToDouble();
    for (var lon = (minLonVis / stepDeg).floor() * stepDeg;
        lon <= maxLonVis;
        lon += stepDeg) {
      final p1 = _geoToScreen(lon, 85, size);
      final p2 = _geoToScreen(lon, -85, size);
      canvas.drawLine(Offset(p1.dx, 0), Offset(p2.dx, size.height), gridPaint);
    }
    final latSpan = lonSpan * (size.height / math.max(size.width, 1.0));
    final minLatVis = (centerLat - latSpan * 0.6).floorToDouble();
    final maxLatVis = (centerLat + latSpan * 0.6).ceilToDouble();
    for (var lat = (minLatVis / stepDeg).floor() * stepDeg;
        lat <= maxLatVis;
        lat += stepDeg) {
      final p1 = _geoToScreen(-180, lat, size);
      final p2 = _geoToScreen(180, lat, size);
      canvas.drawLine(Offset(0, p1.dy), Offset(size.width, p2.dy), gridPaint);
    }

    // 5. AOI Bounding Boxes
    if (vecAoiBounds) {
      final aoiPaint = Paint()
        ..color = const Color(0x800A84FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawRect(_bboxToRect(137.15, -5.35, 138.10, -4.45, size), aoiPaint);
      canvas.drawRect(_bboxToRect(77.25, 18.25, 77.70, 18.62, size), aoiPaint);
    }

    // 6. THEMIS Stamps
    if (vecThemisStamps && zoom >= 4.0) {
      for (var i = 0; i < stamps.length; i += (zoom < 12 ? 3 : 1)) {
        final st = stamps[i];
        final pos = _geoToScreen(st.lon, st.lat, size);
        if (pos.dx < -10 ||
            pos.dx > size.width + 10 ||
            pos.dy < -10 ||
            pos.dy > size.height + 10) {
          continue;
        }
        final isVis = st.frameType.toUpperCase().contains('VIS');
        final color = isVis ? const Color(0xFFE71D36) : const Color(0xFF2EC4B6);
        canvas.drawCircle(pos, zoom > 20 ? 3.2 : 2.2, Paint()..color = color.withValues(alpha: 0.72));
      }
    }

    // 7. Curiosity Rover Trail + Waypoints
    if (vecRoverWaypoints) {
      if (curiosityTrail.length >= 2) {
        final path = Path();
        for (var i = 0; i < curiosityTrail.length; i++) {
          final p = _geoToScreen(curiosityTrail[i].lon, curiosityTrail[i].lat, size);
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xCCFF9F1C)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }

      for (final wp in curiosityWaypoints) {
        final pos = _geoToScreen(wp.point.lon, wp.point.lat, size);
        if (!_onScreen(pos, size)) continue;
        final isLanding = wp.kind.toLowerCase().contains('landing');
        final color = isLanding ? const Color(0xFFFF4D4D) : const Color(0xFFFF9F1C);
        canvas.drawCircle(pos, isLanding ? 6.0 : 4.5, Paint()..color = color);
        canvas.drawCircle(
          pos,
          isLanding ? 6.0 : 4.5,
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        if (zoom >= 14) {
          _drawLabel(canvas, pos + const Offset(7, -5), wp.name, color);
        }
      }
    }

    // 8. Perseverance Waypoints
    if (vecPerseverance) {
      for (final wp in perseveranceWaypoints) {
        final pos = _geoToScreen(wp.point.lon, wp.point.lat, size);
        if (!_onScreen(pos, size)) continue;
        const color = Color(0xFFA855F7);
        canvas.drawCircle(pos, 5.0, Paint()..color = color);
        canvas.drawCircle(
          pos,
          5.0,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
        if (zoom >= 12) {
          _drawLabel(canvas, pos + const Offset(7, -5), wp.name, const Color(0xFFD8B4FE));
        }
      }
    }

    // 9. CRISM / TES Mineral Signatures
    if (vecMinerals) {
      for (final m in minerals) {
        final pos = _geoToScreen(m.lon, m.lat, size);
        if (!_onScreen(pos, size)) continue;
        const color = Color(0xFF00E5FF);
        canvas.drawCircle(pos, 8.0, Paint()..color = color.withValues(alpha: 0.22));
        canvas.drawCircle(pos, 4.5, Paint()..color = color);
        if (zoom >= 10) {
          _drawLabel(canvas, pos + const Offset(8, -6), m.name, color);
        }
      }
    }

    // 10. Global Mars Landmarks
    if (vecLandmarks) {
      for (final lm in landmarks) {
        final pos = _geoToScreen(lm.lon, lm.lat, size);
        if (!_onScreen(pos, size)) continue;
        const color = Color(0xFF38BDF8);
        canvas.drawCircle(pos, 5.0, Paint()..color = color);
        canvas.drawCircle(
          pos,
          8.0,
          Paint()
            ..color = color.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        _drawLabel(canvas, pos + const Offset(9, -6), lm.name, const Color(0xFFBAE6FD));
      }
    }

    // 11. Planned Waypoints
    if (vecPlannedWaypoints) {
      for (final wp in plannedWaypoints) {
        final pos = _geoToScreen(wp.point.lon, wp.point.lat, size);
        if (!_onScreen(pos, size)) continue;
        const color = Color(0xFFFFD60A);
        canvas.drawCircle(pos, 5.5, Paint()..color = color);
        canvas.drawCircle(
          pos,
          5.5,
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        _drawLabel(canvas, pos + const Offset(8, -6), wp.name, color);
      }
    }

    // 12. EVA Tactical (PNR Safe Boundary, EVA-1 / Buddy, Active Planned Route)
    if (vecEvaTactical) {
      // 5 km PNR boundary around landingSite (5 km ≈ 0.0845° on Mars)
      final pnrCenter = _geoToScreen(landingSite.lon, landingSite.lat, size);
      final pnrEdge = _geoToScreen(landingSite.lon + 0.0845, landingSite.lat, size);
      final pnrRadiusPx = (pnrEdge.dx - pnrCenter.dx).abs();
      if (pnrRadiusPx > 8 && pnrRadiusPx < size.width * 3) {
        canvas.drawCircle(
          pnrCenter,
          pnrRadiusPx,
          Paint()
            ..color = const Color(0x5930D158)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }

      // EVA-1 & Buddy markers
      final eva1Pos = _geoToScreen(landingSite.lon, landingSite.lat, size);
      final buddyPos = _geoToScreen(buddyPoint.lon, buddyPoint.lat, size);
      if (_onScreen(eva1Pos, size)) {
        canvas.drawLine(
          eva1Pos,
          buddyPos,
          Paint()
            ..color = const Color(0x9930D158)
            ..strokeWidth = 1.5,
        );
        canvas.drawCircle(eva1Pos, 6.0, Paint()..color = const Color(0xFF30D158));
        canvas.drawCircle(buddyPos, 5.0, Paint()..color = const Color(0xFF0A84FF));
      }

      // Active EVA Route Polyline
      if (activeEvaPlan != null && activeEvaPlan!.points.length >= 2) {
        final routePath = Path();
        for (var i = 0; i < activeEvaPlan!.points.length; i++) {
          final p = _geoToScreen(
            activeEvaPlan!.points[i].lon,
            activeEvaPlan!.points[i].lat,
            size,
          );
          if (i == 0) {
            routePath.moveTo(p.dx, p.dy);
          } else {
            routePath.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(
          routePath,
          Paint()
            ..color = const Color(0x5900E5FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7.0
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawPath(
          routePath,
          Paint()
            ..color = const Color(0xFF00E5FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round,
        );

        for (var i = 0; i < plannedRouteStops.length; i++) {
          final st = plannedRouteStops[i];
          final pos = _geoToScreen(st.point.lon, st.point.lat, size);
          if (!_onScreen(pos, size)) continue;
          final isEnd = i == 0 || i == plannedRouteStops.length - 1;
          final c = i == 0
              ? const Color(0xFF30D158)
              : (i == plannedRouteStops.length - 1
                  ? const Color(0xFFFF453A)
                  : const Color(0xFF00E5FF));
          canvas.drawCircle(pos, isEnd ? 6.0 : 4.2, Paint()..color = c);
          _drawLabel(
            canvas,
            pos + const Offset(7, -6),
            i == 0
                ? 'START'
                : (i == plannedRouteStops.length - 1 ? 'GOAL' : 'WP$i'),
            c,
          );
        }
      } else if (evaStartPoint != null) {
        final pos = _geoToScreen(evaStartPoint!.lon, evaStartPoint!.lat, size);
        canvas.drawCircle(pos, 6.5, Paint()..color = const Color(0xFF30D158));
        _drawLabel(canvas, pos + const Offset(8, -6), 'EVA START', const Color(0xFF30D158));
      }
    }

    // 13. Selected Feature Reticle
    if (selectedFeature != null) {
      final pos = _geoToScreen(
        selectedFeature!.point.lon,
        selectedFeature!.point.lat,
        size,
      );
      if (_onScreen(pos, size)) {
        canvas.drawCircle(
          pos,
          11,
          Paint()
            ..color = const Color(0xFF0A84FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }
    }

    canvas.restore();
  }

  bool _onScreen(Offset pos, Size size) {
    return pos.dx >= -40 &&
        pos.dx <= size.width + 40 &&
        pos.dy >= -40 &&
        pos.dy <= size.height + 40;
  }

  void _drawLabel(Canvas canvas, Offset pos, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 4),
            Shadow(color: Colors.black, blurRadius: 8),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 180);
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _Ares2DMapPainter oldDelegate) => true;
}

class _WeatherSparklinePainter extends CustomPainter {
  _WeatherSparklinePainter({
    required this.meda,
    required this.rangeMode,
  });

  final List<MedaRecord> meda;
  final String rangeMode;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    if (w <= 0 || h <= 0) return;

    final airVals = <double>[];
    final groundVals = <double>[];

    if (rangeMode == 'sol100' && meda.isNotEmpty) {
      for (final r in meda) {
        if (r.airTempMean != null) airVals.add(r.airTempMean!);
        if (r.groundTempMean != null) groundVals.add(r.groundTempMean!);
      }
    } else {
      final count = rangeMode == 'rems_30'
          ? 30
          : (rangeMode == 'rems_90' ? 90 : 120);
      for (var i = 0; i < count; i++) {
        final phase = (i / count) * 2 * math.pi;
        groundVals.add(-12.0 + 14.0 * math.sin(phase));
        airVals.add(-72.0 + 11.0 * math.sin(phase - 0.3));
      }
    }

    if (airVals.length < 2) return;
    final all = [...airVals, ...groundVals];
    final minV = all.reduce(math.min) - 4;
    final maxV = all.reduce(math.max) + 4;
    final span = math.max(1.0, maxV - minV);

    void drawCurve(List<double> vals, Color color) {
      final path = Path();
      for (var i = 0; i < vals.length; i++) {
        final x = pad + (i / (vals.length - 1)) * w;
        final y = pad + (1.0 - (vals[i] - minV) / span) * h;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }

    if (groundVals.length >= 2) {
      drawCurve(groundVals, const Color(0xFFFF9F0A));
    }
    drawCurve(airVals, const Color(0xFF0A84FF));
  }

  @override
  bool shouldRepaint(covariant _WeatherSparklinePainter oldDelegate) =>
      oldDelegate.rangeMode != rangeMode || oldDelegate.meda.length != meda.length;
}

