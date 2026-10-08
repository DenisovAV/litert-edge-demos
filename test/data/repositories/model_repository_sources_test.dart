import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/model_catalog.dart';
import 'package:litert_hackathon/data/repositories/model_repository.dart';
import 'package:litert_hackathon/data/services/knowledge/embedder_service.dart';
import 'package:litert_hackathon/data/services/model_store/bundled_model_files.dart';
import 'package:litert_hackathon/data/services/speech/stt_service.dart';
import 'package:litert_hackathon/domain/models/detector_spec.dart';
import 'package:litert_hackathon/domain/models/model_id.dart';
import 'package:litert_hackathon/domain/models/model_state.dart';
import 'package:litert_hackathon/utils/result.dart';

import '../../fakes/fake_bundled_files.dart';
import '../../fakes/fake_detector_runtime.dart';
import '../../fakes/fake_knowledge.dart';
import '../../fakes/fake_llm_service.dart';
import '../../fakes/fake_model_files.dart';
import '../../fakes/fake_speech.dart';

/// Where each model's files come from. A developer define wins
/// (docs/design/distribution.md D5); otherwise every model but the chat
/// model is built into the app; the chat model is the one chosen, or none.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('model_sources'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('the chat model (the app ships none)', () {
    test(
      'GEMMA_MODEL_PATH with no model chosen loads (a developer define)',
      () async {
        final llm = FakeLlmService();
        final models = ModelRepository(
          bundled: FakeBundledFiles(),
          detector: fakeDetectorService(),
          bundledDetector: fakeBundledDetector,
          gemmaModelPath: '/dev/gemma.litertlm',
          llm: llm,
          stt: fakeSttService(),
          tts: fakeTtsService(),
          embedder: EmbedderService(),
        );
        addTearDown(models.close);

        expect(await models.prepareAll(), isA<Ok<void>>());
        expect(llm.installs, ['/dev/gemma.litertlm']);
      },
    );

    test(
      'neither a chosen model nor the define: the slot is unavailable with '
      'how to choose one; setup fails, everything else still loads',
      () async {
        final llm = FakeLlmService();
        final models = ModelRepository(
          bundled: FakeBundledFiles(),
          detector: fakeDetectorService(),
          bundledDetector: fakeBundledDetector,
          gemmaModelPath: '',
          llm: llm,
          stt: fakeSttService(),
          tts: fakeTtsService(),
          embedder: EmbedderService(),
        );
        addTearDown(models.close);

        expect(await models.prepareAll(), isA<Error<void>>());
        expect(llm.installs, isEmpty);
        expect(
          models.states.value[ModelId.chat],
          isA<ModelUnavailable>().having(
            (s) => s.reason,
            'reason',
            startsWith('No chat model yet: choose a .litertlm'),
          ),
        );
        expect(models.states.value[ModelId.whisperBase], isA<ModelReady>());
        expect(models.states.value[ModelId.inflectNano], isA<ModelReady>());
      },
    );
  });

  group('speech models (built in)', () {
    test('by default from the files built into the app: each recognizer\'s '
        'model and tokenizer, the TTS bundle by its directory', () async {
      final sources = <SttSource>[];
      final directories = <String>[];
      final models = ModelRepository(
        bundled: FakeBundledFiles(),
        detector: fakeDetectorService(),
        bundledDetector: fakeBundledDetector,
        gemmaModelPath: kTestChatModelPath,
        llm: FakeLlmService(),
        stt: fakeSttService(sources: sources),
        tts: fakeTtsService(directories: directories),
        embedder: EmbedderService(),
      );
      addTearDown(models.close);

      expect(await models.prepareAll(), isA<Ok<void>>());
      final files = sources.whereType<SttFromFiles>().toList();
      expect(files.map((s) => s.modelPath), [
        '/bundled/${kBundledWhisperModel.name}',
        '/bundled/${kBundledMoonshineModel.name}',
      ]);
      expect(files.first.tokenizerPath, '/bundled/whisper_base_tokenizer.json');
      expect(directories, ['/bundled']);
    });

    test('a built-in file that cannot be found or extracted (a full disk): '
        'Whisper or Inflect fail setup with the reason; moonshine fails its '
        'row with Retry (not "unavailable")', () async {
      ModelRepository build(Set<String> failing) {
        final models = ModelRepository(
          bundled: FakeBundledFiles(failing: failing),
          detector: fakeDetectorService(),
          bundledDetector: fakeBundledDetector,
          gemmaModelPath: kTestChatModelPath,
          llm: FakeLlmService(),
          stt: fakeSttService(),
          tts: fakeTtsService(),
          embedder: EmbedderService(),
        );
        addTearDown(models.close);
        return models;
      }

      final whisperless = build({kBundledWhisperModel.asset});
      expect(await whisperless.prepareAll(), isA<Error<void>>());
      expect(
        whisperless.states.value[ModelId.whisperBase],
        isA<ModelFailed>().having(
          (s) => s.message,
          'message',
          contains('The built-in Whisper base (STT)'),
        ),
      );

      final voiceless = build({kBundledInflectFiles.last.asset});
      expect(await voiceless.prepareAll(), isA<Error<void>>());
      expect(
        voiceless.states.value[ModelId.inflectNano],
        isA<ModelFailed>().having(
          (s) => s.message,
          'message',
          contains('The built-in Inflect-nano-v2 (TTS)'),
        ),
      );

      final moonshineless = build({kBundledMoonshineTokenizer.asset});
      expect(await moonshineless.prepareAll(), isA<Ok<void>>());
      expect(
        moonshineless.states.value[ModelId.moonshineTiny],
        isA<ModelFailed>().having(
          (s) => s.message,
          'message',
          contains('The built-in moonshine-tiny (STT, Demo 3)'),
        ),
      );
    });
  });

  group('detector (built in, docs/design/distribution.md)', () {
    late String devPath;
    late List<String> bundledReads;

    setUp(() {
      devPath = '${dir.path}/dev_yolo.tflite';
      File(devPath).writeAsBytesSync(Uint8List(kFakeBundledDetectorBytes));
      bundledReads = [];
    });

    ModelRepository build({
      required String define,
      Future<Uint8List> Function()? bundled,
    }) {
      final models = ModelRepository(
        bundled: FakeBundledFiles(),
        gemmaModelPath: kTestChatModelPath,
        llm: FakeLlmService(),
        stt: fakeSttService(),
        tts: fakeTtsService(),
        detector: fakeDetectorService(),
        bundledDetector:
            bundled ??
            () async {
              bundledReads.add('asset');
              return fakeBundledDetector();
            },
        detectorModelPath: define,
        embedder: EmbedderService(),
      );
      addTearDown(models.close);
      return models;
    }

    test('DETECTOR_MODEL_PATH wins over the built-in asset', () async {
      final models = build(define: devPath);

      expect(await models.prepareAll(), isA<Ok<void>>());
      expect(models.states.value[ModelId.yolo26n], isA<ModelReady>());
      expect(bundledReads, isEmpty, reason: 'the asset is not even read');
    });

    test('without the define the built-in asset loads', () async {
      final models = build(define: '');

      expect(await models.prepareAll(), isA<Ok<void>>());
      expect(bundledReads, ['asset']);
      expect(models.states.value[ModelId.yolo26n], isA<ModelReady>());
    });

    test('an asset that cannot be read fails the row with the reason; setup '
        'still succeeds (the detector is optional)', () async {
      final models = build(
        define: '',
        bundled: () async => throw StateError('asset missing'),
      );

      expect(await models.prepareAll(), isA<Ok<void>>());
      final state = models.states.value[ModelId.yolo26n];
      expect(state, isA<ModelFailed>());
      final message = (state! as ModelFailed).message;
      expect(message, contains(kDetModelAsset));
      expect(message, contains('asset missing'));
    });

    test('a wrong-size asset is rejected by the size check', () async {
      final models = build(define: '', bundled: () async => Uint8List(10));

      expect(await models.prepareAll(), isA<Ok<void>>());
      final state = models.states.value[ModelId.yolo26n];
      expect(state, isA<ModelFailed>());
      expect((state! as ModelFailed).message, contains('10'));
    });
  });

  group('embedder (built in, docs/design/distribution.md)', () {
    ({ModelRepository models, List<EmbedderSource> sources}) build({
      String define = '',
      BundledModelFiles? bundled,
    }) {
      final sources = <EmbedderSource>[];
      final models = ModelRepository(
        bundled:
            bundled ??
            FakeBundledFiles.at({
              kBundledEmbedderModel.asset: '${dir.path}/m.tflite',
              kBundledEmbedderTokenizer.asset: '${dir.path}/t.model',
            }),
        detector: fakeDetectorService(),
        bundledDetector: fakeBundledDetector,
        gemmaModelPath: kTestChatModelPath,
        llm: FakeLlmService(),
        stt: fakeSttService(),
        tts: fakeTtsService(),
        embedder: EmbedderService(
          install: (config, source, onProgress) async {
            sources.add(source);
            return 'embeddinggemma-300M_seq512_mixed-precision';
          },
          load: (config) async => FakeEmbeddingModel(),
        ),
        embeddingModelDir: define,
      );
      addTearDown(models.close);
      return (models: models, sources: sources);
    }

    setUp(() {
      File('${dir.path}/m.tflite').writeAsBytesSync([1]);
      File('${dir.path}/t.model').writeAsBytesSync([1]);
    });

    test('EMBEDDING_MODEL_DIR wins over the built-in files', () async {
      File('${dir.path}/$kEmbedderModelFile').writeAsBytesSync(Uint8List(4));
      File('${dir.path}/sentencepiece.model').writeAsBytesSync(Uint8List(4));
      final bundled = FakeBundledFiles.at(const {});
      final (:models, :sources) = build(define: dir.path, bundled: bundled);

      await models.prepareAll();

      expect(
        sources.single,
        isA<EmbedderFromDirectory>().having((s) => s.dir, 'dir', dir.path),
      );
      expect(
        bundled.requested,
        isNot(contains(kBundledEmbedderModel.asset)),
        reason: 'the embedder bundle is not asked',
      );
    });

    test(
      'without the define the built-in files are installed in place',
      () async {
        final (:models, :sources) = build();

        await models.prepareAll();

        expect(
          sources.single,
          isA<EmbedderFromFiles>()
              .having((s) => s.modelPath, 'model', '${dir.path}/m.tflite')
              .having(
                (s) => s.tokenizerPath,
                'tokenizer',
                '${dir.path}/t.model',
              ),
        );
        expect(models.states.value[ModelId.embeddingGemma], isA<ModelReady>());
      },
    );

    test(
      'a broken bundle fails the row with the reason; setup succeeds',
      () async {
        final (:models, :sources) = build(
          bundled: FakeBundledFiles(
            error: const BundledFileException('sentencepiece.model is missing'),
          ),
        );

        expect(await models.prepareAll(), isA<Ok<void>>());

        expect(sources, isEmpty);
        final state = models.states.value[ModelId.embeddingGemma];
        expect(state, isA<ModelFailed>());
        expect(
          (state! as ModelFailed).message,
          contains('sentencepiece.model is missing'),
        );
      },
    );
  });
}
