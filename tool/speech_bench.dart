// Times the STT (Whisper base by default, moonshine-tiny with
// `--dart-define=STT=moonshine`) on Demo 3's camera question and Inflect
// (TTS) on its answer outside debug mode, where `flutter test` cannot run:
//
//   fvm flutter run --profile -d macos -t tool/speech_bench.dart
//
// Prints `SPEECH_BENCH mode=profile stt=[…]ms tts=[…]ms` and exits. Uses the
// speech models built into the app.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:litert_hackathon/config/bootstrap.dart';
import 'package:litert_hackathon/data/services/model_store/bundled_model_files.dart';
import 'package:litert_hackathon/data/services/speech/stt_service.dart';
import 'package:litert_hackathon/data/services/speech/tts_service.dart';
import 'package:litert_hackathon/domain/models/model_id.dart';
import 'package:litert_hackathon/utils/result.dart';

import '../integration_test/support/wav.dart';

const kStt = String.fromEnvironment('STT', defaultValue: 'whisper');

/// The recognizer's files built into the app.
Future<SttSource> benchSttSource(ModelId id) async {
  final files = kBundledSttFiles[id]!;
  final bundled = BundledModelFiles();
  final model = await bundled.pathOf(files.model);
  final tokenizer = await bundled.pathOf(files.tokenizer);
  return switch ((model, tokenizer)) {
    (Ok(value: final m), Ok(value: final t)) => SttFromFiles(
      modelPath: m,
      tokenizerPath: t,
    ),
    _ => throw StateError('the built-in ${id.name} files: $model $tokenizer'),
  };
}

/// The built-in Inflect bundle's directory.
Future<String> benchTtsDirectory() async =>
    switch (await BundledModelFiles().directoryOf(kBundledInflectFiles)) {
      Ok(:final value) => value,
      Error(:final error) => throw StateError('the built-in Inflect: $error'),
    };

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initEdgeAi();
  final model = kStt == 'moonshine'
      ? ModelId.moonshineTiny
      : ModelId.whisperBase;
  final stt = SttService();
  final tts = TtsService();
  final source = await benchSttSource(model);
  final ttsDirectory = await benchTtsDirectory();
  for (final step in <Future<Result<Object>> Function()>[
    () => stt.install(model, source: source, onProgress: (_) {}),
    () => stt.load(model),
    stt.warmUp,
    () => tts.install(directory: ttsDirectory, onProgress: (_) {}),
    tts.load,
    tts.warmUp,
  ]) {
    if (await step() case Error(:final error)) {
      stdout.writeln('SPEECH_BENCH failed: $error');
      exit(1);
    }
  }
  final wav = (await rootBundle.load('test_assets/q_cats.wav')).buffer
      .asUint8List();
  final pcm = pcm16FromWav(wav); // walks the chunks: any header size
  final sttMs = <int>[];
  String transcript = '';
  for (var i = 0; i < 5; i++) {
    final watch = Stopwatch()..start();
    transcript = await stt.transcribe(pcm);
    sttMs.add(watch.elapsedMilliseconds);
  }
  final ttsMs = <int>[];
  for (var i = 0; i < 5; i++) {
    final watch = Stopwatch()..start();
    await tts.synthesizer.synthesize('I count two cats.');
    ttsMs.add(watch.elapsedMilliseconds);
  }
  final mode = kReleaseMode
      ? 'release'
      : kProfileMode
      ? 'profile'
      : 'debug';
  stdout.writeln(
    'SPEECH_BENCH mode=$mode model=${model.name} stt=$sttMs ms tts=$ttsMs ms '
    'transcript="${transcript.trim()}"',
  );
  await stt.close();
  await tts.close();
  exit(0);
}
