import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_edge_ai/flutter_edge_ai.dart' show PreferredBackend;
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/demos.dart';
import 'package:litert_hackathon/data/repositories/model_repository.dart';
import 'package:litert_hackathon/data/services/detector/detector_service.dart';
import 'package:litert_hackathon/data/services/knowledge/embedder_service.dart';
import 'package:litert_hackathon/ui/features/home/view_models/home_view_model.dart';

import '../../../../fakes/fake_bundled_files.dart';
import '../../../../fakes/fake_detector_runtime.dart';
import '../../../../fakes/fake_llm_service.dart';
import '../../../../fakes/fake_model_files.dart';
import '../../../../fakes/fake_speech.dart';

void main() {
  late FakeLlmService llm;

  ({ModelRepository models, HomeViewModel home}) build({
    String detectorModelPath = '',
  }) {
    final models = ModelRepository(
      gemmaModelPath: kTestChatModelPath,
      bundled: FakeBundledFiles(),
      detector: fakeDetectorService(),
      bundledDetector: fakeBundledDetector,
      llm: llm,
      stt: fakeSttService(),
      tts: fakeTtsService(),
      detectorModelPath: detectorModelPath,
      embedder: EmbedderService(),
    );
    final home = HomeViewModel(models: models.states);
    addTearDown(() async {
      home.dispose();
      await models.close();
    });
    return (models: models, home: home);
  }

  DemoTile tileOf(HomeViewModel home, Demo demo) =>
      home.tiles.singleWhere((t) => t.demo == demo);

  setUp(() => llm = FakeLlmService());

  test('before setup both tiles wait for Gemma', () {
    final (:models, :home) = build();

    for (final demo in Demo.values) {
      expect(tileOf(home, demo).available, isFalse);
      expect(tileOf(home, demo).status, 'The chat model is still loading');
    }
    expect(
      tileOf(home, Demo.voiceChat).subtitle,
      'Demo 1 · talk or type to the chat model',
    );
  });

  test('after setup without DETECTOR_MODEL_PATH both demos are ready: the '
      'detector is built in', () async {
    final (:models, :home) = build();
    var notified = 0;
    home.addListener(() => notified++);

    await models.prepareAll();

    expect(notified, greaterThan(0));
    final chat = tileOf(home, Demo.voiceChat);
    expect(chat.available, isTrue);
    expect(chat.status, 'Ready');
    expect(chat.subtitle, 'Demo 1 · talk or type to Gemma 4 E2B on the GPU');
    final camera = tileOf(home, Demo.liveCamera);
    expect(camera.available, isTrue);
    expect(camera.status, 'Ready');
  });

  test(
    'a detector file that cannot load disables Demo 3 with the reason',
    () async {
      final (:models, :home) = build(detectorModelPath: '/m/yolo26n.tflite');

      await models.prepareAll();

      final camera = tileOf(home, Demo.liveCamera);
      expect(camera.available, isFalse);
      expect(camera.status, startsWith('YOLO26n detector: '));
      expect(camera.status, contains('not found'));
    },
  );

  group('with a loadable detector', () {
    late Directory dir;
    late String modelPath;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('home_view_model_test');
      modelPath = '${dir.path}/yolo26n.tflite';
      File(modelPath).writeAsBytesSync(Uint8List(64));
    });

    tearDown(() => dir.deleteSync(recursive: true));

    ({ModelRepository models, HomeViewModel home}) withDetector(
      String backend,
      FakeDetectorRuntime runtime,
    ) {
      final models = ModelRepository(
        gemmaModelPath: kTestChatModelPath,
        bundled: FakeBundledFiles(),
        bundledDetector: fakeBundledDetector,
        llm: llm,
        stt: fakeSttService(),
        tts: fakeTtsService(),
        detector: DetectorService(runtime: runtime, expectedModelBytes: 64),
        detectorModelPath: modelPath,
        detectorBackend: backend,
        embedder: EmbedderService(),
      );
      final home = HomeViewModel(models: models.states);
      addTearDown(() async {
        home.dispose();
        await models.close();
      });
      return (models: models, home: home);
    }

    test('on the GPU, Demo 3 is enabled and Ready', () async {
      final (:models, :home) = withDetector('gpu', const FakeDetectorRuntime());

      await models.prepareAll();

      final camera = tileOf(home, Demo.liveCamera);
      expect(camera.available, isTrue);
      expect(camera.status, 'Ready');
      expect(camera.warning, isFalse);
    });

    test('on the chosen CPU, Demo 3 is enabled with an amber CPU (chosen) '
        'status', () async {
      final (:models, :home) = withDetector(
        'cpu',
        const FakeDetectorRuntime(fullyAccelerated: false),
      );

      await models.prepareAll();

      final camera = tileOf(home, Demo.liveCamera);
      expect(camera.available, isTrue);
      expect(camera.status, 'Ready · YOLO26n detector on CPU (chosen)');
      expect(camera.warning, isTrue);
      expect(tileOf(home, Demo.voiceChat).warning, isFalse);
    });

    test('a failed GPU load leaves Demo 3 open (amber) so its screen can '
        'offer the CPU', () async {
      final (:models, :home) = withDetector(
        'gpu',
        const FakeDetectorRuntime(fullyAccelerated: false),
      );

      await models.prepareAll();

      final camera = tileOf(home, Demo.liveCamera);
      expect(camera.available, isTrue);
      expect(camera.warning, isTrue);
      expect(
        camera.status,
        startsWith(
          'The detector failed on the GPU: open Demo 3 to run it on '
          'the CPU',
        ),
      );
      expect(camera.status, contains('only partly on the GPU'));
    });

    test('a failed CPU load offers the GPU back', () async {
      final (:models, :home) = withDetector(
        'cpu',
        const FakeDetectorRuntime(createError: 'no XNNPACK'),
      );

      await models.prepareAll();

      final camera = tileOf(home, Demo.liveCamera);
      expect(camera.available, isTrue);
      expect(
        camera.status,
        startsWith(
          'The detector failed on the CPU: open Demo 3 to run it on the GPU',
        ),
      );
    });
  });

  test('a Gemma failure disables both tiles with its reason', () async {
    llm.activeBackend = PreferredBackend.cpu;
    final (:models, :home) = build();

    await models.prepareAll();

    for (final demo in Demo.values) {
      final tile = tileOf(home, demo);
      expect(tile.available, isFalse);
      expect(tile.status, startsWith('The chat model: Gemma 4 E2B: '));
      expect(tile.status, contains('Fallback is disabled'));
    }
  });
}
