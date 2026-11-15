import 'package:flutter/widgets.dart';

import 'ares_state.dart';

class AresScope extends InheritedNotifier<AresState> {
  const AresScope({super.key, required AresState state, required super.child})
    : super(notifier: state);

  static AresState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AresScope>();
    assert(scope != null, 'AresScope is missing above this widget.');
    return scope!.notifier!;
  }

  static AresState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AresScope>();
    assert(scope != null, 'AresScope is missing above this widget.');
    return scope!.notifier!;
  }
}
