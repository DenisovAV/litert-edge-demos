import 'dart:async';

import 'package:flutter/foundation.dart';

/// Every test: an Error a `Command` caught (a programmer bug, reported with
/// `library: 'command'`) fails the test it happened in, as it did when it
/// escaped the command. A plain `test` would only print it; `testWidgets`
/// installs its own handler for its body (`tester.takeException` reads it).
/// Other reports keep the default handler.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library == 'command') {
      Zone.current.handleUncaughtError(
        details.exception,
        details.stack ?? StackTrace.current,
      );
      return;
    }
    previous?.call(details);
  };
  await testMain();
}
