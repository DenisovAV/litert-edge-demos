# Upstream issues for the flutter_gemma maintainer

Found while wiring this app. Per AGENTS.md rule 6: not patched here.

## `code_assets ^1.2.0` pin blocks hooks-v2 plugins (flutter_soloud 5.x)

- **Packages:** `flutter_gemma_litertlm` 1.8.5 and `flutter_gemma_rag_sqlite` 1.4.0 (the latest of each on
  2026-10-01) both declare `code_assets: ^1.2.0` (with `hooks: ^2.0.0`).
- **Effect:** any app that also depends on a plugin built on `code_assets` 2.x cannot resolve. Hit with
  `flutter_soloud` ≥ 5.0.0-pre.2 (latest 5.1.5):
  ```
  Because flutter_soloud >=5.0.0-pre.2 depends on code_assets ^2.0.0 and flutter_gemma_rag_sqlite >=1.1.0
  depends on code_assets ^1.2.0, flutter_soloud >=5.0.0-pre.2 is incompatible with flutter_gemma_rag_sqlite >=1.1.0.
  ```
- **Workaround in this app:** `flutter_soloud: ^4.1.7`.
- **Ask:** widen to `code_assets: '>=1.2.0 <3.0.0'` (or move to ^2.0.0) in both packages, after checking the
  build hooks against the 2.x API.

## flutter_gemma_agent → flutter_inappwebview_ios: app dies at launch on iOS < 26 (Xcode 26 builds)

- **Chain:** `flutter_gemma_agent` 0.2.6 → `flutter_inappwebview` → `flutter_inappwebview_ios` 1.1.x (CocoaPods; no
  SwiftPM support, which also turns this SPM app into an SPM + CocoaPods hybrid on iOS and macOS).
- **Effect:** built with Xcode 26.5 (iOS SDK 26.5, app deployment target 15.0), the framework has a **strong**
  `LC_LOAD_DYLIB /usr/lib/swift/libswiftWebKit.dylib` (`otool -l`: `minos 15.0`, `sdk 26.5`). That dylib exists in
  the iOS 26.5 runtime but not in iOS 18.5, so on iOS 18.5 dyld aborts before `main`:
  ```
  Library not loaded: /usr/lib/swift/libswiftWebKit.dylib
  Referenced from: …/Runner.app/Frameworks/flutter_inappwebview_ios.framework/flutter_inappwebview_ios
  ```
  Reproduced on the iOS 18.5 simulator on 2026-10-01. The real-device build has the same strong link, so any iPhone
  on iOS < 26 is expected to crash the same way. Effective iOS floor: 26, whatever the deployment target says.
- **Possible fixes:** upstream weak-links the overlay (`-weak-lswiftWebKit`) or stops using the Swift-only WebKit
  API. Or `flutter_gemma_agent` makes the JS-skill WebView optional (a separate package or a federated opt-in), so
  apps that don't run JS skills don't link WebKit at all.
- **App-side workaround (not applied):** in `ios/Podfile` `post_install`, add `-Wl,-weak-lswiftWebKit` to the
  `flutter_inappwebview_ios` target's `OTHER_LDFLAGS`. It's only safe if JS skills never run on iOS < 26.

## flutter_gemma_agent `schedule_notification`: plugin never initialized, Android setup undocumented

- **Where:** `flutter_gemma_agent` 0.2.6, `lib/src/executors/native_intent_executor.dart:326` —
  `plugin.zonedSchedule(..., androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle)`. Nothing in the package
  calls `FlutterLocalNotificationsPlugin().initialize(...)`.
- **Effect:** with no `initialize()` there is no default Android small icon and no iOS permission request. On Android
  31+, without an exact-alarm permission, flutter_local_notifications throws `exact_alarms_not_permitted`. Without
  its `ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver` in the app manifest (the plugin doesn't
  merge them), the alarm fires into nothing. The README "Setup" mentions only desugaring.
- **Ask:** either initialize the plugin inside the executor (or expose an init hook), and document the manifest
  entries plus the exact-alarm permission choice in the README; or state that the app owns the notification setup.
- **This app:** manifest entries added; `initialize()` belongs in app startup once the timer skill exists.

## flutter_gemma_agent 0.2.6 on pub.dev ships no bundled SKILL.md files

- **Evidence:** the published package (`~/.pub-cache/hosted/pub.dev/flutter_gemma_agent-0.2.6`) contains only
  `README.md` and `CHANGELOG.md` as `.md` files, yet its `pubspec.yaml` declares `assets/skills/calculate-hash/`,
  `assets/skills/qr-code/`, …. The repo's `.pubignore` excludes `**/*.md` except README and CHANGELOG.
- **Effect:** `AssetSkillSource.load()` catches the missing assets and returns `[]`, so the bundled skill catalog
  comes back silently empty. No error, no log.
- **Ask:** re-include `assets/skills/**/SKILL.md` in `.pubignore` (e.g. `!assets/skills/**/*.md`). Optionally, make
  an empty asset catalog loud in debug builds.
- **This app:** Demo 1 ships its own skills (docs/design/demo1-voice-chat.md, D12–D13), so it is not affected.

## `InferenceChat.currentTokens` never counts user text

- **Where:** flutter_gemma 1.11.3 `lib/core/chat.dart` — `_currentTokens` grows only by `+= 257` per image (:198)
  and by `responseTokens` after a reply (:714). User-message text is never added.
- **Effect:** the context-budget check (`_currentTokens >= maxTokens - tokenBuffer`, :717/:937) reads low. With RAG
  excerpts (~1k tokens per turn) the chat can overflow the native context before the Dart trimming kicks in.
- **Ask:** count user text (or read native session metrics). **This app:** uses the native
  `getSessionMetrics().totalTokens` for the overlay and budget (Demo 1 Inc 5).

## macOS: no GPU top-k sampler staged → LiteRT-LM samples on CPU

- **Evidence:** `~/Library/Caches/flutter_gemma/native/macos_arm64/` has no `libLiteRtTopKMetalSampler.dylib` (Android
  ships `libLiteRtTopKOpenClSampler.so` / `libLiteRtTopKWebGpuSampler.so`). The macOS native log shows
  `Could not load shared library libLiteRtTopKMetalSampler.dylib` and `sampler_factory.cc:771] GPU sampler
  unavailable. Falling back to CPU sampling`.
- **Effect:** the decoder runs on the GPU, but every token's top-k sampling round-trips to the CPU. It still works
  (~66 tok/s on E2B in Demo 1 Inc 1), so expect some throughput left on the table. Not checked on iOS yet.
- **Ask:** ship and stage the Metal sampler for macOS (and iOS if it's missing there too), or document that it's
  expected.

## flutter_gemma_speech 0.5.2 — found while specifying Demo 1 Inc 3

Details and file:line citations: `docs/design/inc3-voice-wiring.md` §8.
- **U1** There is no getter for the STT/TTS backend actually used, and reusing the singleton ignores a different
  `preferredBackend`. An app can't show the real backend or fail fast on a fallback.
- **U2** The TTS installer has no `fromFile(s)`, only network. Offline or pre-provisioned demo devices can't install
  TTS from local files.
- **U3** The `VoiceSession` clause splitter can't be injected (`voice_session.dart:342`), so there's no app-side
  control over clause boundaries (abbreviations, citations, numbers).
- **U4** The worst case for `interrupt()` is 2 × `drainTimeout` (≈10 s: stop timeout, then drain), which isn't
  documented. An `interrupt()` issued before anyone listens to the turn stream hangs: the driver starts on
  `onListen` (`voice_session.dart:210-213`, :241-266).
- **U5** The example says "Inflect (Metal)" (`flutter_gemma_speech/example/lib/main.dart:196-197`), but the default
  backend is the CPU.
- **U6** (found in Inc 3) A `VoiceSession` turn that ends normally never completes inside `testWidgets`: after the
  reply stream ends, `_drive` runs `await sub.cancel()` (`voice_session.dart:451`) on the finished subscription,
  which returns the root zone's completed null future, and its continuation is queued on the root zone's microtask
  queue, which the fake clock of `testWidgets` never runs. Turns that are interrupted with a forced drain skip the
  cancel and do complete. Plain `test()` (real async) is unaffected. This app's widget test wraps the end of a turn
  in `tester.runAsync`. **Ask:** skip `sub.cancel()` when the stream is already done (or don't await it), and note
  it in the testing docs.

## camera_desktop 2.0.0 (third party, hugo.ml): macOS runtime camera errors are dropped

- **Evidence:** the Swift side sends `cameraError` with the key `"message"`
  (`macos/camera_desktop/Sources/camera_desktop/CameraSession.swift:299, :309`). The Dart handler reads
  `args['description']! as String` (`lib/src/camera_desktop_plugin.dart:122`), which throws, so no
  `CameraErrorEvent` is ever emitted.
- **Effect:** when the camera is unplugged, interrupted or taken by another app, the app is never told. The preview
  freezes and the stream simply stops.
- **This app:** a source watchdog in `LiveDetectionRepository` fails the pipeline after 2 s without frames (D3-2
  review fix).
- **Ask (camera_desktop maintainer):** use one key on both sides.

## flutter_gemma_agent 0.2.6: found while specifying Demo 1 Inc 6

Details: `docs/design/inc6-7-skills-wiring.md`.

| # | Issue | Where |
|---|---|---|
| U-A1 | Map/List tool args are stringified with `toString`, not `jsonEncode` | `agent_loop.dart:453-457` |
| U-A2 | Custom `NativeIntentExecutor` handlers always fail validation, so the app needs its own `SkillExecutor` | `native_intent_executor.dart:153`, `:528-529` |
| U-A3 | A cancelled tool round's staged response is prepended to the next user message | `chat.dart:864-884`; flutter_gemma_litertlm ffi `:449-463`, `:485` |
| U-A4 | Selection toggles never reach the model: the prompt is built once and `get` ignores selection. `addAll` defaults to `selected: false`, which leaves the prompt's skill list empty | `agent_session.dart:140-156`; `skill_registry.dart:58-66`; `ui/skill_manager_view.dart:242-244` |
| U-A5 | Cancelling the `ask` subscription doesn't stop native generation, so callers must call `stopGeneration()` and drain | `agent_loop.dart:225-236` |
| U-A6 | A non-string `name` in SKILL.md front matter throws `TypeError` instead of a parse error | `skill_md_parser.dart:60-61` |
| U-A7 | (found in Inc 6) A stop that cuts a generation short still ends the run with `DoneEvent` (the partial text): core returns on a call-free turn without polling `isCancelled`, so `cancelledSeen` stays false. `AgentLoop.run`'s doc promises no `DoneEvent` after a cancel. This app decides "stopped" from its own flag (`test/data/repositories/conversation_repository_skills_test.dart`, "Stop during the answer") | `chat.dart` `generateChatResponseWithTools` (`if (pending.isEmpty) return;`); `agent_loop.dart:217-222` |

## flutter_gemma 1.11.3 / rag_sqlite 1.4.0: found while specifying Demo 1 Inc 4–5

Details: `docs/design/inc4-5-images-rag-wiring.md` §upstream. Numbered there U1–U5; prefixed IR- here so they don't clash with the speech U1–U6.

- **IR-U1** (extends the `currentTokens` issue) An image counts as 257 tokens; Gemma 4 measures ~270. Message removal
  subtracts `images.length × 257` (`chat.dart:944-947`), which is 0 for `Message(imageBytes:)`.
- **IR-U2** `_recreateSessionWithReducedChunks` (`chat.dart:936-962`) replays history through `addQueryChunk`. On FFI
  that only buffers into the next user turn (`ffi_inference_model.dart:402-445`), so all history and every earlier
  image get glued onto one message. Rebuild through `messagesJson` instead.
- **IR-U3** `maxNumImages` isn't enforced: document what it does or enforce it.
- **IR-U4** An image on a non-vision session should throw, not be dropped (`:434`).
- **IR-U5** `SqliteVectorStore` has no batch insert. Each row autocommits on the caller's isolate (`:297`).

**macOS testing note (not a bug):** an integration-test app that is not in focus gets App Nap'd after ~30 s (embeddings 9× slower, image prefill 10 s). Before latency tests: `defaults write dev.fluttergemma.litertHackathon NSAppSleepDisabled -bool YES`. Set on this Mac on 2026-10-02.

## flutter_gemma_speech 0.5.2 U7: STT on GPU fails or silently returns garbage

- **Where:** STT can request the GPU (`litert_graph.dart:36-40` → `stt_core.dart:427`).
- **Whisper base int8 on GPU** fails to load: `LiteRtCreateCompiledModel (status=3)`.
- **moonshine-tiny on GPU** loads but returns garbage ("The death of the family of the family…"). Nothing validates
  the output, so an app gets wrong transcripts with no error. Measured on macOS, 2026-10-02.
- **Ask:** reject unsupported GPU STT at load, or validate it with a known clip at warm-up. Also expose the backend
  actually used (see U1).
- **This app:** STT stays on CPU. Demo 3 uses moonshine-tiny (~65 ms per question vs 1.8 s for Whisper base, which
  always encodes a 30 s window). Demo 1 keeps Whisper base (30 s window). The STT singleton switches when you enter a
  demo (`flutter_gemma_desktop.dart:584-605`).

## flutter_gemma_litertlm 1.8.5: image JSON encoding runs on the main isolate

- `LiteRtLmFfiClient.buildMessageJson` does base64 + `jsonEncode` + `toNativeUtf8` of the image on the caller's
  (main) isolate. A standalone AOT benchmark on an M4 Pro measured 6.5 ms for a 790 KB PNG and 12.9 ms for 1.58 MB,
  probably 2–3× more on phones, at the start of every image turn. Not yet measured inside the app.
- **Ask:** do it off the main isolate, or pass the image bytes natively without base64 JSON.

## flutter_gemma_agent 0.2.6 / flutter_gemma_litertlm 1.8.5: found while measuring Demo 1 latency (Inc 8)

Measured with `integration_test/first_turn_latency_test.dart` on macOS (M4 Pro), each turn on a fresh chat.

- **IL-1 The `runIntent` tool description invites invented intents.** `agent_tools.dart:84-102` describes it as
  "Run a native intent. It is used to interact with the device to perform certain actions." With the two-tool agent
  chat (`loadSkill`, `runIntent`) at temperature 0.6, Gemma 4 E2B called `runIntent` with an invented intent
  (`AnswerQuestion`, `get_location`, `image-classification`, `camera-watch`) on 7 of 18 plain or photo questions
  (photo questions 5 of 6). Each call costs an extra generation (+0.3–1.0 s before the first text). This app
  declares its own `loadSkill` / `runIntent` with the same names and parameters but descriptions that tie
  `runIntent` to a loaded skill (`kAgentTools`), which with a stricter system prompt brought it to 3 of 18.
  **Ask:** tie the description to loaded skills ("Runs an intent that a loaded skill's instructions name"), or let
  apps pass the descriptions.
- **IL-2 No way to prefill a conversation's preface ahead of the first turn.** LiteRT-LM prefills the system message
  and the tool declarations with the first user message (`ffi_inference_model.dart` / `litert_lm_client.dart:1112-1139`:
  `conversation_config_set_system_message` / `_set_tools`, no prefill call). The agent chat's first turn therefore
  prefills ~390 extra tokens (+~150 ms on the GPU, steady state). The native API has `litert_lm_conversation_clone`
  and `litert_lm_session_run_prefill` (`litert_lm_bindings.dart:848, 1420`), but neither is exposed through
  `InferenceModel` / `InferenceChat`. **Ask:** an `InferenceChat.prefill()` (or a cloned, pre-prefilled preface) so an
  app can pay the system prompt when a screen opens, without a dummy turn in the history.

## flutter_litert 3.9.3 (third party, hugocornellier): Linux crash next to flutter_gemma

Found on 2026-10-05 while preparing the Linux build. Patched locally: `tool/flutter_litert/flutter_litert-3.9.3.patch`,
applied by `tool/flutter_litert/vendor.sh` (`dependency_overrides` → `third_party/flutter_litert`). Details:
[design/detector-linux.md](design/detector-linux.md).

- **FL-1 The model-loading ABI is chosen by platform, not by the loaded library.** LiteRT 2.1.6 added an
  environment as the first argument of `LiteRtCreateModelFromBuffer` / `…FromFile` without renaming the symbols.
  `bindings/litert_ffi.dart:100-139` uses the new signature only when `Platform.isAndroid`. On Linux an app that also
  uses flutter_gemma loads flutter_gemma's newer `libLiteRt.so` (same file name in `bundle/lib`, it overwrites
  flutter_litert's 2.1.5 copy). The legacy call then passes the buffer as the environment, and the process dies in
  `CompiledModel.fromBuffer`. Reproduced on macOS with `LITERT_LIB_PATH` pointed at flutter_gemma's
  `libLiteRtLm.dylib` (same LiteRT pin, exports the same C API): crash before `compiled_model.cc` logs anything; with
  the patch the CPU output is bit-identical to 2.1.5 (sum 10824521.620584637). **Ask:** decide per library. Do not
  use `LiteRtCreateModelFromFd` alone as the marker (our first patch did): flutter_litert's own iOS runtime
  (`litert-ios-v1.0.1`) exports it, yet its `LiteRtCreateModelFromBuffer` takes `(buffer, size, model)` (arm64
  disassembly, device and simulator slices), so an environment-first call fails every iOS model with
  `kLiteRtStatusErrorInvalidFlatbuffer` (501). Our patch keeps the platform rule on iOS. In every binary we inspected,
  `LiteRtCreateModelFromAllocation` tracks the environment ABI: present in Android 2.2.0 and the LiteRT-LM v0.17.1
  bundle, absent from macOS 2.1.5 and `litert-ios-v1.0.1`.
- **FL-2 Linux ships x86_64-only runtimes with a glibc 2.38 floor for the Interpreter.** `linux/lib/libLiteRt.so`
  (GLIBC_2.27) and the downloaded `libLiteRtWebGpuAccelerator.so` are x86_64 only; `libtensorflowlite_c-linux.so`
  needs GLIBC_2.38 (Ubuntu 24.04+) and has no arm64 build. `verifyCompiledModel` depends on that Interpreter, so on
  Ubuntu 22.04 and on arm64 (Jetson) it can only return *skipped*. **Ask:** arm64 builds and a lower glibc floor, or a
  `verifyCompiledModel` reference that can use the LiteRT CPU path.

## flutter_edge_ai 2.1.0: the active STT model is persisted as five separate keys

- **Where:** `MobileModelManager._persistActiveSttIdentity`
  (`lib/core/model_management/managers/mobile_model_manager.dart`) writes `active_stt_filename`,
  `active_stt_tokenizer_filename`, `active_stt_model_type`, `active_stt_source` and `active_stt_tokenizer_source`
  with five `SharedPreferences.setString` calls under one `Future.wait`. Each is its own write; nothing makes the
  five land together.
- **Seen:** 2026-10-07, macOS, `integration_test/camera_assistant_test.dart`. The test switches the active STT to
  moonshine and back to Whisper; the process exited during the switch back. On disk: `active_stt_filename` was
  Whisper's, the other four were moonshine's.
- **Effect:** `_restoreActiveSttModel` on the next launch reads `active_stt_filename` + `active_stt_tokenizer_filename`
  + `active_stt_model_type` without checking they belong together, so it can build a spec of Whisper weights with
  moonshine's tokenizer and type. This app re-activates its recognizer on every demo entry, so it is not hit; an app
  that relies on the restored model would get a broken recognizer until it activates one again.
- **Ask:** persist the identity as one value (one JSON string under one key, written once), or write a version
  marker last and ignore a set whose marker does not match; the same applies to the TTS and embedding identities
  written the same way.

## flutter_edge_ai_litertlm 1.9.0 + flutter_litert ≥ 3.4.0 on iOS: `LiteRtMetalAccelerator.framework` collides

- **Packages:** `flutter_edge_ai_litertlm` 1.9.0 (Native Assets, `native-v0.17.1-a`) and `flutter_litert` 3.9.3
  (SwiftPM, `litert-ios-v1.0.1`, LiteRT 2.1.5). Both ship a framework named `LiteRtMetalAccelerator.framework`.
- **Effect (iPhone 17 Pro, iOS 26.5.2, 2026-10-08):** the app keeps one copy, LiteRT-LM's (Native Assets embed after
  SwiftPM and overwrite it silently). Gemma runs on Metal; flutter_litert's runtime logs
  `GPU accelerator could not be loaded and registered`, so every flutter_litert GPU model fails (our detector:
  "failed on the GPU"). ~40 duplicate ObjC classes are reported between `LiteRtMetalAccelerator` and `LiteRt`.
- **Why now:** flutter_litert 3.4.0 replaced its bare `libLiteRtMetalAccelerator.dylib` with a framework of the same
  name as LiteRT-LM's (App Store ITMS-90426, its issue #15); `~/Work/litert_demo` (3.3.1, simulator, CPU) predates it.
- **Workaround in this app:** the detector's standard backend on iOS is the CPU (`standardDetectorBackend()`).
- **Ask:** ship LiteRT-LM's Metal accelerator under its own name (e.g. `LiteRtLmMetalAccelerator.framework`):
  `hook/build.dart:241` companions, `native/litert_lm/patch_c_api.sh:339` (`FLUTTER_GEMMA_METAL_FW_PATH`), the native
  release tarballs. Full brief: [handoff/flutter-edge-ai-ios-metal-accelerator-collision.md](handoff/flutter-edge-ai-ios-metal-accelerator-collision.md).
