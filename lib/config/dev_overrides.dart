import '../domain/models/model_id.dart';
import 'env.dart';

/// A developer `--dart-define` that supplies a model instead of the app's
/// own: [define] is its name, [value] the path it was given.
final class const DevOverride(final String define, final String value);

/// The model dart-defines of a developer build (docs/design/distribution.md
/// D5). When one is set it wins over the built-in model (for
/// `GEMMA_MODEL_PATH`: fills the chat slot while none is chosen), so the dev
/// loop and the integration tests that pass them keep their local files.
/// Tester builds set none of them.
final class const DevModelOverrides({
  final String gemmaModelPath = '',
  final String embeddingModelDir = '',
  final String detectorModelPath = '',
}) {
  /// The values this build was compiled with.
  static const environment = DevModelOverrides(
    gemmaModelPath: kGemmaModelPath,
    embeddingModelDir: kEmbeddingModelDir,
    detectorModelPath: kDetectorModelPath,
  );

  /// The define that supplies [id]; null when none is set.
  DevOverride? forModel(ModelId id) => switch (id) {
    ModelId.chat when gemmaModelPath.isNotEmpty => DevOverride(
      'GEMMA_MODEL_PATH',
      gemmaModelPath,
    ),
    ModelId.embeddingGemma when embeddingModelDir.isNotEmpty => DevOverride(
      'EMBEDDING_MODEL_DIR',
      embeddingModelDir,
    ),
    ModelId.yolo26n when detectorModelPath.isNotEmpty => DevOverride(
      'DETECTOR_MODEL_PATH',
      detectorModelPath,
    ),
    _ => null,
  };
}
