// Two Demo 1 screenshots for an email (macOS): a photo question and a
// knowledge-base answer with its sources. Overlay off, fresh conversations,
// typed questions; up to three attempts each until the answer is sensible
// (the photo's subject named; no tool step and no digits for the KB one).
//
//   fvm flutter test integration_test/email_shots_test.dart -d macos \
//     --dart-define=GEMMA_MODEL_PATH=$HOME/Work/gemma-4-E2B-it.litertlm \
//     --dart-define=EMBEDDING_MODEL_DIR=$HOME/Work/models/embeddinggemma \
//     --dart-define=SHOWCASE_DIR=$PWD/test_assets/showcase
//
// Shots: the app container's tmp/email_*.png. Prints `EMAIL q=… a=…`.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/app.dart';
import 'package:litert_hackathon/config/demos.dart';
import 'package:litert_hackathon/config/dependencies.dart';
import 'package:litert_hackathon/config/env.dart';
import 'package:litert_hackathon/data/services/images/image_input_service.dart';
import 'package:litert_hackathon/domain/models/chat_entry.dart';
import 'package:litert_hackathon/domain/models/knowledge.dart';
import 'package:litert_hackathon/domain/models/llm_image.dart';
import 'package:litert_hackathon/domain/models/voice.dart';
import 'package:litert_hackathon/ui/core/debug_overlay.dart';
import 'package:litert_hackathon/ui/features/home/views/home_screen.dart';
import 'package:litert_hackathon/ui/features/voice_chat/view_models/voice_chat_view_model.dart';
import 'package:litert_hackathon/ui/features/voice_chat/views/chat_keys.dart';
import 'package:litert_hackathon/ui/features/voice_chat/views/citation_chips.dart';
import 'package:litert_hackathon/ui/features/voice_chat/views/voice_chat_screen.dart';
import 'package:provider/provider.dart';

import 'support/app_window.dart';
import 'support/pump.dart';

const kShowcaseDir = String.fromEnvironment('SHOWCASE_DIR');
final _screenKey = GlobalKey();

/// A gallery that returns whatever [encoded] is at pick time.
final class _SwitchablePicker implements ImageInputService {
  Uint8List encoded = Uint8List(0);

  @override
  bool supports(ImageSourceKind source) => source == ImageSourceKind.gallery;

  @override
  Future<Uint8List?> pick(ImageSourceKind source) async => encoded;
}

void main() {
  initIntegrationTest();

  testWidgets('email shots: photo question and knowledge base', (tester) async {
    if (kGemmaModelPath.isEmpty || kShowcaseDir.isEmpty) {
      fail('Pass GEMMA_MODEL_PATH, EMBEDDING_MODEL_DIR and SHOWCASE_DIR');
    }
    final picker = _SwitchablePicker();
    final deps = await AppDependencies.create(imageInput: picker);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _screenKey,
        child: App(dependencies: deps),
      ),
    );

    Future<void> shot(String name) async {
      await pumpFor(tester, const Duration(milliseconds: 700));
      final boundary =
          _screenKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('${Directory.systemTemp.path}/$name.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      debugPrint('SHOT ${file.path}');
    }

    await pumpUntil(
      tester,
      () => find.byType(HomeScreen).evaluate().isNotEmpty,
      timeout: const Duration(minutes: 10),
      reason: 'model setup',
    );
    await pumpUntil(
      tester,
      () => deps.knowledge.status.value is KnowledgeReady,
      timeout: const Duration(minutes: 3),
      reason: 'the knowledge base',
    );
    await pumpFor(tester, const Duration(seconds: 1));
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
    DebugOverlayHost.visibilityOf(tester.element(find.byType(VoiceChatScreen)))
            ?.value =
        false;
    // Replies are not spoken: quicker, and nothing to wait for.
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
      await pumpFor(tester, const Duration(milliseconds: 500));
      return vm.entries.lastWhere(
        (e) => e.role == ChatRole.assistant || e.role == ChatRole.error,
      );
    }

    Future<void> fresh() async {
      await vm.newConversation.execute();
      await pumpFor(tester, const Duration(milliseconds: 400));
    }

    // 1. Photo question.
    final photos = [
      ('coco_285_bear.jpg', ['bear']),
      ('coco_1818_zebras.jpg', ['zebra']),
      ('coco_2592_pirate_mug.jpg', ['mug', 'cup', 'knife', 'skull']),
    ];
    var photoDone = false;
    for (final (file, words) in photos) {
      for (final question in [
        "What's going on in this picture?",
        'Describe this photo in two sentences.',
      ]) {
        await fresh();
        picker.encoded = await File('$kShowcaseDir/$file').readAsBytes();
        await tester.tap(find.byKey(ChatKeys.attachGallery));
        await pumpUntil(
          tester,
          () => vm.attachment != null,
          timeout: const Duration(seconds: 10),
          reason: 'the photo',
        );
        await pumpFor(tester, const Duration(milliseconds: 300));
        final reply = await ask(question);
        final ok =
            reply.role == ChatRole.assistant &&
            reply.steps.isEmpty &&
            words.any((w) => reply.text.toLowerCase().contains(w));
        debugPrint(
          'EMAIL photo=$file q="$question" ok=$ok steps=${reply.steps} '
          'a="${reply.text.replaceAll('\n', ' ')}"',
        );
        if (ok) {
          await shot('email_photo');
          photoDone = true;
          break;
        }
      }
      if (photoDone) break;
    }

    // 2. Knowledge base, an answer without numbers and without a tool step.
    var kbDone = false;
    for (final question in const [
      'What is LiteRT, and how is it related to TensorFlow Lite?',
      'How can the voice session start talking before the whole reply is '
          'finished?',
      'What is EmbeddingGemma used for?',
      'What is LiteRT-LM?',
    ]) {
      await fresh();
      final reply = await ask(question);
      final retrieval = reply.knowledge?.retrieval;
      final ok =
          reply.role == ChatRole.assistant &&
          reply.steps.isEmpty &&
          retrieval?.outcome == RetrievalOutcome.used &&
          (reply.knowledge?.cited.isNotEmpty ?? false) &&
          !RegExp(r'\d')
              .hasMatch(reply.text.replaceAll(RegExp(r'\[\d+\]'), ''));
      debugPrint(
        'EMAIL kb q="$question" ok=$ok steps=${reply.steps} '
        'outcome=${retrieval?.outcome.name} cited=${reply.knowledge?.cited} '
        'a="${reply.text.replaceAll('\n', ' ')}"',
      );
      if (!ok) continue;
      await shot('email_kb');
      final chip = reply.knowledge!.cited.first;
      await tester.tap(find.byKey(KnowledgeChipKeys.citation(chip)).last);
      await pumpFor(tester, const Duration(milliseconds: 800));
      await shot('email_kb_source');
      await tester.tap(find.text('Close'));
      await pumpFor(tester, const Duration(milliseconds: 400));
      kbDone = true;
      break;
    }
    debugPrint('EMAIL photo_done=$photoDone kb_done=$kbDone');

    await tester.pumpWidget(const SizedBox.shrink());
    await deps.dispose();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
