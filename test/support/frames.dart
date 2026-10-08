import 'dart:typed_data';

import 'package:litert_hackathon/data/services/detector/frame_message.dart';
import 'package:litert_hackathon/data/services/frames/frame_source.dart';
import 'package:litert_hackathon/domain/models/frame_source_info.dart';

/// A [FrameView] over given planes.
final class TestFrame implements FrameView {
  TestFrame(
    this.width,
    this.height,
    this.format,
    this.rotationDeg,
    this.planes,
  );

  /// A 640×480 RGBA frame, like one fixture slide: black, or every byte
  /// [fill] (a grey of luma [fill]).
  factory TestFrame.rgba({int width = 640, int height = 480, int fill = 0}) =>
      TestFrame(width, height, FramePixelFormat.rgba8888, 0, [
        FramePlane(
          bytes: Uint8List(width * height * 4)
            ..fillRange(0, width * height * 4, fill),
          bytesPerRow: width * 4,
          bytesPerPixel: 4,
        ),
      ]);

  @override
  final int width;
  @override
  final int height;
  @override
  final FramePixelFormat format;
  @override
  final int rotationDeg;
  @override
  final List<FramePlane> planes;
}

/// A black 640×480 RGBA frame, copied for the worker.
FrameMessage rgbaFrame({int frameId = 1}) =>
    FrameMessage.copyOf(TestFrame.rgba(), frameId: frameId);
