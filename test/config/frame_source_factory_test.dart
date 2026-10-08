import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/dependencies.dart'
    show createFrameSource;
import 'package:litert_hackathon/data/services/frames/camera_frame_source.dart';
import 'package:litert_hackathon/data/services/frames/fixture_frame_source.dart';
import 'package:litert_hackathon/data/services/frames/frame_source.dart';
import 'package:litert_hackathon/data/services/frames/network_frame_source.dart';
import 'package:litert_hackathon/domain/models/frame_source_spec.dart';
import 'package:litert_hackathon/utils/result.dart';

/// The app's frame-source factory: which source each spec opens.
void main() {
  FrameSource sourceFor(FrameSourceSpec spec) =>
      switch (createFrameSource(spec)) {
        Ok(:final value) => value,
        Error(:final error) => fail('$spec: $error'),
      };

  test('the device camera spec opens the camera source', () {
    expect(sourceFor(const CameraSourceSpec()), isA<CameraFrameSource>());
  });

  test('a fixture spec opens the slideshow', () {
    expect(
      sourceFor(const FixtureSourceSpec(['/fixtures'], mirrored: true)),
      isA<FixtureFrameSource>(),
    );
  });

  test('a network spec opens the MJPEG source for its URL', () async {
    final source = sourceFor(
      NetworkSourceSpec(Uri.parse('http://192.168.1.23:8080/video')),
    );
    expect(
      source,
      isA<NetworkFrameSource>().having(
        (s) => s.label,
        'label',
        'Network camera · 192.168.1.23:8080',
      ),
    );
    await source.stop();
  });

  test('every spec gets a new source (sources are single-use)', () {
    const spec = CameraSourceSpec();
    expect(sourceFor(spec), isNot(same(sourceFor(spec))));
  });
}
