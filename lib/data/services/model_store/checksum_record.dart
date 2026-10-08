import 'dart:io';

/// The `<file>.sha256` record beside a verified file: `<hex>  <name>` and a
/// newline (the `sha256sum` format), written with `flush: true` once the
/// file is in place, so a later launch trusts the file by its size and
/// record instead of hashing it again. One format for both stores of
/// verified files: the model store's custom chat model (`VerifiedCommit`)
/// and Android's extracted built-in models (`BundledModelFiles`), each with
/// its own commit around it.
abstract final class ChecksumRecord {
  /// The record file of [target].
  static File of(File target) => File('${target.path}.sha256');

  /// The hash [target]'s record names (its first word); null when there is
  /// no record or it is blank.
  static Future<String?> read(File target) async {
    final record = of(target);
    if (!await record.exists()) return null;
    final text = await record.readAsString();
    final first = text.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? null : first;
  }

  /// Records [hex] as the SHA-256 of [target] (called [name] in it).
  static Future<void> write(File target, String hex, String name) =>
      of(target).writeAsString('$hex  $name\n', flush: true);
}
