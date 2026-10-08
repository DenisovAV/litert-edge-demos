import 'dart:typed_data';

/// Where a picked image came from.
enum ImageSourceKind {
  /// The photo library (macOS: a file dialog).
  gallery,

  /// The system camera UI (iPhone and Android only).
  camera,
}

/// A picture ready for Gemma: re-encoded as PNG by `normalizeForLlm`, EXIF
/// orientation applied, at most `kLlmImageMaxSide` on the long side.
///
/// [png] is also the image's identity: the conversation compares it with
/// `identical` and sends it only when the live chat cannot see it. Pass this
/// same object on every turn while the image stays attached.
final class const LlmImage({
  required final Uint8List png,
  required final int width,
  required final int height,

  /// The picked file, before normalization (EXIF-oriented size).
  required final int sourceWidth,
  required final int sourceHeight,
  required final int sourceBytes,

  /// Decode, resize and PNG encode.
  required final Duration normalizeTime,
});
