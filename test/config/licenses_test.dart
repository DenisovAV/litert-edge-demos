import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/licenses.dart';

void main() {
  test('the built-in models are on the licence page: YOLO26n under AGPL-3.0 '
      'with its derivation script, EmbeddingGemma with the Gemma terms', () {
    final yolo = modelLicenses.firstWhere(
      (e) => e.packages.single.startsWith('YOLO26n'),
    );
    final yoloText = yolo.paragraphs.map((p) => p.text).join('\n');
    expect(yoloText, contains('AGPL-3.0'));
    expect(yoloText, contains('tool/prune_yolo26n_head.py'));
    expect(yoloText, contains('Arm/yolo26n-fp16-litert'));

    final gemma = modelLicenses.firstWhere(
      (e) => e.packages.single.startsWith('EmbeddingGemma'),
    );
    final gemmaText = gemma.paragraphs.map((p) => p.text).join('\n');
    expect(
      gemmaText,
      contains(
        'Gemma is provided under and subject to the Gemma Terms of Use found '
        'at https://ai.google.dev/gemma/terms',
      ),
    );
  });

  test('the app itself: Apache-2.0, first on the page; no AGPL for the app '
      'code', () {
    final app = modelLicenses.first;
    expect(app.packages.single, 'LiteRT demos app');
    final text = app.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('LiteRT demos app: Apache-2.0'));
    expect(text, contains('http://www.apache.org/licenses/LICENSE-2.0'));
    expect(text, isNot(contains('AGPL')));
  });

  test('the repository LICENSE is the full Apache-2.0 text', () {
    final license = File('LICENSE').readAsStringSync();
    expect(license, contains('Apache License'));
    expect(license, contains('Version 2.0, January 2004'));
    expect(license, contains('END OF TERMS AND CONDITIONS'));
  });

  test('registered once in the LicenseRegistry', () async {
    registerModelLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    expect(
      entries.expand((e) => e.packages),
      containsAll([
        'LiteRT demos app',
        'YOLO26n detector (built in)',
        'EmbeddingGemma 300M (built in)',
      ]),
    );
  });
}
