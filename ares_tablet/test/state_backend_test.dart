import 'package:ares_tablet/data/ares_dataset.dart';
import 'package:ares_tablet/data/backend_api.dart';
import 'package:ares_tablet/state/ares_state.dart';
import 'package:ares_tablet/util/terrain.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBackend extends AresBackend {
  _FakeBackend() : super(baseUrl: 'http://127.0.0.1:1');

  @override
  Future<bool> ping() async => true;

  @override
  Future<BackendRouteResult?> planRoute(
    RouteGrid grid, {
    double maxSlopeDeg = 30,
    double slopeWeight = 2,
    double riskWeight = 5,
  }) async {
    return BackendRouteResult(
      status: 'success',
      cells: [
        GridCell(grid.startX, grid.startY),
        GridCell(grid.goalX, grid.goalY),
      ],
      distanceM: 2500,
      elevationGainM: 12,
      exploredNodes: 42,
    );
  }
}

void main() {
  testWidgets('backend re-solves the startup traverse and reports the link', (
    tester,
  ) async {
    late AresDataset dataset;
    await tester.runAsync(() async {
      dataset = await AresDataset.load();
    });
    final state = AresState(dataset, backend: _FakeBackend());

    await tester.runAsync(() async {
      for (var i = 0; i < 100 && !state.routeSolvedByBackend; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(state.backendOnline, isTrue);
    expect(state.backendChecked, isTrue);
    expect(state.routeSolvedByBackend, isTrue);
    expect(state.backendExploredNodes, 42);
    expect(state.routeSolverLabel, 'BACKEND A*');
    expect(state.backendStatusLabel, 'BACKEND LINK · LIVE');
    expect(state.route, isNotNull);
    expect(state.route!.targetName, 'VERA RUBIN RIDGE');

    state.dispose();
  });
}
