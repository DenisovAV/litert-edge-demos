import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/data/repositories/live_detection_repository.dart';
import 'package:litert_hackathon/domain/models/frame_source_spec.dart';
import 'package:litert_hackathon/domain/models/live_state.dart';
import 'package:litert_hackathon/domain/use_cases/gpu_arbiter.dart';
import 'package:litert_hackathon/utils/result.dart';

import '../../fakes/fake_detector.dart';
import '../../fakes/fake_frame_source.dart';

void main() {
  late ValueNotifier<bool> generating;
  late FakeFrameSource source;
  late LiveDetectionRepository live;

  setUp(() {
    generating = ValueNotifier(false);
    source = FakeFrameSource();
    live = LiveDetectionRepository(
      detector: FakeDetector(autoComplete: true),
      createSource: (_) => Result.ok(source),
    );
  });

  tearDown(() async {
    await live.close();
    generating.dispose();
  });

  test('pauses detection while the chat model generates, naming it, and '
      'resumes after', () async {
    final arbiter = GpuArbiter(
      llmBusy: generating,
      setDetectorDuty: live.setDuty,
      duringGeneration: DetectorDuty.paused,
      chatModelName: () => 'Gemma 4 E2B',
    );
    addTearDown(arbiter.dispose);
    await live.start(const FixtureSourceSpec(['/x']), owner: Object());
    expect(live.state.value, isA<LiveRunning>());

    generating.value = true;
    final paused = live.state.value;
    expect(paused, isA<LivePaused>());
    expect((paused as LivePaused).reason, 'Gemma 4 E2B');
    expect(live.duty, DetectorDuty.paused);

    generating.value = false;
    expect(live.state.value, isA<LiveRunning>());
    expect(live.duty, DetectorDuty.live);
  });

  test('without a name the pause says "the chat model"', () async {
    final arbiter = GpuArbiter(
      llmBusy: generating,
      setDetectorDuty: live.setDuty,
      duringGeneration: DetectorDuty.paused,
      chatModelName: () => null,
    );
    addTearDown(arbiter.dispose);
    await live.start(const FixtureSourceSpec(['/x']), owner: Object());

    generating.value = true;

    expect((live.state.value as LivePaused).reason, 'the chat model');
  });

  test('a generation already running when the arbiter is created pauses at '
      'once; after dispose it no longer reacts', () {
    generating.value = true;
    final arbiter = GpuArbiter(
      llmBusy: generating,
      setDetectorDuty: live.setDuty,
      duringGeneration: DetectorDuty.paused,
    );
    expect(live.duty, DetectorDuty.paused);

    arbiter.dispose();
    generating.value = false;
    expect(live.duty, DetectorDuty.paused, reason: 'detached');
  });

  test('duringGeneration: live keeps detecting (the measurement mode)', () {
    final arbiter = GpuArbiter(
      llmBusy: generating,
      setDetectorDuty: live.setDuty,
      duringGeneration: DetectorDuty.live,
    );
    addTearDown(arbiter.dispose);

    generating.value = true;

    expect(live.duty, DetectorDuty.live);
  });
}
