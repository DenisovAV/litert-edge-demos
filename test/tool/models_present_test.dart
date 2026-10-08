// The built-in models in this checkout are the ones tool/models.lock pins.
// They are not in git: tool/fetch_models.sh fetches them. Without them
// `flutter test` never gets here (the asset bundle fails first: "No file or
// variants found for asset: assets/models/…"), so this catches a stale or
// partial copy, e.g. after the lock moves to a new revision, with the list of
// files and the command that fixes it. Two other tests read the real files
// (test/data/services/detector/detector_service_test.dart, the real bundle;
// test/data/services/model_store/bundled_model_files_test.dart, the real
// assets).
@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assets/models matches tool/models.lock (tool/fetch_models.sh '
      '--check)', () {
    final result = Process.runSync('/bin/sh', [
      'tool/fetch_models.sh',
      '--check',
    ]);
    expect(
      result.exitCode,
      0,
      reason:
          '${result.stdout}${result.stderr}'
          'Fix: tool/fetch_models.sh (the models are not in git).',
    );
  });
}
