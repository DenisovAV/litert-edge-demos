import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart' show PreferredBackend;
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/model_catalog.dart';
import 'package:litert_hackathon/data/repositories/model_repository.dart';
import 'package:litert_hackathon/data/services/knowledge/embedder_service.dart';
import 'package:litert_hackathon/data/services/model_store/bundled_model_files.dart';
import 'package:litert_hackathon/domain/models/model_id.dart';
import 'package:litert_hackathon/domain/models/model_state.dart';
import 'package:litert_hackathon/utils/result.dart';

import '../../fakes/fake_bundled_files.dart';
import '../../fakes/fake_detector_runtime.dart';
import '../../fakes/fake_knowledge.dart';
import '../../fakes/fake_llm_service.dart';
import '../../fakes/fake_model_files.dart';
import '../../fakes/fake_speech.dart';

/// EmbeddingGemma is an optional model. Whatever happens to it is its
/// row's; setup succeeds without it.
void main() {
  late Directory bundleDir;
  late Map<String, String> bundledPaths;

  setUp(() {
    bundleDir = Directory.systemTemp.createTempSync('bundled_embedder');
    bundledPaths = {
      kBundledEmbedderModel.asset: (File(
        '${bundleDir.path}/${kBundledEmbedderModel.name}',
      )..writeAsBytesSync([1])).path,
      kBundledEmbedderTokenizer.asset: (File(
        '${bundleDir.path}/${kBundledEmbedderTokenizer.name}',
      )..writeAsBytesSync([1])).path,
    };
  });

  tearDown(() => bundleDir.deleteSync(recursive: true));

  ModelRepository build({
    EmbedderService? embedder,
    String modelDir = '',
    bool bundled = true,
  }) {
    final models = ModelRepository(
      gemmaModelPath: kTestChatModelPath,
      bundled: bundled ? FakeBundledFiles.at(bundledPaths) : FakeBundledFiles(),
      detector: fakeDetectorService(),
      bundledDetector: fakeBundledDetector,
      llm: FakeLlmService(),
      stt: fakeSttService(),
      tts: fakeTtsService(),
      embedder: embedder ?? EmbedderService(),
      embeddingModelDir: modelDir,
    );
    addTearDown(models.close);
    return models;
  }

  EmbedderService fakeEmbedder(FakeEmbeddingModel model) => EmbedderService(
    install: (config, source, onProgress) async {
      onProgress(40);
      onProgress(100);
      return 'embeddinggemma-300M_seq512_mixed-precision';
    },
    load: (config) async => model,
  );

  test('without EMBEDDING_MODEL_DIR the built-in files are installed (no '
      'download, no token)', () async {
    final sources = <EmbedderSource>[];
    final models = build(
      embedder: EmbedderService(
        install: (config, source, onProgress) async {
          sources.add(source);
          return 'eg';
        },
        load: (config) async => FakeEmbeddingModel(),
      ),
    );

    expect(await models.prepareAll(), isA<Ok<void>>());

    expect(
      sources.single,
      isA<EmbedderFromFiles>()
          .having(
            (s) => s.modelPath,
            'model',
            bundledPaths[kBundledEmbedderModel.asset],
          )
          .having(
            (s) => s.tokenizerPath,
            'tokenizer',
            bundledPaths[kBundledEmbedderTokenizer.asset],
          ),
    );
    expect(models.states.value[ModelId.embeddingGemma], isA<ModelReady>());
  });

  test('a built-in file that cannot be found fails the row with the reason; '
      'setup succeeds', () async {
    final models = build(bundled: false);

    expect(await models.prepareAll(), isA<Ok<void>>());

    expect(models.requiredReady, isTrue);
    final state = models.states.value[ModelId.embeddingGemma];
    expect(state, isA<ModelFailed>());
    expect(
      (state! as ModelFailed).message,
      contains('The built-in EmbeddingGemma: No app bundle in tests'),
    );
  });

  test('a directory without the files is unavailable, not a failure', () async {
    final dir = Directory.systemTemp.createTempSync('model_repo_embedder');
    addTearDown(() => dir.deleteSync(recursive: true));
    final models = build(modelDir: dir.path);

    expect(await models.prepareAll(), isA<Ok<void>>());

    final state = models.states.value[ModelId.embeddingGemma];
    expect(state, isA<ModelUnavailable>());
    expect((state! as ModelUnavailable).reason, contains(kEmbedderModelFile));
  });

  test('installs, loads on the CPU and warms up: ready with its backend and '
      'dimension', () async {
    final model = FakeEmbeddingModel();
    final models = build(embedder: fakeEmbedder(model));
    // The embedder's own transitions (the listener fires for every model).
    final seen = <ModelState>[];
    models.states.addListener(() {
      final state = models.states.value[ModelId.embeddingGemma]!;
      if (state is ModelPending) return;
      if (seen.isEmpty || !identical(seen.last, state)) seen.add(state);
    });

    expect(await models.prepareAll(), isA<Ok<void>>());

    expect(seen.map((s) => s.runtimeType).toSet(), {
      ModelInstalling,
      ModelLoading,
      ModelWarmingUp,
      ModelReady,
    });
    expect(seen.whereType<ModelInstalling>().map((s) => s.percent), [
      null,
      40,
      100,
    ]);
    final info =
        (models.states.value[ModelId.embeddingGemma]! as ModelReady).info;
    expect(info.modelId, 'embeddinggemma-300M_seq512_mixed-precision');
    expect(info.backend, 'cpu');
    expect(info.detail, 'CPU · 768-d');
    expect(model.queries, hasLength(1), reason: 'one warm-up embedding');
  });

  test(
    'a wrong backend fails the row only; Demo 1 still has its models',
    () async {
      final model = FakeEmbeddingModel(backend: PreferredBackend.gpu);
      final models = build(embedder: fakeEmbedder(model));

      expect(await models.prepareAll(), isA<Ok<void>>());

      expect(models.requiredReady, isTrue);
      final state = models.states.value[ModelId.embeddingGemma];
      expect(state, isA<ModelFailed>());
      expect((state! as ModelFailed).message, contains('reports gpu'));
      expect(model.closeCalls, 1);
    },
  );

  test('a rejected warm-up fails the row and releases the model', () async {
    final model = FakeEmbeddingModel(zeroVectors: true);
    final embedder = fakeEmbedder(model);
    final models = build(embedder: embedder);

    expect(await models.prepareAll(), isA<Ok<void>>());

    final state = models.states.value[ModelId.embeddingGemma];
    expect(state, isA<ModelFailed>());
    expect((state! as ModelFailed).message, contains('all-zero'));
    expect(model.closeCalls, 1);
    expect(embedder.isLoaded, isFalse);
  });

  test('close() closes the embedder', () async {
    final model = FakeEmbeddingModel();
    final models = ModelRepository(
      gemmaModelPath: kTestChatModelPath,
      bundled: FakeBundledFiles.at(bundledPaths),
      detector: fakeDetectorService(),
      bundledDetector: fakeBundledDetector,
      llm: FakeLlmService(),
      stt: fakeSttService(),
      tts: fakeTtsService(),
      embedder: fakeEmbedder(model),
    );
    await models.prepareAll();

    await models.close();

    expect(model.closeCalls, 1);
  });
}
