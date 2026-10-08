import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/ui/features/live_camera/views/live_preview.dart';

import '../../../../fakes/fake_camera_controller.dart';

void main() {
  CameraValue initialized(DeviceOrientation orientation) =>
      const CameraValue.uninitialized(kMacCamera).copyWith(
        isInitialized: true,
        previewSize: const Size(1280, 720),
        deviceOrientation: orientation,
      );

  test('the cover box has the preview\'s upright size, like CameraPreview\'s '
      'aspect ratio: landscape as reported, portrait swapped', () {
    expect(
      uprightPreviewSize(initialized(DeviceOrientation.landscapeLeft)),
      const Size(1280, 720),
    );
    expect(
      uprightPreviewSize(initialized(DeviceOrientation.portraitUp)),
      const Size(720, 1280),
    );
    expect(
      uprightPreviewSize(
        initialized(DeviceOrientation.portraitUp).copyWith(
          lockedCaptureOrientation: const Optional.of(
            DeviceOrientation.landscapeRight,
          ),
        ),
      ),
      const Size(1280, 720),
      reason: 'a locked orientation wins',
    );
    expect(
      uprightPreviewSize(const CameraValue.uninitialized(kMacCamera)),
      isNull,
    );
  });
}
