import 'dart:typed_data';

import 'package:litert_hackathon/domain/models/detection.dart';

/// A detected 640×480 frame with [boxes] as (class, score), sorted by score
/// like the detector's output.
DetectionFrame detections(int frameId, [List<(int, double)> boxes = const []]) {
  final sorted = [...boxes]..sort((a, b) => b.$2.compareTo(a.$2));
  return DetectionFrame(
    frameId: frameId,
    width: 640,
    height: 480,
    boxes: Float32List.fromList([
      for (final (cls, score) in sorted) ...[
        10,
        20,
        110,
        220,
        score,
        cls.toDouble(),
      ],
    ]),
    preMicros: 1000,
    runMicros: 4000,
    postMicros: 1000,
    backend: DetectorBackend.gpu,
  );
}
