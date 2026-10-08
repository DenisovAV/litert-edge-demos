import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/data/services/hardware/system_access.dart';

void main() {
  test('LocalSystemFiles: sysfs-style names with ":" and links, missing '
      'paths are null/empty', () {
    final dir = Directory.systemTemp.createTempSync('sysfs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final device = Directory('${dir.path}/devices/0000:00:04.0')
      ..createSync(recursive: true);
    File('${device.path}/class').writeAsStringSync('0x030200\n');
    Link('${dir.path}/bus/0000:00:04.0')
        .createSync(device.path, recursive: true);

    const files = LocalSystemFiles();
    expect(files.list('${dir.path}/bus'), ['0000:00:04.0']);
    expect(files.read('${dir.path}/bus/0000:00:04.0/class'), '0x030200\n');
    expect(files.read('${dir.path}/nope'), isNull);
    expect(files.list('${dir.path}/nope'), isEmpty);
  });

  test(
    'LocalProcessRunner: a missing tool is null, output is captured',
    () async {
      const runner = LocalProcessRunner();
      expect(await runner.run('no-such-tool-for-the-probe', const []), isNull);
      final echo = await runner.run('echo', const ['hello']);
      expect(echo!.exitCode, 0);
      expect(echo.stdout.trim(), 'hello');
    },
  );
}
