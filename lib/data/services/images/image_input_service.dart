import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/model_catalog.dart';
import '../../../domain/models/llm_image.dart';

/// [ImageSourceKind] the platform cannot provide: the camera on macOS
/// (`image_picker_macos` has no camera without a delegate and throws).
final class UnsupportedImageSourceException implements Exception {
  const UnsupportedImageSourceException(this.source);

  final ImageSourceKind source;

  @override
  String toString() => switch (source) {
    ImageSourceKind.camera =>
      'Taking a photo needs the iPhone or Android app; on this platform pick '
          'an image from the gallery',
    ImageSourceKind.gallery => 'This platform has no image gallery',
  };
}

/// Picks an encoded image from the platform. `ImageRepository` normalizes
/// it; integration tests replace this with a fixture.
abstract interface class ImageInputService {
  /// Whether [pick] can use [source] on this platform.
  bool supports(ImageSourceKind source);

  /// The picked file's bytes (any format the platform returns: JPEG, PNG,
  /// HEIC, WebP…); null when the user cancelled. Throws
  /// [UnsupportedImageSourceException] for a source [supports] rejects, and
  /// the plugin's `PlatformException` for denied access or no camera.
  Future<Uint8List?> pick(ImageSourceKind source);
}

/// [ImageInputService] over `image_picker`: the gallery everywhere, the
/// camera on iOS and Android (inc4-5 §1.4).
final class PlatformImageInputService implements ImageInputService {
  PlatformImageInputService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  bool supports(ImageSourceKind source) =>
      _picker.supportsImageSource(_toPlugin(source));

  @override
  Future<Uint8List?> pick(ImageSourceKind source) async {
    if (!supports(source)) throw UnsupportedImageSourceException(source);
    // maxWidth/maxHeight shrink on iOS and Android before the bytes cross
    // the channel (macOS ignores them; normalization covers it).
    // requestFullMetadata: false skips the iOS photo-library permission
    // prompt (the picker itself is out of process).
    final file = await _picker.pickImage(
      source: _toPlugin(source),
      maxWidth: kLlmImageMaxSide.toDouble(),
      maxHeight: kLlmImageMaxSide.toDouble(),
      requestFullMetadata: false,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  static ImageSource _toPlugin(ImageSourceKind source) => switch (source) {
    ImageSourceKind.gallery => ImageSource.gallery,
    ImageSourceKind.camera => ImageSource.camera,
  };
}
