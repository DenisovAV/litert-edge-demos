import 'dart:typed_data';

import 'knowledge.dart';
import 'skill_step.dart';

enum ChatRole {
  user,
  assistant,
  error,

  /// Not a message: "Didn't catch that" after a capture with no LLM call.
  notice,
}

/// One committed line of the conversation. The reply that is still streaming
/// is not an entry; it lives in the view model's `partialReply` notifier.
final class const ChatEntry({
  required final ChatRole role,
  required final String text,

  /// An assistant reply cut short by Stop or a barge-in.
  final bool interrupted = false,

  /// A user entry's attached picture (the PNG sent to the model), shown as a
  /// thumbnail. The same object as the attachment: no copy per entry.
  final Uint8List? image,

  /// An assistant reply's knowledge-base retrieval and citations.
  final ReplyKnowledge? knowledge,

  /// The skill steps behind a reply (or a failed turn), in order.
  final List<SkillStep> steps = const [],
});
