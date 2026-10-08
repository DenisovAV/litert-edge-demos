/// One finished in-app self-test.
final class const SelfTestOutcome({
  /// The delimited SELFTEST block, as `--selftest` prints it.
  required final String text,
  required final bool passed,

  /// Where the block was written; null when it could not be.
  final String? reportPath,

  /// The run passed its time limit and had still not ended after the stop
  /// grace (`kSelfTestStopGrace`): no other run starts until the app
  /// restarts.
  final bool stillRunning = false,

  /// With [stillRunning]: the run's own chat model engine may still be
  /// loaded (`SelfTestRunner.chatEngineMayBeLoaded`), so the app's is not
  /// loaded again (one engine per process). False when it hung before its
  /// chat model load or after closing it: the app's chat model loads again
  /// as usual.
  final bool chatEngineMayBeLoaded = true,
});
