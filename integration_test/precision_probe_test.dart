// Gemma's GPU activations, float16 (the engine default) vs float32
// (macOS). Run once per value; nothing in the app changes by default.
//
//   fvm flutter test integration_test/precision_probe_test.dart -d macos \
//     --dart-define=GEMMA_MODEL_PATH=$HOME/Work/gemma-4-E2B-it.litertlm \
//     --dart-define=DETECTOR_MODEL_PATH=$HOME/Work/models/yolo26n/fp16/yolo26n_fp16_rawhead.tflite \
//     --dart-define=EMBEDDING_MODEL_DIR=$HOME/Work/models/embeddinggemma \
//     --dart-define=SHOWCASE_DIR=$PWD/test_assets/showcase \
//     --dart-define=GEMMA_ACTIVATION=fp32        # or fp16
//
// In order, in one process: a voice turn (first audio), an on-topic
// knowledge-base turn (TTFT), a first photo (TTFT), the number-copy golden
// (5 knowledge-base questions whose answers hold numbers, 2 runs, a fresh
// conversation each; a reply passes when it has the key number and no number
// outside the question's allowed set, e.g. "[1, 3,6400,640]" fails), then a
// Demo 3 detailed turn (TTFT). Prints `PREC …` lines, and `PREC pid=…` with a
// 20 s pause so a shell can sample the process's GPU memory (vmmap).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/app.dart';
import 'package:litert_hackathon/config/demos.dart';
import 'package:litert_hackathon/config/dependencies.dart';
import 'package:litert_hackathon/config/env.dart';
import 'package:litert_hackathon/domain/models/chat_entry.dart';
import 'package:litert_hackathon/domain/models/frame_source_spec.dart';
import 'package:litert_hackathon/domain/models/knowledge.dart';
import 'package:litert_hackathon/domain/models/live_state.dart';
import 'package:litert_hackathon/domain/models/model_id.dart';
import 'package:litert_hackathon/domain/models/model_state.dart';
import 'package:litert_hackathon/domain/models/voice.dart';
import 'package:litert_hackathon/ui/features/home/views/home_screen.dart';
import 'package:litert_hackathon/ui/features/live_camera/view_models/live_camera_view_model.dart';
import 'package:litert_hackathon/ui/features/live_camera/views/live_camera_screen.dart';
import 'package:litert_hackathon/ui/features/voice_chat/view_models/voice_chat_view_model.dart';
import 'package:litert_hackathon/ui/features/voice_chat/views/chat_keys.dart';
import 'package:litert_hackathon/ui/features/voice_chat/views/voice_chat_screen.dart';
import 'package:litert_hackathon/utils/pcm.dart';
import 'package:litert_hackathon/utils/result.dart';
import 'package:provider/provider.dart';

import 'support/app_window.dart';
import 'support/demo3_settings.dart';
import 'support/fixtures.dart';
import 'support/pump.dart';
import 'support/wav.dart';

const kShowcaseDir = String.fromEnvironment('SHOWCASE_DIR');

/// Question, the numbers of which one must appear, the numbers allowed in
/// the reply (a correct alternative fact, e.g. the RTF 0.064 instead of
/// 317.7 ms, or "32-bit offsets", is not a copying error).
const _numberGolden = [
  (
    'What is the input shape of the YOLO 26 nano detector?',
    '640',
    {'1', '3', '640', '26', '16', '32'},
  ),
  (
    'How many dimensions does EmbeddingGemma produce?',
    '768',
    {'768', '512', '256', '128', '300', '3'},
  ),
  (
    'What is the maximum audio length for Gemma 4 E2B?',
    '30',
    {'30', '4', '2', '12', '60', '1'},
  ),
  (
    'How long does Inflect Nano take on a Raspberry Pi 5 with int8 weights?',
    '317.7|0.064',
    {'317.7', '5', '8', '0.064', '495.3', '0.099', '32', '2'},
  ),
  ('What is the size limit of a FlatBuffer model file in LiteRT?', '2', {'2'}),
];

String ms(Duration? d) => d == null ? '–' : '${d.inMilliseconds}';

void main() {
  initIntegrationTest();

  testWidgets('precision probe', (tester) async {
    if (kGemmaModelPath.isEmpty || kShowcaseDir.isEmpty) {
      fail(
        'Pass GEMMA_MODEL_PATH, DETECTOR_MODEL_PATH, EMBEDDING_MODEL_DIR, '
        'SHOWCASE_DIR (and GEMMA_ACTIVATION)',
      );
    }
    final act = kGemmaActivation.isEmpty ? 'default' : kGemmaActivation;
    final france = (await rootBundle.load('test_assets/france_16k.pcm')).buffer
        .asUint8List();
    final mic = FixtureMicService(france);
    final bear = await File('$kShowcaseDir/coco_285_bear.jpg').readAsBytes();
    await resetDemo3Settings();
    final deps = await AppDependencies.create(
      mic: mic,
      imageInput: FixtureImageInputService(bear),
      frameSource: const Result.ok(
        FixtureSourceSpec(['$kShowcaseDir/sign_wifi.jpg']),
      ),
    );
    await tester.pumpWidget(App(dependencies: deps));
    await pumpUntil(
      tester,
      () => find.byType(HomeScreen).evaluate().isNotEmpty,
      timeout: const Duration(minutes: 12),
      reason: 'model setup',
    );
    await pumpUntil(
      tester,
      () => deps.knowledge.status.value is KnowledgeReady,
      timeout: const Duration(minutes: 3),
      reason: 'the knowledge base',
    );
    if (deps.models.states.value[ModelId.chat] case ModelReady(:final info)) {
      debugPrint(
        'PREC act=$act load=${ms(info.loadTime)}ms warm=${ms(info.warmUpTime)}ms '
        'backend=${info.backend}',
      );
    }

    // Demo 1.
    await tester.tap(find.byKey(HomeKeys.tile(Demo.voiceChat)));
    await pumpUntil(
      tester,
      () => find.byType(VoiceChatScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 5),
      reason: 'Demo 1',
    );
    final vm = Provider.of<VoiceChatViewModel>(
      tester.element(find.byType(VoiceChatScreen)),
      listen: false,
    );
    await pumpUntil(
      tester,
      () => vm.isReady && vm.hasSkills,
      timeout: const Duration(seconds: 30),
      reason: 'the chat',
    );
    await pumpFor(tester, const Duration(seconds: 1));

    // 1. A voice turn: first audio after release.
    final turn = vm.submitUtterance(
      Utterance(pcm: france, held: pcm16Duration(france.length, 16000)),
    );
    await pumpUntil(
      tester,
      () => vm.phase == TurnPhase.idle && vm.entries.length >= 2,
      timeout: const Duration(seconds: 60),
      reason: 'the voice turn',
    );
    await turn;
    final voice = deps.diagnostics.latest.lastVoiceTurn;
    debugPrint(
      'PREC act=$act voice first_audio=${ms(voice?.firstAudio)}ms '
      'stt=${ms(voice?.stt)}ms ttft=${ms(deps.diagnostics.latest.lastGeneration?.timeToFirstToken)}ms '
      'reply="${vm.entries.last.text}"',
    );
    vm.setSpeakReplies(enabled: false);

    Future<ChatEntry> ask(String prompt) async {
      final before = vm.entries.length;
      await tester.tap(find.byKey(ChatKeys.input));
      await tester.pump();
      await tester.enterText(find.byKey(ChatKeys.input), prompt);
      await tester.pump();
      await tester.tap(find.byKey(ChatKeys.send));
      await pumpUntil(
        tester,
        () => vm.entries.length > before,
        timeout: const Duration(seconds: 10),
        reason: 'the turn to start',
      );
      await pumpUntil(
        tester,
        () => !vm.send.running && vm.phase == TurnPhase.idle,
        timeout: const Duration(seconds: 120),
        reason: 'the reply',
      );
      await pumpFor(tester, const Duration(milliseconds: 200));
      return vm.entries.lastWhere(
        (e) => e.role == ChatRole.assistant || e.role == ChatRole.error,
      );
    }

    Future<void> fresh() async {
      await vm.newConversation.execute();
      await pumpFor(tester, const Duration(milliseconds: 300));
    }

    // 2. An on-topic knowledge-base turn.
    await fresh();
    final rag = await ask(
      'What is LiteRT, and how is it related to TensorFlow Lite?',
    );
    debugPrint(
      'PREC act=$act rag ttft=${ms(deps.diagnostics.latest.lastGeneration?.timeToFirstToken)}ms '
      'steps=${rag.steps.length} cited=${rag.knowledge?.cited}',
    );

    // 3. A first photo.
    await fresh();
    await tester.tap(find.byKey(ChatKeys.attachGallery));
    await pumpUntil(
      tester,
      () => vm.attachment != null,
      timeout: const Duration(seconds: 10),
      reason: 'the photo',
    );
    final photo = await ask("What's going on in this picture?");
    debugPrint(
      'PREC act=$act image ttft=${ms(deps.diagnostics.latest.lastGeneration?.timeToFirstToken)}ms '
      'reply="${photo.text.replaceAll('\n', ' ')}"',
    );

    // 4. The number-copy golden.
    var passed = 0;
    var total = 0;
    for (var run = 1; run <= 2; run++) {
      for (final (question, key, allowed) in _numberGolden) {
        await fresh();
        final reply = await ask(question);
        // Citation markers ([1]…[3]) are not numbers the model copied.
        final text = reply.text.replaceAll(RegExp(r'\[[1-3]\]'), '');
        final inQuestion = {
          for (final m in RegExp(r'\d+(?:\.\d+)?').allMatches(question)) m[0]!,
        };
        final numbers = [
          for (final m in RegExp(r'\d+(?:\.\d+)?').allMatches(text)) m[0]!,
        ];
        final stray = [
          for (final n in numbers)
            if (!allowed.contains(n) && !inQuestion.contains(n)) n,
        ];
        final ok = key.split('|').any(numbers.contains) && stray.isEmpty;
        total++;
        if (ok) passed++;
        debugPrint(
          'PREC act=$act golden run=$run ok=$ok key=$key stray=$stray '
          'q="$question" a="${reply.text.replaceAll('\n', ' ')}"',
        );
      }
    }
    debugPrint('PREC act=$act golden=$passed/$total');

    // 5. Demo 3: a detailed turn on the sign.
    await tester.pageBack();
    await pumpUntil(
      tester,
      () => find.byType(VoiceChatScreen).evaluate().isEmpty,
      timeout: const Duration(seconds: 5),
      reason: 'back home',
    );
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.byKey(HomeKeys.tile(Demo.liveCamera)));
    await pumpUntil(
      tester,
      () => find.byType(LiveCameraScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 5),
      reason: 'Demo 3',
    );
    final cam = Provider.of<LiveCameraViewModel>(
      tester.element(find.byType(LiveCameraScreen)),
      listen: false,
    );
    await pumpUntil(
      tester,
      () => cam.chatReady && deps.live.state.value is LiveRunning,
      timeout: const Duration(seconds: 20),
      reason: 'the camera chat and the live view',
    );
    await pumpFor(tester, const Duration(seconds: 2));
    mic.pcm = pcm16FromWav(
      await File('$kShowcaseDir/q_sign.wav').readAsBytes(),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(LiveCameraKeys.mic)),
    );
    await pumpUntil(
      tester,
      () => cam.isListening,
      timeout: const Duration(seconds: 3),
      reason: 'the mic',
    );
    await pumpFor(
      tester,
      pcm16Duration(mic.pcm.length, 16000) + const Duration(milliseconds: 550),
    );
    await gesture.up();
    await pumpUntil(
      tester,
      () => cam.phase == TurnPhase.idle && cam.exchange.answer != null,
      timeout: const Duration(seconds: 60),
      reason: 'the detailed answer',
    );
    debugPrint(
      'PREC act=$act detailed ttft=${ms(deps.diagnostics.latest.lastGeneration?.timeToFirstToken)}ms '
      'first_audio=${ms(deps.diagnostics.latest.lastVoiceTurn?.firstAudio)}ms '
      'q="${cam.exchange.question}" a="${cam.exchange.answer}"',
    );

    final mem = deps.diagnostics.latest;
    debugPrint(
      'PREC act=$act rss=${(mem.rssBytes ?? 0) >> 20}MB '
      'peak=${(mem.peakRssBytes ?? 0) >> 20}MB',
    );
    debugPrint('PREC pid=$pid sample-now');
    await pumpFor(tester, const Duration(seconds: 20));

    await tester.pumpWidget(const SizedBox.shrink());
    await deps.dispose();
  }, timeout: const Timeout(Duration(minutes: 25)));
}
