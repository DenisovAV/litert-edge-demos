import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/data/services/audio/audio_session_service.dart';
import 'package:litert_hackathon/domain/models/hardware_profile.dart';

void main() {
  test('Linux gets the explicit no-op session, which says so', () async {
    expect(
      audioSessionServiceFor(HostPlatform.linux),
      isA<NoAudioSessionService>(),
    );
    final lines = <String>[];
    await NoAudioSessionService(log: lines.add).configureHalfDuplex();
    expect(lines, ['[AudioSession] none on Linux (PulseAudio/PipeWire)']);
  });

  test('the other platforms keep audio_session', () {
    for (final platform in [
      HostPlatform.macos,
      HostPlatform.ios,
      HostPlatform.android,
    ]) {
      expect(
        audioSessionServiceFor(platform),
        isA<PlatformAudioSessionService>(),
        reason: platform.name,
      );
    }
  });
}
