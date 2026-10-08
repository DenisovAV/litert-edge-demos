// A port: an interface that the domain and the view models depend on and an
// outer layer implements. Every port lives in lib/domain/ports/;
// function-typed dependencies stay next to their one consumer.

import '../models/voice.dart';

/// Where the voice turn machine (`VoiceAssistant`) reports its phases and
/// each turn's figures, for the debug overlay. `DiagnosticsRepository`
/// implements it.
abstract interface class VoiceDiagnosticsSink {
  /// The assistant's phase (a few changes per turn).
  void recordVoicePhase(TurnPhase phase);

  /// The running or finished turn's timings, as they become known.
  void recordVoiceTurn(VoiceTurnMetrics metrics);

  /// A barge-in's cost, as the stop is confirmed and the drain ends.
  void recordBargeIn(BargeInMetrics metrics);
}
