import 'package:litert_hackathon/domain/models/self_test.dart';
import 'package:litert_hackathon/domain/ports/self_test_launcher.dart';
import 'package:litert_hackathon/utils/result.dart';

/// [SelfTestLauncher] for screens that show the "Run self-test" card: a run
/// reports one progress line and [outcome] (by default, that it cannot run
/// in a widget test).
final class FakeSelfTestLauncher implements SelfTestLauncher {
  FakeSelfTestLauncher([Result<SelfTestOutcome>? outcome])
    : outcome =
          outcome ?? Result.error(Exception('no self-test in a widget test'));

  final Result<SelfTestOutcome> outcome;
  int runs = 0;

  /// After a run, the launcher's answer to [SelfTestLauncher.stuck].
  bool stuckAfterRun = false;

  @override
  bool stuck = false;

  @override
  Future<Result<SelfTestOutcome>> run({
    required void Function(String line) progress,
  }) async {
    runs++;
    progress('step 1 hardware probe …');
    stuck = stuckAfterRun;
    return outcome;
  }
}
