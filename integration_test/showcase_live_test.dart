// Live showcase with the REAL camera: a person stands in front of the Mac
// while this test drives both demos and saves clean screenshots (debug overlay
// off). Questions are pre-recorded clips fed through the fixture mic; a large
// cue banner above the app (outside the screenshot boundary) tells the person
// what to hold up next.
//
//   fvm flutter test integration_test/showcase_live_test.dart -d macos \
//     --dart-define=GEMMA_MODEL_PATH=$HOME/Work/gemma-4-E2B-it.litertlm \
//     --dart-define=DETECTOR_MODEL_PATH=$HOME/Work/models/yolo26n/fp16/yolo26n_fp16_rawhead.tflite \
//     --dart-define=EMBEDDING_MODEL_DIR=$HOME/Work/models/embeddinggemma \
//     --dart-define=SHOWCASE_AUDIO_DIR=$PWD/build/live-shots/q
//
// Clips: what.wav, people.wav, cup.wav, sign.wav, holding.wav, wearing.wav
// (16 kHz mono WAV, e.g. `say -o x.aiff "…" && afconvert -f WAVE -d
// LEI16@16000 -c 1 x.aiff x.wav`). Screenshots land in the app container's
// tmp/ as live_*.png. Nothing is asserted about the answers: it's a showcase,
// and a wait that times out moves on (`tryPumpUntil`) instead of failing.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/app.dart';
import 'package:litert_hackathon/config/demos.dart';
import 'package:litert_hackathon/config/dependencies.dart';
import 'package:litert_hackathon/config/env.dart';
import 'package:litert_hackathon/domain/models/voice.dart';
import 'package:litert_hackathon/ui/core/debug_overlay.dart';
import 'package:litert_hackathon/ui/features/home/views/home_screen.dart';
import 'package:litert_hackathon/ui/features/live_camera/view_models/live_camera_view_model.dart';
import 'package:litert_hackathon/ui/features/live_camera/views/live_camera_screen.dart';
import 'package:litert_hackathon/ui/features/voice_chat/view_models/voice_chat_view_model.dart';
import 'package:litert_hackathon/ui/features/voice_chat/views/chat_keys.dart';
import 'package:litert_hackathon/ui/features/voice_chat/views/voice_chat_screen.dart';
import 'package:litert_hackathon/utils/pcm.dart';
import 'package:provider/provider.dart';

import 'support/app_window.dart';
import 'support/demo3_settings.dart';
import 'support/fixtures.dart';
import 'support/pump.dart';
import 'support/wav.dart';

const kAudioDir = String.fromEnvironment('SHOWCASE_AUDIO_DIR');

final _screenKey = GlobalKey();
final _cue = ValueNotifier<String>('Getting ready…');

Future<void> shot(String name) async {
  final boundary =
      _screenKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return;
  final image = await boundary.toImage(pixelRatio: 2);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (png == null) return;
  final file = File('${Directory.systemTemp.path}/live_$name.png');
  await file.writeAsBytes(png.buffer.asUint8List());
  debugPrint('SHOT ${file.path}');
}

/// Shows [text] in the cue banner and counts down [seconds] on screen.
Future<void> cue(WidgetTester tester, String text, int seconds) async {
  for (var s = seconds; s > 0; s--) {
    _cue.value = '$text   ($s)';
    await pumpFor(tester, const Duration(seconds: 1));
  }
  _cue.value = text;
}

void main() {
  initIntegrationTest();

  testWidgets('live showcase with the real camera', (tester) async {
    if (kAudioDir.isEmpty) fail('Pass SHOWCASE_AUDIO_DIR');
    if (kFrameSource != 'camera') fail('FRAME_SOURCE must be camera');
    Uint8List clip(String name) =>
        pcm16FromWav(File('$kAudioDir/$name.wav').readAsBytesSync());

    final mic = FixtureMicService(clip('what'));
    await resetDemo3Settings();
    final deps = await AppDependencies.create(mic: mic);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            RepaintBoundary(
              key: _screenKey,
              child: App(dependencies: deps),
            ),
            // The cue banner: visible in the window, not in the screenshots.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: ValueListenableBuilder<String>(
                  valueListenable: _cue,
                  builder: (context, text, _) => Container(
                    color: const Color(0xEE6A1B9A),
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    _cue.value = 'Loading models…';
    await tryPumpUntil(
      tester,
      () => find.byType(HomeScreen).evaluate().isNotEmpty,
      timeout: const Duration(minutes: 8),
    );
    await pumpFor(tester, const Duration(milliseconds: 500));
    // Clean screenshots: hide the debug overlay.
    if (find.byKey(DebugOverlayKeys.panel).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(DebugOverlayKeys.toggle).first);
      await pumpFor(tester, const Duration(milliseconds: 400));
    }
    await shot('00_home');

    // ---------------- Demo 3: live camera ----------------
    await tester.tap(find.byKey(HomeKeys.tile(Demo.liveCamera)));
    await tryPumpUntil(
      tester,
      () => find.byType(LiveCameraScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
    );
    final cam = Provider.of<LiveCameraViewModel>(
      tester.element(find.byType(LiveCameraScreen)),
      listen: false,
    );
    await cue(tester, 'Stand in front of the camera and wave 👋', 6);

    Future<void> askCamera(String name, String label) async {
      mic.pcm = clip(name);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(LiveCameraKeys.mic)),
      );
      await tryPumpUntil(
        tester,
        () => cam.isListening,
        timeout: const Duration(seconds: 3),
      );
      await pumpFor(
        tester,
        pcm16Duration(mic.pcm.length, 16000) +
            const Duration(milliseconds: 550),
      );
      await gesture.up();
      // A detailed answer is shot while the view is still frozen on the
      // frame it is about: once the answer has been generated and shows in
      // the caption, before playback drains and the view goes live again.
      var shotFrozen = false;
      await tryPumpUntil(tester, () {
        if (!shotFrozen &&
            cam.frozen.value != null &&
            !deps.conversation.isGenerating.value &&
            cam.partialReply.value.isNotEmpty) {
          shotFrozen = true;
          return true;
        }
        return cam.phase == TurnPhase.idle && cam.exchange.answer != null;
      }, timeout: const Duration(seconds: 60));
      if (shotFrozen) {
        await pumpFor(tester, const Duration(milliseconds: 300));
        debugPrint(
          'LIVE q=${cam.exchange.question} a=${cam.partialReply.value} '
          '(frozen)',
        );
        await shot(label);
        await tryPumpUntil(
          tester,
          () => cam.phase == TurnPhase.idle && cam.exchange.answer != null,
          timeout: const Duration(seconds: 60),
        );
        return;
      }
      await pumpFor(tester, const Duration(milliseconds: 900));
      debugPrint('LIVE q=${cam.exchange.question} a=${cam.exchange.answer}');
      await shot(label);
    }

    await askCamera('what', '01_what_do_you_see');
    await cue(tester, 'Stay in frame — next: how many people', 4);
    await askCamera('people', '02_how_many_people');
    await cue(tester, 'Hold up a CUP ☕', 7);
    await askCamera('cup', '03_is_there_a_cup');
    await cue(tester, 'Hold up your SIGN 📝 close to the camera', 9);
    await askCamera('sign', '04_what_does_the_sign_say');
    await cue(tester, 'Hold any object in your hand ✋', 7);
    await askCamera('holding', '05_what_am_i_holding');
    await cue(tester, 'Stand back so your clothes are visible 👕', 6);
    await askCamera('wearing', '06_what_am_i_wearing');

    // ---------------- Demo 1: voice chat + skills ----------------
    await tester.pageBack();
    await tryPumpUntil(
      tester,
      () => find.byType(HomeScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(HomeKeys.tile(Demo.voiceChat)));
    await tryPumpUntil(
      tester,
      () => find.byType(VoiceChatScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
    );
    final chat = Provider.of<VoiceChatViewModel>(
      tester.element(find.byType(VoiceChatScreen)),
      listen: false,
    );
    await tryPumpUntil(
      tester,
      () => chat.isReady,
      timeout: const Duration(seconds: 30),
    );

    Future<void> type(String prompt, String label) async {
      final before = chat.entries.length;
      await tester.tap(find.byKey(ChatKeys.input));
      await tester.pump();
      await tester.enterText(find.byKey(ChatKeys.input), prompt);
      await tester.pump();
      await tester.tap(find.byKey(ChatKeys.send));
      await tryPumpUntil(
        tester,
        () => chat.entries.length > before,
        timeout: const Duration(seconds: 10),
      );
      await tryPumpUntil(
        tester,
        () => !chat.send.running && chat.phase == TurnPhase.idle,
        timeout: const Duration(seconds: 120),
      );
      await pumpFor(tester, const Duration(milliseconds: 900));
      final last = chat.entries.isEmpty ? null : chat.entries.last;
      debugPrint('CHAT q="$prompt" a="${last?.text}" steps=${last?.steps}');
      await shot(label);
    }

    await type('What time is it?', '07_time');
    await type('Which accelerator is running right now?', '12_device_info');
    await type(
      'What is the input size of the YOLO 26 nano detector?',
      '13_knowledge_base',
    );
    _cue.value = 'Done — thank you! 🎉';
    await pumpFor(tester, const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(minutes: 30)));
}
