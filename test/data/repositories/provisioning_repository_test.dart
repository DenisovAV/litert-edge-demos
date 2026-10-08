import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart' show PreferredBackend;
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/dev_overrides.dart';
import 'package:litert_hackathon/config/model_catalog.dart';
import 'package:litert_hackathon/data/repositories/provisioning_repository.dart';
import 'package:litert_hackathon/data/services/model_store/bundled_model_files.dart';
import 'package:litert_hackathon/data/services/model_store/model_store.dart';
import 'package:litert_hackathon/domain/models/chat_model.dart';
import 'package:litert_hackathon/domain/models/model_id.dart';
import 'package:litert_hackathon/domain/models/provisioning.dart';
import 'package:litert_hackathon/domain/ports/chat_model_planner.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('provisioning_test'));
  tearDown(() => root.deleteSync(recursive: true));

  ProvisioningRepository build({
    DevModelOverrides overrides = const DevModelOverrides(),
    ChatModelPlanner? chatModels,
  }) {
    final store = ModelStore(root: () async => root);
    addTearDown(store.close);
    return ProvisioningRepository(
      store: store,
      overrides: overrides,
      chatModels: chatModels,
    );
  }

  test('every model but the chat model is built in; only the chat model can '
      'be missing', () {
    final repo = build();

    expect(repo.presenceOf(ModelId.chat), isA<ChatModelNotChosen>());
    for (final id in ModelId.values.where((id) => id != ModelId.chat)) {
      expect(repo.presenceOf(id), isA<PresentBundled>(), reason: '$id');
      expect(ProvisioningRepository.bundledBytes(id), bundledModelBytes(id));
      expect(ProvisioningRepository.bundledBytes(id), greaterThan(0));
    }
    expect(repo.requiredPresent, isFalse);
  });

  test('the chat model: none chosen is not present (setup waits); your own '
      'fills the slot; a blocked one counts as present so the setup attempt '
      'shows why', () {
    final none = build(chatModels: _Planner(const NoChatModelPlan(note: 'n')));
    expect(
      none.presenceOf(ModelId.chat),
      isA<ChatModelNotChosen>().having((p) => p.note, 'note', 'n'),
    );
    expect(none.requiredPresent, isFalse);
    expect(
      ProvisioningRepository.isPresent(none.presenceOf(ModelId.chat)),
      isFalse,
    );

    final planner = _Planner(
      const CustomChatPlan(
        path: '/store/custom/mine.litertlm',
        model: CustomChatModel(
          displayName: 'Mine',
          source: ImportedModelSource('/picked/mine.litertlm'),
          file: CustomModelFile(
            name: 'mine.litertlm',
            sizeBytes: 4321,
            sha256: '0000000000000000000000000000000000000000000000000000000000000000',
            checksumMatched: false,
          ),
          backend: PreferredBackend.npu,
          maxTokens: 1280,
        ),
      ),
    );
    final repo = build(chatModels: planner);

    expect(
      repo.presenceOf(ModelId.chat),
      isA<PresentAsCustomChatModel>()
          .having((p) => p.name, 'name', 'Mine')
          .having((p) => p.sizeBytes, 'sizeBytes', 4321),
    );
    expect(repo.requiredPresent, isTrue);
    expect(
      (repo.presenceOf(ModelId.chat) as PresentAsCustomChatModel).where,
      'model store (custom/) · verified',
    );
    final local = planner.plan as CustomChatPlan;
    planner.plan = CustomChatPlan(
      path: '/data/local/tmp/mine.litertlm',
      model: local.model.copyWith(
        source: const LocalModelSource('/data/local/tmp/mine.litertlm'),
      ),
    );
    expect(
      (repo.presenceOf(ModelId.chat) as PresentAsCustomChatModel).where,
      'in place: /data/local/tmp/mine.litertlm',
    );

    planner.plan = const ChatPlanBlocked('mine.litertlm is gone');
    expect(repo.presenceOf(ModelId.chat), isA<CustomChatModelBlocked>());
    expect(repo.requiredPresent, isTrue);
  });

  group('developer defines', () {
    test('GEMMA_MODEL_PATH fills the chat slot while none is chosen; your '
        'own model wins over it', () {
      const overrides = DevModelOverrides(gemmaModelPath: '/dev/g.litertlm');
      final repo = build(overrides: overrides);

      expect(
        repo.presenceOf(ModelId.chat),
        isA<PresentByDefine>()
            .having((p) => p.define, 'define', 'GEMMA_MODEL_PATH')
            .having((p) => p.value, 'value', '/dev/g.litertlm'),
      );
      expect(repo.requiredPresent, isTrue);

      final mine = build(
        overrides: overrides,
        chatModels: _Planner(
          const CustomChatPlan(
            path: '/models/mine.litertlm',
            model: CustomChatModel(
              displayName: 'Mine',
              source: LocalModelSource('/models/mine.litertlm'),
              backend: PreferredBackend.gpu,
              maxTokens: 8192,
            ),
          ),
        ),
      );
      expect(mine.presenceOf(ModelId.chat), isA<PresentAsCustomChatModel>());
    });

    test('DETECTOR_MODEL_PATH and EMBEDDING_MODEL_DIR win over the built-in '
        'files', () {
      final repo = build(
        overrides: const DevModelOverrides(
          detectorModelPath: '/dev/yolo.tflite',
          embeddingModelDir: '/dev/eg',
        ),
      );

      expect(
        repo.presenceOf(ModelId.yolo26n),
        isA<PresentByDefine>().having(
          (p) => p.define,
          'define',
          'DETECTOR_MODEL_PATH',
        ),
      );
      expect(repo.presenceOf(ModelId.embeddingGemma), isA<PresentByDefine>());
      expect(repo.presenceOf(ModelId.whisperBase), isA<PresentBundled>());
    });
  });

  test('pruning after a start keeps the chosen file in place, waits while the '
      'chat model is blocked, and runs once', () async {
    final retired = File('${root.path}/$kRetiredGemmaFolder/$kRetiredGemmaFile')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final planner = _Planner(const ChatPlanBlocked('its file changed'));
    final repo = build(chatModels: planner);

    expect(await repo.pruneOldModelFolders(), isEmpty, reason: 'blocked: wait');
    expect(retired.existsSync(), isTrue);

    planner.plan = CustomChatPlan(
      path: retired.path,
      model: CustomChatModel(
        displayName: 'Gemma 4 E2B',
        source: LocalModelSource(retired.path),
        backend: PreferredBackend.gpu,
        maxTokens: 8192,
      ),
    );
    expect(
      await repo.pruneOldModelFolders(),
      isEmpty,
      reason: 'the chosen file',
    );
    expect(retired.existsSync(), isTrue);

    planner.plan = const NoChatModelPlan();
    expect(
      await repo.pruneOldModelFolders(),
      isEmpty,
      reason: 'once per start',
    );
    expect(retired.existsSync(), isTrue);
  });

  test(
    'pruning with no chat model chosen removes the earlier downloads',
    () async {
      for (final name in [kRetiredGemmaFolder, 'whisperBase', 'custom']) {
        File('${root.path}/$name/f')
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
      }
      final repo = build(chatModels: _Planner(const NoChatModelPlan()));

      final removed = await repo.pruneOldModelFolders();

      expect(removed.map((p) => p.split('/').last).toSet(), {
        kRetiredGemmaFolder,
        'whisperBase',
      });
      expect(Directory('${root.path}/custom').existsSync(), isTrue);
    },
  );
}

final class _Planner implements ChatModelPlanner {
  _Planner(this.plan);

  @override
  ChatModelPlan plan;
}
