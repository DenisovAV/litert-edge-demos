// The tester's path on macOS with no chat model shipped: the chat model is a
// `.litertlm` in the app's models folder, chosen in the Chat model card; the
// speech models, the detector, the embedder and the knowledge-base index are
// built in. Put a model there first (an APFS clone, instant):
//
//   mkdir -p ~/Library/Containers/dev.fluttergemma.litertHackathon/Data/Documents/models
//   cp -c ~/Work/gemma-4-E2B-it.litertlm \
//     ~/Library/Containers/dev.fluttergemma.litertHackathon/Data/Documents/models/
//   fvm flutter test integration_test/macos_check_test.dart -d macos
//
// 1. The Chat model card: the file in the models folder, picked and applied
//    (or already chosen: then setup hands over at once, and the card, with
//    nothing to apply, shows it loaded). Every built-in model ready, none
//    downloaded.
// 2. The knowledge base from the prebuilt index (no embedding on the Mac).
// 3. Demo 1 by voice: test_assets/france_16k.pcm through the view model's
//    PCM entry point (the one a mic release uses) → the built-in Whisper →
//    the chosen model → the built-in Inflect TTS at 24 kHz.
// 4. A typed knowledge-base question with its sources.
// 5. The in-app self-test from the Models screen (audio skipped: no TCC
//    prompt in a test run).
//
// One `MACOS_CHECK step=… status=PASS|FAIL …` line per step and a screenshot
// per step in the system temp folder.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/app.dart';
import 'package:litert_hackathon/config/demos.dart';
import 'package:litert_hackathon/config/dependencies.dart';
import 'package:litert_hackathon/config/model_catalog.dart';
import 'package:litert_hackathon/domain/models/chat_entry.dart';
import 'package:litert_hackathon/domain/models/chat_model.dart';
import 'package:litert_hackathon/domain/models/knowledge.dart';
import 'package:litert_hackathon/domain/models/model_id.dart';
import 'package:litert_hackathon/domain/models/model_state.dart';
import 'package:litert_hackathon/domain/models/voice.dart';
import 'package:litert_hackathon/selftest/self_test_options.dart';
import 'package:litert_hackathon/ui/core/debug_overlay.dart';
import 'package:litert_hackathon/ui/features/home/views/home_screen.dart';
import 'package:litert_hackathon/ui/features/setup/view_models/chat_model_view_model.dart';
import 'package:litert_hackathon/ui/features/setup/view_models/self_test_view_model.dart';
import 'package:litert_hackathon/ui/features/setup/view_models/setup_view_model.dart';
import 'package:litert_hackathon/ui/features/setup/views/chat_model_section.dart';
import 'package:litert_hackathon/ui/features/setup/views/self_test_card.dart';
import 'package:litert_hackathon/ui/features/setup/views/setup_screen.dart';
import 'package:litert_hackathon/ui/features/voice_chat/view_models/voice_chat_view_model.dart';
import 'package:litert_hackathon/ui/features/voice_chat/views/chat_keys.dart';
import 'package:litert_hackathon/ui/features/voice_chat/views/voice_chat_screen.dart';
import 'package:litert_hackathon/utils/pcm.dart';
import 'package:litert_hackathon/utils/result.dart';
import 'package:provider/provider.dart';

import 'support/app_window.dart';
import 'support/fixtures.dart';
import 'support/pump.dart';

/// The waits pump every 50 ms.
const _every = Duration(milliseconds: 50);

final _screenKey = GlobalKey();

void main() {
  initIntegrationTest();

  testWidgets('macOS: the chat model from the models folder, built-in speech, '
      'the prebuilt KB, Demo 1 by voice, the self-test', (tester) async {
    final lines = <String>[];
    var failures = 0;
    final shotsDir = Directory.systemTemp.createTempSync('macos_check');

    Future<void> shot(String name) async {
      await tester.pump(const Duration(milliseconds: 300));
      final boundary =
          _screenKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('${shotsDir.path}/${lines.length + 1}_$name.png')
        ..writeAsBytesSync(png!.buffer.asUint8List());
      debugPrint('MACOS_CHECK shot=${file.path}');
    }

    Future<void> step(String name, Future<String> Function() body) async {
      final watch = Stopwatch()..start();
      String line;
      try {
        final detail = await body();
        line =
            'MACOS_CHECK step=$name status=PASS '
            'ms=${watch.elapsedMilliseconds} $detail';
      } catch (e, st) {
        failures++;
        line =
            'MACOS_CHECK step=$name status=FAIL '
            'ms=${watch.elapsedMilliseconds} error="$e"';
        debugPrint('$st');
      }
      lines.add(line);
      debugPrint(line);
    }

    final fixture = (await rootBundle.load('test_assets/france_16k.pcm')).buffer
        .asUint8List();
    final deps = await AppDependencies.create(
      mic: FixtureMicService(fixture),
      selfTestOptions: const SelfTestOptions(skipAudio: true),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: _screenKey,
        child: App(dependencies: deps),
      ),
    );

    final listing = (await deps.chatModels.listFolders()).first;
    if (listing.error case final error?) throw StateError(error);
    final folder = listing.files;
    if (folder.isEmpty) {
      fail(
        'No .litertlm in the models folder: ${listing.path}. See the header.',
      );
    }
    final model = folder.first;

    // 1. The chat model from the folder.
    /// Home › More › Models.
    Future<void> openModels() async {
      await tester.tap(find.byKey(HomeKeys.menu));
      await pumpUntil(
        tester,
        () => find.byKey(HomeKeys.models).hitTestable().evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10),
        reason: 'the menu',
        step: _every,
      );
      await tester.tap(find.byKey(HomeKeys.models));
      await pumpUntil(
        tester,
        () => find.byType(SetupScreen).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10),
        reason: 'the Models screen',
        step: _every,
      );
      // The push animates; taps are ignored until it is done.
      await tester.pump(const Duration(milliseconds: 1200));
    }

    /// Picks [model] in the Chat model card on screen and applies it. When
    /// the card already shows it chosen (its row selected, taking no tap)
    /// and Apply is off because it runs with these settings, it counts as
    /// applied: the slot is checked the same way.
    Future<String> chooseInCard(String where) async {
      final chat = Provider.of<ChatModelViewModel>(
        tester.element(find.byType(SetupScreen)),
        listen: false,
      );
      // An earlier saved model may still be loading: the card waits.
      await pumpUntil(
        tester,
        () => !chat.busy,
        timeout: const Duration(minutes: 2),
        reason: 'the card to be idle',
        step: _every,
      );
      final tile = find.descendant(
        of: find.byKey(ChatModelKeys.folder(0)),
        matching: find.byKey(ChatModelKeys.localFile(model.name)),
      );
      await pumpUntil(
        tester,
        () => tile.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        reason: 'the file in the folder list',
        step: _every,
      );
      final activeBefore = chat.activeLine;
      await tester.ensureVisible(tile);
      if (!await tryPumpUntil(
        tester,
        () => tile.hitTestable().evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10),
        step: _every,
      )) {
        await shot('${where}_card_blocked');
        throw StateError('timed out: the file row to take taps');
      }
      await shot('${where}_card');
      // The saved model may be this file already: its row is selected and
      // takes no tap.
      final alreadyChosen = tester.widget<ListTile>(tile).selected;
      if (!alreadyChosen) {
        await tester.tap(tile);
        // The saved model may be an earlier one: wait for this file, in
        // place.
        await pumpUntil(
          tester,
          () =>
              !chat.useLocal.running &&
              switch (chat.saved?.source) {
                LocalModelSource(:final path) => path == model.path,
                _ => false,
              },
          timeout: const Duration(seconds: 20),
          reason: 'the pick',
          describe: () => 'localError=${chat.localError}',
          step: _every,
        );
      }
      final apply = find.byKey(ChatModelKeys.apply);
      await tester.ensureVisible(apply);
      await tester.pump(const Duration(milliseconds: 300));
      await shot('${where}_chosen');
      final watch = Stopwatch()..start();
      final String applied;
      if (tester.widget<FilledButton>(apply).enabled) {
        applied = 'now';
        // An Apply can end within one frame (a file that fails to load at
        // once): a listener sees it start, and the wait is for its outcome,
        // so such a failure is reported as the load said it, not as a
        // timeout.
        var started = false;
        void onApply() {
          if (chat.apply.running) started = true;
        }

        chat.apply.addListener(onApply);
        try {
          await tester.tap(apply);
          await pumpUntil(
            tester,
            () => started,
            timeout: const Duration(seconds: 10),
            reason: 'Apply to start',
            step: _every,
          );
          await pumpUntil(
            tester,
            () => !chat.apply.running && !deps.chatModelSwitcher.busy.value,
            timeout: const Duration(minutes: 3),
            reason: 'the model to load',
            describe: () => chat.activeLine,
            step: _every,
          );
        } finally {
          chat.apply.removeListener(onApply);
        }
        if (chat.apply.result case Error(:final error)) {
          throw StateError(
            'Apply failed: $error (load error: ${chat.loadError})',
          );
        }
      } else if (alreadyChosen) {
        // Nothing to apply: the card runs this file with these settings
        // (Apply turns on for a change, or after a failed load).
        applied = 'already';
      } else {
        throw StateError(
          'Apply is off after picking ${model.name}: ${chat.draftProblem}',
        );
      }
      final slot = deps.models.states.value[ModelId.chat];
      final source = slot is ModelReady ? slot.info.chat?.source : null;
      if (source != 'in place: ${model.path}') {
        throw StateError(
          'the chat model runs from $source (${chat.loadError})',
        );
      }
      return 'where=$where before="$activeBefore" file=${model.path} '
          'applied=$applied apply_ms=${watch.elapsedMilliseconds} '
          'chat=${slot is ModelReady ? '${slot.info.backend} load=${slot.info.loadTime.inMilliseconds}ms' : slot}';
    }

    // 1. The chat model from the folder: on the setup screen (a first run),
    //    else from Models (an earlier model was chosen and loaded).
    await step('choose_model', () async {
      await pumpUntil(
        tester,
        () =>
            find.byType(SetupScreen).evaluate().isNotEmpty ||
            find.byType(HomeScreen).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'the first screen',
        step: _every,
      );
      await tester.pump(const Duration(seconds: 1));
      // A debug build shows the diagnostics panel over the top of every
      // screen: hidden, as a tester sees the app.
      if (DebugOverlayHost.visibilityOf(
            tester.element(find.byKey(DebugOverlayKeys.toggle).first),
          )?.value ??
          false) {
        await tester.tap(find.byKey(DebugOverlayKeys.toggle).first);
        await tester.pump(const Duration(milliseconds: 300));
      }
      if (find.byType(HomeScreen).evaluate().isEmpty) {
        final setup = Provider.of<SetupViewModel>(
          tester.element(find.byType(SetupScreen)),
          listen: false,
        );
        // Settled: handed over (an earlier saved model loaded), or the
        // setup attempt ended without a chat model.
        await pumpUntil(
          tester,
          () =>
              find.byType(HomeScreen).evaluate().isNotEmpty ||
              (setup.prepare.result != null &&
                  !setup.prepare.running &&
                  !setup.allReady),
          timeout: const Duration(minutes: 2),
          reason: 'the setup to settle',
          step: _every,
        );
        await tester.pump(const Duration(seconds: 1));
      }
      final String detail;
      if (find.byType(HomeScreen).evaluate().isEmpty) {
        detail = await chooseInCard('setup');
        await pumpUntil(
          tester,
          () => find.byType(HomeScreen).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 30),
          reason: 'the hand-over to home',
          step: _every,
        );
      } else {
        await openModels();
        detail = await chooseInCard('models');
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .popUntil((route) => route.settings.name == Routes.home);
        await pumpUntil(
          tester,
          () => find.byType(SetupScreen).evaluate().isEmpty,
          timeout: const Duration(seconds: 10),
          reason: 'back to home',
          step: _every,
        );
      }
      return detail;
    });

    await step('built_in_models', () async {
      await shot('home');
      final states = deps.models.states.value;
      final rows = [
        for (final id in ModelId.values)
          '${id.name}=${switch (states[id]) {
            ModelReady(:final info) => 'ready(${info.backend})',
            final other => '$other',
          }}',
      ];
      for (final id in ModelId.values) {
        if (states[id] is! ModelReady) throw StateError(rows.join(' '));
      }
      return rows.join(' ');
    });

    // 2. The prebuilt knowledge-base index.
    await step('kb_prebuilt', () async {
      await pumpUntil(
        tester,
        () => deps.knowledge.status.value is KnowledgeReady,
        timeout: const Duration(minutes: 3),
        reason: 'the knowledge base',
        step: _every,
      );
      final ready = deps.knowledge.status.value as KnowledgeReady;
      final detail =
          'origin=${ready.origin.name} chunks=${ready.chunks} '
          'reused=${ready.reused} ms=${ready.elapsed.inMilliseconds} '
          'skipped=${ready.prebuiltSkipped}';
      if (ready.origin != KnowledgeOrigin.prebuilt && !ready.reused) {
        throw StateError('not the prebuilt index: $detail');
      }
      return detail;
    });

    // 3. Demo 1 by voice.
    late VoiceChatViewModel vm;
    await step('demo1_voice', () async {
      final tile = find.byKey(HomeKeys.tile(Demo.voiceChat));
      await pumpUntil(
        tester,
        () => tester.widget<ListTile>(tile).enabled,
        timeout: const Duration(seconds: 30),
        reason: 'the Demo 1 tile',
        step: _every,
      );
      await tester.tap(tile);
      await pumpUntil(
        tester,
        () => find.byType(VoiceChatScreen).evaluate().length == 1,
        timeout: const Duration(seconds: 10),
        reason: 'the chat screen',
        step: _every,
      );
      vm = Provider.of<VoiceChatViewModel>(
        tester.element(find.byType(VoiceChatScreen)),
        listen: false,
      );
      await pumpUntil(
        tester,
        () => vm.isReady && vm.canSend,
        timeout: const Duration(seconds: 60),
        reason: 'the chat to open',
        step: _every,
      );
      TurnResult? result;
      unawaited(
        vm
            .submitUtterance(
              Utterance(
                pcm: fixture,
                held: pcm16Duration(fixture.length, 16000),
              ),
            )
            .then((r) => result = r),
      );
      await pumpUntil(
        tester,
        () => result != null,
        timeout: const Duration(seconds: 90),
        reason: 'the voice turn',
        step: _every,
      );
      await shot('demo1_voice');
      final user = vm.entries.lastWhere((e) => e.role == ChatRole.user);
      final reply = vm.entries.last;
      final voice = deps.diagnostics.latest.lastVoiceTurn;
      final detail =
          'outcome=${result!.outcome.name} heard="${user.text}" '
          'reply="${reply.text.replaceAll('\n', ' ')}" '
          'stt=${voice?.stt?.inMilliseconds}ms '
          'first_text=${voice?.firstText?.inMilliseconds}ms '
          'first_audio=${voice?.firstAudio?.inMilliseconds}ms '
          'rate=${voice?.sampleRate}Hz';
      if (result!.outcome != TurnOutcome.completed ||
          !user.text.toLowerCase().contains('france') ||
          !reply.text.toLowerCase().contains('paris') ||
          voice?.firstAudio == null ||
          voice?.sampleRate != kTtsConfig.sampleRate) {
        throw StateError(detail);
      }
      return detail;
    });

    // 4. A typed knowledge-base question with its sources.
    await step('demo1_kb', () async {
      await pumpUntil(
        tester,
        () => vm.canSend,
        timeout: const Duration(seconds: 60),
        reason: 'Send',
        step: _every,
      );
      final before = vm.entries.length;
      final input = find.byKey(ChatKeys.input);
      await tester.tap(input);
      await tester.enterText(
        input,
        'What is the input size of the YOLO 26 nano detector?',
      );
      await tester.pump();
      await tester.tap(find.byKey(ChatKeys.send));
      await pumpUntil(
        tester,
        () =>
            !vm.send.running &&
            vm.entries.skip(before).any((e) => e.role == ChatRole.assistant),
        timeout: const Duration(seconds: 90),
        reason: 'the reply',
        step: _every,
      );
      await shot('demo1_kb');
      final reply = vm.entries.last;
      final g = deps.diagnostics.latest.lastGeneration;
      final sources = reply.knowledge?.retrieval.passages.length ?? 0;
      final detail =
          'reply="${reply.text.replaceAll('\n', ' ')}" sources=$sources '
          'ttft=${g?.timeToFirstToken?.inMilliseconds}ms '
          'tok_s=${g?.tokensPerSecond?.toStringAsFixed(1)}';
      if (sources == 0) throw StateError(detail);
      return detail;
    });

    // 5. The in-app self-test.
    await step('self_test', () async {
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.popUntil((route) => route.settings.name == Routes.home);
      await pumpUntil(
        tester,
        () => find.byType(VoiceChatScreen).evaluate().isEmpty,
        timeout: const Duration(seconds: 10),
        reason: 'the chat to close',
        step: _every,
      );
      await openModels();
      final run = find.byKey(SelfTestKeys.run);
      await tester.scrollUntilVisible(
        run,
        400,
        scrollable: find
            .descendant(
              of: find.byType(SetupScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // On a small window the list's viewport ends below it: on screen.
      await tester.ensureVisible(run);
      await tester.pumpAndSettle();
      final selfTest = Provider.of<SelfTestViewModel>(
        tester.element(find.byKey(SelfTestKeys.card)),
        listen: false,
      );
      await pumpUntil(
        tester,
        () => selfTest.canRun,
        timeout: const Duration(seconds: 60),
        reason: 'Run self-test',
        step: _every,
      );
      await tester.tap(run);
      await pumpUntil(
        tester,
        () => selfTest.run.running,
        timeout: const Duration(seconds: 10),
        reason: 'the self-test to start',
        step: _every,
      );
      await pumpUntil(
        tester,
        () => !selfTest.run.running,
        timeout: const Duration(minutes: 6),
        reason: 'the self-test',
        step: _every,
      );
      await tester.ensureVisible(find.byKey(SelfTestKeys.card));
      await shot('self_test');
      final outcome = selfTest.outcome;
      if (outcome == null) throw StateError('no report: ${selfTest.error}');
      for (final l in outcome.text.split('\n')) {
        debugPrint('MACOS_CHECK self_test| $l');
      }
      final detail = 'passed=${outcome.passed} report=${outcome.reportPath}';
      if (!outcome.passed) throw StateError(detail);
      return detail;
    });

    debugPrint('MACOS_CHECK summary failures=$failures shots=${shotsDir.path}');
    expect(failures, 0, reason: lines.join('\n'));
  });
}
