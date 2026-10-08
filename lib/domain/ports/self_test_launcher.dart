// A port: an interface that the domain and the view models depend on and an
// outer layer implements. Every port lives in lib/domain/ports/;
// function-typed dependencies stay next to their one consumer.

import '../../utils/result.dart';
import '../models/self_test.dart';

/// What the Models screen's "Run self-test" runs (`InAppSelfTest`; tests
/// use a fake).
abstract interface class SelfTestLauncher {
  /// A run passed its time limit and never ended (`kSelfTestStillRunning`):
  /// no other run may start, nor the chat model load, until the app
  /// restarts.
  bool get stuck;

  Future<Result<SelfTestOutcome>> run({
    required void Function(String line) progress,
  });
}
