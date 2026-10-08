/// Which source `LiveDetectionRepository.start` should open.
sealed class const FrameSourceSpec();

/// The device camera.
final class const CameraSourceSpec() extends FrameSourceSpec;

/// A slideshow of still images; each path is an image file or a directory of
/// images. [mirrored] flips frames and preview like camera_desktop on macOS
/// does, to test that Gemma gets the frame mirrored back.
final class const FixtureSourceSpec(
  final List<String> paths, {
  final bool mirrored = false,
}) extends FrameSourceSpec;

/// An MJPEG stream over HTTP (`multipart/x-mixed-replace`), e.g. the IP
/// Webcam app's `http://<phone>:8080/video`.
final class const NetworkSourceSpec(final Uri url) extends FrameSourceSpec;

/// A source cannot be opened in this build or configuration.
final class FrameSourceUnavailableException implements Exception {
  const FrameSourceUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
