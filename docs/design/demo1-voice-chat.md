# Demo 1 — Multimodal voice chat with skills (design)

Status: design, 2026-10-02 (`flutter-architect`). Checked against the resolved sources in `~/.pub-cache`:
flutter_gemma 1.11.3, flutter_gemma_litertlm 1.8.5, flutter_gemma_speech 0.5.2, flutter_gemma_agent 0.2.6,
flutter_gemma_rag_sqlite 1.4.0, record 7.1.1 (record_ios 2.1.1), flutter_soloud 4.1.7, audio_session 0.2.4,
image_picker 1.2.3 (image_picker_macos 0.2.2+1) and flutter_litert 3.9.3. Anything marked **unverified** needs a
device run or a repo check, and the check is named next to it.

> **Amended by [demo3-live-camera.md](demo3-live-camera.md) §12 (2026-10-02)** — where they differ, Demo 3's design wins:
> `WatcherRepository` → `LiveDetectionRepository` (data, shared with Demo 3) + `CameraWatcher` (domain use case); the
> detector is resident from setup (optional model); a macOS camera exists for development via `camera_desktop`;
> `VoiceAssistant` is generic (`VoiceAssistant<S>` + `TurnResponderFactory<S>`, no Demo 1 types); Inc 7's
> `takePicture()` → `capture()` + `encodeForLlm()`. Increment order across both demos: Inc 1 → D3-0 → D3-1 → D3-2 →
> Inc 3 → D3-3 → Inc 4 → D3-4 → Inc 5 → Inc 6 → Inc 7 → Inc 2 + D3-5 (device) → Inc 8. Voice wiring details:
> [inc3-voice-wiring.md](inc3-voice-wiring.md) (barge-in worst case ≈10 s, RMS from PCM not record's amplitude,
> soloud `bufferingTimeNeeds` 0.2 s, `ask` failures must be rethrown by the responder).

> **Amended in Inc 8 (2026-10-02): values as built**, where they differ from the text below:
> - **RAG gate 0.40** (`kKbMinSimilarity`, tuned on the golden set in Inc 5), not 0.45 (D9).
> - **`maxTokens` 8192**, not 4096 (D16): agent turns (skills system prompt + tool rounds) plus RAG excerpts and an
>   image reset the chat every 2–3 turns at 4096 (`kLlmConfig`).
> - **STT per demo**: Demo 1 keeps Whisper base (30 s window); Demo 3 uses moonshine tiny (5 s window, ~65 ms per
>   question). STT is a singleton, so each demo makes its own recognizer active on entry (D6; upstream U7: STT stays
>   on the CPU).
> - **Live skill questions skip retrieval** (`SkillQuestionRouter`): device facts, time, timers and the camera watch go
>   to the skills without knowledge-base excerpts, because device questions clear the gate against the GPU docs.
> - **Permissions on entry**: Demo 1 asks for the microphone, then the camera (for the watcher); Demo 3 for the
>   microphone after its camera starts. Denials are lasting bars with the settings path and Retry.
> - **Watcher**: re-arm after 1.2 s of continuous absence with a 0.15 score hysteresis (not 2 frames); a sighting
>   queued behind a reply is said while the object is still in view (no 5 s TTL); the watcher takes the camera only
>   when it is free.

> **Amended 2026-10-06: camera-watch and timer removed** (user decision; supersedes D14, D15, Inc 7, the
> announcement queue and the watcher items above). Demo 1's skills are now `current-time`, `device-info` and any
> `SKILL.md` dropped in at run time (Skills → Reload, no rebuild).
> - **Why:** a simpler Demo 1 with no camera in the chat (the photo buttons stay: they use the system picker), and
>   less memory on the Jetson (no detector pipeline or frame buffers behind the chat).
> - **Gone:** the `camera-watch` and `timer` skills and their intents (`watch_camera`, `stop_watching`,
>   `start_timer`, `cancel_timer`, `list_timers`); `CameraWatcher`, `TimerRepository`, `watch_config`, the
>   picture-in-picture, the announcement queue in `VoiceAssistant` and `AnnouncementHub`; Demo 1's camera
>   permission request on entry; the router's watch and timer phrasings; the watcher-only helpers
>   (`start(onlyIfFree:)`, `isOwnedBy`, `requestCameraAccess`, `probeCameraAccess`, `SpeechRepository.synthesize`).
>   Demo 3 is unchanged.
> - **Upgrades:** the seeder retires a skill an earlier version bundled and this one does not, if its `SKILL.md` is
>   still as seeded (`SeedReport.retired`); an edited copy is kept and shows its errors in the Skills sheet.
> - **`device_info` now reads the hardware report** (`describeHardware`): the chip (on Android the SoC by name, e.g.
>   "Snapdragon 8 Gen 3 (SM8650)"), memory and GPU, then where each loaded model runs, the chat model first, with
>   how that is known: "confirmed" (the runtime reported it), "inferred" or "requested". It is still the spoken
>   reply as is, and still run directly for live device questions.
> - **The runtime-skill example** is now `kid-clock` (composes `current_time` under a new trigger and a new way
>   of saying it;
>   `integration_test/support/skill_fixtures.dart`).

> **Amended 2026-10-08: §3 and §4 rebuilt from the code** (f9bc207); the rest keeps the 2026-10-02 plan with the
> amendments above. Since then:
> - the flutter_gemma packages became flutter_edge_ai (versions in `AGENTS.md`);
> - the chat model is the tester's own `.litertlm`, the only one: the app ships none, and it runs on the backend
>   chosen for it ([custom-chat-model.md](custom-chat-model.md)). Every other model is built in
>   ([distribution.md](distribution.md)), so §6's "Gemma 4 E2B on the GPU" and §7's downloads are history;
> - YOLO26n belongs to Demo 3 only.

## 1. Decision summary

- **One pipeline for every turn.** Each turn builds a new `VoiceSession.custom(streamAudio: true)`. It is pure
  orchestration: PCM goes in, events come out. Its responder wraps `AgentSession.ask(text, imageBytes:)`. Typed turns
  go through the same session with a `TypedTextRecognizer`.
- **The app owns the audio.** VoiceSession "owns NO microphone, NO player" (the source's own wording). So `record`
  captures, `flutter_soloud` plays the streamed PCM, and `audio_session` is the only component that configures the
  audio session.
- **Half-duplex push-to-talk.** Pressing the mic while the assistant speaks is the barge-in. v1 has no VAD and does
  not depend on echo cancellation (AEC).
- **Models.** Gemma 4 E2B runs on the GPU, with its vision encoder on the CPU. Whisper-base int8 (STT),
  Inflect-nano-v2 (TTS) and EmbeddingGemma-300M all run on the CPU. All of them stay loaded after setup. YOLO26n
  is loaded only while the camera watcher runs.
- **RAG without an extra LLM pass.** Each turn embeds the question and, if the best match clears a similarity gate,
  injects the top 3 chunks into the prompt. The app renders the citations from chunk metadata.
- **Skills.** SKILL.md files live in a user-writable `skills/` directory. One `AppIntentExecutor` (priority 10) runs
  every app intent. The chat is built with only two tools: `loadSkill` and `runIntent`.
- **Structure.** Data and domain code are grouped by layer, UI code by feature. This is the official MVVM pattern
  with Command/Result and `provider`. Demo 3 reuses every service and repository.

## 2. Goals and non-goals

**Target devices:** iPhone 17 Pro on iOS 26, an 8–12 GB Android phone once one is available, and macOS for
development.

| Goal | Target |
|---|---|
| Time from mic release to first audio | ≤2.5 s for a text turn, ≤4 s with an image, ≤5 s with one skill call (iPhone) |
| Barge-in | playback silent ≤150 ms after the press |
| Offline | the full demo script passes in airplane mode after setup |
| Memory | peak footprint ≤3.5 GB on iPhone; no jetsam in a 15-minute session |
| Debug overlay | backend per model, model ids, load time, time to first token, tokens/s, STT time, time to first audio, retrieval time and top similarity, RSS/footprint, detector fps and accelerator |

**Non-goals:**
- Hands-free VAD or full-duplex audio.
- Qwen3-TTS or multilingual speech output.
- JS or MCP skills.
- Timers or watchers while the app is closed.
- A camera on macOS.
- New Dart capabilities added through Markdown. Markdown skills can only combine the intents the app already has.

## 3. Architecture

> **§3 and §4 describe the code as of 2026-10-08** (rebuilt from `find lib -name '*.dart'` at f9bc207). The
> increments in §8 keep their original plan; where they name a file or an API that differs, this section is the
> current state. Demo 3's own files are mapped in [demo3-live-camera.md](demo3-live-camera.md) §3.1.

### 3.1 Components and threads

```
UI (main isolate)
  SetupScreen ─ SetupViewModel · ChatModelViewModel · SelfTestViewModel   (/ first run, /models)
  HomeScreen ─ HomeViewModel ............ per-demo availability, "This device" card
  VoiceChatScreen ─ VoiceChatViewModel .. ChangeNotifier + Commands; owns its VoiceAssistant
    VoiceChatReducer ...... turn events → entries, notices, the turn's retrieval and steps (pure)
    SkillsApplier ......... a changed skill set → a new agent chat, between turns
    message list .......... ListenableBuilder (low-rate commits)
    streaming bubble ...... ValueListenableBuilder(partialReply), skill steps below it
    MicButton ............. CustomPaint(LevelRingPainter(repaint: inputLevel))
    SkillsSheet ........... scanned skills, their errors, Reload
  DebugOverlayHost ........ over every route: ValueListenableBuilder(diagnostics snapshot)
Domain (main isolate)
  VoiceAssistant<ChatSideEvent> ... turn state machine and barge-in (§4); PushToTalkCapture, TurnMetricsPublisher
  ChatTurnResponder ............... direct intents (SkillQuestionRouter) · retrieval gate → PromptBuilder →
                                    ConversationRepository.ask (+ the attached image)
  AppIntentExecutor ............... current_time, device_info (the hardware report)
  ChatModelSwitcher · GpuArbiter .. app-scoped: the chat model's reloads; the detector's pause (Demo 3)
Data: repositories (main isolate)
  Model · ChatModel · Provisioning · Conversation · Knowledge · Speech · Audio · Image · Skill · Hardware ·
  Diagnostics (Demo 3 adds LiveDetection and LiveCameraSettings)
Data: services → where they run
  LlmService ............ LiteRT-LM native threads; the chat model's chosen backend (GPU, CPU or NPU)
  SttService, TtsService  flutter_edge_ai_speech, CPU
  EmbedderService ....... LiteRT, CPU (the package forces it)
  VectorStoreService .... flutter_edge_ai_rag over flutter_edge_ai_sqlite (sqlite-vec FFI)
  MicService ............ record's native capture thread
  PcmPlayerService ...... soloud/miniaudio audio thread
  AudioSessionService ... platform channel (no-op on Linux); AudioDeviceService: pactl (Linux), CoreAudio (macOS)
  ModelStore, BundledModelFiles, SkillStoreService, ImageInputService, hardware info, memory probe, native log tap
```

### 3.2 File map (`lib/`)

| Path | Responsibility / public API |
|---|---|
| `main.dart`, `app.dart` | entry (`--selftest` → `selftest/self_test_mode.dart`); routes `/` (setup), `/models`, `/home`, `/chat`, `/camera`; each route builds its view model and, for the voice demos, its `VoiceAssistant` (§3.3) |
| `config/env.dart`, `config/dev_overrides.dart` | developer defines (`GEMMA_MODEL_PATH`, `EMBEDDING_MODEL_DIR`, `DETECTOR_MODEL_PATH`, `DETECTOR_BACKEND`, `FRAME_SOURCE`, `NETWORK_CAMERA_URL`, `FIXTURE_DIR`, `VOICE_GATE_DBFS`, `GEMMA_ACTIVATION`); `DevModelOverrides` maps them to models |
| `config/model_catalog.dart` | `kLlmConfig`, `kDefineChatModel` (Gemma 4 E2B's settings for `GEMMA_MODEL_PATH`), the STT/TTS/embedder configs (`kSttConfigs`, `kTtsConfig`, `kEmbedderConfig`), `kSampler`, the token-budget constants, `ConversationProfile` (`kVoiceChatProfile`, `kCameraProfile`), `kAgentTools`, the retired Gemma pin (`kRetiredGemma*`) |
| `config/voice_config.dart`, `config/knowledge_config.dart`, `config/demos.dart` | `VoiceConfig` (`kVoiceConfig`: 300 ms minimum hold, silence gate −45 dBFS unless `VOICE_GATE_DBFS`, 160 ms voiced) and the playback constants; `kKbMinSimilarity` 0.40, `kKbTopK` 3; `enum Demo` with each demo's recognizer |
| `config/bootstrap.dart` | `initEdgeAi()`: one `FlutterEdgeAi.initialize(inferenceEngines: [LiteRtLmEngine()], sttBackends: [LiteRtSttBackend()], ttsBackends: [LiteRtTtsBackend()], embeddingBackends: [LiteRtEmbeddingBackend()], embeddingTokenizers: [GemmaEmbeddingTokenizers()])` |
| `config/dependencies.dart` | `AppDependencies.create()` builds the graph (§3.3); `providers`; `dispose()` closes each user before what it uses (a running self-test first) |
| `config/build_info.dart`, `config/licenses.dart`, `config/live_camera_config.dart` | the build's version and package versions; the model licences for the Licences page; Demo 3's constants |
| `utils/result.dart`, `utils/command.dart` | `Result<T>` (`Ok`/`Error`); `Command0`/`Command1` with `running`/`error`/`completed` |
| `utils/pcm.dart`, `utils/spoken_text.dart`, `utils/spoken_numbers.dart`, `utils/citations.dart`, `utils/markdown_chunker.dart` | PCM analysis and the silence gate (`measureVoice`); what TTS reads (`toSpokenText`: no `[n]`, markdown or URLs); numbers as words; citation markers; the knowledge-base chunker |
| `utils/serial_queue.dart`, `utils/waits.dart`, `utils/worker_channel.dart`, `utils/frame_rate_gate.dart`, `utils/stall_watchdog.dart` | one-at-a-time async queue; bounded waits; isolate request/response; Demo 3's frame gate and watchdogs |
| `domain/models/*` | immutable values: `TurnPhase`, `Utterance`, `NotHeardReason`, `TurnOutcome` (`voice.dart`); `AssistantEvent` (sealed) and `GenerationMetrics`; `ChatSideEvent`; `ChatEntry`; `ChatCapabilities`; `CustomChatModel`, `CustomModelSource`, `ChatModelPlan`; `ModelId`, `ModelState`; `Passage`, `Retrieval`, `KnowledgeStatus`; `SkillStep`, `SkillCatalog`; `LlmImage`; `HardwareProfile`, `AcceleratorEvidence`, `AudioSystem`, `AudioDeviceStatus`; `DiagnosticsSnapshot`; `SelfTestOutcome`; Demo 3's frame, detection and scene types |
| `domain/models/chat_model_config.dart` | `LlmConfig` (the arguments of `getActiveModel`) and `ChatModelConfig` (name, install type, `LlmConfig`, tools): the types; the app's values are in `config/model_catalog.dart` |
| `domain/models/model_source_resolver.dart` | `ModelSourceResolver`: where each model's file comes from (distribution.md D5); `ModelRepository` loads by it and the self-test resolves by it |
| `domain/ports/*` | interfaces the domain and the view models depend on, implemented outside: `KnowledgeRetriever`, `VoiceDiagnosticsSink`, `ModelStates`, `ChatModelPlanner`, `ModelFilePicker`, `SelfTestLauncher` |
| `domain/use_cases/turn_responder_factory.dart` | `TurnResponderFactory<S>` (+ `TurnRequest`, `TurnPreparation`): the LLM step of each voice turn; its consumer (`VoiceAssistant`) and both implementers are use cases, so it is not a port |
| `domain/use_cases/voice_assistant.dart` | `VoiceAssistant<S>({speech, audio, responders, diagnostics, config, recognizer})`: `phase`, `partialReply`, `inputLevel`, `events`, `speakReplies`, `micDown()`, `micUp({image})`, `submitUtterance(...)`, `sendText(text, {image})`, `stop()`, `prepareAudio()`, `requestMicAccess()`, `dispose()` (§4) |
| `domain/use_cases/push_to_talk_capture.dart` | `PushToTalkCapture`: one press from `open` to the capture handed over at `release`; `pressAgain()` re-arms a press released while the mic still opens; `drop()` |
| `domain/use_cases/voice_turn_metrics.dart` | `TurnMetricsBuilder` (one turn's figures) and `TurnMetricsPublisher` (newest turn wins in the overlay) |
| `domain/use_cases/chat_turn_responder.dart` | `ChatTurnResponder implements TurnResponderFactory<ChatSideEvent>`: a direct intent for the questions `SkillQuestionRouter` recognizes, otherwise retrieval → `PromptBuilder` → `ConversationRepository.ask(prompt, image:, onStep:)`; side events `ChatRetrieval`, `ChatSkillStep`, `ChatContextReset`, `ChatGenerationDone` |
| `domain/use_cases/skill_question_router.dart`, `prompt_builder.dart` | live skill questions (time, device facts) skip retrieval; the prompt with the excerpts and the `[n]` citations read back |
| `domain/use_cases/chat_model_switcher.dart` | `ChatModelSwitcher`: `exclusive(body)`, `reload()`, `unload()`, `busy`; releases the chat first; `ReplyStillStoppingException` (custom-chat-model.md C10) |
| `domain/use_cases/gpu_arbiter.dart`, `camera_turn_responder.dart`, `question_router.dart`, `fast_answer_composer.dart`, `camera_prompt.dart` | Demo 3 (demo3 §3.1) |
| `domain/skills/app_intents.dart` | `abstract final class AppIntent { deviceInfo, currentTime; static const all = {...}; }` |
| `domain/skills/app_intent_executor.dart`, `app_intent_handlers.dart` | see the code block below; `buildAppIntents(deviceFacts:)`, `describeHardware(...)` |
| `domain/hardware/*`, `domain/audio/*`, `domain/vision/*` | pure logic: accelerator inference, the "This device" summary, the diagnostics report, the native log parser, the SoC table; the audio device verdicts; COCO names and STT corrections (Demo 3) |
| `data/services/llm/llm_service.dart`, `npu_availability.dart` | `install(...)`, `load(ChatModelConfig) → Result<LlmInfo>` (exactly the requested backend: `BackendMismatchException`, `NpuUnavailableException`, `ChatModelLoadException`), `warmUp`, `model`, `unload()`, `close()`; the NPU gate |
| `data/services/speech/*` | `SttService` / `TtsService`: install from the built-in files, load, warm up, unload; the recognizer and synthesizer decorators (`InstrumentedRecognizer`, `ActiveRecognizer`, `TypedTextRecognizer`, `InstrumentedSynthesizer`, `SpokenSynthesizer`, `SilentSynthesizer`) |
| `data/services/knowledge/*` | `EmbedderService` (install, load, `embedQuery`, `embedDocuments`); `VectorStoreService` (`open`, `add`, `search`, `stats`, `clear`); the prebuilt index (`AssetPrebuiltKbIndex`), its marker and key, the KB documents, the embedder digests |
| `data/services/audio/*` | `MicService` (record), `PcmPlayerService` (soloud buffer stream), `AudioSessionService.configureHalfDuplex()`, `AudioDeviceService` (`checkInput`, `audioSystem`) |
| `data/services/images/*` | `ImageInputService` (image_picker), `normalizeForLlm` (≤1024 px, EXIF orientation), Demo 3's `SnapshotEncoder` |
| `data/services/skills/skill_store_service.dart` | `seed()` (`SeedReport`, retired skills), `scan()` → `SkillCatalog` (skills plus per-file errors) |
| `data/services/model_store/*` | `ModelStore` (the custom chat model's file: use in place, import, download, prune), `BundledModelFiles` (built-in files in place or extracted on Android), the importer, the downloader, `.sha256` records, the models folders and the `.litertlm` header reader |
| `data/services/settings/*`, `data/services/hardware/*`, `data/services/detector/*`, `data/services/frames/*` | `TypedSettings` over `SharedPreferencesAsync`; the hardware probes per platform, the memory probe and the native log tap; Demo 3's detector worker and frame sources |
| `data/repositories/model_repository.dart` (+ `model/model_load_pipeline.dart`) | `implements ModelStates`: `states`, `preparing`, `requiredReady`, `prepareAll()`, `activeStt`, `activateStt(id)`, `reloadDetector()`, `reloadChatModel()`, `unloadChatModel()`, `refuseChatModelLoads(reason)`, `close()`. `ModelLoadPipeline.run`: install → load → warm up, with `ModelInstalling`/`ModelLoading`/`ModelWarmingUp` published and a `LoadOutcome` (`LoadReady`, `LoadFailed`, `LoadStopped`) |
| `data/repositories/chat_model_repository.dart` (+ `chat_model/custom_chat_model_codec.dart`), `provisioning_repository.dart` | the chosen `.litertlm` and its settings (`plan`, `useLocalFile`, `importFile`, `download`, `apply`, `runOn`); presence per model and `pruneOldModelFolders()` (custom-chat-model.md) |
| `data/repositories/conversation_repository.dart`, `conversation_repository_edge_ai.dart` (+ `conversation/*`) | see the code block below. Helpers: `LiveChat` (the one chat slot and its turn), `OpenQueue` (opens and resets, newest wins), `ChatFactory`/`AgentChat` (`native_chat.dart`), `askTurn`/`askAgent` (the plain and agent turn paths), `AgentTurnFold`, `ContextBudget` and `guardBudget` (`turn_start.dart`), `ImageContextTracker`, `GenerationMetricsBuilder` |
| `data/repositories/speech_repository.dart` | `Result<VoiceTurn> startTurn({pcm, typedText, expectedStt, required responder, required speak, onTiming})`: one `VoiceSession.custom(streamAudio: true)` per turn |
| `data/repositories/audio_repository.dart`, `audio_repository_device.dart` | `prepare()`, `requestMicAccess()`, `startCapture({maxLength, onLimit}) → CaptureHandle` (`stop() → Utterance`, `cancel()`), `beginPlayback(rate) → PlaybackHandle` (`enqueue`, `end`, `drained`, `stop`), `inputLevel`, `devices`, `close()` |
| `data/repositories/knowledge_repository.dart` | `implements KnowledgeRetriever`: `status`, `ensureIndexed()`, `retrieve(question) → Result<Retrieval>` (top `kKbTopK`, gated at `kKbMinSimilarity`); installs the prebuilt index or indexes on the device |
| `data/repositories/skill_repository.dart`, `image_repository.dart`, `hardware_repository.dart`, `diagnostics_repository.dart` | `catalog`, `ensureLoaded()`, `refresh()`; `pick(source) → Result<LlmImage?>`; `probe()`, `summary()`, `report()`, `modelDiagnostics()`; `snapshot` plus `record*` sinks (`implements VoiceDiagnosticsSink`) |
| `data/repositories/live_detection_repository.dart` (+ `live_detection/*`), `live_camera_settings_repository.dart` | Demo 3 (demo3 §3.1) |
| `selftest/*` | the self-test, as `--selftest` and as the Models screen's Run self-test: `SelfTestRunner` (step 1 itself, then `DetectorSteps`, `ChatModelSteps`, `AudioSteps`), `StepRecorder`, `EvidenceJudge`, the cats golden, the adapters over the app's services (`self_test_adapters.dart`, `self_test_ports.dart`), `InAppSelfTest`, the report formatter, the options parser |
| `ui/core/*` | `debug_overlay.dart` (+ `debug_overlay/*`: host, panel, lines, layout, keys), `device_card.dart`, `level_meter.dart` (`MicButton`), `voice_notices.dart`, `detection_painter.dart`, `warning_color.dart` |
| `ui/features/setup/`, `ui/features/home/`, `ui/features/voice_chat/` | `view_models/` and `views/` in each. Demo 1: `voice_chat_view_model.dart`, `voice_chat_reducer.dart` (`VoiceChatReducer`, pure), `skills_applier.dart` (`SkillsApplier`, owned by the view model); views: the screen, composer, message bubble, citation chips, attachment bar, skill steps, Skills sheet |
| `ui/features/live_camera/` | Demo 3 (demo3 §3.1) |
| `assets/skills/<name>/SKILL.md`, `assets/kb/*.md`, `assets/kb_index/` | seed skills, knowledge-base documents, the prebuilt index |

```dart
abstract interface class ConversationRepository {
  ValueListenable<bool> get isGenerating;   // from a turn's start to its last event
  bool get isOpen;
  ConversationProfile? get profile;
  bool get hasSkills;                       // an agent chat (opened with skills)
  bool get skillsNeedTools;                 // skills asked for, but the chat model has tools off
  ChatCapabilities get capabilities;        // images, tools, the model's name

  // Stops a running turn (waits for a draining one, bounded), then rebuilds the chat; rebuilds run one at a
  // time and a queued open that a later one replaces is not built (ConversationSupersededException).
  Future<Result<void>> open(ConversationProfile profile, {List<Skill> skills = const []});

  // Exactly one AssistantDone or AssistantFailed last; failures (a busy chat included) never as stream errors.
  // Pass the SAME image object every turn while it stays attached: it is sent only when the chat cannot see it.
  Stream<AssistantEvent> ask(String prompt, {Uint8List? image, void Function(SkillStep step)? onStep});
  Uint8List? get imageInContext;            // null after a stop, a failure, open/reset or a budget reset

  Future<void> stop();                      // completes once the running turn has ended
  // Rebuilds only while ifCurrent is still the profile most recently opened; otherwise Ok and nothing.
  Future<Result<void>> reset({required ConversationProfile ifCurrent});
  // Stops the turn and closes the chat but stays usable: the chat model is about to be unloaded or replaced.
  // ConversationNotReadyException when the stopped turn still generates after the stop timeout (then nothing
  // is closed, and the caller must not close the chat model either).
  Future<Result<void>> release();
  Future<void> close();                     // after any chat still being built; safe to call twice
}
// Exceptions: ConversationNotReadyException, ConversationImageUnsupportedException,
// ConversationTooLongException, SkillLoopException, ConversationSupersededException.

final class AppIntentExecutor extends SkillExecutor {
  AppIntentExecutor(Map<String, AppIntentSpec> intents,   // exactly AppIntent.all, or ArgumentError
      {Duration timeout = const Duration(seconds: 3), Skill? Function(String name)? skillNamed});
  @override int get priority => 10;
  @override bool canExecuteSkill(Skill s) => s.type == SkillType.intent; // type only (contract)
  Future<SkillResult> run(String intent, String paramsJson);            // the app's direct intents
  @override Future<SkillResult> execute(Skill skill, String dataJson, {String? secret});
  // The intent is the probed skill's name (the agent loop sets it from runIntent) or {"intent", "parameters"}
  // in the data; a skill name, an unknown intent, bad parameters or a throwing handler → ErrorResult listing
  // what to do instead. Never throws.
}
```

### 3.3 Provider wiring

`AppDependencies.create()` (`config/dependencies.dart`) builds everything in this order:
1. The native log tap, then `initEdgeAi()`.
2. Services: `ModelStore`, `BundledModelFiles`, `LlmService`, `SttService`, `TtsService`, `DetectorService`,
   `EmbedderService`.
3. Repositories: `ChatModelRepository` (its saved choice is read before anything can load), `ProvisioningRepository`,
   `LiveCameraSettingsRepository`, `ModelRepository` (the services, the detector backend choice, the log tap, the
   chat model planner), `DeviceAudioRepository`, `HardwareRepository` (probed once in the background),
   `KnowledgeRepository`, `LiveDetectionRepository`, `SpeechRepository`, `ImageRepository`, `SkillRepository`.
4. `AppIntentExecutor`: its handlers come from `buildAppIntents(deviceFacts: () => describeHardware(...))`, which reads
   the hardware report when called; `skillNamed` looks a loaded skill up by name.
5. `EdgeAiConversationRepository(llm:, executors: [appIntents, TextSkillExecutor()])`. It knows the LLM service and the
   executors, never another repository. Then `DiagnosticsRepository`, which listens to the model, live, knowledge,
   skill and audio states and to `isGenerating`.
6. App-scoped use cases: `GpuArbiter(llmBusy: conversation.isGenerating, setDetectorDuty: live.setDuty,
   duringGeneration: kDetectorDuringGeneration, chatModelName: …)` and `ChatModelSwitcher(conversation:,
   reloadChatModel:, unloadChatModel:, refuseChatModelLoads:)`; the Models screen's `InAppSelfTest` is built on first
   use.

The repositories are exposed with `MultiProvider([Provider.value(...)])`; `ModelRepository` only as its read-only
`ModelStates`. What changes the models (`prepareModels`, `activateStt`, `reloadDetector`, `chatModelSwitcher`,
`selfTest`) and the direct intents (`intents.run`) are passed explicitly to the view models that need them
(`app.dart`). Each route creates its own view model; Demo 1's owns and disposes its assistant:

```dart
ChangeNotifierProvider(create: (c) => VoiceChatViewModel(
  conversation: c.read(), diagnostics: c.read(), images: c.read(),
  activateStt: deps.activateStt, skills: c.read<SkillRepository>(),
  assistant: VoiceAssistant<ChatSideEvent>(
    speech: c.read(), audio: c.read(),
    responders: ChatTurnResponder(conversation: c.read(),
        retriever: c.read<KnowledgeRepository>(), direct: deps.intents.run),
    diagnostics: c.read<DiagnosticsRepository>(),
    config: kVoiceConfig.withMaxUtterance(kSttConfigs[Demo.voiceChat.stt]!.window),
    recognizer: Demo.voiceChat.stt)))
```

Rule for the reviewer: `FlutterEdgeAi.getActive*` and `FlutterEdgeAi.install*` appear only in the model services
(`data/services/llm/`, `data/services/speech/`, `data/services/knowledge/embedder_service.dart`), which
`ModelRepository` drives (the self-test reaches them through its adapters over the same services). `openSession` is
never used.

## 4. One voice turn with an image

Phases (`TurnPhase`): `idle`, `openingMic`, `listening`, `transcribing`, `thinking`, `speaking`, `error`. The next
action starts from `error` as from `idle`. `VoiceAssistant` keeps the phases; `PushToTalkCapture` says how each step
of a press ended.

| From | Event | To | Action |
|---|---|---|---|
| idle / error | mic down (models ready) | openingMic | `PushToTalkCapture.open` → `startCapture(maxLength: STT window, onLimit: micUp)`; UI "Opening the mic…". The start waits for the audio warm-up (up to 2.6 s on a cold macOS output start); nothing is recorded yet |
| openingMic | the capture starts, button still held | listening | the capture runs: the hold and the STT window count from here |
| openingMic | the capture fails | error | `MicUnavailable` (the `MicAccessException` text, or "The microphone did not start: …") |
| openingMic | mic up | openingMic until the start ends, then idle | `ReleasedWhileOpening`: nothing was recorded, no STT. Once the start ends its capture is cancelled and the turn ends as `NotHeard(NotHeardReason.releasedBeforeListening)`: "The mic was still opening — wait for Listening… before you speak." |
| openingMic (released) | mic down again before the start ends | openingMic, then listening | `pressAgain()` re-arms the same press: the start already running becomes this press's capture, and the release that was waiting for it is superseded (no notice) |
| listening | mic up, or the STT window ends (`onLimit`) | transcribing | `TurnResponderFactory.prepare` at once (in parallel with closing the capture); `CaptureHandle.stop()` → `Utterance`; then the gate |
| transcribing | gate: held < 300 ms | idle | `NotHeard(tooShort)`: no STT, no LLM |
| transcribing | gate: no samples, or all digital zeros | error | `MicUnavailable` (macOS TCC delivers zeros instead of failing) |
| transcribing | gate: voiced < 160 ms (a frame is voiced at the silence gate, −45 dBFS by default, and 10 dB above the noise floor, that part capped at −30 dBFS) | idle | `NotHeard(silent)` |
| transcribing | gate passes | transcribing | waits for a barged-in turn's drain (P2), `AudioRepository.prepare()`, then `SpeechRepository.startTurn(pcm:, responder:, expectedStt:)` |
| transcribing | `VoiceTranscriptEvent` with words | thinking | `UserSaid(text, image)`: the user entry with the thumbnail. Responder: a direct intent, or retrieve → prompt → `conversation.ask(prompt, image:, onStep:)` |
| transcribing | `VoiceTurnCompleteEvent('', '')` | idle | `NotHeard(emptyTranscript)` |
| thinking | first non-empty `VoiceReplyAudioEvent` | speaking | `beginPlayback(sampleRate)`, then enqueue (zero-byte chunks start nothing) |
| thinking / speaking | `VoiceTurnCompleteEvent` | idle once `playback.drained` | `AssistantSaid(reply)`; the reducer commits it with the turn's citations and skill steps. An empty reply fails the turn (`EmptyReplyException`) |
| any active | mic down (barge-in) | openingMic | the turn is detached at once: playback stops first, the partial reply is committed as interrupted (once the user's words were), and the session drains in the background (the next turn waits for it); then the capture starts |
| any active | Stop | idle | a capture that is open or starting is dropped; a running turn is interrupted, its partial reply committed as interrupted (`VoiceTurnInterruptedEvent`) |
| any | turn error | error | playback silenced, a partial reply committed, `TurnFailed(error)`; the image stays attached |

- **Typed turn:** `sendText(text, image:)` goes `idle → thinking` through `startTurn(typedText:)` with a
  `TypedTextRecognizer`. The transcript event echoes the typed text.
- **Images:** the attached image goes with every turn (`micUp(image:)`, `sendText(image:)`). Whether it is sent again
  is the conversation's call: it re-sends only what the live chat cannot see (`imageInContext`), so a stop, a failure,
  a reset or a budget reset never leaves a follow-up without its picture.
- **Text in the UI vs. text spoken:** the UI shows the raw `VoiceReplyTextEvent` text, including `[n]` citations. TTS
  gets whole clauses through `SpokenSynthesizer` (`toSpokenText`; a clause with nothing speakable returns zero bytes
  without calling the model). "Speak replies" off uses `SilentSynthesizer`.
- **Side channel:** retrieval, skill steps, a context reset and the generation figures reach the view model as
  `ChatSideEvent`s through the responder's `onSide`.
- **Barge-in cost:** silence is immediate; the conversation stops native generation and drains the turn, and the next
  turn starts after that drain (worst case ≈10 s, inc3-voice-wiring.md).

## 5. Data flows

The watcher's rows (announcements, camera frames, detections) went with it on 2026-10-06; Demo 3's per-frame
pipeline is in demo3-live-camera.md §5.

| Stream | Producer → consumer | Type / rate | Buffering / backpressure | Thread | Cancellation |
|---|---|---|---|---|---|
| Mic PCM | record → AudioRepository | PCM16, 16 kHz mono, about 64 ms chunks | `BytesBuilder` capped at the STT window (30 s = 960 KB); hitting the cap ends the press (`onLimit`) | native → main | `CaptureHandle.stop()` / `cancel()` |
| Mic level | RMS of each PCM chunk (not record's amplitude) → `ValueNotifier<double>` `inputLevel` | per chunk | latest value only | main | 0 on stop |
| Utterance | AudioRepository → VoiceSession → STT | 1 per turn | one turn in flight (`runTurn` throws otherwise) | STT isolate | `interrupt()` |
| Retrieval | ChatTurnResponder → `KnowledgeRetriever` (KnowledgeRepository) | query → ≤3 `Passage` | none | embedder + sqlite | not cancellable (about 100 ms) |
| LLM tokens | LiteRT-LM → ConversationRepository `AssistantTextDelta` (agent chats: from AgentLoop `TextChunkEvent`s) → responder → VoiceSession | 15–30 tokens/s | UI: `partialReply` notifier (bubble only). TTS: clause queue, bounded by `maxOutputTokens` 384 | native → main | `ConversationRepository.stop()`: `stopGeneration` and drain |
| Skill steps | AgentLoop events → `ask(onStep:)` → `ChatSkillStep` side event → the reply's steps | rare | none | main | ends with the turn |
| TTS audio | TTS → `VoiceReplyAudioEvent` → soloud buffer stream (`BufferingType.released`, s16le mono) | 1 chunk per clause, at the synthesizer's rate | bounded by reply length | TTS → audio thread | `PlaybackHandle.stop()` |
| Diagnostics | all components → `ValueNotifier<DiagnosticsSnapshot>` | coalesced to ≤4 Hz | latest value only | main | — |

## 6. Model lifecycle and resource budget

| Model | File | Backend | Resident | Memory (estimate; measure in Inc 2) |
|---|---|---|---|---|
| Gemma 4 E2B `.litertlm` | 2.54 GB (local) | GPU text decoder. Vision encoder on CPU: Metal hard-fails on it (LiteRT-LM#2461, comment in `litert_lm_client.dart`) | startup to exit | 1.2–2.0 GB at 4K context with vision. AGENTS.md gives 0.7–1.7 GB for text only. |
| Whisper base int8 (30 s window) | 73 MB | CPU, requested explicitly (the API does not report the backend) | startup | ~0.15 GB |
| Inflect-nano-v2 (24 kHz) | ~36 MB | CPU | startup | ~0.1 GB |
| EmbeddingGemma-300M seq512 | ~180 MB | CPU, forced by the package (the GPU returns zero vectors) | startup | 0.25–0.35 GB |
| YOLO26n 640², derived `yolo26n_fp16_rawhead.tflite` (see `detector-yolo26n.md`) | 10.36 MB | strict GPU fp32 (fully accelerated on macOS, 4.1 ms); explicit CPU fallback runs FP32 (~23 ms on M-series); paused during generation | only while the watcher runs | ~0.1 GB including camera buffers |
| App, Flutter, sqlite | — | — | — | 0.2–0.3 GB |
| **Peak** | | | | **~1.9–3.0 GB** |

- **Device headroom.** iPhone 17 Pro has 12 GB (spec sheet, verify) plus the `increased-memory-limit` entitlement.
  Read the actual headroom with `flutter_gemma_diagnostics` `availableBytes`; check that the package is published on
  pub.dev, otherwise use `ProcessInfo.currentRss`. On Android, GPU memory sits mostly outside `anonymousBytes`, so
  read the Graphics line of `dumpsys meminfo`.
- **Disk.** The compiled GPU program cache for E2B is about 600 MB per activation precision.
- **Load order and warm-up.** The LLM loads first: it is the largest, so a failure shows up early, and a non-GPU
  `activeBackend` stops setup with an error. Its warm-up is one `createSession(maxOutputTokens: 1)` generation,
  closed before the chat opens. Then STT loads (warm-up: transcribe 0.5 s of silence), then TTS (warm-up:
  `"Ready."`), then the embedder (warm-up: one retrieval), followed by KB indexing if needed.
- **Singleton rule.** Any argument that differs from the previous `getActive*` call rebuilds the model and closes
  the old one (`firstDifference` in `flutter_gemma_mobile.dart`). So `kLlmConfig` sets `supportImage: true` from
  Inc 1 onward. `activationDataType` (fp16 vs fp32) is decided once, in Inc 2, because switching it recompiles the
  GPU program cache.
- **One generation at a time.** `createChat` fills the model's only chat slot. ConversationRepository owns that one
  chat, and all turns go through VoiceAssistant one at a time.

## 7. Model delivery

- **Gemma.**
  - If `GEMMA_MODEL_PATH` is set, install with `fromFile`. On macOS that is `~/Work/…`, readable through the
    DebugProfile sandbox exception. On iPhone, copy it with `xcrun devicectl device copy to` into Documents and pass
    a documents-relative path. On Android, `adb push` to `/sdcard/Android/data/dev.fluttergemma.litert_hackathon/files/`.
  - Otherwise use `fromHuggingFace('litert-community/gemma-4-E2B-it-litert-lm', file: 'gemma-4-E2B-it.litertlm')`.
    The filename is **unverified**; check the repo. Pass an explicit `file:` because manifest mode needs the network
    on every install.
- **STT and embedder:** `modelFromNetwork` / `tokenizerFromNetwork`, or `modelFromFile`.
- **TTS:** 1.11.3 only has `fromNetwork`, so it must be downloaded once with a network connection.
- **HF token:** pass `HUGGINGFACE_TOKEN` with `--dart-define-from-file=.env` and hand it to
  `initialize(huggingFaceToken:)`. If the token is missing and the embedder is not installed, the knowledge base is
  shown as `unavailable('HUGGINGFACE_TOKEN missing')` in the UI and the overlay; chat keeps working, so the failure is
  visible rather than silent. Use a read-only token: it can be pulled out of the binary.
- **Setup screen:** one row per model with size, state and percentage (`withProgress`, or `withModelProgress` plus
  `withTokenizerProgress`), plus the error text and a Retry button.

## 8. Increments

**Inc 1 — Skeleton, streaming text chat, debug overlay (macOS).**
- **Scope:** bootstrap, catalog, LlmService, ModelRepository (LLM only), ConversationRepository (plain `createChat`,
  final `kLlmConfig`), Diagnostics, Setup and Chat screens (text field, Stop), overlay, Result/Command. Move
  `path_provider` from dev_dependencies to dependencies.
- **Accept:**
  - The model loads on the GPU. A non-GPU backend shows a blocking error and never falls back to the CPU.
  - Tokens update only the bubble.
  - Stop takes ≤500 ms and the next turn works.
  - The overlay shows GPU, model id, load time, time to first token, tokens/s and RSS.
- **Verify:**
  - `fvm flutter run -d macos --dart-define=GEMMA_MODEL_PATH=$HOME/Work/gemma-4-E2B-it.litertlm`
  - `fvm flutter test` (ViewModel with a fake repository; bubble widget test)
  - `fvm flutter test integration_test/chat_smoke_test.dart -d macos --dart-define=GEMMA_MODEL_PATH=…` should print
    `CHAT backend=gpu ttft=…ms tokps=…` and pass
  - `fvm flutter analyze` reports 0 issues.

**Inc 2 — Device bring-up and GPU coexistence check (iPhone 17 Pro; Android when available).** Blocked until Xcode is
signed in to an Apple ID.
- **Scope:** run Inc 1 on the device, plus the GPU coexistence check. The planned `gpu_coexistence_test.dart` was
  built as `integration_test/detector_coex_test.dart` (YOLO26n + Gemma 4 E2B in one process, without the app's UI):
  1. The detector — the derived raw-head file, never Arm's original (it throws on strict GPU) — loads with exactly
     the requested backend (`DETECTOR_BACKEND`, GPU by default) and passes the CPU-reference check (exact steps:
     `detector-yolo26n.md` §4.3, §8).
  2. Cats: the golden classes, box ≤ 3 px, |Δscore| ≤ 0.03, 10 identical runs.
  3. Gemma loads on `GEMMA_BACKEND` (GPU by default, no fallback) next to the loaded detector and generates up to 64
     tokens.
  4. The detector's output afterwards is bit-identical to before.

  The plan's fp16 vs fp32 prefill comparison is not part of it.
- **Verify:** `fvm flutter test integration_test/detector_coex_test.dart -d <device-id>
  --dart-define=GEMMA_MODEL_PATH=… --dart-define=DETECTOR_MODEL_PATH=…/yolo26n_fp16_rawhead.tflite
  --dart-define=FIXTURE_DIR=…/coco30` should print `DETCOEX os=… det=… vs=… box=… gemma=… tokps=… identical=…`. On an
  iPhone also run `codesign -d --entitlements - build/ios/iphoneos/Runner.app`.
- **Decision gate:** if the test fails, the detector moves to the CPU (explicitly, and shown in the
  overlay) and Demo 3 goes to `litert-expert`. Record the precision decision in `model_catalog.dart`.

**Inc 3 — Push-to-talk voice loop (macOS, then iPhone).**
- **Scope:** AudioSession, Mic, Player and Audio repositories; STT/TTS with the `InstrumentedRecognizer` and
  `SpokenSynthesizer` decorators; SpeechRepository; VoiceAssistant; TurnResponder (no RAG yet); mic button and level
  meter; typed turns; a "speak replies" toggle (when off, a `SilentSynthesizer` is used).
- **Accept:**
  - Audio starts after the first finished sentence.
  - Barge-in silences playback in ≤150 ms and starts a new recording.
  - A silent or too-short recording makes no LLM call.
  - The overlay shows STT time, time to first audio and TTS time per clause.
- **Verify:**
  - Unit tests drive VoiceAssistant through a real `VoiceSession.custom` with a fake recognizer, responder and
    synthesizer. They cover barge-in during thinking and during speaking, error → idle, and an empty transcript.
  - `fvm flutter test integration_test/voice_loop_test.dart -d macos …` feeds `test_assets/france_16k.pcm` with the
    mic bypassed. It asserts "France" in the transcript, "Paris" in the reply, and that a first audio chunk arrives,
    and prints `VOICE stt=… ttfa=…`.

**Inc 4 — Images.**
- **Scope:** ImageInputService. `image_picker` provides the gallery everywhere and the camera on iOS and Android.
  Images are normalized to ≤1024 px because `image_picker_macos` silently ignores `maxWidth`. Attachment bar. Sticky
  image: re-send it after an interrupted or failed turn, because `.litertlm` stops seeing earlier images after
  `stopGeneration`.
- **Accept:** a voice question about the photo gets an answer about it. A question after a barge-in still works, and
  the log shows `image resent`.
- **Verify:** an integration test with `test_assets/cat.jpg` and the question "What animal is this?" expects "cat".
  Then a manual camera run on the iPhone.

**Inc 5 — Knowledge base.**
- **Scope:** chunker, Embedder and VectorStore services, KnowledgeRepository (hash-gated indexing with progress),
  PromptBuilder, citation chips, spoken-text sanitizer.
- **Accept:**
  - The first launch indexes the KB with progress; later launches skip indexing.
  - An on-topic question gets citation chips (doc › section, similarity).
  - An off-topic question shows "below gate" in the overlay.
  - TTS never reads "[1]" aloud.
- **Verify:** unit tests for the chunker, prompt builder and sanitizer.
  `fvm flutter test integration_test/kb_retrieval_test.dart -d macos --dart-define-from-file=.env` runs a 20-question
  golden set: the expected document in the top 3 for ≥9/10 on-topic questions, and the gate rejects ≥8/10 off-topic
  ones. It prints a threshold sweep so `kKbMinSimilarity` can be tuned.

**Inc 6 — Agent skills.**
- **Scope:**
  - ConversationRepository switches to `AgentSession(chat: model.createChat(tools: [loadSkillTool, runIntentTool],
    supportsFunctionCalls: true, modelType: ModelType.gemma4, supportImage: true, systemInstruction:
    AgentSession.buildSystemPrompt(registry, systemPromptTemplate: kVoicePrompt), maxOutputTokens: 384), registry: …,
    executors: [appIntents, TextSkillExecutor()])`.
  - SkillStoreService, TimerRepository, the intent handlers, the steps panel and the Skills sheet with a Reload
    button.
  - Add `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` to the iOS Info.plist.
- **Accept:**
  - "Set a timer for 10 seconds" shows `loadSkill(timer)` then `runIntent(start_timer)`, speaks a confirmation, and
    speaks an announcement when the timer fires.
  - Device-info answers name the real backends.
  - A newly dropped `tea-timer/SKILL.md` works after Reload, without a rebuild.
  - A malformed SKILL.md is listed with its parse error.
- **Verify:**
  - Unit tests: every bundled SKILL.md parses, and every intent it names is in `AppIntent.all`. Executor parameter
    validation.
  - `integration_test/skills_test.dart -d macos`.
  - Adding a skill at runtime:
    - macOS: `cp -r tea-timer ~/Library/Containers/dev.fluttergemma.litertHackathon/Data/Documents/skills/`
    - Android: `adb push tea-timer /sdcard/Android/data/dev.fluttergemma.litert_hackathon/files/skills/`
    - iOS: Finder → iPhone → Files.

**Inc 7 — Camera watcher (iPhone).**
- **Scope:** CameraService (the single camera owner), DetectorService, and WatcherRepository: 3 fps, debounce over 2
  frames, 10 s cooldown, paused while the LLM generates. Intents `watch_camera {label, min_score}` (the label is
  checked against the model's Darknet-spelled COCO names plus the aliases in `detector-yolo26n.md` §1) and `stop_watching`. Picture-in-picture preview with boxes. While watching, the chat
  camera uses `CameraService.takePicture()` instead of `image_picker`.
- **Accept:**
  - "Tell me when you see a cup" leads to "I can see a cup." within about 1 s of the cup appearing.
  - The overlay shows the GPU, fps, ms and "paused (LLM busy)".
  - On macOS the request fails with an explicit spoken message.
- **Verify:** unit tests for the watch rule and the latest-frame-wins gate. `fvm flutter run -d <iphone-id> --profile`
  with the DevTools timeline: no UI frame over 16 ms from detection updates. A 5-minute run grows footprint by less
  than 50 MB.

**Inc 8 — Demo hardening.**
- **Scope:** download-everything setup flow, airplane-mode run, an Android run of the Inc 2 and Inc 3 tests, a
  15-minute soak for thermals and memory, failure UX (permissions, missing models), and `flutter build` on every
  platform before the event so prebuilts are fetched in advance.
- **Verify:** the scripted demo checklist; `fvm flutter test integration_test/model_smoke_test.dart -d <android-id> …`;
  `adb shell dumpsys meminfo dev.fluttergemma.litert_hackathon`.

## 9. Decisions

| # | Topic | Default | Why (evidence) |
|---|---|---|---|
| D1 | Layout | Data and domain grouped by layer, UI by feature (`ui/features/<f>/{view_models,views}`) | Official skill layout; Demo 3 shares the whole data layer |
| D2 | Voice orchestration | `VoiceSession.custom(..., streamAudio: true)`, a new one per turn | `fromChat` takes no image. `custom` accepts any `SpeechRecognizer` or `VoiceResponder`. Per-turn instances are cheap and let typed turns share the path. |
| D3 | Audio ownership | `record` captures, `flutter_soloud` buffer stream plays, `audio_session` is the only owner; call `record.manageAudioSession(false)` | VoiceSession has no audio I/O. `record_ios` otherwise calls `setCategory(.playAndRecord)` itself. Soloud 4.1.7 sets up miniaudio with `ma_ios_session_category_none` and does not activate the session. |
| D4 | Session config | iOS: `.playAndRecord`, `defaultMode`, options `defaultToSpeaker` and `allowBluetoothA2DP`. Android: usage `assistant`, content type speech, focus `gainTransient`. `record`: `voiceRecognition` source, `echoCancel: false`. | In half-duplex mode the mic is closed during playback, so there is no echo. `record` enables voice processing (VPIO) on its own `AVAudioEngine`, so soloud's output is likely not its echo reference (**unverified**). Full-duplex needs capture and playback in one native engine (`swift-architect` / `android-architect`). |
| D5 | Endpointing | Push-to-talk; tapping the mic during a reply is the barge-in; maximum utterance = STT window | STT is batch-only and truncates silently. Push-to-talk costs one button. VAD costs a CPU model per 30 ms frame, needs AEC for voice barge-in, and false-triggers in a noisy venue. VAD can come after v1. |
| D6 | STT | Whisper base int8 with `language: 'en'` | moonshine's 5 s window cuts off longer questions. If Whisper takes more than 800 ms on the iPhone (Inc 3), switch to moonshine plus a segmenting recognizer decorator. |
| D7 | TTS | Inflect-nano-v2 on CPU | Catalog: about 36 MB, "very fast". Qwen3-TTS has RTF≈3 and runs on CPU only. |
| D8 | Images with sentence-by-sentence TTS | Confirmed: responder over `AgentSession.ask(imageBytes:, isCancelled:)` | Corrections: `respond` receives only text, so the image comes in through a closure. `isCancelled` is checked only between iterations, so `stopGeneration()` is required. Text the model writes before a tool call is spoken too. Earlier images are lost after a stop, hence the sticky re-send. |
| D9 | RAG trigger | Similarity-gated retrieval before every turn: top 3, gate 0.45 (tuned in Inc 5) | No extra generation; a retrieval tool would cost two more generations (about 1–3 s). Citations are controlled by the app. |
| D10 | KB build | Index `assets/kb/*.md` at first launch, keyed by a hash of (assets + chunker version + model id); on mismatch `rag.clear()` | Demonstrates "chunked and indexed" live. Whether a shipped vec0 database is portable is unverified. |
| D11 | Chunking | Split on headings, 800–1400 characters, one-sentence overlap, prefix "Title › Section", id `doc#n`, metadata `{doc,title,section,chunk}` | Fits the seq512 window; no `filterSchema` needed |
| D12 | Skills directory | `skills/` under Documents (Android: the external files dir), seeded from `AssetManifest` when absent, rescanned on Reload and on resume | Users can write there: Files/Finder on iOS, `adb push` on Android. The Android `app_flutter` directory is not writable by adb. |
| D13 | Skill execution | Two tools only; `AppIntentExecutor` plus `TextSkillExecutor`; no `NativeIntentExecutor`, JS or MCP | `validateIntentParams` returns "unknown intent" for any custom handler. The agent never initializes `flutter_local_notifications`. JS would need the WebView. |
| D14 | Timers | In-app `start_timer {seconds, label}` → Dart `Timer` → spoken announcement | The built-in `schedule_notification` needs wall-clock hour/minute arithmetic and plugin setup, and it never speaks |
| D15 | Watcher | YOLO26n (user decision 2026-10-02, AGPL-3.0 accepted) at 3 fps, paused while generating; a fixed announcement template (no LLM) | GPU contention policy; about 1 s from event to speech |
| D16 | Generation | `maxTokens` 4096, `maxOutputTokens` 384, temperature 0.6, topK 40, thinking off, a "New conversation" command | An image costs hundreds of tokens; replies are short because they are spoken |

## 10. Open questions (each has a recommended answer)

1. **What goes in the knowledge base?** Recommended: 10–20 pages of LiteRT and flutter_gemma documentation
   (Apache-2.0, on-topic for judges).
2. **Support only iOS 26 and later?** Recommended: yes. If a demo device runs iOS < 26, the `-weak-lswiftWebKit`
   workaround is safe here, because Demo 1 registers no JS executor.
3. **English only?** Recommended: yes. Inflect speaks English only, and Whisper is pinned to `'en'`.
4. **Is hands-free voice (VAD) needed for the demo?** Recommended: no. v1 is push-to-talk; VAD plus AEC can be an
   increment after v1.
5. **Which Android phone?** Recommended: name it by Inc 8 (12 GB, Pixel 9 Pro or S25 class). The design assumes at
   least 8 GB.

## 11. Risks

| Risk | Check that reveals it | Retired in |
|---|---|---|
| Two LiteRT copies, or two Metal accelerators, conflict on the GPU | `integration_test/detector_coex_test.dart` | Inc 2 (CPU detector as an explicit fallback) |
| App dies at launch below iOS 26 (inappwebview) | launch on the target iPhone | Inc 2 / Q2 |
| Android is untested (no device) | smoke, coexistence and voice tests on the device | Inc 8 |
| iOS signing is still pending | a signed build plus `codesign` read-back | Inc 2; macOS work continues meanwhile |
| Memory peak or jetsam | snapshots after each load; 15-minute soak | Inc 2, Inc 8 |
| GPU fp16 corrupts digits (timer seconds) | a timer-args test, fp16 vs fp32 | Inc 2 / Inc 6 |
| STT truncation, or hallucination on near-silence | long-utterance and silence tests; RMS gate | Inc 3 |
| Barge-in drain takes up to 5 s | logged interrupt-to-idle time | Inc 3 |
| Image dropped after a stop | re-send test | Inc 4 |
| Context overflow from images and excerpts | `chat.currentTokens` in the overlay over 10 turns | Inc 5, Inc 6 |
| Two extra generations per skill call; the model picks the wrong skill | per-phase timings; executor errors fed back to the model | Inc 6 |
| `image_picker` and the watcher compete for the camera | the camera test while watching | Inc 7 |
| Thermal throttling (no Dart API for thermal state) | soak; tokens/s drift | Inc 8 (a Pigeon thermal probe from `swift-architect` if needed) |
| Venue Wi-Fi; native prebuilts fetched at first build | airplane-mode run; pre-built apps | Inc 8 |

## 12. Hand-off

- **`flutter-coder`:** all Dart in Inc 1–8.
- **`flutter-gemma-expert`:** reviews the ConversationRepository, AgentSession, VoiceSession and RAG wiring before
  Inc 3, 5 and 6 are coded.
- **`litert-expert`:** I/O contract for YOLO26n (`Arm/yolo26n-fp16-litert`: input layout/normalization, the NMS-free output, class names, GPU vs XNNPACK); defines its I/O and
  preprocessing contract; provides the Inc 2 fixture and test; measures CPU vs GPU numbers.
- **`swift-architect`:** reviews the iOS audio session for Inc 3; plans full-duplex if Q4 changes.
- **`android-architect`:** Android audio focus and record source; camera YUV (Inc 7, Inc 8).
- **`flutter-reviewer`:** reviews after every increment. Checks: no `FlutterEdgeAi.getActive*` outside the model
  services (§3.3); no `notifyListeners` per token; every stream and subscription closed; no swallowed errors.

## 13. Findings recorded elsewhere

- `docs/upstream-issues.md`: the published flutter_gemma_agent 0.2.6 contains no bundled SKILL.md files.
- `docs/setup-checklist.md`: `path_provider` → `dependencies`; `assets/skills/` + `assets/kb/` in `pubspec.yaml`;
  iOS file-sharing keys (Inc 6); `image_picker_macos` ignores `maxWidth`/`imageQuality` and throws for the camera
  source; the TTS installer has no file source in 1.11.3 (history: Inflect is built in since 2026-10-07).

Sources read (beyond `~/.pub-cache`): `AGENTS.md`, `docs/demos.md`, `docs/setup-checklist.md`,
`docs/upstream-issues.md`, `integration_test/model_smoke_test.dart`,
`.claude/skills/flutter-gemma-{speech,rag,function-calling,inference,diagnostics}/SKILL.md`,
`~/Work/flutter_gemma/packages/flutter_gemma_agent/.pubignore`,
`~/Work/flutter_gemma/packages/flutter_gemma/example/lib/models/{tts,stt,embedding}_model.dart`.
