/// The app's intents: the only actions a Markdown skill can run (design
/// §2 non-goals: Markdown combines intents, it never adds Dart). A SKILL.md
/// names them as intent `current_time` and calls `run_intent` with one.
///
/// Camera-watch and timer were removed on 2026-10-06 (docs/design/
/// demo1-voice-chat.md): simpler, no camera in the chat, less memory.
abstract final class AppIntent {
  static const deviceInfo = 'device_info';
  static const currentTime = 'current_time';

  static const all = {deviceInfo, currentTime};

  /// `device_info, current_time`, for error results the model reads.
  static String get listed => all.join(', ');

  /// [raw] as an intent name: trimmed, lowercased, `-` → `_` (small models
  /// echo `current-time`). Null when that is not one of [all].
  static String? normalize(String raw) {
    final name = raw.trim().toLowerCase().replaceAll('-', '_');
    return all.contains(name) ? name : null;
  }
}

/// The intents a SKILL.md body names, written as intent `name` (in
/// backticks, the form every bundled skill uses). The scan checks them
/// against [AppIntent.all] so a typo is listed as an error, not discovered
/// by the model at run time.
Set<String> intentsNamedIn(String body) => {
  for (final match in _namedIntent.allMatches(body)) match[1]!.trim(),
};

final _namedIntent = RegExp(r'\bintent\s+`([^`\n]+)`');
