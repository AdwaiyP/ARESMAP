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
  testWidgets('ARES boots to mission control on a 1280x800 tablet', (
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

    expect(find.text('MISSION CONTROL'), findsOneWidget);
    expect(find.text('GALE CRATER · AEOLIS PALUS'), findsOneWidget);
    expect(state.stamps.length, 730);
    expect(state.meda.length, 63);
    expect(state.route, isNotNull);

    await tester.tap(find.text('MAP'));
    await tester.pump();
    expect(find.text('SURFACE MAP'), findsOneWidget);

    await tester.tap(find.text('SCIENCE'));
    await tester.pump();
    expect(find.text('SCIENCE / SAMPLE LOG'), findsOneWidget);

    await tester.tap(find.text('SURFACE'));
    await tester.pump();
    expect(find.text('SURFACE IMAGERY'), findsOneWidget);
    final surfaceException = tester.takeException();

    await tester.tap(find.text('MISSION'));
    await tester.pump();
    expect(find.text('MISSION CONTROL'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    expect(surfaceException, isNull);
  });
}
