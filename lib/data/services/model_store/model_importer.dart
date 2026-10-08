import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../domain/models/provisioning.dart';
import 'model_file_ops.dart';
import 'store_operation.dart';
import 'verified_commit.dart';

/// Takes a picked file into the model store as the model store does it:
/// into `<target>.import` by [ImportMethod.moved] (the picker's own
/// temporary copy, inside `moveFrom`), [ImportMethod.cloned] (APFS
/// copy-on-write on macOS/iOS) or [ImportMethod.copied] (hashed on the way),
/// then committed by [VerifiedCommit]. A link is followed to the file it
/// points to; the picker's temporary copy is not kept twice. A failure
/// leaves the target as it was and no `.import` behind.
///
/// State goes to a [FileStateReporter]: [StoreFileCopying] or
/// [StoreFileVerifying] at once, then as progress; [StoreFileReady] once
/// committed. Logs as `[ModelStore]`.
final class ModelImporter {
  /// [_commit] is the store's own, so imports and downloads commit alike.
  const ModelImporter(this._ops, this._commit);

  final ModelFileOps _ops;
  final VerifiedCommit _commit;

  /// Imports [source] ([sizeBytes] long, stored as [name]) onto [target]:
  /// checked against [expectedSha256] when one is given, and recorded.
  /// Returns how it came in and its SHA-256. Completing [cancel] stops a
  /// hash or a copy ([OperationCancelledException]).
  Future<(ImportMethod, String)> importFile(
    String source,
    File target, {
    required String name,
    required int sizeBytes,
    required String? expectedSha256,
    required String? moveFrom,
    required CancelToken cancel,
    required FileStateReporter reporter,
  }) async {
    final temp = File('${target.path}.import');
    try {
      final watch = Stopwatch()..start();
      final (method, hex) = await _takeIn(
        name,
        source,
        sizeBytes,
        temp,
        cancel,
        reporter,
        moveFrom: moveFrom,
      );
      await _commit.commit(
        ExpectedFile(
          name: name,
          sizeBytes: sizeBytes,
          sha256: expectedSha256,
          source: source,
        ),
        temp,
        target,
        hex,
        reporter,
      );
      await _dropPickerCopy(method, source, moveFrom);
      debugPrint(
        '[ModelStore] custom $name: imported (${method.name}) from $source in '
        '${watch.elapsedMilliseconds} ms, sha256 $hex',
      );
      return (method, hex);
    } finally {
      await deleteQuietly(temp);
    }
  }

  /// Brings [source] into [temp] (moved from the picker's own temporary
  /// copy, APFS-cloned, or copied while hashing) and returns how and the
  /// SHA-256 of what landed in [temp].
  Future<(ImportMethod, String)> _takeIn(
    String name,
    String source,
    int size,
    File temp,
    CancelToken cancel,
    FileStateReporter reporter, {
    required String? moveFrom,
  }) async {
    await deleteQuietly(temp);
    // A link in the picked folder: clone or copy the file it points to.
    final real = await File(source).resolveSymbolicLinks();
    ImportMethod? method;
    if (moveFrom != null && _isInside(source, moveFrom)) {
      try {
        await File(source).rename(temp.path);
        method = ImportMethod.moved;
      } on FileSystemException catch (e) {
        debugPrint('[ModelStore] $name: move failed ($e); copying');
      }
    }
    if (method == null && _ops.tryClone(real, temp.path)) {
      method = ImportMethod.cloned;
    }
    if (method != null) {
      return (method, await _commit.hash(name, size, temp, cancel, reporter));
    }
    reporter.report(StoreFileCopying(copied: 0, total: size));
    final hex = await _ops.copyAndHash(
      real,
      temp.path,
      onProgress: (done, total) =>
          reporter.progress(StoreFileCopying(copied: done, total: total)),
      cancel: cancel.onCancel,
    );
    return (ImportMethod.copied, hex);
  }

  /// The picker's own temporary copy, when it was copied rather than moved:
  /// not kept twice.
  Future<void> _dropPickerCopy(
    ImportMethod method,
    String source,
    String? moveFrom,
  ) async {
    if (method != ImportMethod.moved &&
        moveFrom != null &&
        _isInside(source, moveFrom)) {
      await deleteQuietly(File(source));
    }
  }

  static bool _isInside(String path, String directory) {
    final dir = directory.endsWith(Platform.pathSeparator)
        ? directory
        : '$directory${Platform.pathSeparator}';
    return path.startsWith(dir);
  }
}
