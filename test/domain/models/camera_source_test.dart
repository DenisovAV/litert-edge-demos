import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/domain/models/camera_source.dart';
import 'package:litert_hackathon/utils/result.dart';

String errorOf(Result<Uri> result) => switch (result) {
  Ok(:final value) => fail('expected an error, got $value'),
  Error(:final error) => error.toString(),
};

void main() {
  group('parseNetworkCameraUrl', () {
    test('an IP Webcam URL', () {
      final uri = (parseNetworkCameraUrl(
        ' http://192.168.1.23:8080/video ',
      ) as Ok<Uri>).value;
      expect((uri.host, uri.port, uri.path), ('192.168.1.23', 8080, '/video'));
    });

    test('a missing scheme means http://', () {
      final uri =
          (parseNetworkCameraUrl('192.168.1.23:8080/video') as Ok<Uri>).value;
      expect(uri.toString(), 'http://192.168.1.23:8080/video');
    });

    test("the example's placeholders must be replaced", () {
      expect(
        errorOf(parseNetworkCameraUrl(kNetworkCameraUrlExample)),
        contains('Replace 192.168.x.x'),
      );
    });

    test('empty, not http, not a URL', () {
      expect(errorOf(parseNetworkCameraUrl('  ')), contains('Enter'));
      expect(
        errorOf(parseNetworkCameraUrl('rtsp://192.168.1.23:8554/live')),
        contains('starts with http://'),
      );
      expect(errorOf(parseNetworkCameraUrl('http://')), contains('not a URL'));
    });
  });

  test('the label shows host and port, never the path or a password', () {
    expect(
      networkCameraLabel(Uri.parse('http://user:pw@192.168.1.23:8080/video')),
      'Network camera · 192.168.1.23:8080',
    );
    expect(
      networkCameraLabel(Uri.parse('http://cam.local/video')),
      'Network camera · cam.local:80',
    );
  });

  test('CameraSourceKind round-trips its persisted name', () {
    for (final kind in CameraSourceKind.values) {
      expect(CameraSourceKind.tryParse(kind.name), kind);
    }
    expect(CameraSourceKind.tryParse('webcam'), isNull);
  });
}
