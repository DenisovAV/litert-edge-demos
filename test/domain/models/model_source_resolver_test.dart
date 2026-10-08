import 'package:flutter_edge_ai/flutter_edge_ai.dart'
    show ModelType, PreferredBackend;
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/dev_overrides.dart';
import 'package:litert_hackathon/config/model_catalog.dart';
import 'package:litert_hackathon/domain/models/chat_model.dart';
import 'package:litert_hackathon/domain/models/chat_model_config.dart';
import 'package:litert_hackathon/domain/models/model_id.dart';
import 'package:litert_hackathon/domain/models/model_source_resolver.dart';

/// docs/design/distribution.md D5 and docs/design/custom-chat-model.md: one
/// precedence for every model, shared by the app and the self-test.
void main() {
  const allDefines = DevModelOverrides(
    gemmaModelPath: '/dev/gemma.litertlm',
    embeddingModelDir: '/dev/embedder',
    detectorModelPath: '/dev/yolo.tflite',
  );

  const custom = CustomChatPlan(
    path: '/store/custom/g3.litertlm',
    model: CustomChatModel(
      displayName: 'Gemma 3 1B NPU',
      source: ImportedModelSource('/picked/g3.litertlm'),
      backend: PreferredBackend.npu,
      maxTokens: 1280,
    ),
  );

  group('the chat model', () {
    test('the chosen model wins over GEMMA_MODEL_PATH', () {
      final source = const ModelSourceResolver(defines: allDefines)
          .chat(custom);

      expect(source, isA<CustomChatSource>());
      expect((source as CustomChatSource).plan, same(custom));
    });

    test('a blocked choice stays blocked, even with GEMMA_MODEL_PATH set', () {
      final source = const ModelSourceResolver(defines: allDefines)
          .chat(const ChatPlanBlocked('g3.litertlm is gone'));

      expect(
        source,
        isA<BlockedChatSource>().having(
          (s) => s.reason,
          'reason',
          'g3.litertlm is gone',
        ),
      );
    });

    test('none chosen: GEMMA_MODEL_PATH with Gemma 4 E2B\'s settings', () {
      final source = const ModelSourceResolver(defines: allDefines)
          .chat(const NoChatModelPlan(note: 'retired'));

      final define = source as DefineChatSource;
      expect(define.define.define, 'GEMMA_MODEL_PATH');
      expect(define.define.value, '/dev/gemma.litertlm');
      expect(define.config, same(kDefineChatModel));
    });

    test('the define\'s settings can be replaced', () {
      const config = ChatModelConfig(
        name: 'Gemma 4 E2B',
        modelType: ModelType.gemma4,
        llm: LlmConfig(
          maxTokens: 4096,
          backend: PreferredBackend.cpu,
          supportImage: false,
          maxNumImages: 1,
        ),
        tools: true,
      );

      final source = const ModelSourceResolver(
        defines: allDefines,
        defineChatModel: config,
      ).chat(const NoChatModelPlan());

      expect((source as DefineChatSource).config, same(config));
    });

    test('none chosen and no define: nothing, with the note', () {
      final source = const ModelSourceResolver(
        defines: DevModelOverrides(
          embeddingModelDir: '/dev/embedder',
          detectorModelPath: '/dev/yolo.tflite',
        ),
      ).chat(const NoChatModelPlan(note: 'Gemma 4 E2B is retired.'));

      expect(
        source,
        isA<NoChatSource>().having(
          (s) => s.note,
          'note',
          'Gemma 4 E2B is retired.',
        ),
      );
    });
  });

  group('the detector and the embedder', () {
    test('their define wins over the files built into the app', () {
      const sources = ModelSourceResolver(defines: allDefines);

      final detector = sources.detector() as DefineFileSource;
      expect(detector.define.define, 'DETECTOR_MODEL_PATH');
      expect(detector.define.value, '/dev/yolo.tflite');
      final embedder = sources.embedder() as DefineFileSource;
      expect(embedder.define.define, 'EMBEDDING_MODEL_DIR');
      expect(embedder.define.value, '/dev/embedder');
    });

    test('without it, the files built into the app; other defines do not '
        'count', () {
      const sources = ModelSourceResolver(
        defines: DevModelOverrides(gemmaModelPath: '/dev/gemma.litertlm'),
      );

      expect(sources.detector(), isA<BuiltInFileSource>());
      expect(sources.embedder(), isA<BuiltInFileSource>());
    });

    test('the speech models have no define: always built in; the chat model '
        'is not built in at all', () {
      const sources = ModelSourceResolver(defines: allDefines);

      for (final id in [
        ModelId.whisperBase,
        ModelId.moonshineTiny,
        ModelId.inflectNano,
      ]) {
        expect(sources.files(id), isA<BuiltInFileSource>(), reason: '$id');
      }
      expect(() => sources.files(ModelId.chat), throwsArgumentError);
    });
  });

  test('by default, the build\'s own defines (none in tests)', () {
    const sources = ModelSourceResolver();

    expect(sources.defines, same(DevModelOverrides.environment));
    expect(sources.chat(const NoChatModelPlan()), isA<NoChatSource>());
    expect(sources.detector(), isA<BuiltInFileSource>());
    expect(sources.embedder(), isA<BuiltInFileSource>());
  });
}
