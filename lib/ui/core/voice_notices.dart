import '../../domain/models/voice.dart';

/// The notice both voice demos show for a capture that made no LLM call.
String notHeardText(NotHeardReason reason) => switch (reason) {
  NotHeardReason.tooShort =>
    "Didn't catch that — hold the mic button while you speak.",
  NotHeardReason.releasedBeforeListening =>
    'The mic was still opening — wait for Listening… before you speak.',
  NotHeardReason.silent => "Didn't catch that — it was too quiet.",
  NotHeardReason.emptyTranscript =>
    "Didn't catch that — no words were recognized.",
};
