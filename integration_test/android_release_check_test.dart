// Android check on a real phone (Firebase Test Lab; tool/run_android_check_ftl.sh),
// through the app's UI like a tester. The app ships no chat model and needs no
// download: the script's --model pushes a `.litertlm` into the models folder
// (/sdcard/Android/data/<app>/files/models/) and /data/local/tmp/litert-models/
// (readable whatever the order). The test picks it in the setup screen's Chat
// model card (through "Path…" if the folder copy cannot be read) with the
// defaults its header gives — an NPU build: NPU, images off; Gemma 4 E2B: GPU,
// images on — applies it and checks activeBackend. Then: the built-in models
// extracted from the APK once (Whisper, moonshine, the Inflect bundle,
// EmbeddingGemma), the device card's chip from the hardware probe, the
// knowledge base from the prebuilt index (its golden set), Demo 1 (a
// knowledge-base question with source chips, a plain question, "Which
// accelerator are you running on?" whose reply must name the backend and
// should name the SoC), Demo 3 on the camera, and the in-app self-test from
// the Models screen (audio skipped: a rack has no listener).
//
// Build mode: PROFILE (AOT, release-like). integration_test is a dev
// dependency, and Flutter leaves dev-dependency plugins out of release builds
// (flutter_tools flutter_plugins.dart `injectPlugins`), so a release APK cannot
// host this test.
//
// One `ANDROID_CHECK step=… status=PASS|WARN|SKIP|FAIL ms=… …` line per step,
// and a screenshot per step, written to the app's external files dir `ftl/`
// (/sdcard/Android/data/dev.fluttergemma.litert_hackathon/files/ftl, pulled by
// the script).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart' show PreferredBackend;
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/app.dart';
import 'package:litert_hackathon/config/demos.dart';
import 'package:litert_hackathon/config/dependencies.dart';
import 'package:litert_hackathon/config/knowledge_config.dart';
import 'package:litert_hackathon/data/services/model_store/bundled_model_files.dart'
    show kBundledModelFiles;
import 'package:litert_hackathon/data/services/model_store/models_folder.dart';
import 'package:litert_hackathon/domain/models/chat_entry.dart';
import 'package:litert_hackathon/domain/models/knowledge.dart';
import 'package:litert_hackathon/domain/models/live_state.dart';
import 'package:litert_hackathon/domain/models/model_id.dart';
import 'package:litert_hackathon/domain/models/model_state.dart';
import 'package:litert_hackathon/selftest/self_test_options.dart';
import 'package:litert_hackathon/ui/core/device_card.dart';
import 'package:litert_hackathon/ui/features/home/views/home_screen.dart';
import 'package:litert_hackathon/ui/features/live_camera/views/live_camera_screen.dart';
import 'package:litert_hackathon/ui/features/setup/view_models/chat_model_view_model.dart';
import 'package:litert_hackathon/ui/features/setup/view_models/self_test_view_model.dart';
import 'package:litert_hackathon/ui/features/setup/views/chat_model_section.dart';
import 'package:litert_hackathon/ui/features/setup/views/self_test_card.dart';
import 'package:litert_hackathon/ui/features/setup/views/setup_screen.dart';
import 'package:litert_hackathon/ui/features/voice_chat/view_models/voice_chat_view_model.dart';
import 'package:litert_hackathon/ui/features/voice_chat/views/chat_keys.dart';
import 'package:litert_hackathon/ui/features/voice_chat/views/citation_chips.dart';
import 'package:litert_hackathon/ui/features/voice_chat/views/voice_chat_screen.dart';
import 'package:litert_hackathon/utils/result.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'support/app_window.dart';
import 'support/pump.dart';

/// The waits pump every 200 ms on a phone unless they ask for longer.
const _every = Duration(milliseconds: 200);

const _kbQuestion = 'What is the input size of the YOLO 26 nano detector?';
const _plainQuestion = 'Write one short sentence about the sea.';
const _deviceQuestion = 'Which accelerator are you running on?';
final _screenKey = GlobalKey();

enum _Status { pass, warn, skip, fail }

final class _Step {
  _Step(this.name, this.status, this.ms, this.detail);

  final String name;
  final _Status status;
  final int ms;
  final String detail;

  String get line =>
      'ANDROID_CHECK step=$name status=${status.name.toUpperCase()} '
      'ms=$ms $detail';
}

/// A step that is not a failure but needs a note (e.g. no camera frames).
final class _Warn implements Exception {
  _Warn(this.detail);

  final String detail;
}

/// A step that does not apply on this run (e.g. no NPU model pushed).
final class _Skip implements Exception {
  _Skip(this.detail);

  final String detail;
}

/// What one typed turn produced.
typedef _Turn = ({
  ChatEntry reply,
  int ms,
  int? ttftMs,
  double? tokS,
  int sources,
  String path,
});

String _mb(int? bytes) =>
    bytes == null ? '?' : '${(bytes / (1 << 20)).toStringAsFixed(0)}MB';

void main() {
  final binding = initIntegrationTest();

  testWidgets('Android check: download, setup, KB, Demo 1, Demo 3, self-test, '
      'NPU', (tester) async {
    final steps = <_Step>[];
    final shots = <String>[];
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null &&
          (message.contains('[Bundled]') ||
              message.contains('[DetectorService]') ||
              message.contains('[LlmService]') ||
              message.contains('[Conversation]') ||
              message.contains('[ChatTurnResponder]') ||
              message.contains('[Voice] turn') ||
              message.contains('[ChatModel]'))) {
        logged.add(message);
      }
      original(message, wrapWidth: wrapWidth);
    };

    final out = Directory('${(await getExternalStorageDirectory())!.path}/ftl')
      ..createSync(recursive: true);

    Future<void> shot(String name, {bool platform = false}) async {
      try {
        await tester.pump(const Duration(milliseconds: 300));
        final boundary =
            _screenKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final file = File('${out.path}/${shots.length + 1}_$name.png')
          ..writeAsBytesSync(png!.buffer.asUint8List());
        shots.add(file.path);
        debugPrint('ANDROID_CHECK shot=${file.path}');
      } catch (e) {
        debugPrint('ANDROID_CHECK shot=$name failed: $e');
      }
      if (!platform) return;
      // The camera preview is a texture: the platform screenshot has it even
      // where the layer snapshot leaves it black.
      try {
        await binding.convertFlutterSurfaceToImage().timeout(
          const Duration(seconds: 10),
        );
        await tester.pump(const Duration(milliseconds: 500));
        final bytes = await binding
            .takeScreenshot(name)
            .timeout(const Duration(seconds: 20));
        final file = File('${out.path}/${shots.length + 1}_${name}_device.png')
          ..writeAsBytesSync(bytes);
        shots.add(file.path);
        debugPrint('ANDROID_CHECK shot=${file.path}');
      } catch (e) {
        debugPrint('ANDROID_CHECK platform shot=$name failed: $e');
      }
    }

    Future<void> step(String name, Future<String> Function() body) async {
      final watch = Stopwatch()..start();
      _Step result;
      try {
        final detail = await body();
        result = _Step(name, _Status.pass, watch.elapsedMilliseconds, detail);
      } on _Warn catch (w) {
        result = _Step(name, _Status.warn, watch.elapsedMilliseconds, w.detail);
      } on _Skip catch (w) {
        result = _Step(name, _Status.skip, watch.elapsedMilliseconds, w.detail);
      } catch (e, st) {
        result = _Step(
          name,
          _Status.fail,
          watch.elapsedMilliseconds,
          'error="${'$e'.replaceAll('\n', ' ')}"',
        );
        debugPrint('ANDROID_CHECK step=$name stack: $st');
      }
      steps.add(result);
      debugPrint(result.line);
    }

    NavigatorState navigator() =>
        tester.state<NavigatorState>(find.byType(Navigator).first);

    Future<void> backToHome() async {
      FocusManager.instance.primaryFocus?.unfocus();
      navigator().popUntil((route) => route.settings.name == Routes.home);
      // A pop animates (800 ms on Android): the leaving screen stays in the
      // tree meanwhile, and finding it right after the next push hands back
      // its view model, disposed a moment later (the S26 run's second chat
      // sent into the old chat and waited 4 minutes for its reply).
      await pumpUntil(
        tester,
        () =>
            find.byType(VoiceChatScreen).evaluate().isEmpty &&
            find.byType(LiveCameraScreen).evaluate().isEmpty &&
            find.byType(SetupScreen).evaluate().isEmpty,
        timeout: const Duration(seconds: 10),
        reason: 'the previous screen to close',
        step: _every,
      );
      // Home's list is lazy: scrolled down (to the device card), the demo
      // tiles at its top are not built (the first S26 run: "No element").
      final list = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scrollable),
      );
      if (list.evaluate().isNotEmpty) {
        tester.state<ScrollableState>(list.first).position.jumpTo(0);
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// Home › More (⋮) › Models, as a tester; the menu item is tapped once
    /// it is on screen (the popup animates in).
    Future<void> openModels() async {
      await backToHome();
      await tester.tap(find.byKey(HomeKeys.menu));
      await pumpUntil(
        tester,
        () => find.byKey(HomeKeys.models).hitTestable().evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10),
        reason: 'the More menu',
        step: _every,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(HomeKeys.models));
      // The screen, not a card on it: the Models list is lazy, and the
      // self-test card at its end is not built until scrolled to (waiting
      // for it timed out on the S24).
      await pumpUntil(
        tester,
        () => find.byType(SetupScreen).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        reason: 'the Models screen',
        step: _every,
      );
      await tester.pump(const Duration(milliseconds: 600));
    }

    /// Scrolls the Models list until [target] is built and on screen.
    Future<void> scrollTo(Finder target) async {
      await tester.scrollUntilVisible(
        target,
        400,
        scrollable: find
            .descendant(
              of: find.byType(SetupScreen),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 60,
      );
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<VoiceChatViewModel> openChat() async {
      await backToHome();
      final tile = find.byKey(HomeKeys.tile(Demo.voiceChat));
      await pumpUntil(
        tester,
        () => tester.widget<ListTile>(tile).enabled,
        timeout: const Duration(seconds: 60),
        reason: 'the Voice chat tile',
        step: _every,
      );
      await tester.tap(tile);
      await pumpUntil(
        tester,
        () => find.byType(VoiceChatScreen).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'the chat screen',
        step: _every,
      );
      final vm = Provider.of<VoiceChatViewModel>(
        tester.element(find.byType(VoiceChatScreen)),
        listen: false,
      );
      await pumpUntil(
        tester,
        () => vm.isReady,
        timeout: const Duration(seconds: 90),
        reason: 'the chat to open',
        step: _every,
      );
      return vm;
    }

    /// Types [question] and sends it as a tester does: once Send is
    /// enabled (`canSend`: the chat open, no turn or greeting running), a
    /// tap in the field (the real keyboard opens), the text, a tap on the
    /// send button. The text goes into the field's controller: on a device
    /// the integration binding leaves the real keyboard in place
    /// (`registerTestTextInput` is false), so `enterText`/`receiveAction`
    /// talk to a test keyboard the field is not connected to and the field
    /// stays empty (the S24 run's send button then did nothing). Only if
    /// the button starts no turn, the send command itself; [_Turn.path]
    /// says which one did.
    Future<_Turn> ask(VoiceChatViewModel vm, String question) async {
      await pumpUntil(
        tester,
        () => vm.canSend,
        timeout: const Duration(seconds: 90),
        reason: 'Send to be enabled before "$question"',
        step: _every,
      );
      final before = vm.entries.length;
      final input = find.byKey(ChatKeys.input);
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 500));
      final field = tester.widget<TextField>(input).controller!;
      field.text = question;
      await tester.pump(const Duration(milliseconds: 300));
      bool started() =>
          vm.send.running || vm.isGenerating || vm.entries.length > before;
      Future<bool> startedWithin(Duration d) async {
        final w = Stopwatch()..start();
        while (!started() && w.elapsed < d) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        return started();
      }

      final watch = Stopwatch()..start();
      var path = 'send button';
      final send = find.byKey(ChatKeys.send);
      await tester.ensureVisible(send);
      await tester.tap(send);
      if (!await startedWithin(const Duration(seconds: 3))) {
        path = 'send command (the button did nothing: field="${field.text}")';
        field.clear();
        unawaited(vm.send.execute(question));
      }
      if (!await startedWithin(const Duration(seconds: 20))) {
        throw StateError(
          'the turn did not start ("$question"): canSend=${vm.canSend} '
          'error=${vm.error}',
        );
      }
      debugPrint('ANDROID_CHECK turn started via $path: "$question"');
      await pumpUntil(
        tester,
        () =>
            !vm.send.running &&
            vm.entries
                .skip(before)
                .any(
                  (e) =>
                      e.role == ChatRole.assistant || e.role == ChatRole.error,
                ),
        timeout: const Duration(minutes: 4),
        reason: 'the reply to "$question"',
        step: _every,
      );
      final reply = vm.entries.lastWhere(
        (e) => e.role == ChatRole.assistant || e.role == ChatRole.error,
      );
      await tester.pump(const Duration(milliseconds: 600));
      final g = deps().diagnostics.latest.lastGeneration;
      return (
        reply: reply,
        ms: watch.elapsedMilliseconds,
        ttftMs: g?.timeToFirstToken?.inMilliseconds,
        tokS: g?.tokensPerSecond,
        sources: reply.knowledge?.retrieval.passages.length ?? 0,
        path: path,
      );
    }

    String turnLine(_Turn t) =>
        'reply="${t.reply.text.replaceAll('\n', ' ')}" role=${t.reply.role.name} '
        'sources=${t.sources} ttft=${t.ttftMs}ms tok_s=${t.tokS?.toStringAsFixed(1)} '
        'total_ms=${t.ms} via="${t.path}"';

    String memory() {
      final latest = deps().diagnostics.latest;
      return 'rss=${_mb(ProcessInfo.currentRss)} peak_rss=${_mb(ProcessInfo.maxRss)} '
          'diag_rss=${_mb(latest.rssBytes)}';
    }

    /// Models › Run self-test; the report is saved as [file].
    Future<String> selfTest(String name, String file) async {
      await openModels();
      final run = find.byKey(SelfTestKeys.run);
      await scrollTo(run);
      final vm = Provider.of<SelfTestViewModel>(
        tester.element(find.byKey(SelfTestKeys.card)),
        listen: false,
      );
      await pumpUntil(
        tester,
        () => vm.canRun,
        timeout: const Duration(seconds: 90),
        reason: 'Run self-test to be enabled',
        step: _every,
      );
      await tester.tap(run);
      await pumpUntil(
        tester,
        () => vm.run.running,
        timeout: const Duration(seconds: 10),
        reason: 'the self-test to start',
        step: _every,
      );
      await pumpUntil(
        tester,
        () => !vm.run.running,
        timeout: const Duration(minutes: 10),
        reason: 'the self-test',
        step: const Duration(seconds: 1),
      );
      await tester.ensureVisible(find.byKey(SelfTestKeys.card));
      await shot(name);
      final outcome = vm.outcome;
      if (outcome == null) throw StateError('no report: ${vm.error}');
      File('${out.path}/$file').writeAsStringSync(outcome.text);
      final lines = outcome.text.split('\n');
      String pick(String prefix) => lines
          .where((l) => l.trimLeft().startsWith(prefix))
          .map((l) => l.trim())
          .join(' | ');
      for (final l in lines) {
        debugPrint('ANDROID_CHECK $name| $l');
      }
      final detail =
          'passed=${outcome.passed} "${pick('chat model')}" '
          '"${pick('PASS')} ${pick('FAIL')} ${pick('SKIP')}"';
      if (!outcome.passed) throw StateError(detail);
      return detail;
    }

    final created = await AppDependencies.create(
      selfTestOptions: const SelfTestOptions(skipAudio: true),
    );
    deps = () => created;
    await tester.pumpWidget(
      RepaintBoundary(
        key: _screenKey,
        child: App(dependencies: created),
      ),
    );

    String states() => [
      for (final MapEntry(:key, :value) in created.models.states.value.entries)
        '${key.name}=${switch (value) {
          ModelReady(:final info) => 'ready(${info.backend})',
          ModelFailed(:final message) => 'failed(${message.split('\n').first})',
          ModelUnavailable(:final reason) => 'unavailable($reason)',
          _ => value.runtimeType.toString(),
        }}',
    ].join(' ');

    // A tester's own .litertlm (the script's --model): pushed into the
    // models folder, and the same file into /data/local/tmp/litert-models
    // for when the folder copy cannot be read by the app (Test Lab may push
    // before the app has created its folder; the first S26 run saw none).
    const tmpModels = '/data/local/tmp/litert-models';
    final appFolder = (await created.chatModels.listFolders()).first;
    final folderFiles = appFolder.files;
    final tmpFiles = <String>[];
    try {
      for (final entry in Directory(tmpModels).listSync()) {
        if (entry is File && entry.path.toLowerCase().endsWith('.litertlm')) {
          tmpFiles.add(entry.path);
        }
      }
    } on FileSystemException catch (e) {
      debugPrint('ANDROID_CHECK $tmpModels: ${e.message} ${e.osError ?? ''}');
    }
    final folderPath = appFolder.path ?? 'unavailable (${appFolder.error})';
    Future<String> ls(String path) async {
      try {
        final r = await Process.run('ls', ['-laZ', path]);
        return '${r.stdout}${r.stderr}'.trim().replaceAll('\n', ' | ');
      } catch (e) {
        return 'ls failed: $e';
      }
    }

    final listingLine = switch (appFolder.error) {
      null => folderFiles.map((e) => '${e.name}:${e.sizeBytes}').join(','),
      final error => 'error($error)',
    };
    final pushedDiag =
        'folder=$folderPath listing=[$listingLine] '
        'ls="${await ls(folderPath)}" tmp=[${tmpFiles.join(',')}] '
        'ls_tmp="${await ls(tmpModels)}"';
    debugPrint('ANDROID_CHECK pushed $pushedDiag');
    final pushedModel = folderFiles.isNotEmpty || tmpFiles.isNotEmpty;

    /// Picks the pushed model in the Chat model card as a tester does, with
    /// the defaults its header gives (an NPU build: NPU, images off), applies
    /// it and checks it runs on the backend the card shows.
    Future<String> selectPushedModel() async {
      // The Chat model card of the setup screen (first run) or of Models.
      await pumpUntil(
        tester,
        () =>
            find.byType(SetupScreen).evaluate().isNotEmpty ||
            find.byType(HomeScreen).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
        reason: 'the first screen',
        step: _every,
      );
      if (find.byType(SetupScreen).evaluate().isEmpty) await openModels();
      final card = find.byKey(ChatModelKeys.section);
      await pumpUntil(
        tester,
        () => card.evaluate().isNotEmpty,
        timeout: const Duration(minutes: 2),
        reason: 'the Chat model card',
        step: _every,
      );
      final chat = Provider.of<ChatModelViewModel>(
        tester.element(find.byType(SetupScreen)),
        listen: false,
      );
      // The built-in models load first (and extract on a first launch).
      await pumpUntil(
        tester,
        () => !chat.busy,
        timeout: const Duration(minutes: 5),
        reason: 'the card to be idle',
        step: const Duration(milliseconds: 500),
      );
      await shot('setup_no_model');
      final rescan = find.byKey(ChatModelKeys.rescan);
      await tester.ensureVisible(rescan);
      await tester.tap(rescan);
      await tester.pump(const Duration(milliseconds: 300));
      await pumpUntil(
        tester,
        () => !chat.rescan.running,
        timeout: const Duration(seconds: 20),
        reason: 'Rescan',
        step: _every,
      );
      // The tester's way: the file's row in the models folder list; if
      // that copy cannot be used, the same file through "Path…".
      final inFolder = folderFiles.firstOrNull;
      final folderProblem = inFolder == null
          ? 'not in the models folder'
          : switch (await inspectLitertlm(inFolder.path)) {
              Ok() => null,
              Error(:final error) => '$error',
            };
      final tmp = tmpFiles.firstOrNull;
      final String via;
      final String chosen;
      if (inFolder != null && folderProblem == null) {
        via = 'models folder';
        chosen = inFolder.path;
        // The app's own folder's row: the same file pushed to both folders
        // is listed twice.
        final tile = find.descendant(
          of: find.byKey(ChatModelKeys.folder(0)),
          matching: find.byKey(ChatModelKeys.localFile(inFolder.name)),
        );
        await pumpUntil(
          tester,
          () => tile.evaluate().isNotEmpty,
          timeout: const Duration(seconds: 20),
          reason: 'the pushed file in the models folder list',
          step: _every,
        );
        await tester.ensureVisible(tile);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(tile);
      } else if (tmp != null) {
        via = 'Path… (models folder: $folderProblem)';
        chosen = tmp;
        // The second folder lists it too; Path… is the explicit way.
        final pathButton = find.byKey(ChatModelKeys.pathButton);
        await tester.ensureVisible(pathButton);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(pathButton);
        final field = find.byKey(ChatModelKeys.pathField);
        await pumpUntil(
          tester,
          () => field.evaluate().isNotEmpty,
          timeout: const Duration(seconds: 10),
          reason: 'the Path… dialog',
          step: _every,
        );
        await tester.pump(const Duration(milliseconds: 500));
        // The real keyboard is up: the text goes into the controller (see
        // ask()).
        tester.widget<TextField>(field).controller!.text = tmp;
        await tester.pump(const Duration(milliseconds: 300));
        await shot('path_dialog');
        await tester.tap(find.byKey(ChatModelKeys.pathSubmit));
      } else {
        throw StateError(
          'the pushed model cannot be used: $folderProblem; $pushedDiag',
        );
      }
      await pumpUntil(
        tester,
        () => chat.useLocal.running || chat.useLocal.result != null,
        timeout: const Duration(seconds: 10),
        reason: 'the pick to start',
        step: _every,
      );
      await pumpUntil(
        tester,
        () => !chat.useLocal.running,
        timeout: const Duration(seconds: 60),
        reason: 'the file to be picked',
        step: _every,
      );
      if (chat.localError case final error?) {
        throw StateError('$error (via $via; $pushedDiag)');
      }
      final wanted = chat.draftBackend;
      if (wanted == PreferredBackend.npu && !chat.npuOffered) {
        await shot('npu_not_offered');
        throw StateError(
          'NPU not offered on this device: ${chat.npuUnavailableReason}',
        );
      }
      if (wanted == PreferredBackend.npu && chat.draftImages) {
        throw StateError('an NPU build with images on: ${chat.saved}');
      }
      await tester.ensureVisible(find.byKey(ChatModelKeys.backend));
      await shot('model_chosen');
      final apply = find.byKey(ChatModelKeys.apply);
      await tester.ensureVisible(apply);
      await tester.pump(const Duration(milliseconds: 300));
      final watch = Stopwatch()..start();
      await tester.tap(apply);
      await pumpUntil(
        tester,
        () => chat.apply.running || created.chatModelSwitcher.busy.value,
        timeout: const Duration(seconds: 10),
        reason: 'Apply to start',
        step: _every,
      );
      await pumpUntil(
        tester,
        () => !chat.apply.running && !created.chatModelSwitcher.busy.value,
        timeout: const Duration(minutes: 6),
        reason: 'the model to load',
        step: const Duration(milliseconds: 500),
      );
      await tester.pump(const Duration(seconds: 1));
      await shot('model_applied');
      final slot = created.models.states.value[ModelId.chat];
      final model = chat.saved!;
      final settings =
          'file=$chosen via="$via" ${model.settingsLine} '
          'npu="${chat.npuLine}" apply_ms=${watch.elapsedMilliseconds}'
          '${switch (chat.apply.result) {
            Error(:final error) => ' apply_error="$error"',
            _ => '',
          }}';
      switch (slot) {
        case ModelReady(:final info) when info.backend == wanted.name:
          return 'activeBackend=${info.backend} '
              'load_ms=${info.loadTime.inMilliseconds} '
              'warmup_ms=${info.warmUpTime.inMilliseconds} '
              'ctx=${info.chat?.contextTokens} $settings ${memory()}';
        case ModelReady(:final info):
          throw StateError(
            'activeBackend=${info.backend}, not ${wanted.name}: $settings '
            'log="${logged.where((l) => l.contains('[LlmService]')).join(' | ')}"',
          );
        case ModelFailed(:final message):
          throw StateError('the load failed: $message ($settings)');
        case final other:
          throw StateError(
            'chat slot $other: ${chat.loadError ?? chat.activeLine} '
            '($settings) ${chat.localProblem ?? ''}',
          );
      }
    }

    String? runningBackend() =>
        switch (created.models.states.value[ModelId.chat]) {
          ModelReady(:final info) => info.backend,
          _ => null,
        };

    // 1. The chat model: the pushed file, chosen on the setup screen.
    await step('chat_model', () async {
      if (!pushedModel) {
        throw StateError('no pushed .litertlm (run with --model): $pushedDiag');
      }
      return selectPushedModel();
    });

    // 2. The setup hands over to home: every model ready.
    await step('setup_ready', () async {
      await pumpUntil(
        tester,
        () => find.byType(HomeScreen).evaluate().isNotEmpty,
        timeout: const Duration(minutes: 5),
        reason: 'setup done (home)',
        step: const Duration(seconds: 1),
      );
      await shot('setup_done_home');
      for (final id in ModelId.values) {
        if (created.models.states.value[id] is! ModelReady) {
          throw StateError('$id not ready: ${states()}');
        }
      }
      return '${states()} ${memory()}';
    });

    // 3. The built-in models, extracted from the APK once.
    await step('bundled_extract', () async {
      final lines = logged.where((l) => l.contains('[Bundled]')).toList();
      final extracted = lines
          .where((l) => l.contains('extracted and verified'))
          .map((l) => l.substring(l.indexOf('[Bundled]') + 10))
          .toList();
      final expected = [for (final f in kBundledModelFiles) f.name]
          .where((n) => !extracted.any((l) => l.startsWith('$n:')));
      final detail =
          'extracted=${extracted.length}/${kBundledModelFiles.length} '
          'log="${extracted.join(' | ')}"';
      if (expected.isNotEmpty) {
        throw StateError('not extracted: ${expected.join(', ')}; $detail');
      }
      return detail;
    });

    // 4. The device card: the chip from the hardware probe.
    await step('device_card', () async {
      final summary = created.hardware.summary();
      final chip = summary.device
          .where((l) => l.label == 'Chip')
          .map((l) => l.value)
          .firstOrNull;
      final gpu = summary.device
          .where((l) => l.label == 'GPU')
          .map((l) => l.value)
          .firstOrNull;
      final card = find.byType(DeviceCard);
      if (card.evaluate().isNotEmpty) {
        await tester.ensureVisible(card);
        await tester.pump(const Duration(milliseconds: 400));
        await shot('device_card');
      }
      final detail = 'title="${summary.title}" chip="$chip" gpu="$gpu"';
      if (chip == null || chip.startsWith('unknown')) {
        throw StateError('no chip on the card: $detail');
      }
      return detail;
    });

    // 5. The knowledge base: the golden set's on- and off-topic counts.
    await step('kb_golden', () async {
      await pumpUntil(
        tester,
        () => created.knowledge.status.value is KnowledgeReady,
        timeout: const Duration(minutes: 6),
        reason: 'the knowledge base index',
        step: const Duration(seconds: 1),
      );
      final ready = created.knowledge.status.value as KnowledgeReady;
      final golden = jsonDecode(
        await rootBundle.loadString('test_assets/kb_golden.json'),
      ) as Map<String, Object?>;
      var on = 0;
      var onTotal = 0;
      var off = 0;
      var offTotal = 0;
      for (final entry in golden['on_topic']! as List<Object?>) {
        final map = entry! as Map<String, Object?>;
        final q = map['q']! as String;
        final doc = map['expect_doc']! as String;
        onTotal++;
        final r = await created.knowledge.retrieve(q);
        if (r case Ok(:final value)
            when value.candidates.isNotEmpty &&
                value.candidates.first.similarity >= kKbMinSimilarity &&
                value.candidates.take(3).any((p) => p.doc == doc)) {
          on++;
        }
      }
      for (final q in golden['off_topic']! as List<Object?>) {
        offTotal++;
        final r = await created.knowledge.retrieve(q! as String);
        if (r case Ok(:final value)
            when value.candidates.isEmpty ||
                value.candidates.first.similarity < kKbMinSimilarity) {
          off++;
        }
      }
      final detail =
          'on=$on/$onTotal off=$off/$offTotal chunks=${ready.chunks} '
          'origin=${ready.origin.name} index_ms=${ready.elapsed.inMilliseconds} '
          'reused=${ready.reused} skipped=${ready.prebuiltSkipped}';
      if (on < 17 || off < 10) throw StateError(detail);
      if (ready.origin != KnowledgeOrigin.prebuilt) {
        throw _Warn('not the prebuilt index: $detail');
      }
      return detail;
    });

    // 6. Demo 1: a typed question, answered with source chips.
    await step('demo1_chat', () async {
      final vm = await openChat();
      final turn = await ask(vm, _kbQuestion);
      await shot('demo1_answer');
      final detail = '${turnLine(turn)} ${memory()}';
      if (turn.reply.role != ChatRole.assistant || turn.reply.text.isEmpty) {
        throw StateError(detail);
      }
      final chips = find.byKey(KnowledgeChipKeys.citation(1)).evaluate();
      if (turn.sources == 0 || chips.isEmpty) {
        throw StateError(
          'no source chips (${chips.length} on screen): $detail',
        );
      }
      return detail;
    });

    // 7. Demo 1: a plain question, and the accelerator question: the reply
    //    must name the backend the chat model runs on, and should name the
    //    SoC the hardware probe found.
    await step('demo1_accelerator', () async {
      final backend = runningBackend()?.toUpperCase();
      if (backend == null) throw StateError('no chat model running');
      final vm = await openChat();
      final plain = await ask(vm, _plainQuestion);
      await shot('demo1_plain');
      final device = await ask(vm, _deviceQuestion);
      await shot('demo1_accelerator');
      final summary = created.hardware.summary();
      final chip =
          summary.device
              .where((l) => l.label == 'Chip')
              .map((l) => l.value)
              .firstOrNull ??
          '';
      // "Snapdragon 8 Elite (SM8750) · 8 cores": any of its names.
      final socNames = RegExp(
        r'(SM\d{4}|Snapdragon[^·(]*|Tensor[^·(]*|Exynos\s*\d+|Dimensity\s*\d+)',
      ).allMatches(chip).map((m) => m.group(0)!.trim()).toSet();
      final reply = device.reply.text;
      final namesSoc = socNames.any(
        (n) => reply.toLowerCase().contains(n.toLowerCase()),
      );
      final detail =
          'plain{${turnLine(plain)}} device{${turnLine(device)}} '
          'backend=$backend soc_names=$socNames names_backend='
          '${reply.contains(backend)} names_soc=$namesSoc ${memory()}';
      final failed = [plain, device].where(
        (t) => t.reply.role != ChatRole.assistant || t.reply.text.isEmpty,
      );
      if (failed.isNotEmpty) throw StateError(detail);
      if (!reply.contains(backend)) {
        throw StateError('the reply does not name the $backend: $detail');
      }
      if (!namesSoc) throw _Warn('the reply does not name the SoC: $detail');
      return detail;
    });

    // 8. Demo 3: the camera with live boxes (if the rack's camera gives
    //    frames).
    await step('demo3_camera', () async {
      await backToHome();
      final tile = find.byKey(HomeKeys.tile(Demo.liveCamera));
      await pumpUntil(
        tester,
        () => tester.widget<ListTile>(tile).enabled,
        timeout: const Duration(seconds: 30),
        reason: 'the Live camera tile',
        step: _every,
      );
      await tester.tap(tile);
      await pumpUntil(
        tester,
        () => find.byType(LiveCameraScreen).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        reason: 'the camera screen',
        step: _every,
      );
      var frames = 0;
      final watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: 20)) {
        await tester.pump(const Duration(milliseconds: 250));
        if (created.live.frames.value != null) frames++;
        if (created.live.state.value is LiveFailed) break;
      }
      final stats = created.live.stats.value;
      final boxes = created.live.frames.value?.count ?? 0;
      final black = find
          .byKey(LiveCameraKeys.blackFrames)
          .evaluate()
          .isNotEmpty;
      await shot('demo3_camera', platform: true);
      final detail =
          'state=${created.live.state.value.runtimeType} frames_seen=$frames '
          'boxes=$boxes fps=${stats.fps.toStringAsFixed(1)} '
          'run_ms=${stats.runMs?.toStringAsFixed(1)} black=$black';
      if (created.models.states.value[ModelId.yolo26n] is! ModelReady) {
        throw StateError('detector not ready: $detail');
      }
      if (created.live.state.value is LiveFailed || frames == 0) {
        throw _Warn('no camera frames on this device: $detail');
      }
      if (black) throw _Warn('the rack camera gives black frames: $detail');
      return detail;
    });

    // 9. The in-app self-test from the Models screen, on the chosen model.
    await step('self_test', () => selfTest('self_test_report', 'selftest.txt'));

    final summary = steps.map((s) => s.line).join('\n');
    File('${out.path}/summary.txt')
        .writeAsStringSync('$summary\n\nshots:\n${shots.join('\n')}\n');
    final failed = steps.where((s) => s.status == _Status.fail).toList();
    debugPrint(
      'ANDROID_CHECK summary '
      'pass=${steps.where((s) => s.status == _Status.pass).length} '
      'warn=${steps.where((s) => s.status == _Status.warn).length} '
      'skip=${steps.where((s) => s.status == _Status.skip).length} '
      'fail=${failed.length} shots=${shots.length}',
    );
    debugPrint = original;
    expect(failed.map((s) => s.line), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 43)));
}

/// The app's dependencies once created (the helpers above need them).
late AppDependencies Function() deps;
