import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_embeddings/flutter_edge_ai_embeddings.dart'
    show GemmaEmbeddingTokenizers;
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_edge_ai_speech/flutter_edge_ai_speech.dart';

/// One-time flutter_edge_ai setup: the LiteRT-LM engine, the LiteRT speech
/// backends, the LiteRT embedding backend and Gemma's embedding
/// tokenizer (wiring §2.1). The sqlite-vec store is no longer
/// registered here: since flutter_edge_ai 2.0 RAG is `flutter_edge_ai_rag`,
/// opened by `VectorStoreService`. Registering loads nothing; models load
/// in `getActive*`. Keep this the only `initialize` call: a second one
/// returns early and silently ignores its arguments (inc3-voice-wiring §1).
Future<void> initEdgeAi() => FlutterEdgeAi.initialize(
  inferenceEngines: const [LiteRtLmEngine()],
  sttBackends: const [LiteRtSttBackend()],
  ttsBackends: const [LiteRtTtsBackend()],
  embeddingBackends: const [LiteRtEmbeddingBackend()],
  embeddingTokenizers: const [GemmaEmbeddingTokenizers()],
);
