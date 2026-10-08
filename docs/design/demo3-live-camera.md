# Demo 3 — Live camera assistant (design)

Status: design, 2026-10-02 (`flutter-architect`). Checked against the Inc 1 code under `lib/` and the resolved sources:
camera 0.12.1, camera_avfoundation 0.10.3+1, camera_android_camerax 0.7.5+1, flutter_litert 3.9.3, flutter_gemma
1.11.3, flutter_gemma_litertlm 1.8.5 and flutter_gemma_speech 0.5.2. Anything marked **unverified** names the check
that settles it. Detector contract: [detector-yolo26n.md](detector-yolo26n.md). Demo 1:
[demo1-voice-chat.md](demo1-voice-chat.md).

> **2026-10-06:** Demo 1's camera watcher (`CameraWatcher`, Inc 7) was removed; `LiveDetectionRepository` now serves
> Demo 3 only. The mentions of the watcher below are history.

## 1. Decision summary

- **One camera pipeline, two demos.** A new `LiveDetectionRepository` owns the chain FrameSource → DetectorService
  worker → `ValueListenable<DetectionFrame>`. Demo 3 uses it directly. Demo 1's watcher (Inc 7) becomes a small
  `CameraWatcher` use case on top of it. This replaces Demo 1's `WatcherRepository`, because repositories must not
  depend on each other.
- **macOS now: add `camera_desktop: ^2.0.0`.** It implements `camera_platform_interface`, so the same
  `CameraController` code runs on macOS. A `FixtureFrameSource` (image slideshow) is kept for deterministic tests.
- **Router.** Keyword rules over a COCO vocabulary (about 0.1 ms). Fast answers are spoken from templates, with no
  LLM. Anything the rules are unsure about goes to Gemma.
- **Detailed path.** At mic-up the app captures the next frame and runs the detector on that exact frame. If Gemma is
  needed, the view freezes on that frame. It is sent as a PNG of at most 1024 px, un-mirrored, through the same
  `ConversationRepository` under a stateless "camera" profile.
- **GPU.** The detector pauses while Gemma generates. The frozen view makes that honest, and the overlay shows
  `det paused (<chat model name>)`.
- **Shared models.** Everything loads once at setup and stays loaded. Switching demos only re-opens the single chat
  with that demo's profile and hands over the camera.

## 2. Goals and non-goals

| Goal | Target |
|---|---|
| Live boxes | ≥15 fps processed (capped); boxes ≤80 ms behind the preview; no UI frame over 16 ms caused by detection |
| Fast answer: mic-up → first audio | ≤1.0 s on macOS, ≤1.3 s on iPhone |
| Detailed answer: mic-up → first audio | ≤3.0 s on macOS, ≤4.0 s on iPhone |
| Detector resumes after generation | ≥12 fps within 1 s |
| Memory | peak ≤3.5 GB on iPhone with both demos' models loaded |
| Honesty | overlay shows the source, detector backend, fps, pre/run/post ms, route + rule, and per-turn timings |

**Non-goals:** hands-free VAD; multi-turn camera chat; tracking or IDs across frames; non-COCO fast answers; Android
before a device exists.

## 3. Architecture

> **§3 describes the code as of 2026-10-08** (rebuilt from `find lib -name '*.dart'` at f9bc207). The increments in
> §8 keep their original plan. Demo 1's files and the shared ones are mapped in
> [demo1-voice-chat.md](demo1-voice-chat.md) §3.2.

```
UI (main isolate)
  HomeScreen ─ HomeViewModel ........... per-demo availability from ModelStates.states
  LiveCameraScreen ─ LiveCameraViewModel  phase, frozen frame, last exchange (low rate); owns its VoiceAssistant
    CameraExchangeReducer ... turn events → the caption, freeze/unfreeze, overlay records (pure)
    LiveSettingsApplier ..... camera source and detector backend, saved and applied one at a time
    LivePreview ............. CameraCoverPreview | RawImage (by PreviewSource), cover-fit
    detection layer ......... CustomPaint(DetectionPainter(repaint: live.frames))  ≤15 Hz
    frozen layer ............ RawImage(snapshot image) + static DetectionPainter
    caption ................. ValueListenableBuilder(partialReply); route chip
    MicButton ............... CustomPaint(LevelRingPainter(repaint: inputLevel))
    CameraSettingsSheet ..... source (device / network URL), detector (GPU / CPU)
Domain (main isolate)
  VoiceAssistant<CameraSideEvent> ... shared with Demo 1 (generic)
  CameraTurnResponder ............... QuestionRouter · FastAnswerComposer · buildCameraPrompt
  GpuArbiter (app-scoped) ........... Conversation.isGenerating → setDetectorDuty callback (live.setDuty)
Data: repositories (main)
  LiveDetectionRepository ........... + live_detection/: LiveStatsTracker, BlackFrameDetector, SceneCapture
  LiveCameraSettingsRepository · Conversation · Speech · Audio · Model · Diagnostics (shared)
Data: services
  CameraFrameSource .. camera → avfoundation / camerax / camera_desktop (platform thread → main callback)
  NetworkFrameSource . MJPEG over HTTP → TurboJPEG worker isolate (or the engine codec) (§13, §15)
  FixtureFrameSource . Timer on main; images decoded once by the engine
  DetectorService .... long-lived worker isolate: GatherPlan → CompiledModel.run (GPU fp32) → selectRaw
  SnapshotEncoder .... dart:ui (raster/IO threads): ImageDescriptor.raw → scale/flip → PNG
  LlmService (LiteRT-LM native) · STT · TTS · record · soloud · audio_session
```

### 3.1 File map (`lib/`)

| Path | Responsibility / API |
|---|---|
| `config/env.dart` | `kDetectorModelPath` (`DETECTOR_MODEL_PATH`; empty = the built-in detector), `kDetectorBackend` (`gpu`\|`cpu`; empty by default = Demo 3's saved setting, §14), `kFrameSource` (`camera` by default = the user's choice; `fixture` and `network` lock it), `kNetworkCameraUrl`, `kFixtureDir` |
| `config/model_catalog.dart` | `ModelId.yolo26n` (`domain/models/model_id.dart`); `kSampler` (temperature 0.6, topK 40, shared); `kLlmImageMaxSide` 1024; `ConversationProfile`; `kCameraProfile` (stateless, `maxOutputTokens` 160) |
| `config/live_camera_config.dart` | `kLiveDetectFps = 15`, `kSummaryWindow = 5`, `kSummaryMaxAge`, `kCountScore = 0.4`, `kCaptureTimeout`, `kCameraPreset = ResolutionPreset.high`, `kCameraFps = 30`, `kDetectorDuringGeneration = DetectorDuty.paused`, the watchdog and black-frame thresholds, the fixture and network-camera constants, `kMaxPaintedBoxes` |
| `domain/vision/coco_vocabulary.dart`, `stt_corrections.dart` | `kCocoVocabulary` (Darknet spellings, aliases from detector doc §1): `resolveNoun(String) → int?`, `spokenName(cls, count)`, `withArticle`, `counted`; words the recognizer hears instead of a COCO object |
| `domain/models/detection.dart`, `detector_spec.dart`, `detector_choice.dart` | `DetectorInfo`, `DetectionFrame` (detector doc §7.2: upright boxes `count × 6`, pre/run/post µs, backend); the raw-head contract; who chose the backend |
| `domain/models/scene_snapshot.dart` | `RgbaPixels`; `SceneSnapshot({frameId, detections, summary, pixels, mirrored, …})`; `EncodedSnapshot({png, frameId, width, height, unmirrored, encodeTime})`; `CaptureFailure`, `CaptureUnavailableException` |
| `domain/models/detection_summary.dart` | `DetectionSummary`: per class, the median count over the window at ≥ `kCountScore` |
| `domain/models/route_decision.dart` | `sealed RouteDecision`: `FastRoute(intent, cls, rule)` or `DetailedRoute(rule)`; `enum FastIntent` |
| `domain/models/live_state.dart` | `enum DetectorDuty {live, paused}`; `sealed LiveState`: `LiveStopped` / `LiveStarting` / `LiveRunning(source)` / `LivePaused(source, reason, since)` / `LiveFailed(message)`; `LiveStats` |
| `domain/models/camera_side_event.dart` | `SnapshotTaken`, `SnapshotFailed`, `TranscriptCorrected`, `RouteChosen`, `CameraChatUnavailable`, `FrameSentToGemma`, `DetailedAnswered`, `CameraChatReset`, `FastAnswered`, `DetailedUnavailable`; `CameraTurnMetrics` |
| `domain/models/frame_source_info.dart`, `frame_source_spec.dart`, `camera_source.dart` | `FramePixelFormat`, `FrameSourceInfo` (below); `sealed FrameSourceSpec`: `CameraSourceSpec`, `FixtureSourceSpec(paths, mirrored)`, `NetworkSourceSpec(url)`; the user's camera source choice |
| `domain/use_cases/voice_assistant.dart` | `VoiceAssistant<S>({speech, audio, responders, diagnostics, config, recognizer})`: `phase`, `partialReply`, `inputLevel`, `events` (`VoiceAssistantEvent<S>`, side events included), `micDown()`, `micUp()`, `stop()`, `dispose()` (demo1 §4). No announcements: they went with the watcher |
| `domain/use_cases/turn_responder_factory.dart` | `TurnResponderFactory<S> { TurnPreparation<S> prepare(TurnRequest request); }`, called at release before the capture closes; `TurnPreparation<S>`: `responder(onSide)` when the turn runs, `discard()` when it does not |
| `domain/use_cases/camera_turn_responder.dart` | `CameraTurnResponder({capture, conversation, encode, …}) implements TurnResponderFactory<CameraSideEvent>` (§6); `capture`/`encode` are `LiveDetectionRepository.capture`/`encodeForLlm` |
| `domain/use_cases/question_router.dart` | `const QuestionRouter()`; `RouteDecision classify(String transcript)` |
| `domain/use_cases/fast_answer_composer.dart` | `String compose(FastRoute route, DetectionSummary summary)` |
| `domain/use_cases/camera_prompt.dart` | `String buildCameraPrompt(String question, DetectionFrame frame, {required bool mirrored, …})`: the question plus at most 8 detections with coarse positions, labelled "may be incomplete" |
| `domain/use_cases/gpu_arbiter.dart` | `GpuArbiter({required ValueListenable<bool> llmBusy, required DetectorDutySetter setDetectorDuty, required DetectorDuty duringGeneration, String? Function()? chatModelName})`, `dispose()`. The app passes `live.setDuty`, `kDetectorDuringGeneration` and the loaded chat model's name (the pause reason) |
| `data/services/frames/frame_source.dart` | the interface below; `FramePlane`, `FrameView`, `PreviewSource`; the `SingleUseStart` lifecycle every source mixes in |
| `data/services/frames/camera_frame_source.dart` | `CameraController(desc, kCameraPreset, enableAudio: false, fps: 30, imageFormatGroup: Android ? nv21 : bgra8888)`; back camera on phones, the first camera on desktop |
| `data/services/frames/fixture_frame_source.dart` | `FixtureFrameSource({required paths, fps = kFixtureFps, hold = kFixtureHold, mirrored = false, …})`: decodes each image once to RGBA, emits `rgba8888` frames, preview is an `ImagePreviewSource` |
| `data/services/frames/network_frame_source.dart`, `mjpeg_parser.dart`, `jpeg_decoder.dart`, `turbojpeg.dart`, `engine_image_decoder.dart` | the network camera (§13, §15): MJPEG parts, TurboJPEG in a worker isolate, the engine codec |
| `data/services/detector/detector_service.dart` (+ `detector_worker.dart`, `detector_engine.dart`, `detector_codec.dart`, `detector_verification.dart`, `frame_message.dart`) | `load({source, backend}) → Result<DetectorInfo>`, `detect(FrameMessage) → Result<DetectionFrame>`, `detectWithSnapshot(FrameMessage) → Result<SnapshotDetection>` (also returns upright RGBA), `close()`; the strict-GPU and CPU-reference checks (detector doc §4.3) |
| `data/services/images/snapshot_encoder.dart` | `SnapshotEncoder.toPng(...) → EncodedSnapshot` (≤ `kLlmImageMaxSide`, mirrored back when the source mirrors) |
| `data/repositories/live_detection_repository.dart` | see the code block below |
| `data/repositories/live_detection/live_stats_tracker.dart` | `LiveStatsTracker`: source frames, drops (`FrameDrop`), processed frames → `LiveStats` at most every `kLiveStatsInterval` (pure, injected clock) |
| `data/repositories/live_detection/black_frame_detector.dart` | `BlackFrameDetector`: sampled frames dark and flat for `kBlackFramesAfter` → `BlackFramesStarted`; a bright or textured sample → `BlackFramesEnded` (pure) |
| `data/repositories/live_detection/scene_capture.dart` | `SceneCapture`: the summary window, the one pending question capture (`capture`, `wantsFrame`, `claimFrame`, `complete`, `fail`), captures waiting for a starting source, `encodeForLlm`, `snapshotImage` |
| `utils/stall_watchdog.dart` | `StallWatchdog` (no source frame within the timeout) and `DeadlineWatchdog` (a frame in flight not answered in time); both re-arm instead of failing when the app itself was suspended |
| `utils/frame_rate_gate.dart` | `FrameRateGate`: at most `fps` frames on average, jitter tolerated |
| `data/repositories/live_camera_settings_repository.dart` | `readSource()`, `saveSource(choice)`, `resolveSource() → FrameSourceSpec`, `readBackend()`, `saveBackend(backend)`, `sourceLock`, `backendLock` (§13, §14) |
| `data/repositories/conversation_repository*.dart` | shared with Demo 1 (demo1 §3.2): `open(ConversationProfile, {skills})` stops and waits for a draining turn first; `profile`; `capabilities`; `ask(prompt, {image, onStep})`; `reset(ifCurrent:)` |
| `data/repositories/model_repository.dart` | `prepareAll` order: the chat model, Whisper, Inflect, then the optional detector (detector doc §4.3 checks), moonshine and the embedder; an optional model fails without blocking setup; `reloadDetector()` after a backend switch |
| `data/repositories/diagnostics_repository.dart` | listens to `live.state` and `live.stats` (constructor arguments); `recordCameraTurn(CameraTurnMetrics)`, `recordCameraReset(elapsed, {error})`, `recordFrozen(frameId)` |
| `ui/features/live_camera/view_models/live_camera_view_model.dart` | `LiveCameraViewModel`: owns its `VoiceAssistant`, the frozen frame (`FrozenFrame`), the detector failure card (`DetectorFailure`), the settings applier |
| `ui/features/live_camera/view_models/live_settings_applier.dart` | `LiveSettingsApplier`: Demo 3's settings (camera source, detector backend) saved and applied — one at a time, the newest pending choice wins field by field, source before backend; `load()`, `apply({kind, networkUrl, backend})`, `runDetectorOn(backend)`, `close()`; it starts and stops live detection through closures the view model gives it |
| `ui/features/live_camera/view_models/camera_exchange_reducer.dart` | `CameraExchangeReducer`: pure `reduce(CameraExchangeState, VoiceAssistantEvent<CameraSideEvent>, ChatCapabilities) → CameraExchangeUpdate` (next state + effects: unfreeze, freeze, overlay records, chat reset, rebuild); owns the failure, barge-in (detached) and freeze rules of the caption |
| `ui/features/live_camera/views/*`, `ui/features/home/…`, `ui/core/detection_painter.dart` | `LiveCameraScreen`, `LivePreview` (+ `CameraCoverPreview`), `CameraSettingsSheet`; `DetectionPainter({required ValueListenable<DetectionFrame?> frames, required bool mirror, double minScore = kDetDisplayScore, int maxBoxes = kMaxPaintedBoxes})` |

```dart
enum FramePixelFormat { bgra8888, rgba8888, nv21, yuv420 }    // domain/models/frame_source_info.dart

/// Valid only during the callback: camera_desktop's FFI path may recycle the buffer.
abstract interface class FrameView {
  int get width; int get height; FramePixelFormat get format;
  int get rotationDeg; List<FramePlane> get planes; // bytes, bytesPerRow, bytesPerPixel
}
abstract interface class FrameSource {                        // single-use: start once, stop once
  Future<Result<FrameSourceInfo>> start(void Function(FrameView) onFrame,
      {void Function(Exception error)? onError});             // a failure after a good start, once
  Future<void> stop();
  PreviewSource get preview;
}
final class const FrameSourceInfo({required final String label, required final int width,
  required final int height, required final FramePixelFormat format, required final bool mirrored,
  final bool previewMirrored = false, final Duration? stallTimeout, final String? decoder});
sealed class const PreviewSource();
final class const CameraPreviewSource(final CameraController controller) extends PreviewSource;
final class const ImagePreviewSource(final ValueListenable<ui.Image?> image) extends PreviewSource;

class LiveDetectionRepository {
  LiveDetectionRepository({required Detector detector, required FrameSourceFactory createSource, …});
  ValueListenable<LiveState> get state;
  ValueListenable<DetectionFrame?> get frames;       // ≤ kLiveDetectFps
  ValueListenable<PreviewSource?> get preview;
  ValueListenable<LiveStats> get stats;              // at most every kLiveStatsInterval
  ValueListenable<bool> get blackFrames;             // the black-frames warning
  FrameSourceInfo? get sourceInfo; DetectorInfo? get detectorInfo; DetectorDuty get duty;
  Future<Result<FrameSourceInfo>> start(FrameSourceSpec spec, {required Object owner}); // serialized; a take-over
  Future<void> stop({required Object owner});        // no-op if another owner holds it
  void setDuty(DetectorDuty duty, {String? reason});
  Future<Result<SceneSnapshot>> capture();           // next frame + its own detection, even while paused
  Future<Result<EncodedSnapshot>> encodeForLlm(SceneSnapshot s); // PNG ≤ kLlmImageMaxSide, mirrored back
  Future<Result<ui.Image>> snapshotImage(SceneSnapshot s);       // the frozen view's image (caller disposes)
  Future<void> close();
}
```

## 4. Launcher, shared models, ownership

- **Routes:** `/` setup → `/home` → push `/chat` (Demo 1) or `/camera` (Demo 3). Back pops to home, which disposes
  that demo's view model. Home shows each tile's availability:
  - Demo 1 needs the chat model, STT and TTS. Without the embedder the knowledge base is shown as unavailable.
  - Demo 3 needs the chat model, STT, TTS and the detector. A failure shows on the tile, for example
    `GPU rejected YOLO26n: … (DETECTOR_BACKEND=cpu runs the explicit CPU mode)`.
- **Models:** `ModelRepository` is app-scoped and loads everything once. The chat model's `ChatModelConfig.llm`
  (images on or off per its saved settings, custom-chat-model.md C6) is the only `getActiveModel` argument set. A
  profile is a *chat* setting, never a model argument. The profiles share `kSampler`, because on `.litertlm` the
  first session's sampler can stay in effect (inference skill). Profiles vary only `systemInstruction`,
  `maxOutputTokens` and the skills template.
- **Use only the `createChat` lane.** `ffi_inference_model.dart`: `openSession` (the virtual multiplexer) tears down
  only its own virtual conversation, never the legacy chat. Mixing the two lanes could leave two live native
  conversations (upstream #966). So Demo 3 never calls `openSession`. Reviewer check: grep for it.
- **Demo switch:** the entering view model calls `conversation.open(itsProfile)`, which awaits any draining stop.
  Demo 1's history is dropped, and home says so.
- **Camera:** `LiveDetectionRepository` is the only camera owner. An owner token stops a late, unawaited `dispose()`
  from stopping the next demo's camera.
- **Audio:** `audio_session` is configured once (Demo 1 D3/D4). Both demos are half-duplex. The camera must use
  `enableAudio: false`. Verified: camera_avfoundation then sets
  `automaticallyConfiguresApplicationAudioSession = false` and never calls `upgradeAudioSessionCategory`.

## 5. Per-frame pipeline

| Edge | Type | Rate | Buffering / backpressure | Thread | Cancellation |
|---|---|---|---|---|---|
| Camera → `onFrame` | BGRA 1280×720 (Apple), NV21 (Android), RGBA (fixture) | 30 fps | none | platform → main | `stop()` |
| Gate | — | ≤15 fps | **one slot**: frames are dropped while the worker is busy, while paused, or within 66 ms of the last send; the busy flag is released in `finally` | main | — |
| Copy → worker | `FrameMessage` (`TransferableTypedData`, 3.7 MB) | ≤15 fps | copied inside the callback only when the gate is open | main → worker | the worker drains the in-flight frame on `stop` |
| Preprocess + run + decode | NCHW 640² → `[8400,84]` → ≤100 dets | ≤15 fps | 720p letterboxes to 640×360 with pad bars; one reused input tensor | worker isolate, GPU | `close()` awaits the in-flight frame |
| Worker → main | `DetectionFrame` (<3 KB) | ≤15 fps | latest value only, plus a ring of the last 5 frames for the summary | main | — |
| Painter | `CustomPaint(repaint:)` | ≤15 Hz | no widget rebuild; at most 50 boxes | raster | — |
| `capture()` | next frame copied twice (snapshot + worker) → `detect(withSnapshot)` → upright RGBA | per question | waits for the in-flight frame (≤20 ms); ignores pause | main ↔ worker | turn interrupt |
| Diagnostics | fps, drop %, p50 pre/run/post | ≤4 Hz | coalesced | main | — |

Expected per-frame cost: about 9–11 ms on an M4 Pro (detector doc §5). A phone may be 1.5–3× slower, still inside
the 66 ms budget. Under thermal throttling the fps drops on its own and nothing queues.

## 6. Question turn

At **mic-up** (the release):
1. `CameraTurnResponder.prepare(request)` starts `snap = live.capture()` at once, in parallel with closing the
   capture, the silence gate and STT (`request.image` is ignored: the camera is the image). A turn that does not run
   discards it.
2. `VoiceSession.custom(streamAudio: true)` runs the turn with the preparation's `responder(onSide)`. Its
   `respond(transcript)`:
   - `s = await snap`; on failure it speaks "The camera isn't running." (or the timed-out / failed variant) and the
     reason shows in the UI (`SnapshotFailed`).
   - `r = router.classify(transcript)`, then `onSide(RouteChosen)`.
   - **Fast path:** `yield composer.compose(r, s.summary)`. Detection stays live and the view is not frozen. A chip
     shows the basis, e.g. "person ×2 · cup — detector, no LLM".
   - **Detailed path:**
     0. Chat model with images off: the detector's list is spoken instead (`DetailedUnavailable`), nothing freezes.
     1. The view model freezes on `s` (RawImage plus the snapshot's own boxes, "Answering about this frame").
     2. `png = await encodeForLlm(s)` (`EncodedSnapshot`); the previous detailed turn's reset is awaited first.
     3. `yield* conversation.ask(buildCameraPrompt(...), image: png.png)` as text deltas.
     4. Afterwards an unawaited `conversation.reset(ifCurrent: kCameraProfile)` gives the next turn a clean chat, off
        the critical path; it only applies while the camera profile is still the open one, and its time goes to the
        overlay (`CameraChatReset`).
   - `stop` stops the chat only while this turn's own ask runs.
3. **Unfreeze** when playback has drained, on mic-down (barge-in, Demo 1 semantics), or on a tap.

**Router rules** (normalized lowercase, punctuation stripped, ordered):
1. Detail cues win and go detailed: describe, read, say(s), text, sign, label, colo(u)r, wearing, doing, happening,
   where, left, right, behind, next to, on top, under, between, closest, what kind/type, brand, breed, why, explain,
   tell me about, look closer, are you sure, who, and "what is this/that/it".
2. Inventory ("what (do|can) you see", "what's in front of me", "what objects") goes fast.
3. `how many X` and `is/are there (a|any) X`, `do/can you see X`: fast **only if** `resolveNoun(X)` hits COCO.
   Otherwise detailed (`unknown-noun`).
4. Everything else is detailed (`default`).

Spatial judgments go to Gemma, as the spec says. Negative answers are hedged: "I don't see a giraffe right now."

| Option | Classify | Phrase | Verdict |
|---|---|---|---|
| Rules + templates | ~0.1 ms | ~0 ms | **chosen**: deterministic and testable |
| Embedding classifier (EmbeddingGemma, CPU) | ~50–150 ms (estimate) | — | only if the golden set fails |
| Text-only LLM over the detection list | ~0.3–0.8 s (chat reset + ~150-token prefill; estimate) | +0.8–1.5 s to the first clause | rejected: holds the GPU and the chat slot, and is not "immediate" |

| Latency (mic-up →) | Fast | Detailed |
|---|---|---|
| STT (Whisper base) | Inc 3 measure; iPhone ≤800 ms (D6) | same |
| capture (parallel with STT) | ≤100 ms, hidden | same |
| route + compose / PNG encode | <1 ms | ≤50 ms (**unverified**) |
| Gemma TTFT with image (CPU vision encoder) | — | Mac ~0.5–1 s, iPhone 1–2 s (**unverified**) |
| first clause + TTS | ~0.15 s | ~0.5 s + 0.15 s |
| **Target, first audio** | **≤1.0 s Mac / ≤1.3 s iPhone** | **≤3 s / ≤4 s** |

## 7. GPU and memory

| Situation | Detector | View | Overlay |
|---|---|---|---|
| idle / listening / fast reply | live, 15 fps | live | `det GPU fp32 full · 15.0 fps · p50 9 ms` |
| Gemma generating (Demo 3 detailed turn, or a Demo 1 turn) | paused: gate closed, in-flight frame finishes | frozen (Demo 3) | `det paused (Gemma 4 E2B) 2.4 s` |
| generation done, TTS still speaking | live again | still frozen | `det live · view frozen` |

Why pause: `flutter_litert` has no GPU priority knob (detector doc §4.2), contention would slow down the answer the
user is waiting for, and live boxes would be hidden under the frozen view anyway.

| Model | Demo | Backend | Resident | Memory |
|---|---|---|---|---|
| Gemma 4 E2B | both | GPU decoder, CPU vision encoder | setup → exit | 1.2–2.0 GB |
| Whisper base int8 / Inflect-nano-v2 | both | CPU | setup → exit | ~0.25 GB |
| EmbeddingGemma-300M | 1 | CPU | setup → exit | 0.25–0.35 GB |
| YOLO26n raw-head | 3 | strict GPU fp32, or CPU only if explicitly chosen | **setup → exit** (Demo 1 said "while watching") | ~0.1 GB incl. worker |
| 720p buffers + snapshot (raw 3.7 MB, `ui.Image`, PNG ≤1.5 MB) | 3 | — | while Demo 3 is open | 30–50 MB |
| App, Flutter, sqlite | — | — | — | 0.2–0.3 GB |
| **Peak** | | | | **~2.0–3.1 GB** |

## 8. Increments (interleaved with Demo 1)

Order: Inc 1 ✅ → **D3-0 → D3-1 → D3-2** → Inc 3 → **D3-3** → Inc 4 → **D3-4** → Inc 5, Inc 6 → Inc 7 (now only
`CameraWatcher`, reusing D3-1/D3-2) → Inc 2 + **D3-5** (device) → Inc 8.

Common flags: `M=--dart-define=GEMMA_MODEL_PATH=$HOME/Work/gemma-4-E2B-it.litertlm
--dart-define=DETECTOR_MODEL_PATH=$HOME/Work/models/yolo26n/fp16/yolo26n_fp16_rawhead.tflite`. Every increment also
ends with `fvm flutter analyze` = 0 and `fvm flutter test`.

**D3-0 — Launcher and profiles (macOS).**
- **Scope:** HomeScreen and HomeViewModel; `ConversationProfile`; `open(profile)` awaits `stop()`; optional models; a
  placeholder `/camera` screen.
- **Accept:**
  - Setup leads to home.
  - The Demo 3 tile shows `DETECTOR_MODEL_PATH not set` when the flag is missing.
  - Going Demo 1 → home → Demo 1 works, with a fresh chat.
  - `open()` during a draining turn waits instead of failing (unit test with `FakeLlmService`).
  - `chat_smoke_test` still passes.

**D3-1 — Detector and fixture live view (macOS).** Pulls Inc 7's DetectorService forward.
- **Scope:** worker (with the RGBA gather); ModelRepository detector step; `FixtureFrameSource`;
  `LiveDetectionRepository` without capture; `DetectionPainter`; Demo 3 screen with boxes and the overlay; `GpuArbiter`.
- **Accept:**
  - The coco30 slideshow shows aligned boxes.
  - Cats via the fixture path give the golden classes (box ≤3 px, |Δscore| ≤0.03; JPEG decode differs from PIL).
  - ≥15 fps processed.
  - `DETECTOR_BACKEND=cpu` shows an amber "CPU (explicit)". The Arm original file shows a load error.
  - macOS coexistence: 20 detections are bit-identical before and after a 64-token generation, and the overlay shows
    `paused (<chat model name>)` during it.
- **Verify:**
  - `fvm flutter test test/data/services/detector/gather_plan_test.dart
    test/data/repositories/live_detection_repository_test.dart` (BGRA/RGBA/NV21
    × 4 rotations against the `dart_probe` reference; latest-frame-wins; pause; stop with a frame in flight).
  - `fvm flutter test integration_test/live_detection_test.dart -d macos $M --dart-define=FRAME_SOURCE=fixture
    --dart-define=FIXTURE_DIR=$HOME/Work/models/yolo26n/test_images/coco30` prints
    `LIVE src=fixture det=gpu-fp32 full=true fps=… pre/run/post=… COEX identical=true`.
  - `--profile` with the DevTools timeline: no frame over 16 ms.

**D3-2 — Camera source (macOS via camera_desktop; iPhone pending).**
- **Scope:** add `camera_desktop: 2.0.0` (pinned); `CameraFrameSource`; `PreviewSource`; cover-fit preview;
  permission-denied state.
- **Accept:**
  - The log prints `CAMERA src=camera_desktop 1280x720 bgra stride=… mirrored=true`.
  - A cup held on the left gets its box over it. Frames are mirrored natively, so the painter uses `mirror: false`.
  - The camera LED goes off ≤1 s after leaving Demo 3.
- **Verify:** `fvm flutter run -d macos $M --dart-define=FRAME_SOURCE=camera`, manual checklist.

**D3-3 — Fast path (macOS; needs Inc 3).**
- **Scope:** vocabulary, router, composer, summary, `capture()`, `CameraTurnResponder` (the detailed branch speaks
  "Detailed answers aren't wired yet" with a visible chip), mic button.
- **Accept:**
  - "How many cats do you see?" on cats → "I count two cats." with ≤1.0 s to first audio and `llmTurns == 0`.
  - Router golden set (≥60 utterances, Whisper-styled): ≥95% overall and 100% on the must-be-detailed subset.
- **Verify:**
  - `fvm flutter test test/domain/`
  - Make the question audio: `say -o q.aiff "How many cats do you see?" && afconvert -f WAVE -d LEI16@16000 -c 1 q.aiff
    test_assets/q_cats.wav`.
  - `fvm flutter test integration_test/camera_assistant_test.dart -d macos $M` prints
    `CAMQ route=fast rule=count stt=… first_audio=… answer=…`.

**D3-4 — Detailed path (macOS; needs Inc 4).**
- **Scope:** freeze UI, `encodeForLlm`, `kCameraProfile`, post-turn reset, barge-in unfreeze, synthetic `GATE 42`
  fixture (PIL, from the `.venv`).
- **Accept:**
  - "Describe the scene" on cats mentions 2 of {cat, remote, sofa/couch}.
  - "What does the sign say?" contains "42", including through a fake *mirrored* source (proves the un-mirroring).
  - The PNG long side is ≤1024. The frame id that was encoded equals the frozen frame id.
  - Detection is paused during generation and back to ≥12 fps within 1 s.
  - Barge-in silences playback in ≤150 ms.
  - Demo 1 still works after switching back.
- **Verify:** the same integration file prints
  `CAMQ route=detailed png=…ms reset=…ms ttft=… first_audio=… paused=…ms recover=…ms`.

**D3-5 — Device (pending: iPhone signing, no Android device yet).**
- **iPhone 17 Pro:** back camera BGRA 720p; rotation 90 in portrait; boxes aligned. The worker isolate builds strict
  GPU (detector doc §10). Measure Gemma tok/s and detector ms with the detector at 0 and 15 fps during generation, to
  confirm the pause policy. 10-minute soak: footprint grows <50 MB, fps drift is logged, no jetsam. Airplane-mode run.
- **Android:** NV21 path; GL/CL thread affinity with the worker isolate.
- **Verify:** `fvm flutter test integration_test/camera_assistant_test.dart -d <iphone-id> …`, plus `--profile`.

## 9. Decisions (defaults)

| # | Topic | Default | Why |
|---|---|---|---|
| C1 | Dev frame source | `camera` + `camera_desktop` on macOS, plus `FixtureFrameSource` for tests | camera_desktop 2.0.0: 160 pub points, 13k downloads/30 days, MIT, `is:swiftpm-plugin`, implements `camera`; same publisher as flutter_litert (hugo.ml), whose `camera_frame.dart` already documents its BGRA frames. A looping video would need a decoder with raw-frame access, so it is not worth it. |
| C2 | Camera config | `high` (1280×720), 30 fps, `enableAudio: false` | Text reading needs more than 480p. GatherPlan cost scales with output pixels. Keeping the audio session untouched is verified in source. |
| C3 | Detection rate | latest-frame-wins, one slot, 15 fps cap | backpressure without queues |
| C4 | Fast basis | median count over the last 5 frames at ≥0.4 | absorbs threshold flicker |
| C5 | Snapshot | at mic-up; next frame; its own detection | "the frame the user saw"; boxes match the frozen image |
| C6 | Gemma image | PNG through dart:ui, ≤1024, un-mirrored, with a detector hint | no new dependency; the hint helps spatial answers |
| C7 | Detailed turns | stateless; `reset()` after each turn | no image or context build-up |
| C8 | GPU policy | pause while generating; freeze the view | §7 |
| C9 | Detector lifecycle | loaded at setup, optional, app-scoped | fail fast at setup |
| C10 | Fail fast | strict GPU; `DETECTOR_BACKEND=cpu` explicit and labelled | AGENTS.md rule 2 |

## 10. Open questions (each with a recommended answer)

1. **Snapshot at mic-up or at mic-down?** Recommended: mic-up. The user has finished aiming, and the snapshot goes
   with the transcript.
2. **Follow-up questions about the same frame?** Recommended: no for v1 (stateless). A "same frame" follow-up could
   re-send the frozen snapshot later.
3. **Is dropping Demo 1's history on a demo switch acceptable?** Recommended: yes. Replaying it would need the
   virtual lane, which is ruled out in §4.
4. **720p or 480p stream?** Recommended: 720p, falling back to 480p if the D3-5 copy time on the iPhone exceeds 3 ms.
5. **Fast negatives ("no dog")?** Recommended: hedged template answer. "Look closer" escalates to Gemma.

## 11. Risks

| Risk | Check | When |
|---|---|---|
| camera_desktop maturity (2.0.0 is a week old, single maintainer) | D3-2 run; the fixture path keeps development unblocked; pinned version | D3-2 |
| PNG not accepted by LiteRT-LM's image decoder | D3-4 golden; fallback is JPEG via `package:image` in an isolate | D3-4 |
| `reset()` cost per turn | `reset ms` in the overlay; if >150 ms, keep history and reset every N turns | D3-4 |
| CPU vision encoder makes iPhone TTFT >4 s | D3-5 timing; fallback is a 768 px snapshot | D3-5 |
| Router misses real Whisper phrasing | golden set built from real transcripts; default is detailed | D3-3 |
| Mirroring or rotation misalignment | manual left/right check; mirrored-source test | D3-2, D3-4 |
| Worker isolate + Metal/GL on phones | detector doc §10 checks | D3-5 |
| 720p main-isolate copy cost on a phone | `copy ms` in the overlay | D3-5 |
| Thermal fps decay | 10-minute soak | D3-5, Inc 8 |

## 12. Corrections to other docs

- `demo1-voice-chat.md`: §3.2/§3.3 `WatcherRepository` becomes `LiveDetectionRepository` (data) plus `CameraWatcher`
  (domain); §6 the detector is resident from setup; §2 macOS camera is now possible (development only); Inc 3
  `VoiceAssistant` takes `TurnResponderFactory<S>` and holds no Demo 1 types; Inc 7 `takePicture()` becomes
  `capture()` + `encodeForLlm()`.
- `setup-checklist.md`: the macOS camera note now points to camera_desktop. Its entitlements and usage strings are
  already in place.

## 13. Network camera (MJPEG over HTTP) — 2026-10-06

**Why:** a Raspberry Pi 5 or a Jetson running the Linux build with a screen often has no camera. An Android phone on
the same Wi-Fi running the free **IP Webcam** app serves `http://<phone-ip>:8080/video` as
`multipart/x-mixed-replace` MJPEG; Demo 3 uses that stream as its camera.

- **Choosing it:** Demo 3's settings (the tune icon; a labelled "Camera" button on Linux) offer "Device camera" /
  "Network camera (URL)", the URL prefilled `http://192.168.x.x:8080/video` (the `x` must be replaced; a missing
  `http://` is added). Saved in `TypedSettings` (`camera.source`, `camera.networkUrl`) and read at every start
  (`LiveCameraSettingsRepository.resolveSource`). When the device camera fails and the source is the user's to
  choose, the failure card offers the network camera — as the primary button on Linux. `FRAME_SOURCE=fixture`,
  `FRAME_SOURCE=network` + `NETWORK_CAMERA_URL=…`, and a source a test injects all win and lock the choice; the
  default `FRAME_SOURCE=camera` means "the user's choice".
- **Source:** `NetworkFrameSource` (`lib/data/services/frames/network_frame_source.dart`), next to the camera and fixture
  sources, behind the same `FrameSource` interface; `LiveDetectionRepository` is unchanged apart from the per-source
  stall timeout and the source-rate stats.
  - `MjpegParser` splits the stream incrementally: the boundary from `Content-Type` (leading dashes tolerated), parts
    by `Content-Length`, or without it by walking the JPEG segments from SOI to EOI (an EXIF thumbnail's EOI inside
    APP1 does not end the image); a garbage prefix is skipped; non-JPEG parts are counted and skipped.
  - **Latest frame wins:** one JPEG decodes at a time with the engine's codec (`decodeEncodedImage`, shared with the
    fixture source), off the UI thread, downscaled to 1280 on the long side; while it runs only the newest JPEG
    waits, older ones are dropped. Frames are RGBA (`rgba8888`), upright and unmirrored — the fixture's format — so
    the worker's gather and the question snapshot need nothing new, and detailed questions send network frames to
    Gemma like camera frames.
  - Reports the label `Network camera · 192.168.1.23:8080` (never the path or a password), the size, and the rate:
    the chip shows `… · 1280×720 · 30 fps · GPU fp32 full`, the overlay `det src … 1280×720 @ 29.7 fps`, and the log
    a `[NetworkCamera] … received=… decoded=… dropped=…` line every 5 s.
- **Fail fast, one action:** connection refused, no route (with the macOS/iOS Local Network hint), DNS failure, no
  HTTP answer within 5 s, an HTML page ("IP Webcam serves the stream at /video"), a single JPEG, HTTP 401 ("put the
  user and password in the URL" — `http://user:pass@host:port/video` is sent as Basic auth) and 404, no frame within
  5 s of connecting, no frame for 5 s while running (stalled), the server closing the stream, and 15 undecodable
  frames in a row are each one clear message with **Reconnect** (a new single-use source). There is no switch back
  to the device camera. The repository's 2 s source watchdog is replaced by a 7 s backstop for this source
  (`FrameSourceInfo.stallTimeout`), so the source's own 5 s message comes first. Error texts and logs use the
  exception's own message, never its URI (`HttpException.toString` appends it, password included).
- **Slow starts are reachable:** connecting can take up to ~10 s (connect, then the first frame). The live
  repository keeps the source that is still inside its `start`: the owner's stop (leaving Demo 3), `close` (quitting
  the app) and a take-over stop it at once instead of queuing behind it, and that start then ends as Stopped, not
  Failed.
- **Applies queue:** the sheet's Apply and "Run detector on CPU" run one at a time, in order; one that arrives while
  another runs waits, the newest pending choice wins field by field, and a start still connecting to the replaced
  choice is stopped so the new one runs next.
- **Tests:** `test/data/services/frames/mjpeg_parser_test.dart` (boundaries, split chunks, missing `Content-Length`,
  garbage prefix, ffmpeg style, oversize), `test/data/services/frames/network_frame_source_test.dart` (a local
  `HttpServer` serving MJPEG made from `test_assets/cats.jpg`: frames match the engine-decoded JPEG;
  latest-frame-wins; Basic auth; every error case),
  `test/data/repositories/live_camera_settings_repository_test.dart`,
  `test/ui/features/live_camera/view_models/live_camera_settings_test.dart` (VM wiring, the sheet, Linux's prominent
  offer, a second Apply while the first connects), `live_detection_repository_test.dart` (a slow start reached by
  stop, take-over and close). The settings persist in the app's shared preferences, which manual runs share: the
  integration tests that expect the device camera or the GPU call `resetDemo3Settings()`
  (`integration_test/support/demo3_settings.dart`) first.
- **Try it on a Mac:** `ffmpeg -re -loop 1 -i test_assets/cats.jpg -vf scale=1280:960 -r 30 -q:v 5 -f mpjpeg
  -listen 1 http://127.0.0.1:8090/video` (one client, then it exits), then choose `http://127.0.0.1:8090/video` in
  Demo 3's settings. ffmpeg's HTTP server sends `Content-Type: application/octet-stream`, not multipart: for that
  type the parser reads the boundary from the body's first line (`--ffmpeg`) and fails fast if there is none.
  `integration_test/network_camera_test.dart` runs Demo 3 against an in-test server (stall, loss, Reconnect) or,
  with `NETWORK_CAMERA_URL`, against ffmpeg. Measured on an M-series Mac (debug build): ffmpeg 1280×960 at 30 fps →
  29.8 fps received, 26–28 fps decoded (8.8 ms per frame, the rest dropped while busy), detector 14.2 fps, p50
  latency 15 ms; a detailed question sent frame #85 (1024×768 PNG) to Gemma, which described the two cats. A stall
  failed Demo 3 after 5.2 s; Reconnect took 0.7 s.
- **Unverified:** a real phone with IP Webcam over Wi-Fi (its boundary is `Ba4oTvQMY8ew04N8dcnM`-style, parts carry
  `Content-Length`), and the Linux boards (Pi 5, Jetson) — decode cost per frame and Wi-Fi jitter there. Every
  decoded frame pays an RGBA read-back and copy (3.7 MB at 1280×720) even when the gate drops it or the detector is
  paused for Gemma: measure UI-isolate time and GC on a Pi 5 (`--profile`, DevTools) before optimizing. Live detection
  is not paused when the app goes to the background (a network camera keeps streaming there). Plain `http://` to a
  LAN address: Flutter installs dart:io's connection hook, but iOS sets `may_insecurely_connect_to_all_domains` and
  no Android embedder passes `--disallow-insecure-connections`, so it is allowed (from the engine sources, not
  checked on a phone). iOS 14+ and macOS 15+ ask for Local Network access on the first LAN connection;
  `NSLocalNetworkUsageDescription` is in both Info.plists.

## 14. Detector backend at run time — 2026-10-06

**Why:** the backend was compile-time only (`DETECTOR_BACKEND`). On a Pi 5, VideoCore VII through Vulkan/WebGPU may
refuse YOLO26n or not take the whole graph, and Demo 3 had no way out.

- **Setting:** Demo 3's settings offer Detector: "GPU (default)" / "CPU (slower)", saved as `detector.backend`.
  `ModelRepository` reads it at every detector load (`detectorBackendChoice` → `LiveCameraSettingsRepository
  .readBackend`). `DETECTOR_BACKEND` (now empty by default) still wins when set, and Demo 3 shows the setting locked.
- **A strict GPU failure** is a `ModelFailed` that names its backend (`backend: 'gpu'`), unless the file itself is bad
  (missing, not the raw-head file, wrong I/O: no backend helps). The Demo 3 tile then stays open in amber ("The
  detector failed on the GPU: open Demo 3 to run it on the CPU · …"), and Demo 3 shows the reason with one explicit
  action, **Run detector on CPU** (a CPU failure offers the GPU back). Nothing switches by itself. A reload that ends
  unavailable or with a bad file shows its reason without an action.
- **Switching** (the action or the sheet): save the setting → stop the frame source (its frame in flight comes back)
  → `ModelRepository.reloadDetector()` (`DetectorService.load` replaces the worker) → start the source again. A
  failed reload does not restart: the failure card shows it. A source change and a backend change run one after the
  other, never at once (Applies queue, §13).
- **Labels:** the CPU is only ever a choice, so it reads `CPU (chosen)` everywhere: the overlay (`det CPU (chosen) ·
  …`), the setup row, the Demo 3 chip (amber), the home tile (`… on CPU (chosen)`) and the "This device" card (`CPU →
  CPU (chosen)`).
- **Tests:** `model_repository_test.dart` (setting persistence through a load, define precedence, GPU failure →
  CPU reload → GPU again, a missing file offers no backend), `home_view_model_test.dart`,
  `live_camera_settings_test.dart` (stop → reload → restart order, a failed reload, the lock, the overlay label).
- **Unverified:** a real Pi 5 / Jetson GPU failure and the CPU frame rate there.

## 15. Fast decode for the network camera — 2026-10-07

**Why:** measured on Linux (GCP T4 VM, Ubuntu 22.04, `network_camera_test` under `xvfb-run`, camera
`tool/linux/fake_ipwebcam.py` on the LAN at 15 fps 640×480): `first frame … decode=903.5ms`, `src_fps=2.3
det_fps=2.0`. The engine codec decodes through the IO thread and reads RGBA back from a GPU texture
(`toByteData(rawRgba)`): fine with a real GPU (4–9 ms on macOS), hopeless with software GL, and not to be trusted on a
Pi 5. On Pi and Jetson the network camera is the camera, so it must decode on the CPU.

- **TurboJPEG over FFI** (`lib/data/services/frames/turbojpeg.dart`): `tjInitDecompress`, `tjDecompressHeader3`,
  `tjDecompress2` to `TJPF_RGBA` (the layout the detector's gather and the question snapshot already read), the 2.x
  API that libjpeg-turbo 2.1 (Ubuntu 22.04, JetPack 6, Debian bookworm) and 3.x (Homebrew) both export. A *warning*
  is not an error, in the header read too (stray bytes before a marker, an unknown JFIF revision: the engine shows
  those frames, so must we); a fatal error is one undecodable frame (15 in a row fail the source, as before). A frame
  that would decode to more than 4096×4096 is refused. Buffers are reused frame after frame. A decoder whose worker
  died fails the source with "The JPEG decoder stopped (…)", not as the camera's fault.
- **Off the UI thread:** a long-lived worker isolate (`TurboJpegDecoder` in `jpeg_decoder.dart`) owns the
  `tjhandle`; JPEG bytes go in and RGBA comes back as `TransferableTypedData` (one copy out of the native buffer, none
  on arrival). Latest frame wins as before: one decode in flight, the newest JPEG waiting.
- **Scale at decode:** 1/2, 1/4 or 1/8 (libjpeg's DCT-domain scaling) only while the long side stays ≥ 960
  (`kNetworkDecodeMinSide`): 1920×1080 → 960×540, 640×480 and 1280×720 unscaled. The detector letterboxes to 640 and
  Gemma's image is at most 1024 on its long side, so the frame sent to Gemma keeps the detail it can use; no second
  full-size decode is needed.
- **Preview decoupled:** the detector gets the RGBA first; the preview `ui.Image` is made from the same pixels
  afterwards (an upload, latest wins), so a slow preview never holds up detection.
- **Lookup** (`turboJpegCandidates`): Linux — the bundle's `lib/libturbojpeg.so.0` (shipped from the build machine,
  linux-build §3.1), then the system's; macOS — Homebrew's `jpeg-turbo` (used by unsandboxed runs and the unit tests;
  the sandboxed app cannot read `/opt/homebrew` and uses the engine codec); Android and iOS — the engine codec (fast
  there with a real GPU; not measured on a phone).
- **No silent fallback:** on Linux without libturbojpeg the engine codec runs, the log says `SLOW JPEG decoder … Install
  libturbojpeg`, the source's label becomes "Network camera · host:port · slow JPEG decoder" (chip and overlay), and
  `run.sh` warns before start. Elsewhere the engine codec is the designed decoder and is logged as such.
- **Reported:** `FrameSourceInfo.decoder` (`TurboJPEG (worker isolate, scale to ≥960 px) <path>` or `engine codec`), the
  `NETCAM` first-frame line and the 5 s `[NetworkCamera] … decode_avg=… decoder=…` line; `network_camera_test` prints
  `decoder="…"` and requires `src_fps > 10`.
- **Measured (M-series Mac, unit tests, TurboJPEG 3.2 from Homebrew):** 1.3 ms per 640×480 frame (cats), 0.9 ms for a
  2000×1500 JPEG decoded at 1/2 (1000×750); pixels identical to the engine's decode (mean and max difference 0 — Skia
  decodes with libjpeg-turbo too). Through the source with a local server: 1.9 ms average.
- **Tests:** `test/data/services/frames/jpeg_decoder_test.dart` (the scale table, the lookup order, equality with the
  engine's decode, the 1/2 scale, errors, the worker decoder end to end, the lib-missing and wrong-library paths),
  `network_frame_source_test.dart` (the TurboJPEG source, the "slow JPEG decoder" label), `run_sh_test.dart`.
- **Unverified:** the Linux VMs (`src_fps > 10` under Xvfb with the bundle's or the system's libturbojpeg), a Pi 5 and
  a Jetson (decode ms there; the RGBA → preview upload under their GL), and whether a frame with EXIF orientation
  matters (TurboJPEG ignores EXIF; MJPEG cameras do not set it).

## 16. Hand-off

- **`flutter-coder`:** all Dart in D3-0 to D3-4.
- **`litert-expert`:** reviews the worker's RGBA gather, the 720p letterbox and the snapshot conversion; runs the D3-5
  benchmarks.
- **`flutter-gemma-expert`:** reviews `ConversationProfile`/`reset()`, PNG input and the generic `VoiceAssistant`
  before D3-3 and D3-4.
- **`android-architect`:** CameraX NV21 at 720p (D3-5).
- **`swift-architect`:** only if iOS camera or audio-session problems appear.
- **`flutter-reviewer`:** after every increment. Checks: no `openSession`; `FlutterEdgeAi.getActive*` only in the
  model services (demo1 §3.3); no `notifyListeners` per frame or per token; every source, subscription and isolate is
  closed; no silent CPU path.
