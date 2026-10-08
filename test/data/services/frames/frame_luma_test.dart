import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/live_camera_config.dart';
import 'package:litert_hackathon/data/services/frames/frame_source.dart';
import 'package:litert_hackathon/domain/models/frame_source_info.dart';

import '../../../support/frames.dart';

/// An NV21 frame whose Y plane is [y] at each pixel.
TestFrame nv21(int Function(int x, int y) y, {int width = 640, int h = 480}) {
  final bytes = Uint8List(width * h * 3 ~/ 2);
  for (var row = 0; row < h; row++) {
    for (var x = 0; x < width; x++) {
      bytes[row * width + x] = y(x, row);
    }
  }
  return TestFrame(width, h, FramePixelFormat.nv21, 90, [
    FramePlane(bytes: bytes, bytesPerRow: width, bytesPerPixel: 1),
  ]);
}

bool black(FrameView frame) {
  final s = lumaStats(frame);
  return s.mean < kBlackFrameLuma && s.spread < kBlackFrameSpread;
}

void main() {
  test('limited-range video black (Y 16) with sensor noise is a black frame '
      '(a Test Lab rack camera in a dark box)', () {
    final frame = nv21((x, y) => 16 + (x * 7 + y * 13) % 5);
    final s = lumaStats(frame);
    expect(s.mean, closeTo(18, 1));
    expect(s.spread, lessThan(2));
    expect(black(frame), isTrue);
  });

  test('zeros (macOS camera access attributed to the terminal) are black', () {
    expect(black(TestFrame.rgba()), isTrue);
  });

  test('a dim scene with edges is not black, nor a lit one', () {
    final dim = nv21((x, y) => x ~/ 32 % 2 == 0 ? 4 : 30);
    expect(lumaStats(dim).mean, lessThan(kBlackFrameLuma));
    expect(black(dim), isFalse, reason: 'its edges spread the luma');
    expect(black(TestFrame.rgba(fill: 128)), isFalse);
  });
}
