import 'package:ares_tablet/data/ares_dataset.dart';
import 'package:ares_tablet/screens/eva_screen.dart';
import 'package:ares_tablet/state/ares_scope.dart';
import 'package:ares_tablet/state/ares_state.dart';
import 'package:ares_tablet/theme/ares_theme.dart';
import 'package:ares_tablet/widgets/edac_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('local route opens visor, steps stops and resets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late AresDataset data;
    await tester.runAsync(() async {
      data = await AresDataset.load();
    });
    final state = AresState(data);
    await tester.pumpWidget(
      AresScope(
        state: state,
        child: MaterialApp(theme: buildAresTheme(), home: const EvaScreen()),
      ),
    );
    await tester.tap(find.text('Try a 350 m route'));
    await tester.pump();
    expect(find.text('Walk route in visor'), findsOneWidget);
    await tester.tap(find.text('Walk route in visor'));
    await tester.pump();
    expect(find.text('Visor route rehearsal'), findsOneWidget);
    expect(find.text('1 / 9'), findsOneWidget);
    await tester.tap(find.text('Next stop'));
    await tester.pump();
    expect(find.text('2 / 9'), findsOneWidget);
    await tester.tap(find.text('Walk 10 m'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.text('Next stop'));
      await tester.pump();
    }
    expect(find.text('9 / 9'), findsOneWidget);
    for (var i = 0; i < 9; i++) {
      await tester.tap(find.text('Previous stop'));
      await tester.pump();
    }
    expect(find.text('1 / 9'), findsOneWidget);
    await tester.tap(find.text('Back to plan'));
    await tester.pump();
    await tester.tap(find.text('Clear plan'));
    await tester.pump();
    expect(find.text('Walk route in visor'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('EDAC failure is never shown as a verified packet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAresTheme(),
        home: const Scaffold(body: EdacDialog()),
      ),
    );
    await tester.tap(find.text('Run bit-flip test'));
    await tester.pump();
    expect(find.text('CRC verified · packet recovered'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.text('Run bit-flip test'));
    await tester.pump();
    expect(find.text('CRC mismatch · reject packet'), findsOneWidget);
    expect(find.text('CRC verified · packet recovered'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('Run bit-flip test'));
    await tester.pump();
    expect(find.text('CRC verified · packet recovered'), findsNothing);
    expect(find.text('CRC mismatch · reject packet'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
