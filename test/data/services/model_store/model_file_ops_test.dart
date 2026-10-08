import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/data/services/model_store/model_file_ops.dart';

import '../../../support/failing_file_workers.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('model_file_ops_test');
    file = File('${dir.path}/model.bin')..writeAsBytesSync(List.filled(64, 7));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  // A worker failure must be an Exception: every handler above the file
  // operations (the model store's) catches `on Exception`, and an Error
  // escaped them as an uncaught zone error, the row stuck on Verifying.
  for (final (what, worker, message) in [
    ('crashes', crashingFileWorker, 'file worker crashed: '),
    ('reports an error', erroringFileWorker, 'the worker reported a failure'),
    ('exits without a result', silentFileWorker, 'without a result'),
  ]) {
    test('a worker that $what fails the hash and the copy with '
        'FileOpFailedException, an Exception', () async {
      final ops = ModelFileOps(worker: worker);

      await expectLater(
        ops.sha256OfFile(file.path, onProgress: (_, _) {}),
        throwsA(
          isA<Exception>().having((e) => '$e', 'message', contains(message)),
        ),
      );
      await expectLater(
        ops.copyAndHash(file.path, '${dir.path}/copy', onProgress: (_, _) {}),
        throwsA(isA<FileOpFailedException>()),
      );
    });
  }

  test('the real worker still hashes', () async {
    final hex = await const ModelFileOps().sha256OfFile(
      file.path,
      onProgress: (_, _) {},
    );
    expect(hex, hasLength(64));
  });
}
