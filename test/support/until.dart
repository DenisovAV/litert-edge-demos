import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Completes once [condition] holds: checked now and on every notification
/// of [listenable], so no state is missed between polls and nothing waits
/// longer than the change takes. Fails with [what] after [timeout] of real
/// time, well inside the test's own timeout, so a regression says what it
/// was waiting for instead of hanging.
Future<void> untilNotified(
  Listenable listenable,
  bool Function() condition, {
  required String what,
  Duration timeout = const Duration(seconds: 10),
}) {
  if (condition()) return Future.value();
  final done = Completer<void>();
  void check() {
    if (!done.isCompleted && condition()) done.complete();
  }

  listenable.addListener(check);
  final timer = Timer(timeout, () {
    if (done.isCompleted) return;
    done.completeError(TestFailure('Timed out after $timeout: $what'));
  });
  return done.future.whenComplete(() {
    timer.cancel();
    listenable.removeListener(check);
  });
}
