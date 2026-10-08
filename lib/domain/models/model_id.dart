/// Every model the app loads at setup, in load order (design §6).
enum ModelId {
  chat,
  whisperBase,
  inflectNano,
  yolo26n,
  moonshineTiny,
  embeddingGemma,
}

/// What the setup screen shows about a model. Every model but the chat model
/// is built into the app: its files, sizes and hashes are in
/// `data/services/model_store/bundled_model_files.dart`.
final class const ModelSpec({
  required final ModelId id,
  required final String displayName,

  /// Setup fails without a required model. An optional model's failure is
  /// shown on its row and on the demos that need it, and setup continues.
  final bool required = true,
});

/// The chat model: not shipped with the app, a `.litertlm` the tester
/// chooses (the Chat model card). Required: the demos need it.
const kChatSpec = ModelSpec(id: ModelId.chat, displayName: 'Chat model');

/// Whisper base int8 (D6), Demo 1's speech recognizer: multilingual, a
/// 30 s window, ~1.8 s per question on an M4 Pro (padded to 30 s).
const kWhisperSpec = ModelSpec(
  id: ModelId.whisperBase,
  displayName: 'Whisper base (STT)',
);

/// moonshine-tiny f32, Demo 3's speech recognizer: English only, a 5 s
/// window, ~65 ms per question (Whisper base: 1.8 s); router 96/98 and
/// must-detailed 43/43 on its transcripts (`tool/stt_compare_bench.dart`).
/// Optional: without it Demo 3 is unavailable and says why; Demo 1 is not
/// affected.
const kMoonshineSpec = ModelSpec(
  id: ModelId.moonshineTiny,
  displayName: 'moonshine-tiny (STT, Demo 3)',
  required: false,
);

/// Inflect-nano-v2 (D7), the voice of both demos, built into the app: its
/// two models and the four Matcha G2P files it reuses.
const kInflectSpec = ModelSpec(
  id: ModelId.inflectNano,
  displayName: 'Inflect-nano-v2 (TTS)',
);

/// YOLO26n raw-head (detector doc §2.2), derived locally from
/// `Arm/yolo26n-fp16-litert` (`tool/prune_yolo26n_head.py`); built into the
/// app as an asset (AGPL-3.0, `assets/models/NOTICE.md`).
const kYolo26nSpec = ModelSpec(
  id: ModelId.yolo26n,
  displayName: 'YOLO26n detector',
  required: false,
);

/// EmbeddingGemma-300M, the knowledge base's embedder. Optional:
/// without it Demo 1 chats without the knowledge base and says so.
const kEmbeddingGemmaSpec = ModelSpec(
  id: ModelId.embeddingGemma,
  displayName: 'EmbeddingGemma 300M (knowledge base)',
  required: false,
);

extension ModelIdSpec on ModelId {
  ModelSpec get spec => switch (this) {
    ModelId.chat => kChatSpec,
    ModelId.whisperBase => kWhisperSpec,
    ModelId.inflectNano => kInflectSpec,
    ModelId.yolo26n => kYolo26nSpec,
    ModelId.moonshineTiny => kMoonshineSpec,
    ModelId.embeddingGemma => kEmbeddingGemmaSpec,
  };
}
