// Prints the knowledge base's chunks as JSON, exactly as the app indexes
// them (MarkdownChunker over assets/kb/*.md, sorted by path), for
// tool/measure_skill_triggers.py.
//
//   fvm dart run tool/dump_kb_chunks.dart > build/kb_chunks.json
import 'dart:convert';
import 'dart:io';

import 'package:litert_hackathon/utils/markdown_chunker.dart';

void main() {
  final files =
      Directory('assets/kb')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  const chunker = MarkdownChunker();
  stdout.write(
    jsonEncode([
      for (final file in files)
        for (final chunk in chunker.chunk(
          file.readAsStringSync(),
          docId: file.uri.pathSegments.last,
        ))
          {'id': chunk.id, 'content': chunk.content},
    ]),
  );
}
