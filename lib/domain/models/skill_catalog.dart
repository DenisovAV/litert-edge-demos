import 'package:flutter_edge_ai_agent/flutter_edge_ai_agent.dart' show Skill;

/// A SKILL.md that parsed and passed the checks.
final class const LoadedSkill({
  required final Skill skill,

  /// Relative to the skills directory, e.g. `current-time/SKILL.md`.
  required final String path,
});

/// A file in the skills directory that is not a usable skill, and why:
/// a parse error, bad UTF-8, too large, a duplicate name, an unknown intent
/// (wiring §4).
final class const SkillLoadError({
  /// Relative to the skills directory.
  required final String path,
  required final String message,
});

/// One scan of the runtime skills directory (D12): the skills the agent gets
/// and the files that failed, for the Skills sheet and the overlay.
final class const SkillCatalog({
  /// Where users drop skills; null when the directory is unavailable.
  required final String? directory,
  final List<LoadedSkill> skills = const [],
  final List<SkillLoadError> errors = const [],

  /// A hash of every scanned file's path and bytes: a reload applies only
  /// when it changed (applying drops the conversation's history).
  required final String fingerprint,

  /// The directory could not be used at all (no skills then).
  final String? storeError,
}) {
  List<Skill> get agentSkills => [for (final s in skills) s.skill];
}
