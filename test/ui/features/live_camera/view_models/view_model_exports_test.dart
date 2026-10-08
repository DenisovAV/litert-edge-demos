import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Demo 3's view-model libraries re-export nothing: every type is imported
/// from the file that declares it, so no importer leans on a re-export kept
/// only for compatibility.
void main() {
  test("Demo 3's view-model libraries re-export nothing", () {
    final directory = Directory('lib/ui/features/live_camera/view_models');
    final exports = [
      for (final file in directory.listSync().whereType<File>())
        if (file.path.endsWith('.dart'))
          for (final line in file.readAsLinesSync())
            if (line.trimLeft().startsWith('export ')) '${file.path}: $line',
    ];
    expect(directory.existsSync(), isTrue);
    expect(exports, isEmpty);
  });
}
