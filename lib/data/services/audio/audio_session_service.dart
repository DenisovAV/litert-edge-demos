import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/models/hardware_profile.dart' show HostPlatform;

/// The one owner of the platform audio session (D3). `record` is told not to
/// manage it and soloud never activates it.
abstract interface class AudioSessionService {
  /// Configures half-duplex voice (D4) and activates the session. Call once,
  /// before soloud starts and before the first capture.
  Future<void> configureHalfDuplex();
}

/// The session owner for [platform]: none on Linux (see
/// [NoAudioSessionService]), `audio_session` elsewhere.
AudioSessionService audioSessionServiceFor(HostPlatform platform) =>
    platform == HostPlatform.linux
    ? const NoAudioSessionService()
    : const PlatformAudioSessionService();

/// Linux has no audio session: PulseAudio/PipeWire route per stream. Said
/// explicitly, because `audio_session` 0.2.4 swallows its missing Linux
/// plugin (`AudioSession.instance`, `AudioSession.configure`) and
/// `AudioSession.setActive` answers true, which would log a session that
/// does not exist (linux-build.md §2).
final class NoAudioSessionService implements AudioSessionService {
  const NoAudioSessionService({this._log});

  final void Function(String line)? _log;

  @override
  Future<void> configureHalfDuplex() async => (_log ?? debugPrint)(
    '[AudioSession] none on Linux (PulseAudio/PipeWire)',
  );
}

/// [AudioSessionService] over `audio_session`. On macOS `configure` and
/// `setActive` are no-ops; on iOS this is `.playAndRecord` with the default
/// mode (no voice processing: the mic is closed while the reply plays).
final class PlatformAudioSessionService implements AudioSessionService {
  const PlatformAudioSessionService();

  @override
  Future<void> configureHalfDuplex() async {
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.assistant,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
      ),
    );
    final active = await session.setActive(true);
    debugPrint('[AudioSession] half-duplex configured, active=$active');
  }
}
