# Platform setup checklist

Source: `flutter-reviewer` smoke review of the fresh scaffold, 2026-10-01. Requirements: `AGENTS.md` →
"Platform requirements". Tick each item only after verifying it (build + run), not after editing.

Worked through 2026-10-01. Logs of every verification run: `build/setup-logs/` (gitignored). Platform smoke test:
`integration_test/model_smoke_test.dart` — loads Gemma 4 E2B from a local `.litertlm`, fails on a silent GPU→CPU
fallback, expects "Paris".

## Android
- [x] `android/app/build.gradle.kts`: `minSdk = 30` — APK badging `minSdkVersion:'30'`.
- [x] `android/app/build.gradle.kts`: arm64-v8a only — **`abiFilters.clear()` then `+= "arm64-v8a"`**: a bare `+=`
  is a no-op, because the Flutter Gradle plugin has already filled the set with every Flutter ABI
  (`FlutterPlugin.configureAbiWithoutSplits`). Before the fix the APK carried `armeabi-v7a` + `x86_64`; now `lib/`
  holds only `arm64-v8a`.
- [x] Desugaring: `isCoreLibraryDesugaringEnabled = true` + `desugar_jdk_libs:2.1.5` (latest on Google Maven); AGP 9
  opt-out `android.r8.proguardAndroidTxt.disallowed=false` in `gradle.properties` — needed, because
  `flutter_inappwebview_android` resolves to 1.1.3. `flutter build apk --debug` is green.
- [x] Main manifest: `INTERNET`, `CAMERA`, `RECORD_AUDIO` — present in APK badging. 2026-10-06: `POST_NOTIFICATIONS`
  is removed from the merged manifest (`tools:node="remove"`; flutter_local_notifications merges it): the app posts no
  notifications.
- [x] Agent timers (found in final review): `flutter_gemma_agent`'s `schedule_notification` calls
  `zonedSchedule(exactAllowWhileIdle)`, so the manifest also has `SCHEDULE_EXACT_ALARM` (maxSdk 32) + `USE_EXACT_ALARM`
  and flutter_local_notifications' `ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver` (the
  plugin does not merge them). ~~Still needed in Dart: `FlutterLocalNotificationsPlugin().initialize(...)`.~~ Not
  needed: Demo 1's timers are in-app Dart timers with a spoken announcement (design D14); the app never calls
  `schedule_notification` (verified 2026-10-02: no `flutter_local_notifications` use in `lib/`). 2026-10-06: the
  timer skill is gone, and so are the exact-alarm permissions and both receivers (the app never registers the
  agent's `NativeIntentExecutor`, so `schedule_notification` cannot run).
- [x] `android.builtInKotlin=false` kept.
- [ ] Verify on a real arm64 device — **no Android device connected** on 2026-10-01; only builds are verified:
  `flutter build apk --debug` and `--release` (R8 passes with the AGP 9 opt-out; release `lib/` = 39 × arm64-v8a;
  manifest had the receivers + exact-alarm permissions then; removed 2026-10-06). Gotcha: never run `flutter test` concurrently with
  `flutter build apk --release` in this project — `flutter test` regenerates `GeneratedPluginRegistrant.java` with the
  `integration_test` dev plugin and the release build then fails with `package dev.flutter.plugins.integration_test
  does not exist`.
  On the device run, also check LiteRT coexistence: `libLiteRt.so` comes only from flutter_litert (LiteRT 2.2.0,
  `downloadLitertJni`), `libLiteRtLm.so` does not link it (own runtime), but the GPU accelerator plugins
  (`libLiteRtGpuAccelerator.so`, `libLiteRtOpenClAccelerator.so`, …) come only from flutter_gemma — confirm
  flutter_litert's `CompiledModel` on GPU works with them (or doesn't load them). Command:
  `adb push gemma-4-E2B-it.litertlm /sdcard/Android/data/dev.fluttergemma.litert_hackathon/files/` (adb can't
  write `/data/data`; the app's documents dir is `app_flutter/`, not `files/`), then
  `fvm flutter test integration_test/model_smoke_test.dart -d <id>
  --dart-define=GEMMA_MODEL_PATH=/sdcard/Android/data/dev.fluttergemma.litert_hackathon/files/gemma-4-E2B-it.litertlm`.
  The `/sdcard/Android/data/<pkg>/` dir exists only after the app has been installed once.

## iOS
- [x] `ios/Runner/Info.plist`: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`,
  `NSPhotoLibraryUsageDescription`.
- [ ] Entitlements Increased Memory Limit + Extended Virtual Addressing — `ios/Runner/Runner.entitlements` created
  and linked via `CODE_SIGN_ENTITLEMENTS` in Debug/Release/Profile (what Xcode's Signing & Capabilities writes).
  **Not verified in a signed build:** Xcode on this Mac has no Apple ID (Settings → Accounts is empty), and there
  are no provisioning profiles for team `6ZHF6A3G28`. Sign in, then the first signed build registers both
  capabilities on the App ID; check with `codesign -d --entitlements - build/ios/iphoneos/Runner.app`.
- [x] Deployment target 15.0 in all 3 build configs; `ios/Podfile` now declares `platform :ios, '15.0'`.
- [x] ~~Project uses SwiftPM (no Pods).~~ **No longer true:** `flutter_inappwebview_ios`/`_macos` (via
  `flutter_gemma_agent`) have no SwiftPM support, so iOS and macOS are an SPM + CocoaPods hybrid. Both Podfiles use
  plain `use_frameworks!` (no `:linkage => :static`). Unsigned device build (`flutter build ios --no-codesign`) is
  green; LiteRT copies are separate dynamic frameworks (`LiteRt`, `LiteRtLm`, `LiteRtMetalAccelerator` from
  flutter_gemma; `TensorFlowLiteC*`, `flutter-litert` from flutter_litert).
- [ ] Verify on a real iPhone — blocked on signing (above). Interim evidence: iOS 26.5 simulator smoke test passes
  (CPU, load 4.7 s, "Paris").
- [ ] **New: effective iOS floor is 26.** `flutter_inappwebview_ios` built with the Xcode 26.5 SDK strongly links
  `/usr/lib/swift/libswiftWebKit.dylib`, so on iOS 18.5 the app aborts in dyld before `main` (reproduced on the
  simulator; the device build has the same link). Decide: accept iOS 26+ demo devices, or apply the weak-link
  workaround. Details: [upstream-issues.md](upstream-issues.md).
- Note (Inc 6 review): `UIFileSharingEnabled` exposes all of Documents in the Files app and Finder, including
  `skills/` and everything flutter_gemma keeps there — the ~2.6 GB Gemma `.litertlm` and the other model files. A
  user can delete or replace them. Kept on purpose for the "add a skill without a rebuild" demo (parent decision,
  2026-10-02); revisit before any release build (e.g. move models to Application Support, or turn sharing off).

## macOS
- [x] Both entitlements files: `network.client`, `device.audio-input`, `device.camera`, `cs.disable-library-validation`
  — read back with `codesign -d --entitlements` from the built Debug and Release apps. DebugProfile also has a
  read-only sandbox exception for `~/Work/` (local models); Release does not.
- [x] `macos/Runner/Info.plist`: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`.
- [x] `com.apple.security.files.user-selected.read-only` in both files (found in final review): `image_picker` on
  macOS uses `file_selector` / NSOpenPanel, which the sandbox blocks without it.
- Note: `camera` 0.12.1 has **no macOS implementation** (android/ios/web only). For macOS development Demo 3 adds
  `camera_desktop` 2.0.0 (implements `camera_platform_interface`; frames BGRA, mirrored natively) — D3-2 in
  `docs/design/demo3-live-camera.md`. The macOS camera entitlement and usage string are already in place.
- Note: two Metal accelerators will sit in one process on macOS/iOS — flutter_litert's `libLiteRtMetalAccelerator.dylib`
  (in Resources) and flutter_gemma's staged `LiteRtMetalAccelerator.framework`. Check detector + Gemma both on GPU
  once the detector exists.
- [x] Run Script phase `[flutter_gemma] Setup LiteRT-LM macOS` on the Runner target only, after Flutter's embed
  `ShellScript` phase (CocoaPods' `[CP] Embed Pods Frameworks` follows it — harmless, it only copies the
  inappwebview/OrderedSet frameworks), recipe verbatim (input = embedded `LiteRtLm` binary, output = stamp). The build log shows the stager repointing and
  re-signing `LiteRtLm`. With CocoaPods now active on macOS, `pod install` leaves the phase alone.
- [x] Verify: sandboxed Debug app loads `~/Work/gemma-4-E2B-it.litertlm` on **GPU** and answers "Paris" (load 14.1 s,
  first token 254 ms).

## Dependencies
- [x] Added: `camera` 0.12.1, `record` 7.1.1, `audio_session` 0.2.4, `provider` 6.1.5+1, `flutter_litert` 3.9.3,
  `image_picker` 1.2.3, `path_provider` (now a regular dependency, see below); dev: `integration_test`.
- [x] `flutter_soloud` **4.1.7, not 5.x**: 5.x needs `code_assets ^2.0.0`; `flutter_gemma_litertlm` 1.8.5 and
  `flutter_gemma_rag_sqlite` 1.4.0 pin `^1.2.0` → [upstream-issues.md](upstream-issues.md).
- [x] ~~`vad`~~ — not added: both demos are push-to-talk (design D5); VAD stays a post-v1 option.

## Analyzer
- [x] Enabled `unawaited_futures`, `discarded_futures`, `cancel_subscriptions`, `close_sinks`; `flutter analyze` clean.

## Pre-builds (Inc 8)
- [x] 2026-10-02, on 70a7bd9, sequential and never alongside `flutter test`: `fvm flutter build apk --release` →
  157.7 MB, `lib/` holds 39 × arm64-v8a; `fvm flutter build ios --release --no-codesign` → Runner.app 81.8 MB;
  `fvm flutter build macos --release` → 157.5 MB. Native prebuilts are now in the local caches. A signed iOS
  build is still pending (no Apple ID in Xcode).

## Toolchain
- [x] `.fvmrc` pins 3.47.3 (what AGENTS.md documents and the global `flutter` already ran; the 3.47.4/3.47.5 hotfixes
  cover iOS 27 / Xcode 27 / Windows / App Store only). `.fvm/` gitignored; AGENTS.md says to run `fvm flutter`.
  Side note outside the repo: the global fvm `default` folder is named `3.47.2` but is checked out at 3.47.3.
- [x] **Models not in git** (2026-10-08, user decision): once per checkout, after `tool/flutter_litert/vendor.sh`, run
  `tool/fetch_models.sh` (`HF_TOKEN` in `.env` or the environment for the gated EmbeddingGemma). It fetches the 13
  built-in files (about 420 MB) from `tool/models.lock` and checks each SHA-256. YOLO26n is derived from Arm's
  original with the pinned ai-edge-litert 2.2.0, byte for byte. Verified from a clean worktree of 41d102f:
  `assets/models/` held only `NOTICE.md`, and without models `flutter analyze` gave 8 `asset_does_not_exist`
  warnings and `flutter test` stopped with "No file or variants found for asset". The fetch took 50 s. That run had
  no token, so the two EmbeddingGemma files were copied from the main tree; the gated download itself is still
  unverified. Every SHA-256 matched (`shasum -c`), the YOLO derivation reproduced, and a rerun fetched nothing
  (0.35 s). Then analyze was clean, `flutter test` gave 2192 pass and 4 skipped, and `build macos --debug`
  succeeded; the app bundle's copies passed `--check --dir`. `integration_test/macos_check_test.dart` passed all 6
  steps: choose_model, built_in_models, kb_prebuilt, demo1_voice ("Paris"), demo1_kb and self_test.

## Demo 1 follow-ups (from docs/design/demo1-voice-chat.md, 2026-10-02)
- [x] `path_provider` from `dev_dependencies` → `dependencies` — verified in `pubspec.yaml` (`path_provider: ^2.1.6`
  under `dependencies`), 2026-10-02.
- [x] `pubspec.yaml` `flutter: assets:` → `assets/skills/` (per skill subdir) and `assets/kb/` (Inc 5/6).
- [x] iOS Info.plist `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` so new SKILL.md files can be
  dropped in via Finder/Files without a rebuild (Inc 6). Not yet verified on an iPhone.
- Note: `image_picker_macos` ignores `maxWidth`/`imageQuality` and throws for the camera source — normalize images in
  Dart; camera capture is iOS/Android only.
- Note (updated 2026-10-08): Inflect-nano-v2 is built into the app since 2026-10-07 (`assets/models/inflect/`,
  installed with `installTts().fromFile`); `tool/fetch_models.sh` fetches its six files with the other built-in models
  before a build, and nothing comes from the network at run time. (The TTS installer in flutter_gemma 1.11.3 had only
  `fromNetwork`.)
