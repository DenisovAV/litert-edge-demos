// Whisper base int8 vs moonshine-tiny f32 (flutter_gemma_speech 0.5.2), in
// profile mode: load + warm-up, STT latency on the same clips (5 runs each),
// RSS deltas, the cost of switching the (singleton) STT model through the
// app's SttService — including whether the switch-back to Whisper needs its
// warm-up — a strict GPU attempt for each, and moonshine on the
// router-golden clips.
//
//   fvm dart run tool/make_router_audio.dart            # build/router_audio
//   fvm flutter run --profile -d macos -t tool/stt_compare_bench.dart \
//     --dart-define=ROUTER_AUDIO_DIR=$PWD/build/router_audio \
//     --dart-define=LONG_CLIP=$PWD/build/moonshine/long_q.pcm
//
// Prints `STTB …` lines and exits. The first run downloads moonshine-tiny
// (~111 MB).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart' hide ModelSpec;
import 'package:litert_hackathon/config/bootstrap.dart';
import 'package:litert_hackathon/config/model_catalog.dart';
import 'package:litert_hackathon/data/services/speech/stt_service.dart';
import 'package:litert_hackathon/domain/models/model_id.dart';
import 'package:litert_hackathon/domain/models/route_decision.dart';
import 'package:litert_hackathon/domain/use_cases/question_router.dart';
import 'package:litert_hackathon/domain/vision/coco_vocabulary.dart';
import 'package:litert_hackathon/utils/result.dart';

import '../integration_test/support/wav.dart';
import 'speech_bench.dart' show benchSttSource;

const kRouterAudioDir = String.fromEnvironment('ROUTER_AUDIO_DIR');
const kLongClip = String.fromEnvironment('LONG_CLIP');

SttConfig onGpu(SttConfig c) => SttConfig(
  type: c.type,
  language: c.language,
  backend: PreferredBackend.gpu,
  sampleRate: c.sampleRate,
  window: c.window,
);

void log(String line) => stdout.writeln('STTB $line');

int rssMb() => ProcessInfo.currentRss ~/ (1 << 20);

T ok<T>(Result<T> result, String what) => switch (result) {
  Ok(:final value) => value,
  Error(:final error) => throw StateError('$what failed: $error'),
};

/// install (restores the active spec; downloads only the first time) + load
/// + warm-up of [id] on [stt], timed separately, with the RSS before and
/// after.
Future<void> bring(SttService stt, String name, ModelId id) async {
  final rss0 = rssMb();
  final watch = Stopwatch()..start();
  final source = await benchSttSource(id);
  ok(
    await stt.install(id, source: source, onProgress: (_) {}),
    '$name install',
  );
  final install = watch.elapsedMilliseconds;
  final load = ok(await stt.load(id), '$name load').inMilliseconds;
  final warm = ok(await stt.warmUp(), '$name warm-up').inMilliseconds;
  log(
    '$name ${stt.configOf(id).backend.name} install=${install}ms '
    'load=${load}ms warm=${warm}ms total=${watch.elapsedMilliseconds}ms '
    'rss_before=${rss0}MB rss_after=${rssMb()}MB',
  );
}

Future<void> clips(
  String name,
  SttService stt,
  Map<String, Uint8List> all,
) async {
  for (final MapEntry(key: clip, value: pcm) in all.entries) {
    final times = <int>[];
    var text = '';
    for (var i = 0; i < 5; i++) {
      final watch = Stopwatch()..start();
      text = await stt.transcribe(pcm);
      times.add(watch.elapsedMilliseconds);
    }
    final sorted = [...times]..sort();
    log(
      '$name clip=$clip audio=${pcm.length ~/ 32}ms stt=$times '
      'median=${sorted[2]}ms text="${text.trim()}"',
    );
  }
}

/// A demo switch through `SttService.activate`, then the first three
/// transcriptions of [pcm]: does the first one pay for the skipped warm-up?
Future<void> switchTo(
  SttService stt,
  String label,
  ModelId id,
  Uint8List pcm, {
  required bool warmUp,
}) async {
  final watch = Stopwatch()..start();
  final active = ok(await stt.activate(id, warmUp: warmUp), 'switch $label');
  final switched = watch.elapsedMilliseconds;
  final times = <int>[];
  for (var i = 0; i < 3; i++) {
    final one = Stopwatch()..start();
    await stt.transcribe(pcm);
    times.add(one.elapsedMilliseconds);
  }
  log(
    'switch $label warm_up=$warmUp switch=${switched}ms '
    '(load ${active.loadTime.inMilliseconds}ms, warm '
    '${active.warmUpTime?.inMilliseconds ?? '–'}ms) '
    'first_stt=${times.first}ms next=${times.sublist(1)}ms '
    'switch+first=${switched + times.first}ms',
  );
}

Future<void> router(String name, SttService stt) async {
  if (kRouterAudioDir.isEmpty) return;
  final dir = Directory(kRouterAudioDir);
  final doc = jsonDecode(
    File('${dir.path}/index.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final items = (doc['items']! as List<Object?>).cast<Map<String, Object?>>();
  const router = QuestionRouter();
  final misses = <String>[];
  var mustTotal = 0;
  var mustRight = 0;
  var sttTotal = 0;
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final pcm = File('${dir.path}/$i.pcm').readAsBytesSync();
    final watch = Stopwatch()..start();
    final heard = await stt.transcribe(pcm);
    sttTotal += watch.elapsedMilliseconds;
    final route = router.classify(heard);
    final right = switch ((item['route'], route)) {
      ('fast', FastRoute(:final intent, :final cls)) =>
        intent.name == item['intent'] &&
            (item['class'] == null ||
                cls == kCocoNames.indexOf(item['class']! as String)),
      ('detailed', DetailedRoute()) => true,
      _ => false,
    };
    if (!right) {
      misses.add(
        '"${(item['q']! as String).trim()}" heard "${heard.trim()}" → $route',
      );
    }
    if (item['must'] == true) {
      mustTotal++;
      if (right) mustRight++;
    }
  }
  final correct = items.length - misses.length;
  log(
    '$name ROUTER_REAL golden=${items.length} correct=$correct '
    'accuracy=${(100 * correct / items.length).toStringAsFixed(1)}% '
    'must_detailed=$mustRight/$mustTotal '
    'stt_mean=${sttTotal ~/ items.length}ms'
    '${misses.isEmpty ? '' : '\n  ${misses.join('\n  ')}'}',
  );
}

/// A strict GPU load (the request is the only accelerator), then the same
/// clips; or the error LiteRT gives.
Future<void> gpuAttempt(
  String name,
  ModelId id,
  Map<String, Uint8List> all,
) async {
  final stt = SttService(configs: {id: onGpu(kSttConfigs[id]!)});
  try {
    await bring(stt, '$name-gpu', id);
    await clips('$name-gpu', stt, all);
  } catch (e) {
    log('$name-gpu FAILED: ${'$e'.split('\n').first}');
  } finally {
    await stt.close();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initEdgeAi();
  log('start rss=${rssMb()}MB');
  Future<Uint8List> asset(String path) async =>
      (await rootBundle.load(path)).buffer.asUint8List();
  final wav = await asset('test_assets/q_cats.wav');
  final question = pcm16FromWav(wav); // walks the chunks: any header size
  final all = <String, Uint8List>{
    'q_cats': question,
    'france': await asset('test_assets/france_16k.pcm'),
    if (kLongClip.isNotEmpty) 'long': File(kLongClip).readAsBytesSync(),
  };

  // The app's order: Whisper (Demo 1) then moonshine (Demo 3) at setup.
  final stt = SttService();
  await bring(stt, 'whisper', ModelId.whisperBase);
  await clips('whisper', stt, all);
  await bring(stt, 'moonshine', ModelId.moonshineTiny);
  await clips('moonshine', stt, all);
  await router('moonshine', stt);

  // Demo switches as the view models run them (SttService.activate).
  await switchTo(
    stt,
    'moonshine→whisper',
    ModelId.whisperBase,
    question,
    warmUp: false,
  );
  await switchTo(
    stt,
    'whisper→moonshine',
    ModelId.moonshineTiny,
    question,
    warmUp: false,
  );
  await switchTo(
    stt,
    'moonshine→whisper',
    ModelId.whisperBase,
    question,
    warmUp: true,
  );
  await switchTo(
    stt,
    'whisper→moonshine',
    ModelId.moonshineTiny,
    question,
    warmUp: true,
  );
  await switchTo(
    stt,
    'moonshine→whisper',
    ModelId.whisperBase,
    question,
    warmUp: false,
  );
  await stt.close();

  // Strict GPU for each (the singleton is closed to change the backend).
  await gpuAttempt('whisper', ModelId.whisperBase, all);
  await gpuAttempt('moonshine', ModelId.moonshineTiny, all);

  log('end rss=${rssMb()}MB');
  exit(0);
}
