# Demo runbook

One Flutter app (`litert_hackathon`) with two on-device demos that share one chat model (Gemma 4 E2B, or any
`.litertlm` you choose), the speech models and the YOLO26n detector. Launch → **Preparing models** (setup) →
**On-device AI demos** (home) → a demo tile.

**Models (since 2026-10-07):** every model but the chat model is built into the app: Whisper base, moonshine-tiny,
Inflect-nano-v2, YOLO26n, and EmbeddingGemma with a prebuilt knowledge-base index. Nothing is downloaded. The chat
model is a `.litertlm` file on the device, chosen once in the **Chat model** card of the setup screen (Models), or
passed as the developer define `GEMMA_MODEL_PATH`. The way to put the file there differs per platform (sections
3–5). Design: [custom-chat-model.md](design/custom-chat-model.md).

Status as of 2026-10-07:
- Both demos have run on **macOS** (M4 Pro), through the integration tests. The macOS release self-test passes
  with the chat model from the models folder.
- Android: the release check (`integration_test/android_release_check_test.dart`) passed on Firebase Test Lab on
  a Galaxy S24 and a Galaxy S26 (Android 16), with the chat model pushed into the models folder. No physical
  Android phone has run it yet.
- iPhone: not run yet (iOS signing is blocked).

See [Known limitations](#9-known-limitations).

Scripts: `tool/run_macos.sh`, `tool/provision_ios.sh`, `tool/provision_android.sh` (each takes `--help`). They
predate the built-in models: they still pass or copy the detector and the embedder too, which is harmless (a
define wins over the built-in copy) but no longer needed. Use `fvm flutter` everywhere; the SDK is pinned in
`.fvmrc`.

## 1. What each demo shows

**Demo 1: Voice chat** (tile "Voice chat")
- Push-to-talk voice in. Whisper base transcribes on the CPU, Gemma 4 E2B answers on the GPU, and the reply streams
  as text. Inflect-nano-v2 starts speaking after the first finished sentence.
- Images: from the gallery on every platform, and from the camera on iPhone and Android.
- Knowledge base: 16 LiteRT / flutter_gemma documents, embedded with EmbeddingGemma-300M into sqlite-vec. The app
  ships the index (installed in about 0.1 s on first launch); it re-indexes on the device only when the documents,
  the chunker or the embedder change. Answers come with citation chips (`[n] doc › section`).
- Skills loaded from Markdown: the current time, and device and accelerator info. The plainest requests ("what
  time is it", "which accelerator is running?") run their intent directly, without a model round, so they always
  happen; the steps panel shows `runIntent(…)` as usual. `device_info` speaks the hardware report as is — the chip
  (on Android the SoC by name), memory and GPU, then where each loaded model runs, the chat model first, and how
  that is known. Measured on an M4 Pro: "This Mac has an Apple M4 Pro with twenty-four gigabytes of memory
  and an Apple M4 Pro GPU (Metal). Gemma 4 E2B and the detector run on the GPU (confirmed); speech recognition and
  speech synthesis on the CPU (requested); the embedder on the CPU (confirmed)." A new `SKILL.md` works after
  **Skills → Reload**, without a rebuild; a runtime skill that spells out one call (`kid-clock`, below) runs even
  when the model names the skill instead of its intent. (The camera watcher and timers were removed on 2026-10-06.)
- Barge-in: pressing the mic while the assistant speaks silences it within about 150 ms.

**Demo 3: Live camera** (tile "Live camera")
- Live boxes from YOLO26n on the GPU, at up to 15 fps.
- Push-to-talk questions, transcribed by moonshine-tiny (about 65 ms; 5 s window).
- **Fast path:** count, presence and inventory questions are answered from the detection list, with no LLM. The
  chip reads "… — detector, no LLM", and the spoken answer starts within 1 s of release on macOS.
- **Detailed path:** any other question. The view freezes on the frame ("Answering about this frame · tap for live"),
  the detector pauses ("Detector paused (Gemma 4 E2B)": the chat model's name), and that frame goes to Gemma 4 E2B.

Diagnostics: the toggle in the app bar ("Show diagnostics") shows the model, backend, load time, TTFT, tok/s,
context use, detector fps, route and latencies. Keep it visible: it shows the audience that everything runs on
the GPU and on the device.

## 2. Two-minute scripts

### Demo 1

Prep: start a new conversation (**New conversation** in the app bar), and have the kid-clock skill file ready
(below).

| Time | Say / click | Audience sees |
|---|---|---|
| 0:00 | Home → **Voice chat**. Turn on diagnostics. | The overlay shows Gemma 4 E2B on GPU, Whisper / Inflect / EmbeddingGemma on CPU, and the knowledge base ready |
| 0:10 | Hold the mic: *"What does the E in Gemma 4 E2B stand for?"* Release. | The transcript, then the streamed reply; speech starts at the first sentence; citation chips from `gemma-4-e2b.md` |
| 0:35 | Gallery button (on a phone: camera button) → a photo. Hold: *"What's in this picture?"* Then *"How many are there?"* | A thumbnail in the bubble and a spoken description. The overlay shows `img sent`, then `in context (not re-sent)` |
| 0:55 | While it is speaking, press the mic: *"Stop. Describe it in one sentence."* | Playback cuts at once. If Gemma was still generating, the next turn re-sends the image (overlay: `img resent (lost: stop)`) |
| 1:10 | *"Roughly how late is it right now?"* | Steps `loadSkill(current-time)` → `runIntent(current_time)`, then the time from the app's clock |
| 1:25 | *"Which accelerator are you running on?"* | `device_info`, run directly and spoken as is: the chip and GPU, then Gemma and the detector on the GPU (confirmed), speech on the CPU (requested), the embedder on the CPU (confirmed) |
| 1:40 | Run the kid-clock copy command (below). **Skills** (puzzle icon) → **Reload**. *"Tell my kid what time it is."* | The sheet lists `kid-clock`, and the chat says it started over. `loadSkill(kid-clock)` → `runIntent(current_time)`, then the time said for a five-year-old ("It is six thirty, just a little bit before dinner time!"). No rebuild |

Fallback questions for the knowledge base (golden set, `test_assets/kb_golden.json`):
- *"What is the input size of the YOLO 26 nano detector?"* (640)
- *"How many dimensions does EmbeddingGemma produce?"*
- *"Which entitlements does an iPhone app need to load a big model?"*

Off-topic questions such as *"How long should I boil an egg?"* get no chips: the overlay shows `RAG … below gate`.

Kid-clock skill. Create it once on the laptop:

```bash
mkdir -p /tmp/kid-clock && cat > /tmp/kid-clock/SKILL.md <<'EOF'
---
name: kid-clock
description: Tell the time the way you would to a small child, when the user asks you to tell their kid or a child what time it is.
---
# Kid clock

## Instructions
Call the `run_intent` tool with intent `current_time` and parameters {}.
Then say the time in one short sentence a five-year-old understands, for example "It is quarter past six in the evening."
EOF
```

Then copy it into the app's skills folder:

| Platform | Command |
|---|---|
| macOS | `mkdir -p ~/Library/Containers/dev.fluttergemma.litertHackathon/Data/Documents/skills/kid-clock && cp /tmp/kid-clock/SKILL.md "$_"` |
| iPhone | `xcrun devicectl device copy to --device <device> --domain-type appDataContainer --domain-identifier dev.fluttergemma.litertHackathon --source /tmp/kid-clock/SKILL.md --destination Documents/skills/kid-clock/SKILL.md` |
| Android | `adb push /tmp/kid-clock /sdcard/Android/data/dev.fluttergemma.litert_hackathon/files/skills/` |

To reset after the demo, delete `skills/kid-clock` the same way and Reload.

### Demo 3

Props: a table with COCO objects (cup, bottle, cell phone, laptop, book, scissors, remote, fruit), a person in
frame, and a sign with large text. `test_assets/gate42.png` can be printed or shown on a second screen.

| Time | Say / click | Audience sees |
|---|---|---|
| 0:00 | Home → **Live camera**. Turn on diagnostics. Pan over the table. | Boxes and labels follow the objects; the overlay shows `det GPU fp32 full · 15.0 fps · p50 pre/run/post …` |
| 0:15 | Hold: *"What do you see?"* | Under 1 s: "I see a person, a cup and …". Chip: `… — detector, no LLM` |
| 0:30 | *"How many cups are there?"*, then *"Is there a dog?"* | "I count two cups." / "I don't see a dog right now." Both instant, both without the LLM |
| 0:50 | Hold up the sign: *"What does the sign say?"* | The view freezes ("Answering about this frame"), the detector pauses, Gemma reads the sign aloud |
| 1:15 | Tap to go live. *"Describe the scene."*, then *"What is to the left of the laptop?"* | Frozen frame, then a spoken description; spatial judgments come from Gemma |
| 1:40 | *"Describe everything in detail."* Press the mic mid-answer: *"How many people are there?"* | Barge-in: silence and back to the live view at once, then a fast answer |
| 1:55 | Point at the overlay | `camq fast/count · rule count` vs `camq detailed · rule detail:say`, `llm turns`, frame PNG size and TTFT |

Fast vs detailed (`lib/domain/use_cases/question_router.dart`):

| Fast (no LLM, from the detections) | Detailed (frame → Gemma) |
|---|---|
| "What do you see?", "What can you see?", "What's in front of me?", "What objects …" | Any detail cue: describe, read, say, text, sign, label, color, wearing, doing, where, left/right, behind, next to, on top, under, between, closest, what kind/type, brand, breed, why, explain, who, "what is this/that" |
| "How many *people / cups / bottles* …" (a COCO noun) | A noun outside COCO: "How many pens?" |
| "Is there a *cup*?", "Are there any *chairs*?", "Do you / can you see a *phone*?" | Any qualifier or prefix: "Is there a cup **on the table**?", "**Besides the cat**, …" |

moonshine's known misses are corrected before routing, only towards objects the detector knows: "cop" → cup,
"cultures" → couches, "dobs" → dogs; the caption then reads "Is there a cup? (heard 'cop')".

Keep questions under 5 s (moonshine's window). Detection counts use score ≥ 0.4, as a median over the last 5 frames.

## 3. Run on macOS

```bash
tool/run_macos.sh                 # debug, live camera
tool/run_macos.sh --profile       # AOT speed: use for the demo and for timings
tool/run_macos.sh --fixture ~/Work/models/yolo26n/test_images/coco30   # Demo 3 on stills
```

- The script checks every model file and lists all problems at once, then runs `fvm flutter run -d macos` with
  `GEMMA_MODEL_PATH`, `DETECTOR_MODEL_PATH` and `EMBEDDING_MODEL_DIR` (defaults under `~/Work`, overridable through
  environment variables of the same names; set one to an empty value to leave it out). It no longer passes
  `.env`: no model needs a token.
- `GEMMA_MODEL_PATH` is used only while no chat model is chosen on the Models screen; a chosen file wins. Without
  the define, copy the `.litertlm` into `~/Library/Containers/dev.fluttergemma.litertHackathon/Data/Documents/models/`
  (the card's **Copy the folder path**) and tap it in the **Chat model** card. An app upgraded from a build that
  downloaded Gemma 4 E2B uses that download in place, with a one-time note.
- `DETECTOR_BACKEND` and `VOICE_GATE_DBFS` are passed through from the environment. Everything after `--` goes to
  `flutter run`.
- Sandbox: debug and profile builds may read `~/Work/` only (`DebugProfile.entitlements`).
- `--release` builds lack that read exception, so the script first clones the models into
  `~/Library/Containers/dev.fluttergemma.litertHackathon/Data/Documents/models/` and passes documents-relative
  paths. The clone uses APFS clonefile: it is instant and takes no extra space. Run once without `--release`
  first, so that the container exists.
- `--fixture <dir|image>` sets `FRAME_SOURCE=fixture` and `FIXTURE_DIR`. The fixture plays as a slideshow at
  15 fps with 3 s per image. `test_assets/gate42.png` works as a single-image fixture for the sign question.

First launch:
- Nothing is downloaded: the speech models, the detector and the embedder are read in place from the app bundle.
- Installs the prebuilt knowledge-base index (about 0.1 s; indexing on the device would take about 50 s).
- Gemma's first GPU load takes about 14 s (it builds the GPU program cache); later loads take seconds.

Permissions are asked when a demo opens, not on first use: Demo 1 asks for the microphone (the camera only when you
take a photo, through the system picker); Demo 3 asks for the microphone after its camera has started. A denial shows a lasting bar (Demo 1) or line (Demo 3) with the settings path and Retry.

Camera and microphone permissions on macOS:
- When the app is launched from a terminal, macOS attributes camera and microphone access to **the terminal app**.
  Without that permission the app gets black frames or digital silence instead of an error.
- Grant Terminal, iTerm or VS Code access under System Settings › Privacy & Security › Camera and › Microphone.
- Alternatively, launch the built app directly, so the prompt names the app itself:
  `open build/macos/Build/Products/Profile/litert_hackathon.app`. The dart-defines from the last build are
  compiled in.

## 4. Run on iPhone

Prerequisites:
- iOS 26 or later (see the limitations).
- Developer Mode on.
- An Apple ID in Xcode › Settings › Accounts. The project uses team `6ZHF6A3G28`. The first signed build registers
  the Increased Memory Limit and Extended Virtual Addressing capabilities. Check them with
  `codesign -d --entitlements - build/ios/iphoneos/Runner.app`.

The chat model, without any define (the way testers do it):

```bash
xcrun devicectl list devices                     # device name, e.g. sashamobile
D=sashamobile
fvm flutter run -d "$D" --release                # 1. install once; setup says "No chat model yet"
xcrun devicectl device copy to --device "$D" --domain-type appDataContainer \
  --domain-identifier dev.fluttergemma.litertHackathon \
  --source ~/Work/gemma-4-E2B-it.litertlm \
  --destination Documents/models/gemma-4-E2B-it.litertlm   # 2. 2.5 GB, minutes; or use the Files app
#                                                  3. Chat model card: Rescan, tap the file, Use this model
```

Or with the developer define, as before (the script also copies the detector and the embedder, no longer needed):

```bash
DEFS=(--dart-define=GEMMA_MODEL_PATH=gemma-4-E2B-it.litertlm)  # an array: works in zsh and bash
fvm flutter run -d "$D" --release "${DEFS[@]}"   # 1. install once; setup fails with "Model file not found"
tool/provision_ios.sh "$D"                       # 2. copy the models into Documents/ (2.5 GB, minutes)
#                                                  3. tap Retry on the setup screen, or run step 1 again
```

- `provision_ios.sh` refuses to run until the app is installed (no container yet).
- It copies the files with `xcrun devicectl device copy to --domain-type appDataContainer --domain-identifier
  dev.fluttergemma.litertHackathon`, reads back every file's size, and prints the defines it expects.
- Use the device name or the UDID from `fvm flutter devices`. devicectl's "Identifier" column is not a flutter
  device id.
- Use `--release` for the demo (`--profile` for measurements). Paths are relative to the app's Documents.
- The phone needs about 8 GB free: the model plus LiteRT-LM's GPU caches, which are written next to it on first load.

## 5. Run on Android

Requirements: arm64, Android 11 (API 30) or later, 8–12 GB RAM recommended.

The chat model, without any define (the way testers do it; details in [android-install.md](android-install.md)):

```bash
adb devices
S=<serial>
fvm flutter run -d "$S" --release                # 1. install and launch once: the app creates its models folder
adb -s "$S" push ~/Work/gemma-4-E2B-it.litertlm \
  /sdcard/Android/data/dev.fluttergemma.litert_hackathon/files/models/   # 2.
#                                                  3. Chat model card: Rescan, tap the file, Use this model
```

- Push only after the first launch. A folder or file pushed before the app created its folder belongs to the shell,
  and the app reports "… cannot be read (Permission denied)" with this advice.
- The second models folder, `/data/local/tmp/litert-models/` (`adb shell mkdir -p` it first), has no such
  ordering problem and survives an uninstall. Uninstalling the app deletes everything under `/sdcard/Android/data/…`.
- The first launch extracts the built-in models from the APK once and verifies them (no network). Later launches
  skip the copy.

Or with the developer define, as before:

```bash
P=/sdcard/Android/data/dev.fluttergemma.litert_hackathon/files
DEFS=(--dart-define=GEMMA_MODEL_PATH=$P/gemma-4-E2B-it.litertlm)
fvm flutter run -d "$S" --release "${DEFS[@]}"   # 1. install once (and launch); setup fails until 2
tool/provision_android.sh "$S"                   # 2. adb push --sync, then a size check
#                                                  3. tap Retry
```

- Android takes **absolute** paths: adb cannot write the documents directory (`app_flutter/`).
- Never run `flutter test` while `flutter build apk --release` is running (setup-checklist.md).

## 6. dart-defines

All of them are compiled into the binary (`lib/config/env.dart`). Rebuild after changing any of them.

| Define | Default | Meaning |
|---|---|---|
| `GEMMA_MODEL_PATH` | empty: the chat model chosen on the Models screen ("No chat model yet" until one is) | A local `.litertlm`, loaded with Gemma 4 E2B's settings while no chat model is chosen; a chosen file wins. Absolute, or relative to the app's documents directory |
| `DETECTOR_MODEL_PATH` | empty: the detector built into the app | `yolo26n_fp16_rawhead.tflite`, size-checked at 10,361,332 B. Absolute or documents-relative |
| `DETECTOR_BACKEND` | empty: Demo 3's Detector setting (GPU unless the user chose CPU) | `gpu` or `cpu`; set, it wins over the setting (shown locked). The CPU is a choice, shown amber as "CPU (chosen)". It is never a fallback |
| `EMBEDDING_MODEL_DIR` | empty: the EmbeddingGemma built into the app | A directory holding `embeddinggemma-300M_seq512_mixed-precision.tflite` and `sentencepiece.model`. Absolute or documents-relative |
| `FRAME_SOURCE` | `camera` | `camera` (the user's choice in Demo 3's settings: device camera or network camera), `fixture`, or `network` (with `NETWORK_CAMERA_URL`) |
| `NETWORK_CAMERA_URL` | empty; required with `network` | An MJPEG stream, e.g. `http://192.168.1.23:8080/video` (IP Webcam on a phone) |
| `FIXTURE_DIR` | empty; required with `fixture` | A directory of images, or a single image (jpg/png/webp/bmp). Absolute path only: it is **not** documents-relative. At most 64 images |
| `GEMMA_ACTIVATION` | empty: the engine's own choice (float16 on the GPU) | Measurement knob: `fp16` or `fp32` activations for Gemma. float32 fixes digits the GPU copies wrongly from long prompts, at more GPU memory; changing it rebuilds the GPU program cache once. Any other value fails startup |
| `VOICE_GATE_DBFS` | `-45` | The silence gate in dBFS, in the range [-96, 0). A bad value fails startup. Raise it (e.g. `-40`) in a loud venue |

Used only by tests and tools:
- `GEMMA_BACKEND`: `model_smoke_test`.
- `ROUTER_AUDIO_DIR`: `camera_assistant_test`, `tool/stt_compare_bench.dart`.
- `STT`: `tool/speech_bench.dart`.
- `LONG_CLIP`: `tool/stt_compare_bench.dart`.

## 7. Pre-event checklist

- [ ] **Fetch the built-in models** at home: `tool/fetch_models.sh` (about 420 MB from Hugging Face, `HF_TOKEN` for
  EmbeddingGemma; the models are not in git). `tool/fetch_models.sh --check` verifies them offline.
- [ ] **Pre-build every platform** at home. The first build downloads native prebuilts from GitHub, and venue
  Wi-Fi is unreliable. Run `fvm flutter build macos --profile`, `fvm flutter build ios --release` (signed), and
  `fvm flutter build apk --release`. Sizes on 2026-10-02, before speech was built in (unsigned iOS):
  `apk --release` 157.7 MB (arm64-v8a only), `ios --release --no-codesign` Runner.app 81.8 MB, `macos --release`
  157.5 MB, all green.
- [ ] Free disk space on the Mac, for builds and GPU caches.
- [ ] **Put the chat model on each demo device and choose it** (sections 3–5).
- [ ] **Launch once** on each device: Android extracts the built-in models, the prebuilt knowledge-base index is
  installed, and the first GPU load builds the GPU caches. No network is needed.
- [ ] Open both demos once, so both recognizers have been switched in.
- [ ] **Offline facts** (2026-10-07; not yet tested in airplane mode):
  - The app downloads nothing: every model but the chat model is in the app, and the chat model is a file on the
    device. The knowledge base, its index and the skills are local; native libraries are fetched at build time.
  - After a reinstall Android extracts the built-in models again, without the network. An uninstall deletes a
    chat model pushed under `/sdcard/Android/data/…`; one in `/data/local/tmp/litert-models/` stays.
  - Still, at the venue: no reinstall, no `flutter clean`, no `pub upgrade` (keep `pubspec.lock`).
  - iPhone gallery: use photos stored on the device; an iCloud "optimized" original needs the network.
- [ ] **Airplane-mode test:**
  - Wi-Fi off / airplane mode on.
  - Kill the app and relaunch it.
  - Setup must finish.
  - Run both 2-minute scripts end to end.
- [ ] **App Nap** (macOS dev runs): `defaults write dev.fluttergemma.litertHackathon NSAppSleepDisabled -bool YES`.
  Without it, an unfocused app slows down about 10×. `run_macos.sh` reminds you when it is off.
- [ ] **Camera and microphone permissions:**
  - macOS: System Settings › Privacy & Security › Camera / Microphone, for the terminal you launch from, or for
    `litert_hackathon`.
  - iPhone: Settings › Privacy & Security › Camera / Microphone.
  - Android: App info › Permissions.
- [ ] **iPhone runs iOS 26 or later.** On older versions the app dies in dyld before `main` (flutter_inappwebview_ios).
- [ ] **iOS signing:** an Apple ID in Xcode, a signed build, and the entitlements checked with `codesign`.
- [ ] Props for Demo 3 and the kid-clock `SKILL.md` ready. Delete `skills/kid-clock` from earlier rehearsals.
- [ ] Mac on power, phones charged. Run a 10-minute rehearsal on each device (thermals).

## 8. Troubleshooting

| You see | Cause | Fix |
|---|---|---|
| Setup: "Gemma requested gpu but the engine loaded on cpu. CPU fallback is disabled…" | No usable GPU: the iOS simulator is CPU-only, or GPU init failed | Use a real device. Close memory-heavy apps and Retry |
| Setup: "No chat model yet" | Nothing chosen, and built without `GEMMA_MODEL_PATH` | Put a `.litertlm` into a models folder (sections 3–5), Rescan, tap it, **Use this model** |
| Chat model card: "… cannot be read (Permission denied). A folder or file pushed before the app created this folder belongs to the shell…" | Android: the file was pushed before the app's first launch | Launch the app first, then push again; or push to `/data/local/tmp/litert-models/` |
| Chat model card: "… is not there any more (moved, renamed or deleted?)" / "… changed since it was chosen" | The chosen file was moved, deleted or replaced | Copy it back, or tap it (or another file) again |
| Chat model card: "Using the Gemma 4 E2B you downloaded earlier, where it is…" | An upgrade from a build that downloaded Gemma | Nothing to do: it is the chosen chat model now |
| Chat model card: "Gemma 4 E2B is no longer downloaded by the app: choose a .litertlm…" | An upgrade from a build that had chosen Gemma, without a verified download | Choose a `.litertlm` as above |
| Setup: "Model file not found or not readable: … (check GEMMA_MODEL_PATH and the sandbox read exception)" | The define points at a missing file, or a macOS release build reads `~/Work` | Run the provision script, then Retry; or rebuild without the define and choose the file on the Models screen. On macOS use `run_macos.sh`, which checks paths and stages files for `--release` |
| Setup row: a built-in model shows an error with Retry | A built-in file could not be found, extracted or verified (an incomplete build, or a full disk on Android) | Free some space and Retry; otherwise reinstall a complete build |
| Demo 3 tile: "The detector failed: open Demo 3 to run it on the CPU · GPU rejected YOLO26n: …" | The GPU delegate refused the model (e.g. a Pi 5) | First check the file: "Not the YOLO26n raw-head file" means the wrong file, e.g. Arm's original (that keeps the tile disabled). If the file is right, open Demo 3 and press "Run detector on CPU" (amber "CPU (chosen)", about 23 ms per frame on an M-series Mac); the choice is saved. `DETECTOR_BACKEND=cpu` does the same at build time |
| Demo 3: "Nothing answers at 192.168.…:8080 (connection refused)" / "… is unreachable from this device" | IP Webcam not started, wrong address, another Wi-Fi, or (macOS/iOS) Local Network access denied | Start the server in IP Webcam, check the address it shows, same Wi-Fi; allow Local Network for the app; press Reconnect |
| Demo 3: "… serves a web page (text/html) …, not an MJPEG stream" | The URL is IP Webcam's start page | Add `/video` to the URL in Demo 3's settings |
| Demo 3: "… stopped sending frames (none for 5.0 s)" | The phone slept, IP Webcam stopped, or Wi-Fi dropped | Wake the phone (IP Webcam can keep the screen on), press Reconnect |
| Demo 3 chip: "Camera delivers black frames — lens covered, or camera access attributed to the terminal…" | A covered lens, or on macOS no camera permission for the launching terminal (frames arrive zeroed) | Uncover the lens, or grant Camera to the terminal and relaunch, or `open` the built `.app`. Use `--fixture` as a fallback |
| Demo 3: "The camera stopped delivering frames (none for …)", or a spoken "The camera isn't running." | The camera was unplugged or taken by another app (camera_desktop drops its errors) | Quit Zoom, FaceTime or Photo Booth, then Retry |
| "Microphone access is off for this app — … › Microphone" | Permission denied, or macOS handing a blocked app silent buffers | Grant the microphone (on macOS, to the terminal when launched from one) and relaunch |
| Chat chip or home tile: "Knowledge base unavailable: The built-in EmbeddingGemma: … is not in this app bundle", or "EmbeddingGemma files not found…" | An incomplete build (or a wrong `EMBEDDING_MODEL_DIR`) | Run `tool/fetch_models.sh --check` (the files under `assets/models/` are not in git; `tool/fetch_models.sh` fetches them), then rebuild. Chat keeps working without the knowledge base |
| Home tile: "knowledge base indexing N% (prebuilt index not used)" | The shipped index does not match this build (the overlay says why) | Wait (about 50 s on macOS, minutes on phones); rebuild the index with `tool/build_kb_index.sh` before the event |
| "Didn't catch that — hold the mic button while you speak." | The press lasted under 300 ms | Hold for the whole question |
| "Didn't catch that — it was too quiet." | Below the gate (`-45` dBFS, and 10 dB over the noise floor) | Speak closer. With a quiet mic, rebuild with `VOICE_GATE_DBFS=-50` |
| "Didn't catch that — no words were recognized." | Empty transcript | Repeat; in Demo 3 keep it under 5 s |
| "The conversation got too long for the model, so it started over; earlier turns are forgotten." | The 8192-token budget: about 270 per image, 650–950 per knowledge-base turn | Expected after several image or KB turns. Tap New conversation before the demo, and re-attach the image |
| "The last skill call did not finish, so the conversation started over…" | A skill call interrupted by a stop or barge-in (upstream U-A3) | Ask again |
| "Skills reloaded: N skills…. The conversation started over." | Reload rebuilds the chat with the new skills | Expected |
| Skills sheet lists a file with an error | A malformed `SKILL.md` (front matter missing), or over 600 tokens | Fix the file and Reload |
| Skills sheet lists `timer` or `camera-watch` with "Unknown intent" | A copy you edited under an earlier build (unedited copies are removed on upgrade) | Delete that folder from `skills/` and Reload |
| Demo 1 bar: "Microphone access is off for this app — … Voice input is off; typing still works." | Microphone permission denied when the demo opened | Grant it (macOS: to the terminal when launched from one), then Retry on the bar |
| A Whisper answer takes about 2 s even for short questions | Whisper base always encodes a 30 s window | Expected (Demo 1). Demo 3 uses moonshine |
| iPhone: the app closes at launch ("Library not loaded: /usr/lib/swift/libswiftWebKit.dylib") | iOS older than 26 | Use an iOS 26 device |
| `provision_ios.sh`: "… is not installed" | No app container yet | Run `fvm flutter run -d <device> --release …` once |

## 9. Known limitations

Sources: [upstream-issues.md](upstream-issues.md), [setup-checklist.md](setup-checklist.md).

**Not verified yet**
- No iPhone run so far: iOS signing has no Apple ID, and the app is not installed on the paired iPhone 17 Pro.
- Android only on Firebase Test Lab (Galaxy S24 and S26, the release check); no physical Android phone yet, so no
  live camera or microphone on Android.
- Unchecked on real devices: two LiteRT copies sharing the GPU, Demo 3's phone camera path (D3-5), the iOS
  entitlements in a signed build, and Finder/Files access to Documents.

**Missing features**
- English only: Inflect speaks English, and Whisper is pinned to `en`.
- Push-to-talk only: no VAD, no full duplex.
- The Demo 1 history is dropped on a demo switch. Demo 3 questions are stateless.

**Platform constraints**
- iOS floor is 26, whatever the deployment target says: `flutter_inappwebview_ios`, via `flutter_gemma_agent`,
  strong-links `libswiftWebKit`.
- `UIFileSharingEnabled` exposes all of Documents in Files and Finder, models included. It is kept for the skill-drop
  demo. Don't delete files there.
- The STT and TTS backends are only "requested": no API reports them (U1).
- STT runs on the CPU, because GPU STT fails or produces garbage (U7).
- macOS has no Metal top-k sampler: tokens are sampled on the CPU (still about 66 tok/s on E2B).
- macOS: camera_desktop never reports camera loss; the app's 2 s watchdog does. Taking a photo from the chat works
  only on iPhone and Android (gallery only on macOS).

**Runtime behavior**
- Gemma sometimes calls a tool for a plain question (about 1 in 6 first turns at temperature 0.6, measured), which
  adds 0.3–1 s before the answer; the answer itself stays right. Photo questions carry a direct-answer hint and
  did not (0 of 6). Live skill questions skip the knowledge base.
- The GPU is required for Gemma and, by default, for the detector. There are no silent fallbacks.
- The detector pauses while Gemma generates. In Demo 3 the view stays frozen during that time.
- `interrupt()` can drain for up to about 10 s in the worst case (U4). Playback still stops within about 150 ms,
  but the next turn may wait.
- Image JSON encoding runs on the main isolate: 6–13 ms per image turn on an M4 Pro, more on phones.
- The context is 8192 tokens. The app's budget guard resets the chat, with a notice, before LiteRT-LM overflows.

**Licence and delivery**
- YOLO26n is AGPL-3.0. The derived raw-head file stays AGPL, so ship `tool/prune_yolo26n_head.py` with any
  published build.
- The detector is built into the app; its AGPL notice is in the app's licence list (Home › More › Licences).
