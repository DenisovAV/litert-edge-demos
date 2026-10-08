import '../../utils/result.dart';
import 'detection.dart';

/// Who decided where the detector runs.
enum DetectorChoiceSource {
  /// `--dart-define=DETECTOR_BACKEND=…`: wins over the setting, which Demo 3
  /// then shows locked.
  define,

  /// Demo 3's Detector setting.
  setting,

  /// Nothing chosen: the platform's standard backend (the GPU; the CPU on
  /// iOS, see `standardDetectorBackend`).
  standard,
}

/// The backend the next detector load uses, and why.
final class const DetectorBackendChoice({
  required final DetectorBackend backend,
  required final DetectorChoiceSource source,
});

/// `DETECTOR_BACKEND` is set to something other than `gpu` or `cpu`: a build
/// mistake no setting can fix.
final class InvalidDetectorBackendDefineException implements Exception {
  const InvalidDetectorBackendDefineException(this.value);

  final String value;

  @override
  String toString() => 'DETECTOR_BACKEND must be gpu or cpu, got "$value"';
}

/// The saved Detector setting is unreadable or not `gpu`/`cpu`.
final class InvalidDetectorSettingException implements Exception {
  const InvalidDetectorSettingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The precedence rule: a non-empty [define] wins, then the [saved] setting
/// (`gpu` / `cpu`), then [standard]. Never guesses: a bad define or a bad
/// saved value is an error.
Result<DetectorBackendChoice> resolveDetectorBackend({
  required String define,
  String? saved,
  DetectorBackend standard = DetectorBackend.gpu,
}) {
  if (define.trim().isNotEmpty) {
    return switch (DetectorBackend.tryParse(define)) {
      final backend? => Result.ok(
        DetectorBackendChoice(
          backend: backend,
          source: DetectorChoiceSource.define,
        ),
      ),
      null => Result.error(InvalidDetectorBackendDefineException(define)),
    };
  }
  if (saved != null) {
    return switch (DetectorBackend.tryParse(saved)) {
      final backend? => Result.ok(
        DetectorBackendChoice(
          backend: backend,
          source: DetectorChoiceSource.setting,
        ),
      ),
      null => Result.error(
        InvalidDetectorSettingException(
          'The saved detector setting "$saved" is not gpu or cpu: choose GPU '
          "or CPU in Demo 3's settings",
        ),
      ),
    };
  }
  return Result.ok(
    DetectorBackendChoice(
      backend: standard,
      source: DetectorChoiceSource.standard,
    ),
  );
}
