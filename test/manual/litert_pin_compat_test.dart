// Manual probe: does flutter_litert's CompiledModel binding work on the LiteRT
// build in the LiteRT-LM native bundle (which flutter_edge_ai_litertlm
// downloads)? On Linux that is the copy the app actually loads (the bundle's
// libLiteRt.so overwrites flutter_litert's in bundle/lib,
// docs/design/linux-build.md B1). On macOS the bundle's libLiteRtLm.dylib
// exports the same C API from the same LiteRT pin, so the binding can be
// exercised on the host:
//
//   LITERT_LIB_PATH=$HOME/Library/Caches/flutter_gemma/native/macos_arm64/libLiteRtLm.dylib \
//   DETECTOR_MODEL_FILE=$HOME/Work/models/yolo26n/fp16/yolo26n_fp16_rawhead.tflite \
//   fvm flutter test test/manual/litert_pin_compat_test.dart
//
// PROBE_GPU=0 skips the GPU half: on the macOS host the bundle's Metal
// accelerator is only found inside an app bundle's Frameworks directory.
// Skipped unless both variables are set.

// A manual probe: what it prints is its result, read by hand.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_litert/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/data/services/detector/detector_engine.dart';
import 'package:litert_hackathon/data/services/detector/detector_verification.dart';
import 'package:litert_hackathon/domain/models/detection.dart';
import 'package:litert_hackathon/domain/models/detector_spec.dart';

void main() {
  final lib = Platform.environment['LITERT_LIB_PATH'];
  final modelPath = Platform.environment['DETECTOR_MODEL_FILE'];
  final skip = lib == null || modelPath == null
      ? 'set LITERT_LIB_PATH and DETECTOR_MODEL_FILE'
      : null;

  test(
    'YOLO26n raw head on the given LiteRT: builds, runs, GPU agrees with CPU',
    () {
      final bytes = File(modelPath!).readAsBytesSync();
      final input = Float32List(3 * kDetInput * kDetInput);
      for (var i = 0; i < input.length; i++) {
        input[i] = (i % 251) / 251.0;
      }

      Float32List runOn(Set<Accelerator> accelerators) {
        final model = CompiledModel.fromBuffer(
          bytes,
          accelerators: accelerators,
          precision: Precision.fp32,
          tensorBufferMode: TensorBufferMode.managed,
        );
        try {
          print(
            '$accelerators → accelerators=${model.accelerators} '
            'didFallback=${model.didFallback} '
            'fullyAccelerated=${model.isFullyAccelerated} '
            'in=${model.inputByteSizes} out=${model.outputByteSizes}',
          );
          expect(model.inputByteSizes, [kDetInputBytes]);
          expect(model.outputByteSizes, [kDetOutputBytes]);
          if (accelerators.contains(Accelerator.gpu)) {
            expect(model.accelerators, {Accelerator.gpu});
            expect(model.didFallback, isFalse);
            expect(model.isFullyAccelerated, isTrue);
          }
          final watch = Stopwatch()..start();
          final out = model.run([input]).single;
          for (var i = 0; i < 5; i++) {
            model.run([input]);
          }
          print('  6 runs in ${watch.elapsedMilliseconds} ms');
          return Float32List.fromList(out);
        } finally {
          model.close();
        }
      }

      final cpu = runOn(const {Accelerator.cpu});
      // Compare across runtimes by hand: same input, so the CPU outputs of two
      // LiteRT builds should agree to float noise.
      var sum = 0.0;
      var top = <double>[];
      for (final v in cpu) {
        sum += v;
      }
      top = [for (var i = 4; i < cpu.length; i += 84 * 997) cpu[i]];
      print('CPU checksum: sum=$sum samples=${top.take(6).toList()}');
      if (Platform.environment['PROBE_GPU'] == '0') return;
      final gpu = runOn(const {Accelerator.gpu});

      var lo = double.infinity;
      var hi = -double.infinity;
      var dev = 0.0;
      for (var i = 0; i < cpu.length; i++) {
        if (cpu[i] < lo) lo = cpu[i];
        if (cpu[i] > hi) hi = cpu[i];
        final d = (cpu[i] - gpu[i]).abs();
        if (d > dev || d.isNaN) dev = d.isNaN ? double.infinity : d;
      }
      print('GPU vs CPU: max |Δ| $dev over range ${hi - lo}');
      expect(hi - lo, greaterThan(0), reason: 'CPU output is not constant');
      expect(dev, greaterThan(0), reason: 'bit-identical: did the GPU run?');
      expect(dev / (hi - lo), lessThan(0.01));
    },
    skip: skip,
  );

  test('the LiteRT-CPU reference and the full engine load work on it', () {
    final bytes = File(modelPath!).readAsBytesSync();
    final backend = Platform.environment['PROBE_GPU'] == '0'
        ? DetectorBackend.cpu
        : DetectorBackend.gpu;
    final model = const LiteRtDetectorRuntime().create(bytes, {
      backend == DetectorBackend.gpu ? Accelerator.gpu : Accelerator.cpu,
    });
    try {
      final v = verifyAgainstLiteRtCpu(
        bytes,
        model,
        inputFloats: kDetInputBytes ~/ 4,
      );
      print('vs LiteRT CPU: $v');
      expect(v.agrees, isTrue);
    } finally {
      model.close();
    }

    final engine = DetectorEngine.load(
      modelBytes: bytes,
      backend: backend,
      runtime: const LiteRtDetectorRuntime(),
      log: print,
    );
    engine.close();
  }, skip: skip);
}
