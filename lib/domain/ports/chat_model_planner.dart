// A port: an interface that the domain and the view models depend on and an
// outer layer implements. Every port lives in lib/domain/ports/;
// function-typed dependencies stay next to their one consumer.

import '../models/chat_model.dart';

/// Where `ModelRepository` asks what to load into the chat model slot.
abstract interface class ChatModelPlanner {
  ChatModelPlan get plan;
}
