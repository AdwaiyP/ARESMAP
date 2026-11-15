import 'package:ares_tablet/app_shell.dart';
import 'package:ares_tablet/data/ares_dataset.dart';
import 'package:ares_tablet/state/ares_scope.dart';
import 'package:ares_tablet/state/ares_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadAresFonts() async {
  final display = FontLoader('BarlowCondensed')
    ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-SemiBold.ttf'));
  await display.load();
  final mono = FontLoader('IBMPlexMono')
    ..addFont(rootBundle.load('assets/fonts/IBMPlexMono-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/IBMPlexMono-Medium.ttf'));
  await mono.load();
}

void main() {
  testWidgets('ARES MAP boots to full-bleed Mars EVA Tactical Map on a 1280x800 tablet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late AresDataset dataset;
    await tester.runAsync(() async {
      await _loadAresFonts();
      dataset = await AresDataset.load();
    });
    final state = AresState(dataset);

    await tester.pumpWidget(
      AresScope(state: state, child: const AresAppShell()),
    );
    await tester.pump();

    expect(find.text('ARES MAP'), findsOneWidget);
    expect(find.text('MARS EVA TACTICAL MAP'), findsOneWidget);
    expect(find.text('Controls & Layers'), findsOneWidget);
    expect(find.text('Telemetry & Inspector'), findsOneWidget);
    expect(state.stamps.length, 730);
    expect(state.meda.length, 63);
    expect(state.route, isNotNull);

    // 1. Open Left Drawer (MAP CONTROLS & LAYERS)
    await tester.tap(find.text('Controls & Layers'));
    await tester.pump();
    expect(find.text('MAP CONTROLS & LAYERS'), findsOneWidget);
    expect(find.text('Whole Mars'), findsOneWidget);
    expect(find.text('3D Mars Globe'), findsOneWidget);
    expect(find.text('Launch Mars Street View'), findsOneWidget);

    // 2. Open Right Drawer (TELEMETRY & INSPECTOR) & test Bit-Flip EDAC
    await tester.tap(find.text('Telemetry & Inspector'));
    await tester.pump();
    expect(find.text('TELEMETRY & INSPECTOR'), findsOneWidget);
    expect(find.text('FEATURE & SITE INSPECTOR'), findsOneWidget);
    expect(find.text('CRC32 OK'), findsOneWidget);
    await tester.tap(find.text('Test Bit-Flip EDAC'));
    await tester.pump();
    expect(find.text('EDAC FIXED (1)'), findsOneWidget);

    // 3. Launch 3D Mars Globe Modal & close it
    await tester.tap(find.text('3D Mars Globe'));
    await tester.pump();
    expect(find.text('3D Mars Planet & Terrain'), findsOneWidget);
    await tester.tap(find.text('Close 3D'));
    await tester.pump();
    expect(find.text('3D Mars Planet & Terrain'), findsNothing);

    // 4. Launch 360° Mars Street View Modal & close it
    await tester.tap(find.text('Launch Mars Street View'));
    await tester.pump();
    expect(find.text('Mars 360° Street View'), findsOneWidget);
    expect(find.text('Astronaut'), findsOneWidget);
    await tester.tap(find.text('Astronaut'));
    await tester.pump();
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(find.text('Mars 360° Street View'), findsNothing);

    // 5. Launch Interactive Guide Tour & skip
    await tester.tap(find.text('? Guide'));
    await tester.pump();
    expect(find.textContaining('Welcome to ARES MAP'), findsOneWidget);
    await tester.tap(find.text('Skip Tour'));
    await tester.pump();

    final exception = tester.takeException();
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    expect(exception, isNull);
  });
}
