import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/data/services/knowledge/kb_background.dart';
import 'package:litert_hackathon/data/services/knowledge/kb_documents.dart';
import 'package:litert_hackathon/utils/markdown_chunker.dart';

KbDocument _doc(String name, String markdown) => KbDocument(
  name: name,
  path: 'assets/kb/$name',
  bytes: utf8.encode(markdown),
);

void main() {
  group('chunkInBackground', () {
    test("every document's chunks, in order, as the chunker makes "
        'them', () async {
      const chunker = MarkdownChunker();
      final documents = [
        _doc('alpha.md', '# Alpha\n\n## One\n\nFirst.\n\n## Two\n\nSecond.'),
        _doc('beta.md', '## Three\n\nThird.'),
      ];

      final chunks = await chunkInBackground(chunker, documents);

      final expected = [
        for (final d in documents)
          ...chunker.chunk(utf8.decode(d.bytes), docId: d.name),
      ];
      expect(chunks.map((c) => c.id), [
        'alpha.md#0',
        'alpha.md#1',
        'beta.md#0',
      ]);
      expect(
        [for (final c in chunks) (c.id, c.content, c.metadataJson)],
        [for (final c in expected) (c.id, c.content, c.metadataJson)],
      );
    });

    test('no documents, no chunks', () async {
      expect(
        await chunkInBackground(const MarkdownChunker(), const []),
        isEmpty,
      );
    });

    test("a malformed document's error crosses the isolate", () async {
      await expectLater(
        chunkInBackground(const MarkdownChunker(), [
          _doc('broken.md', '## A\n\nText.\n\n```dart\nvoid f() {}\n'),
        ]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('broken.md'),
          ),
        ),
      );
    });
  });

  test('sha256InBackground is the lowercase hex SHA-256', () async {
    final bytes = Uint8List.fromList(List.generate(4096, (i) => i % 251));

    expect(await sha256InBackground(bytes), sha256.convert(bytes).toString());
    expect(
      await sha256InBackground(Uint8List(0)),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });
}
