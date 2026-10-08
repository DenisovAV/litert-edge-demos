import '../../config/dev_overrides.dart';
import '../../config/model_catalog.dart';
import 'chat_model.dart';
import 'chat_model_config.dart';
import 'model_id.dart';

/// Where the chat model slot's file comes from
/// (docs/design/custom-chat-model.md).
sealed class const ChatModelSource();

/// The tester's own `.litertlm`, chosen in the Chat model card: it wins over
/// `GEMMA_MODEL_PATH`.
final class const CustomChatSource(final CustomChatPlan plan)
    extends ChatModelSource;

/// `GEMMA_MODEL_PATH` (a developer define) while no model is chosen, run with
/// [config] (Gemma 4 E2B's settings). Its value is an absolute path or one
/// relative to the documents directory.
final class const DefineChatSource({
  required final DevOverride define,
  required final ChatModelConfig config,
}) extends ChatModelSource;

/// The chosen model cannot load ([reason]); never replaced by another one.
final class const BlockedChatSource(final String reason)
    extends ChatModelSource;

/// No model chosen and no define: the slot stays empty ([note]: why, after a
/// retired saved choice).
final class const NoChatSource({final String? note}) extends ChatModelSource;

/// Where a model built into the app takes its files from
/// (docs/design/distribution.md D5).
sealed class const ModelFileSource();

/// A developer define names the file or directory, and wins. Its value is an
/// absolute path or one relative to the documents directory.
final class const DefineFileSource(final DevOverride define)
    extends ModelFileSource;

/// The files built into the app.
final class const BuiltInFileSource() extends ModelFileSource;

/// The precedence rule for every model's source. `ModelRepository` loads by
/// it and the self-test resolves by it, so the self-test loads exactly what
/// the app would. Pure: paths are not resolved or checked here.
///
/// The chat model: the model chosen in the Chat model card (or its blocked
/// choice); with none chosen, `GEMMA_MODEL_PATH` when set, else nothing. The
/// detector and the embedder: their define when set, else the files built
/// into the app. The speech models have no define: always built in.
final class const ModelSourceResolver({
  /// The developer defines; the build's own by default.
  final DevModelOverrides defines = DevModelOverrides.environment,

  /// What `GEMMA_MODEL_PATH` loads with.
  final ChatModelConfig defineChatModel = kDefineChatModel,
}) {
  ChatModelSource chat(ChatModelPlan plan) => switch (plan) {
    CustomChatPlan() => CustomChatSource(plan),
    ChatPlanBlocked(:final reason) => BlockedChatSource(reason),
    NoChatModelPlan(:final note) => switch (defines.forModel(ModelId.chat)) {
      final define? => DefineChatSource(
        define: define,
        config: defineChatModel,
      ),
      null => NoChatSource(note: note),
    },
  };

  /// YOLO26n: `DETECTOR_MODEL_PATH`, else the asset built into the app.
  ModelFileSource detector() => files(ModelId.yolo26n);

  /// EmbeddingGemma: `EMBEDDING_MODEL_DIR`, else the files built into the
  /// app.
  ModelFileSource embedder() => files(ModelId.embeddingGemma);

  /// Any model built into the app (every one but the chat model, which
  /// [chat] resolves): its define when it has one and it is set, else the
  /// files built into the app.
  ModelFileSource files(ModelId id) {
    if (id == ModelId.chat) {
      throw ArgumentError.value(
        id,
        'id',
        'The chat model is not built into the app; resolve it with chat()',
      );
    }
    return switch (defines.forModel(id)) {
      final define? => DefineFileSource(define),
      null => const BuiltInFileSource(),
    };
  }
}
