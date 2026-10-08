import '../domain/models/model_id.dart';

/// The demos the launcher offers and the models each one needs before its
/// tile is enabled (design demo3 §4). Both speak: their recognizer ([stt])
/// and the TTS are required.
enum Demo {
  voiceChat(
    title: 'Voice chat',
    subtitle: 'Demo 1 · talk or type to the chat model',
    stt: ModelId.whisperBase,
    models: {ModelId.chat, ModelId.whisperBase, ModelId.inflectNano},
    knowledgeBase: true,
  ),
  liveCamera(
    title: 'Live camera',
    subtitle: 'Demo 3 · live detector boxes, questions about the scene',
    stt: ModelId.moonshineTiny,
    models: {
      ModelId.chat,
      ModelId.moonshineTiny,
      ModelId.inflectNano,
      ModelId.yolo26n,
    },
  );

  const Demo({
    required this.title,
    required this.subtitle,
    required this.stt,
    required this.models,
    this.knowledgeBase = false,
  });

  final String title;
  final String subtitle;

  /// The speech recognizer this demo makes active on entry: Whisper base for
  /// Demo 1 (multilingual, 30 s window), moonshine-tiny for Demo 3 (~65 ms,
  /// so a fast answer reaches the ear in well under a second).
  final ModelId stt;
  final Set<ModelId> models;

  /// Answers from the knowledge base. It is not required: without
  /// it the tile stays enabled and says why the knowledge base is missing.
  final bool knowledgeBase;
}
