import 'package:flutter/foundation.dart';

import '../models/live_state.dart';

/// Opens or closes the detector's gate (`LiveDetectionRepository.setDuty`);
/// [reason] says why it is paused.
typedef DetectorDutySetter = void Function(DetectorDuty duty, {String? reason});

/// App-scoped GPU policy (design demo3 §7, C8): while the chat model
/// generates, the detector gets `duringGeneration` (the app passes
/// `kDetectorDuringGeneration`, paused: no GPU priority knob exists, and
/// contention would slow the answer the user waits for).
final class GpuArbiter {
  GpuArbiter({
    required this._llmBusy,
    required this._setDetectorDuty,
    required this._duringGeneration,
    this._chatModelName,
  }) {
    _llmBusy.addListener(_sync);
    _sync();
  }

  final ValueListenable<bool> _llmBusy;
  final DetectorDutySetter _setDetectorDuty;

  /// The loaded chat model's display name, the pause reason; without it (or
  /// when it says null) the reason is "the chat model".
  final String? Function()? _chatModelName;
  final DetectorDuty _duringGeneration;
  bool _disposed = false;

  void _sync() {
    if (_disposed) return;
    if (_llmBusy.value) {
      _setDetectorDuty(
        _duringGeneration,
        reason: _chatModelName?.call() ?? 'the chat model',
      );
    } else {
      _setDetectorDuty(DetectorDuty.live);
    }
  }

  /// Stops reacting. Dispose before the conversation that owns [_llmBusy].
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _llmBusy.removeListener(_sync);
  }
}
