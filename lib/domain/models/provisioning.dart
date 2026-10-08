import 'dart:io' show FileSystemException;

/// The custom chat model's file in the model store and what is happening to
/// it (docs/design/custom-chat-model.md).
sealed class const StoreFileState();

/// Nothing on disk.
final class const StoreFileMissing() extends StoreFileState;

/// The file is on disk, but its size or checksum record is not the one saved
/// with the custom model (changed on disk, or a crash before the record was
/// written).
final class const StoreFileUnverified() extends StoreFileState;

/// Receiving bytes; [attempt] counts automatic reconnects (1 = the first).
final class const StoreFileDownloading({
  required final int received,
  required final int total,
  final int attempt = 1,
}) extends StoreFileState;

/// Hashing the whole file before it may be used.
final class const StoreFileVerifying({
  required final int processed,
  required final int total,
}) extends StoreFileState;

/// Import: copying (and hashing) the picked file into the store.
final class const StoreFileCopying({
  required final int copied,
  required final int total,
}) extends StoreFileState;

/// Hashed (and checked against the checksum the tester gave, if any) and
/// recorded; [path] is what the chat model loads.
final class const StoreFileReady(final String path) extends StoreFileState;

/// How one picked or found file was taken into the store.
enum ImportMethod {
  /// APFS copy-on-write clone (macOS/iOS): instant, no extra disk.
  cloned,

  /// Byte copy, hashed on the way.
  copied,

  /// Renamed from the app's own temporary copy (iOS document picker).
  moved,
}

/// Why a model counts as present for loading, or not.
sealed class const ModelPresence();

/// A developer `--dart-define` supplies it ([define] = [value]) and wins
/// over the file built into the app (docs/design/distribution.md D5).
final class const PresentByDefine(final String define, final String value)
    extends ModelPresence;

/// Built into the app (a Flutter asset): nothing to download or import.
final class const PresentBundled() extends ModelPresence;

/// The chat slot holds the tester's own model ([name], [sizeBytes]) from
/// the store's `custom/` folder or used in place ([where])
/// (docs/design/custom-chat-model.md).
final class const PresentAsCustomChatModel(
  final String name,
  final int sizeBytes, {

  /// `model store (custom/) · verified`, or `in place: /path`.
  final String where = 'model store (custom/) · verified',
}) extends ModelPresence;

/// The tester's own model is chosen but cannot load ([reason]). It counts
/// as present so the setup attempt shows the reason; no other model is ever
/// loaded in its place.
final class const CustomChatModelBlocked(final String reason)
    extends ModelPresence;

/// No chat model is chosen yet (the app ships none): the Chat model card
/// says how to choose one; [note] explains a retired saved choice. Not
/// present: setup cannot finish, the demos stay off.
final class const ChatModelNotChosen({final String? note})
    extends ModelPresence;

/// A failure to store the custom chat model's file, shown as-is on the Chat
/// model card.
sealed class ProvisioningException implements Exception {
  const ProvisioningException();

  String get message;

  @override
  String toString() => message;
}

/// The host sent a web page instead of the file: Google Drive's virus-scan
/// warning or download-quota page, or a login wall.
final class HtmlInsteadOfFileException extends ProvisioningException {
  const HtmlInsteadOfFileException(
    this.fileName,
    this.url, {
    required this.drive,
  });

  final String fileName;
  final Uri url;
  final bool drive;

  /// The problem only: what to do next depends on the platform (import is
  /// not available everywhere).
  @override
  String get message => drive
      ? 'Google Drive returned a web page instead of $fileName (its '
            'virus-scan warning or download quota), from $url.'
      : '$url returned a web page instead of $fileName.';
}

final class DownloadHttpException extends ProvisioningException {
  const DownloadHttpException(this.fileName, this.url, this.statusCode);

  final String fileName;
  final Uri url;
  final int statusCode;

  @override
  String get message =>
      'Downloading $fileName failed: HTTP $statusCode from '
      '${url.host}.';
}

/// A redirect the download does not follow: to a link that is not HTTP(S),
/// or from HTTPS down to plain HTTP, where the bytes (and, without a
/// checksum, what gets recorded as their hash) could be changed on the way.
/// Only the target's scheme and host are shown: a signed CDN link carries
/// its token in the query.
final class UnsafeRedirectException extends ProvisioningException {
  const UnsafeRedirectException(
    this.fileName, {
    required this.from,
    required this.to,
  });

  final String fileName;

  /// The URL that redirected.
  final Uri from;

  /// Where it redirected to.
  final Uri to;

  @override
  String get message => to.isScheme('http')
      ? 'Downloading $fileName stopped: ${from.host} redirected it from '
            'HTTPS to plain HTTP (http://${to.host}), where the bytes could '
            'be changed on the way.'
      : 'Downloading $fileName stopped: ${from.host} redirected it to a '
            '${to.scheme}: link, not HTTP(S).';
}

/// The network failed (after the automatic reconnects); the partial file is
/// kept and Retry resumes it.
final class DownloadNetworkException extends ProvisioningException {
  const DownloadNetworkException(this.fileName, this.cause, this.partialBytes);

  final String fileName;
  final Object cause;
  final int partialBytes;

  @override
  String get message =>
      'Network error while downloading $fileName: $cause. '
      '${partialBytes > 0 ? 'The partial file is kept (${_mb(partialBytes)}); Retry resumes it.' : 'Retry starts it again.'}';
}

final class SizeMismatchException extends ProvisioningException {
  const SizeMismatchException(
    this.fileName, {
    required this.expected,
    required this.actual,
    required this.source,
  });

  final String fileName;
  final int expected;
  final int actual;
  final String source;

  @override
  String get message =>
      '$fileName from $source is $actual bytes, not the $expected expected. '
      'It is not the right file.';
}

/// The bytes do not hash to the SHA-256 the tester entered. The file is
/// deleted: resuming corrupt bytes could never fix it.
final class ChecksumMismatchException extends ProvisioningException {
  const ChecksumMismatchException(
    this.fileName, {
    required this.expected,
    required this.actual,
    required this.source,
  });

  final String fileName;
  final String expected;
  final String actual;
  final String source;

  @override
  String get message =>
      '$fileName from $source failed verification: SHA-256 $actual, the '
      'checksum you entered expects $expected. The file was deleted; Retry '
      'fetches it again.';
}

/// The disk is full; the partial file is kept.
final class DiskFullException extends ProvisioningException {
  const DiskFullException(this.fileName, this.neededBytes);

  final String fileName;
  final int neededBytes;

  @override
  String get message =>
      'The disk is full while writing $fileName (${_mb(neededBytes)} '
      'needed). Free some space, then Retry.';
}

final class StoreWriteException extends ProvisioningException {
  const StoreWriteException(this.fileName, this.cause);

  final String fileName;
  final FileSystemException cause;

  @override
  String get message =>
      'Could not write $fileName: ${cause.message}'
      '${cause.osError == null ? '' : ' (${cause.osError!.message})'}.';
}

final class StoreBusyException extends ProvisioningException {
  const StoreBusyException();

  @override
  String get message => 'Another download or import is running.';
}

/// A download, an import or a file operation (hash, copy; its worker isolate
/// is killed) was cancelled.
final class OperationCancelledException extends ProvisioningException {
  const OperationCancelledException();

  @override
  String get message => 'Cancelled.';
}

/// The custom chat model's file name or extension is not usable.
final class CustomModelFileException extends ProvisioningException {
  const CustomModelFileException(this.message);

  @override
  final String message;
}

/// The custom model's server does not say how large the file is, and the
/// tester gave no size: without it a download can neither resume nor be
/// checked.
final class UnknownSizeException extends ProvisioningException {
  const UnknownSizeException(this.url);

  final Uri url;

  @override
  String get message =>
      '${url.host} does not report the file size: enter the size in bytes '
      'and download again.';
}

String _mb(int bytes) => '${(bytes / 1e6).toStringAsFixed(1)} MB';
