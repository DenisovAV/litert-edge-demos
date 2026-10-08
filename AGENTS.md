# LiteRT Hackathon — Flutter on-device AI demos

One Flutter app (`litert_hackathon`, org `dev.fluttergemma`, platforms android/ios/macos/linux) hosting two demos
that share one stack (ASR, TTS, a chat LLM from a `.litertlm` file, detector). Full specs:
[docs/demos.md](docs/demos.md).
Platform setup ([docs/setup-checklist.md](docs/setup-checklist.md)): 24 of its 28 items are done; the 4 open ones are a
real Android device run, iOS signing (its entitlements and a real iPhone run) and the effective iOS 26 floor.

- **Demo 1 — Multimodal voice chat with skills**: voice in → the chat LLM, e.g. Gemma 4 E2B (+ camera/gallery
  image) → streamed text + TTS from the first finished sentence; pre-loaded knowledge base (EmbeddingGemma +
  sqlite-vec) with cited sources; agent skills (current time; device/accelerator info from the hardware report:
  chip/SoC, GPU, each model's actual backend) plus SKILL.md files added at run time without a rebuild. Camera
  watcher and timers were removed on 2026-10-06. The chat model is the `.litertlm` the user chooses (Gemma 4 E2B,
  or e.g. a Qualcomm NPU build) and the **only** one: the app ships none.
- **Demo 3 — Live camera assistant**: always-on camera, real-time boxes from a litert-community detector; voice
  questions; simple ones answered from the detection list (no LLM image path), detailed ones send the current
  frame to the chat model (when its images are on); spoken replies.

## Stack decisions (as of 2026-10-01 — re-verify before pinning)

| Need | Decision | Why / caveat |
|---|---|---|
| LLM | a `.litertlm` from a file, via `flutter_edge_ai` + `flutter_edge_ai_litertlm` — the app ships none: models folder (Android adds `/data/local/tmp/litert-models`), Path…, Import, Download from URL | user decision 2026-10-07; e.g. ungated `litert-community/gemma-4-E2B-it-litert-lm` (~2.6 GB, image+audio, tools) or a Qualcomm NPU build; defaults from its header (NPU build: NPU, images off) |
| ASR | `flutter_edge_ai_speech` STT — moonshine-tiny (EN, 5 s window) and Whisper base (multilingual, 30 s), **built into the app** (`assets/models/`) | **batch only, no VAD** → add endpointing (push-to-talk or `vad`/Silero); Parakeet 0.6B is desktop-class (~2.4 GB) |
| TTS | `flutter_edge_ai_speech` TTS — **Inflect-nano-v2**, built in (`assets/models/inflect/`, `installTts().fromFile`) | spec says Qwen-TTS: Qwen3-TTS 0.6B works but is CPU-only, RTF≈3 (~3 s compute per 1 s audio), ~1.9 GB, 6 GB-RAM-class device — per the maintainer's catalog note in `flutter_gemma/packages/flutter_gemma/example/lib/models/tts_model.dart` (API accepts `preferredBackend`, but GPU is not supported for it) → optional "multilingual" mode only; re-measure on device |
| Sentence-by-sentence speech | `VoiceSession(streamAudio: true)`; with images use `VoiceSession.custom` + a responder over `AgentSession.ask(imageBytes:)` speaking `TextChunkEvent`s | `fromChat` has no image parameter |
| Embeddings | **EmbeddingGemma-300M** (`litert-community/embeddinggemma-300m`, gated, 768-dim) | spec says "EmbeddingGemma 2": it exists since LiteRT-LM v0.18.0 (2026-10-06; multimodal, Matryoshka truncation), but the app stays on 300M and its prebuilt index — switching would need a new index (`tool/build_kb_index.sh`); 300M is built into the app (`assets/models/`, Gemma Terms in `NOTICE.md`); no download at run time; `tool/fetch_models.sh` needs `HF_TOKEN` to fetch it before a build |
| Vector store | `flutter_edge_ai_rag` + `flutter_edge_ai_sqlite` (one `RagIndex`, sqlite-vec `vec0`, bound to an embedding profile) | chunking + citation formatting are app code; source in `metadata` JSON; prebuilt index in `assets/kb_index` (`tool/build_kb_index.sh`) |
| Agent skills | `flutter_edge_ai_agent` (`AgentSession`, SKILL.md) | runtime loading = read `*.md` from a directory → `parseSkillMd` → `SkillRegistry.addAll`; **custom intents fail upstream** (`validateIntentParams` default branch) → custom `SkillExecutor` for `SkillType.intent` |
| Detector | **YOLO26n** from `Arm/yolo26n-fp16-litert`, used through the derived `yolo26n_fp16_rawhead.tflite` (`tool/prune_yolo26n_head.py`: head cut at `[1,8400,84]`, ADD→v1). Input `[1,3,640,640]` NCHW float32, RGB/255, letterbox pad 114; top-k in Dart, no NMS. Contract: `docs/design/detector-yolo26n.md`. Built into the app as a Flutter asset (`assets/models/`), loaded from memory; no download | user decision 2026-10-02: **AGPL-3.0 accepted** (app source must be AGPL-compatible if distributed; ship the script). Arm's original file never runs fully on GPU (TopK/GatherND head) and silently runs at CPU speed with `{gpu,cpu}`; the raw-head file is fully accelerated on macOS GPU fp32 (4.1 ms vs 22.8 ms CPU) — run **strict GPU fp32** and check `isFullyAccelerated`. `flutter_litert` bundles LiteRT 2.2.0 on Android, 2.1.5 on macOS, `litert-ios-v1.0.1` on iOS; on Linux it runs on the LiteRT-LM native bundle's `libLiteRt.so` (x86_64 + arm64) through our patched copy (`docs/design/detector-linux.md`). YOLOX (Apache-2.0) is the licence-clean fallback |
| Camera | `camera` 0.12.x — Android `camera_android_camerax`, iOS `camera_avfoundation`, macOS and Linux `camera_desktop` 2.0.0 (pinned; mirrors at capture) — latest-frame-wins | if Dart-side preprocessing caps fps → native detection, stream only boxes |
| Audio | `record` (PCM16 16 kHz mono, no AEC; Android `voiceRecognition` source), streamed playback (`flutter_soloud`), **one** audio-session owner (`AudioSessionService`; none on Linux) | **half-duplex by design**: push-to-talk, the mic is closed while the reply plays (pressing it is the barge-in), so there is no echo to cancel; iOS `.playAndRecord` + `defaultMode`, no voice processing. Full duplex would need capture and playback in one native engine (`docs/design/demo1-voice-chat.md` D4) |
| Architecture | official Flutter MVVM: View + ChangeNotifier ViewModel, repositories/services, Command + Result, `provider` DI | high-rate data (boxes, tokens, levels) via `ValueNotifier` + `CustomPaint(repaint:)`; conventions below |
| NPU | the chosen `.litertlm` on `PreferredBackend.npu`, exactly as requested (no fallback) | **Android Qualcomm:** works via `flutter_edge_ai`. **Linux Qualcomm:** verified outside the app on Arduino VENTUNO Q (QCS8275, Hexagon V75) with LiteRT-LM 0.18.0, a self-built `libLiteRtDispatch_Qualcomm.so` and QAIRT ≥ 2.50; not yet in `flutter_edge_ai`, whose `npuDispatchShipsFor` returns false on Linux. NPU builds are compiled per SoC |

`flutter_litert` and the LiteRT-LM native bundle (`flutter_edge_ai_litertlm`) both carry LiteRT: two dynamic copies
coexist (verified on iOS sim + macOS in `~/Work/litert_demo`); never static-link both. **Real iPhone (2026-10-08):** both
ship `LiteRtMetalAccelerator.framework`, the app keeps LiteRT-LM's, so flutter_litert's GPU fails on iOS — the
detector's standard backend there is the CPU until `flutter_edge_ai_litertlm` renames its copy
([docs/upstream-issues.md](docs/upstream-issues.md)).

## Code conventions (as practised)

| Topic | Convention |
|---|---|
| Errors | I/O wrappers in `data/services` may throw; repositories and use cases return `Result` (`Result.ok` / `Result.error`), never throw across layers; streams carry typed exceptions (e.g. `AssistantFailed(Exception)`), not stream errors — except inside the turn responders (`ChatTurnResponder`, `CameraTurnResponder`), which throw a turn's failure (an `AssistantFailed`'s error, a snapshot that could not be encoded) from their `respond` stream: a `VoiceResponder` for `VoiceSession.custom` has no other failure channel, and the session turns that stream error into the turn's error; every public exception type's name ends in `Exception` (one exception to the name: `UnexpectedError` in `utils/result.dart`, which wraps a non-`Exception` throwable) |
| Layout | data and domain by layer, UI by feature (`ui/features/<f>/{view_models,views}`); ports (interfaces an outer layer implements) in `lib/domain/ports/`; services in `data/services/<area>/`; a repository's helpers in `data/repositories/<repository>/` (`conversation/`, `live_detection/`, `model/`, `chat_model/`); `test/` mirrors `lib/` (plus `test/fakes/`, `test/support/`; `test/goldens/` holds the golden texts, `test/manual/` probes that need local files and skip without them, `test/tool/` the tests of `tool/` scripts, `test/integration_test/support/` the tests of the integration tests' helpers) |

## Team roles

Use the matching role when the active coding environment provides it; otherwise follow the same responsibilities
directly.

| Task | Agent |
|---|---|
| Design a feature/pipeline, data flow, resource budget | `flutter-architect` (read-only) |
| Write Dart | `flutter-coder` |
| Review Dart (after every chunk) | `flutter-reviewer` (read-only, project memory) |
| Any flutter_gemma API: LLM, images, tools, agent skills, RAG, STT/TTS | `flutter-gemma-expert` |
| Detector choice, I/O contract, pre/post-processing, accelerators, benchmarks | `litert-expert` |
| Android native (CameraX, AudioRecord/Track, LiteRT Kotlin, Pigeon) | `android-architect` → `android-coder` → `android-reviewer` |
| iOS native (AVFoundation, AVAudioSession/Engine, LiteRT iOS, Pigeon) | `swift-architect` → `swift-coder` → `swift-reviewer` |

Flow per feature: architect (design → `docs/design/<feature>.md`) → coder (small increments) → reviewer → fix →
device run. Experts are consulted by any of them.

## Project skills

- `flutter-gemma-*` — flutter_gemma package skills (compile-checked per release). Use the copy installed for the
  active coding agent. Refresh after any `flutter pub upgrade` with `dart run skills@ get --all --agent AGENT_ID`,
  replacing `AGENT_ID` with the identifier supported by the current environment.
- `on-device-verification`, `litert-runtime`, and `compiled-model-app-scaffolding` — official LiteRT skills from
  `google-ai-edge/litert-samples@385cfe0` (`skills/`). Use the copy installed for the active coding agent.
- When available, the project-scoped `dart-flutter@dart-flutter` plugin provides official Dart/Flutter skills
  (`flutter-apply-architecture-best-practices`, `flutter-add-widget-test`, `flutter-add-integration-test`, …) and
  the **Dart MCP server** (`analyze_files`, `run_tests`, `hot_reload`, `get_runtime_errors`, `widget_inspector`,
  `pub_dev_search`, `lsp`).

## Toolchain (this machine)

Flutter 3.47.3 / Dart 3.13.3 **pinned in `.fvmrc` — run `fvm flutter …` / `fvm dart …`**. **Once per checkout,
before `pub get`: `tool/flutter_litert/vendor.sh`** (flutter_litert 3.9.3 + our patch into gitignored
`third_party/flutter_litert`, used via `dependency_overrides`). **Once per checkout: `tool/fetch_models.sh`** — the
built-in models are not in git; it fetches them into `assets/models/` from `tool/models.lock` and verifies each SHA-256
(`HF_TOKEN` in `.env` for the gated EmbeddingGemma; `--check` verifies offline). Xcode 26.5, Android SDK
36, native assets enabled. Packages: flutter_edge_ai 2.1.0, flutter_edge_ai_litertlm 1.9.0 (native bundle
`native-v0.17.1-a`, still cached in `~/Library/Caches/flutter_gemma/native`), flutter_edge_ai_speech 0.5.4,
flutter_edge_ai_agent 0.2.7, flutter_edge_ai_embeddings 2.2.2, flutter_edge_ai_rag 1.0.0 + flutter_edge_ai_sqlite 2.0.0;
camera 0.12.1, record 7.1.1, flutter_soloud 4.1.7 (5.x blocked: needs `code_assets` ^2,
flutter_edge_ai_litertlm/sqlite pin ^1.2 — see [docs/upstream-issues.md](docs/upstream-issues.md)),
audio_session 0.2.4, provider 6.1.5, flutter_litert 3.9.3, image_picker 1.2.3.
Local models for macOS iteration: `~/Work/gemma-4-E2B-it.litertlm` (and E4B) — the debug macOS build may read
`~/Work/` (sandbox read-only exception in `DebugProfile.entitlements`). Platform smoke test:
`integration_test/model_smoke_test.dart` (`--dart-define=GEMMA_MODEL_PATH=…`, see its header). macOS integration tests
need the screen unlocked and the test window visible: a locked or covered screen stops frames and `tester.pump`
waits; `integration_test/support/app_window.dart` brings the app to the front before each test and fails fast when
no window shows.

## Platform requirements (apply when wiring features)

- Android: `minSdk 30`, arm64-v8a only (no x86 emulator), permissions `INTERNET`, `CAMERA`, `RECORD_AUDIO`
  (`POST_NOTIFICATIONS` removed from the merge: the app posts none); core-library desugaring for `flutter_edge_ai_agent` (its `flutter_local_notifications`); keep `android.builtInKotlin=false`.
- iOS: deployment 15+, entitlements `increased-memory-limit` + `extended-virtual-addressing` (via Xcode
  capabilities), usage strings for camera, microphone, photo library; simulator is CPU-only for the LLM.
- macOS: network client, audio input, camera, disable-library-validation in **both** entitlements files.
- First build per platform downloads native prebuilts from GitHub — pre-build and pre-download models before the
  event (venue Wi-Fi).

## Rules

1. **Evidence over memory**: verify APIs in the resolved package source / skills; versions move monthly.
2. **Fail fast, no silent fallbacks**: an unavailable GPU/NPU/model is an error the UI shows; the debug overlay
   shows active backend, model, fps, latency.
3. **Real device or it didn't happen** for camera, audio, models and native code. Native integration tests:
   `flutter test integration_test/<file>.dart -d <device-id>` — never `flutter drive` on native targets.
4. `flutter analyze` with zero warnings and `dart format .` before every commit; never edit generated files
   (`*.g.dart`, Pigeon output) — regenerate.
5. Secrets (HF token) only in `.env` (gitignored): `tool/fetch_models.sh` reads `HF_TOKEN` from it. A secret passed with
   `--dart-define-from-file=.env` ends up in the binary.
6. Upstream flutter_gemma bugs → write them up for the maintainer; don't patch `~/Work/flutter_gemma` from here.
