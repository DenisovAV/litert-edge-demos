import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/domain/hardware/device_summary.dart';
import 'package:litert_hackathon/domain/hardware/diagnostics_report.dart';
import 'package:litert_hackathon/domain/models/audio_devices.dart';
import 'package:litert_hackathon/domain/models/diagnostics_snapshot.dart';
import 'package:litert_hackathon/domain/models/hardware_profile.dart';
import 'package:litert_hackathon/ui/core/debug_overlay.dart';

import '../../fakes/fake_hardware.dart';

const _build = BuildInfo(
  appVersion: '0.1.0+1',
  buildMode: 'release',
  flutterVersion: '3.47.3',
  dartVersion: '3.13.3',
  packages: {},
  liteRtLmNative: 'native-v0.17.1-a',
);

const _status = AudioDeviceStatus(
  input: DeviceReady(
    'Built-in Audio Analog Stereo',
    detail: 'PulseAudio (on PipeWire 1.0.5)',
  ),
  output: DeviceUnavailable(
    'No audio output (no PulseAudio/PipeWire/ALSA device): miniaudio fell '
    'back to its silent Null device',
  ),
);

void main() {
  test('the overlay names both devices, or what is wrong', () {
    expect(
      debugOverlayLines(const DiagnosticsSnapshot()),
      contains('audio in unchecked · out unchecked'),
    );
    expect(
      debugOverlayLines(const DiagnosticsSnapshot(audioDevices: _status)),
      contains(
        'audio in Built-in Audio Analog Stereo · out UNAVAILABLE: No audio '
        'output (no PulseAudio/PipeWire/ALSA device): miniaudio fell back to '
        'its silent Null device',
      ),
    );
  });

  test('the card has Mic and Speaker lines; an unusable one is red', () {
    final summary = buildDeviceSummary(
      hardware: kFakeMacProfile,
      hardwareNote: null,
      models: const [],
      audio: _status,
    );
    final mic = summary.device.singleWhere((l) => l.label == 'Mic');
    final speaker = summary.device.singleWhere((l) => l.label == 'Speaker');
    expect(
      mic.value,
      'Built-in Audio Analog Stereo · PulseAudio (on PipeWire 1.0.5)',
    );
    expect(mic.tone, SummaryTone.neutral);
    expect(speaker.value, startsWith('No audio output'));
    expect(speaker.tone, SummaryTone.error);

    final unchecked = buildDeviceSummary(
      hardware: null,
      hardwareNote: 'probing…',
      models: const [],
      audio: const AudioDeviceStatus(),
    );
    expect(
      unchecked.device.singleWhere((l) => l.label == 'Mic').value,
      'not checked yet (a voice demo starts the audio)',
    );
  });

  test('the report has an AUDIO block when the status is known', () {
    final text = formatDiagnostics(
      DiagnosticsInput(
        generatedAt: DateTime.utc(2026, 10, 6),
        build: _build,
        hardware: kFakeMacProfile,
        nativeLog: 'none',
        audio: _status,
      ),
    );
    expect(
      text,
      contains(
        '\nAUDIO\n'
        'input      Built-in Audio Analog Stereo · PulseAudio (on PipeWire '
        '1.0.5)\n'
        'output     UNAVAILABLE · No audio output (no PulseAudio/PipeWire/ALSA '
        'device): miniaudio fell back to its silent Null device\n',
      ),
    );
    expect(
      formatDiagnostics(
        DiagnosticsInput(
          generatedAt: DateTime.utc(2026, 10, 6),
          build: _build,
          nativeLog: 'none',
        ),
      ),
      isNot(contains('AUDIO')),
    );
  });
}
