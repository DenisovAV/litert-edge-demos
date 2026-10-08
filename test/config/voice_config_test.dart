import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/voice_config.dart';

void main() {
  // Every "access is off" hint names the settings path of the platform it
  // runs on (Android has no "Privacy & Security" page).
  test('microphone: macOS, iOS and Android each get their own path', () {
    expect(
      micAccessMessage(TargetPlatform.macOS),
      contains('System Settings › Privacy & Security › Microphone'),
    );
    expect(
      micAccessMessage(TargetPlatform.iOS),
      contains('Settings › Privacy & Security › Microphone'),
    );
    expect(micAccessMessage(TargetPlatform.iOS), isNot(contains('System')));
    final android = micAccessMessage(TargetPlatform.android);
    expect(android, isNot(contains('Privacy & Security')));
    expect(android, contains('Settings › Apps › litert_hackathon'));
    expect(android, contains('Permissions › Microphone'));
  });
}
