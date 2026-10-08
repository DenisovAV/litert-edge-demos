// Frame-time probe for Demo 3, in profile mode (`flutter test` has no
// --profile, so it runs through `flutter run`; DDS off so the binding can
// reach the VM service for the GC timeline):
//
//   fvm flutter run --profile --no-dds -d macos \
//     -t integration_test/frame_timing_test.dart \
//     --dart-define=GEMMA_MODEL_PATH=$HOME/Work/gemma-4-E2B-it.litertlm \
//     --dart-define=DETECTOR_MODEL_PATH=$HOME/Work/models/yolo26n/fp16/yolo26n_fp16_rawhead.tflite \
//     --dart-define=FRAME_SOURCE=fixture \
//     --dart-define=FIXTURE_DIR=$HOME/Work/models/yolo26n/test_images/coco30
//
// Measures 10 s with live detection and 10 s with detection paused (same
// screen, same source), collecting every FrameTiming (build = UI thread,
// raster) and the VM's GC timeline events. Prints `PERF …` lines and
// `PERF_DONE`; the caller stops `flutter run` afterwards.

import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/app.dart';
import 'package:litert_hackathon/config/demos.dart';
import 'package:litert_hackathon/config/dependencies.dart';
import 'package:litert_hackathon/config/env.dart';
import 'package:litert_hackathon/domain/models/live_state.dart';
import 'package:litert_hackathon/ui/features/home/views/home_screen.dart';
import 'package:litert_hackathon/ui/features/live_camera/views/live_camera_screen.dart';

import 'support/app_window.dart';
import 'support/demo3_settings.dart';
import 'support/pump.dart';

/// One 60 Hz frame: the measured stretches pump at a display's rate.
const _frame = Duration(milliseconds: 16);

String stats(List<double> ms) {
  if (ms.isEmpty) return 'n=0';
  final sorted = [...ms]..sort();
  double at(double q) =>
      sorted[math.min(sorted.length - 1, (q * sorted.length).floor())];
  return 'n=${sorted.length} p50=${at(0.5).toStringAsFixed(2)} '
      'p99=${at(0.99).toStringAsFixed(2)} max=${sorted.last.toStringAsFixed(2)} '
      'over16=${sorted.where((v) => v > 16).length}';
}

void main() {
  final binding = initIntegrationTest();

  testWidgets('Demo 3 frame times, live vs paused detection', (tester) async {
    await resetDemo3Settings();
    final deps = await AppDependencies.create();
    await tester.pumpWidget(App(dependencies: deps));
    await pumpUntil(
      tester,
      () => find.byType(HomeScreen).evaluate().isNotEmpty,
      timeout: const Duration(minutes: 6),
      reason: 'model setup',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(HomeKeys.tile(Demo.liveCamera)));
    await pumpUntil(
      tester,
      () =>
          find.byType(LiveCameraScreen).evaluate().isNotEmpty &&
          deps.live.state.value is LiveRunning,
      timeout: const Duration(seconds: 60),
      reason: 'live detection to run (${deps.live.state.value})',
    );
    await pumpFor(tester, const Duration(seconds: 2), step: _frame); // warm-up

    Future<void> measure(String phase) async {
      final timings = <FrameTiming>[];
      void onTimings(List<FrameTiming> batch) => timings.addAll(batch);
      WidgetsBinding.instance.addTimingsCallback(onTimings);
      final before = deps.live.stats.value.processed;
      final timeline = await binding.traceTimeline(
        () => pumpFor(tester, const Duration(seconds: 10), step: _frame),
        streams: const ['GC'],
      );
      // Let the last timings batch arrive.
      await tester.pump(const Duration(milliseconds: 200));
      WidgetsBinding.instance.removeTimingsCallback(onTimings);
      final processed = deps.live.stats.value.processed - before;

      final threads = <int, String>{};
      final kinds = <String, int>{};
      final gc = <String, List<double>>{};
      final gcThreads = <String>{};
      final open = <String, double>{}; // B/E pairs: "tid/name" -> start µs
      final events = timeline.traceEvents ?? const [];
      for (final event in events) {
        final json = event.json ?? const <String, dynamic>{};
        final key = '${json['cat']}/${json['ph']}';
        kinds[key] = (kinds[key] ?? 0) + 1;
        if (json['ph'] == 'M' && json['name'] == 'thread_name') {
          threads[json['tid'] as int] =
              (json['args'] as Map<String, dynamic>)['name'] as String;
        }
      }
      void addGc(Map<String, dynamic> json, double ms) {
        (gc[json['name'] as String] ??= []).add(ms);
        gcThreads.add(threads[json['tid']] ?? '${json['tid']}');
      }

      for (final event in events) {
        final json = event.json ?? const <String, dynamic>{};
        if (json['cat'] != 'GC') continue;
        final ts = (json['ts'] as num?)?.toDouble() ?? 0;
        final pairKey = '${json['tid']}/${json['name']}';
        switch (json['ph']) {
          case 'X':
            addGc(json, (json['dur'] as num).toDouble() / 1000);
          case 'B':
            open[pairKey] = ts;
          case 'E':
            final start = open.remove(pairKey);
            if (start != null) addGc(json, (ts - start) / 1000);
        }
      }
      debugPrint(
        'PERF phase=$phase timeline_events=${events.length} kinds=$kinds',
      );
      debugPrint(
        'PERF phase=$phase source=$kFrameSource processed=$processed '
        'frames=${timings.length}',
      );
      debugPrint(
        'PERF phase=$phase build_ms ${stats([for (final t in timings) t.buildDuration.inMicroseconds / 1000])}',
      );
      debugPrint(
        'PERF phase=$phase raster_ms ${stats([for (final t in timings) t.rasterDuration.inMicroseconds / 1000])}',
      );
      debugPrint(
        'PERF phase=$phase total_ms ${stats([for (final t in timings) t.totalSpan.inMicroseconds / 1000])}',
      );
      for (final MapEntry(:key, :value) in gc.entries) {
        debugPrint('PERF phase=$phase gc $key ${stats(value)}');
      }
      debugPrint('PERF phase=$phase gc_threads=${gcThreads.join('|')}');
    }

    await measure('live');
    deps.live.setDuty(DetectorDuty.paused, reason: 'perf baseline');
    await pumpFor(tester, const Duration(seconds: 1), step: _frame);
    await measure('paused');
    deps.live.setDuty(DetectorDuty.live);
    debugPrint('PERF_DONE');

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await deps.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
