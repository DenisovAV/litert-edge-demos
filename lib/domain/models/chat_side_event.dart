import 'assistant_event.dart';
import 'knowledge.dart';
import 'skill_step.dart';

/// Demo 1's side channel of a voice turn: facts the reply text does not
/// carry. Skill steps join it.
sealed class const ChatSideEvent();

/// The model's turn ended (normally or stopped) with these timings.
final class const ChatGenerationDone(final GenerationMetrics metrics)
    extends ChatSideEvent;

/// The turn's knowledge-base retrieval, before the model is asked:
/// the excerpts in the prompt (cited as `[n]`) or why there are none.
final class const ChatRetrieval(final Retrieval retrieval)
    extends ChatSideEvent;

/// The conversation started over before this turn ([reason]: the context
/// was full, or an interrupted skill call left the chat unusable): the user
/// must be told, whatever happens to the turn afterwards.
final class const ChatContextReset({
  final ContextResetReason reason = ContextResetReason.budget,
}) extends ChatSideEvent;

/// One skill step of the turn (loadSkill, runIntent, its result), as
/// it happens.
final class const ChatSkillStep(final SkillStep step) extends ChatSideEvent;
