// Demo 3's saved settings for the integration tests.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/data/services/settings/settings_store.dart';
import 'package:litert_hackathon/data/services/settings/typed_settings.dart';
import 'package:litert_hackathon/utils/result.dart';

/// Clears Demo 3's saved camera source, network camera URL and detector
/// backend. They live in the app's shared preferences, which a manual run on
/// the same machine (same bundle id) or device shares: a test that expects
/// the device camera or the GPU must not inherit "network camera" or "CPU"
/// from one. The build's defines still win over the defaults.
Future<void> resetDemo3Settings() async {
  final settings = TypedSettings(store: SharedPreferencesSettingsStore());
  for (final setting in [
    Settings.cameraSource,
    Settings.networkCameraUrl,
    Settings.detectorBackend,
  ]) {
    if (await settings.clear(setting) case Error(:final error)) {
      fail('Could not reset ${setting.key}: $error');
    }
  }
  debugPrint('[test] Demo 3 settings reset (device camera, GPU)');
}
