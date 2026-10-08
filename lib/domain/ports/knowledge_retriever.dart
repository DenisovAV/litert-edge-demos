// A port: an interface that the domain and the view models depend on and an
// outer layer implements. Every port lives in lib/domain/ports/;
// function-typed dependencies stay next to their one consumer.

import '../../utils/result.dart';
import '../models/knowledge.dart';

/// What Demo 1's turn responder needs from the knowledge base: one gated
/// search per question (wiring §2.6). `KnowledgeRepository` implements it;
/// responder tests pass a fake.
abstract interface class KnowledgeRetriever {
  /// Ok with [RetrievalOutcome.used] (excerpts for the prompt),
  /// [RetrievalOutcome.belowGate] or [RetrievalOutcome.unavailable] (with
  /// the reason); Error when the search itself failed. Never throws.
  Future<Result<Retrieval>> retrieve(String question);
}
