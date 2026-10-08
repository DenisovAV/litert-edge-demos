/// What the loaded chat model allows (docs/design/custom-chat-model.md C6).
final class const ChatCapabilities({
  /// `Gemma 4 E2B`, or the tester's name for their model.
  required final String modelName,

  /// Loaded with the vision encoder: photos and camera frames can be sent.
  required final bool images,

  /// Chats may declare tools (skills).
  required final bool tools,
});
