import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/demos.dart';
import 'package:litert_hackathon/data/repositories/model_repository.dart';
import 'package:litert_hackathon/data/services/knowledge/embedder_service.dart';
import 'package:litert_hackathon/domain/models/knowledge.dart';
import 'package:litert_hackathon/ui/features/home/view_models/home_view_model.dart';

import '../../../../fakes/fake_bundled_files.dart';
import '../../../../fakes/fake_detector_runtime.dart';
import '../../../../fakes/fake_llm_service.dart';
import '../../../../fakes/fake_model_files.dart';
import '../../../../fakes/fake_speech.dart';

/// The knowledge base never blocks Demo 1, but its tile says what it
/// is doing, and an unavailable one is amber.
void main() {
  late ModelRepository models;
  late ValueNotifier<KnowledgeStatus> knowledge;
  late HomeViewModel home;

  setUp(() async {
    models = ModelRepository(
      gemmaModelPath: kTestChatModelPath,
      bundled: FakeBundledFiles(),
      detector: fakeDetectorService(),
      bundledDetector: fakeBundledDetector,
      llm: FakeLlmService(),
      stt: fakeSttService(),
      tts: fakeTtsService(),
      embedder: EmbedderService(),
    );
    knowledge = ValueNotifier(const KnowledgeWaiting());
    home = HomeViewModel(models: models.states, knowledge: knowledge);
    await models.prepareAll();
  });

  tearDown(() async {
    home.dispose();
    knowledge.dispose();
    await models.close();
  });

  DemoTile chat() => home.tiles.singleWhere((t) => t.demo == Demo.voiceChat);
  DemoTile camera() => home.tiles.singleWhere((t) => t.demo == Demo.liveCamera);

  test('every state keeps Demo 1 enabled and says what the knowledge base '
      'is doing', () {
    var notified = 0;
    home.addListener(() => notified++);

    expect(chat().available, isTrue);
    expect(chat().status, 'Ready · knowledge base loading…');
    expect(chat().warning, isFalse);

    knowledge.value = const KnowledgeIndexing(done: 120, total: 290);
    expect(chat().status, 'Ready · knowledge base indexing 41%');
    expect(chat().warning, isFalse);

    // Embedding on the device because the prebuilt index was not used.
    knowledge.value = const KnowledgeIndexing(
      done: 120,
      total: 290,
      prebuiltSkipped: 'this build has no assets/kb_index/manifest.json',
    );
    expect(
      chat().status,
      'Ready · knowledge base indexing 41% (prebuilt index not used)',
    );
    expect(chat().warning, isFalse);

    knowledge.value = const KnowledgeReady(
      chunks: 290,
      reused: true,
      elapsed: Duration(milliseconds: 40),
    );
    expect(chat().status, 'Ready');
    expect(notified, 3);
  });

  test('unavailable and failed are amber with the reason', () {
    knowledge.value = const KnowledgeUnavailable(
      'The built-in EmbeddingGemma is not in this app bundle',
    );
    expect(chat().available, isTrue);
    expect(
      chat().status,
      'Ready · knowledge base unavailable: The built-in EmbeddingGemma is not '
      'in this app bundle',
    );
    expect(chat().warning, isTrue);

    knowledge.value = const KnowledgeFailed('disk full');
    expect(chat().status, 'Ready · knowledge base failed: disk full');
    expect(chat().warning, isTrue);
  });

  test('Demo 3 has no knowledge base and ignores it', () {
    knowledge.value = const KnowledgeUnavailable('no embedder');

    expect(camera().status, 'Ready', reason: 'no knowledge-base note');
    expect(camera().warning, isFalse);
  });
}
