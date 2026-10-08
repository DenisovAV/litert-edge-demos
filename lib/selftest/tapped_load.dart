import '../data/services/hardware/native_log_tap.dart';
import '../domain/hardware/accelerator_inference.dart';
import '../domain/hardware/native_log_parser.dart';
import '../domain/models/accelerator_evidence.dart';
import '../domain/models/hardware_profile.dart';
import '../utils/result.dart';

/// Runs [load] with [tap] marked before it: its result and what the native
/// runtime printed meanwhile (steps 2, 2b and 4a).
Future<TappedLoad<T>> loadWithNativeLog<T>(
  NativeLogTap tap,
  Future<Result<T>> Function() load,
) async {
  final mark = tap.mark();
  final result = await load();
  final raw = tap.since(mark);
  return TappedLoad._(result, raw, parseNativeLog(raw));
}

/// A model load and the native log lines it printed.
final class TappedLoad<T> {
  TappedLoad._(this.result, this._raw, this._log);

  final Result<T> result;

  /// Every native line printed during the load.
  final List<String> _raw;

  /// What [_raw] says about the accelerator.
  final NativeLogEvidence _log;

  /// Where the model runs: [requested] and what the runtime [reported],
  /// read together with the native log and the probed [hardware].
  AcceleratorEvidence evidence({
    required String requested,
    required String reported,
    required HardwareProfile? hardware,
  }) => inferEvidence(
    requested: requested,
    reported: reported,
    hardware: hardware,
    log: _log,
  );

  /// A failed load's details: [error] (there is no fallback), the evidence
  /// lines, then the native errors and warnings that explain it.
  List<String> failure(Object error) => [
    'load failed (no fallback): $error',
    ...logLines,
    for (final line in nativeProblemLines(_raw))
      if (!_log.lines.contains(line)) 'log: $line',
  ];

  /// `log: …` for each line the evidence came from.
  List<String> get logLines => [for (final line in _log.lines) 'log: $line'];
}
