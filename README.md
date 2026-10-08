# litert_hackathon

One Flutter app (Android, Linux x64/arm64, macOS, iOS) with two on-device AI demos. Everything runs on the device: a
chat LLM through LiteRT-LM (Gemma 4 E2B on the GPU or CPU, or a Qualcomm NPU build of it), speech in and out, a local
knowledge base, and a LiteRT object detector. Once the chat model is on the device it needs no network.

- **Voice chat (Demo 1).** Push-to-talk voice in (Whisper base), streamed answers from the chat model, spoken from the
  first finished sentence (Inflect-nano-v2). Attach a photo and ask about it. Questions about LiteRT and
  flutter_gemma are answered from a built-in knowledge base (EmbeddingGemma-300M + sqlite-vec) with citation chips.
  Skills come from Markdown files and can be added without a rebuild: the current time and device and accelerator
  info (the chip, the GPU and where each model really runs).
- **Live camera (Demo 3).** Live boxes from YOLO26n on the GPU. Ask by voice (moonshine tiny): simple questions
  ("how many cups?") are answered from the detections without the LLM, detailed ones send the current frame to Gemma.

Built on [`flutter_edge_ai`](https://pub.dev/packages/flutter_edge_ai) and its LiteRT-LM, speech, embeddings, RAG and
agent packages, plus [`flutter_litert`](https://pub.dev/packages/flutter_litert) for the detector.

The chat model is not built in: the app loads the `.litertlm` you choose (from its models folder, a path, an import,
or a download link), for example the ungated
[`litert-community/gemma-4-E2B-it-litert-lm`](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm)
(`gemma-4-E2B-it.litertlm` for the GPU or CPU, or a Qualcomm NPU build such as `gemma-4-E2B-it_qualcomm_sm8750.litertlm`
for its chip). Its settings start from the file's header.

## Install guides

Build the app from source ([below](#building-from-source)); the chat model comes from
[litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) (no login
needed), or use your own `.litertlm`.

| Device | Build | Guide |
|---|---|---|
| Android phone (Android 11+, 64-bit, 8 GB RAM recommended) | `litert_hackathon-v0.1.2-arm64.apk` | [docs/android-install.md](docs/android-install.md) |
| Arduino VENTUNO Q (Qualcomm QCS8275) | `litert_hackathon-v0.1.2-linux-arm64.tar.gz` | [docs/ventuno-q.md](docs/ventuno-q.md) |
| Raspberry Pi 5 (8/16 GB) | `litert_hackathon-v0.1.2-linux-arm64.tar.gz` | [docs/raspberry-pi.md](docs/raspberry-pi.md) |
| NVIDIA Jetson Orin (JetPack 6) | `litert_hackathon-v0.1.2-linux-arm64.tar.gz` | [docs/jetson.md](docs/jetson.md) |
| Linux PC (x64, Ubuntu 22.04+, Vulkan GPU) | `litert_hackathon-v0.1.2-linux-x64.tar.gz` | [docs/testers.md](docs/testers.md) |

One arm64 package serves all three boards; only the backend differs (GPU through Vulkan or the CPU; the Qualcomm NPU
on Android today, on Linux in progress). Every guide ends with `./run.sh --selftest` (or the in-app self-test), whose
report says where each model really ran.

## Building from source

The models built into the app are not in git: YOLO26n, EmbeddingGemma-300M, Whisper base, moonshine-tiny and
Inflect-nano-v2, about 420 MB. Fetch them once per checkout, before any `flutter build`, `run` or `test`:

```bash
tool/flutter_litert/vendor.sh   # flutter_litert + our patch into third_party/ (gitignored)
tool/fetch_models.sh            # the built-in models into assets/models/, each one verified
fvm flutter pub get
fvm flutter build macos         # or apk, ios, linux
```

- **What it fetches.** [`tool/models.lock`](tool/models.lock) pins every file: the Hugging Face repo, a commit, the
  path, the size and the SHA-256. The script resumes an interrupted download and skips files it has already verified.
  `tool/fetch_models.sh --check` verifies without the network. `tool/run_macos.sh`, the Firebase Test Lab scripts and
  `tool/linux/package.sh` refuse to start without verified models. A plain `flutter build` or `flutter test` fails with
  "No file or variants found for asset: assets/models/…".
- **Hugging Face token.** EmbeddingGemma (`litert-community/embeddinggemma-300m`) is gated. Accept the Gemma terms on
  [its page](https://huggingface.co/litert-community/embeddinggemma-300m), create a read token, and put it in `.env`
  (gitignored) as `HF_TOKEN=hf_…`, or export `HF_TOKEN`. Only this download uses it; it is not passed to the build.
- **YOLO26n is derived, not downloaded.** The script fetches Arm's `yolo26n_conv2d_f16_weights.tflite` and runs
  `tool/prune_yolo26n_head.py` in a Python venv under `build/` with the pinned `ai-edge-litert`. That needs python3
  3.10–3.14 with venv; the wheels cover macOS arm64 and Linux x86_64/aarch64. The output must match the lock byte for
  byte.
- **Licences** of the fetched files are in [assets/models/NOTICE.md](assets/models/NOTICE.md). EmbeddingGemma is under
  the Gemma Terms of Use. YOLO26n and the derived file are AGPL-3.0, so ship `tool/prune_yolo26n_head.py` with any
  published build. Whisper base and Inflect-nano-v2 are Apache-2.0. moonshine-tiny and Matcha's G2P files are MIT.

## Run it

Requirements: Flutter 3.47.3 through [fvm](https://fvm.app) (pinned in `.fvmrc`), Xcode 26 for Apple platforms, the
built-in models ([Building from source](#building-from-source)) and a chat model (Gemma 4 E2B `.litertlm`).

```bash
fvm flutter pub get
tool/run_macos.sh              # macOS: checks the model files, then flutter run with the right dart-defines
tool/run_macos.sh --profile    # AOT speed, for the demo and for timings
```

Linux (x64 and arm64; verified on Ubuntu 22.04 x64 and arm64 machines and on an Arduino VENTUNO Q, with guides for
the Raspberry Pi 5 and NVIDIA Jetson): build on the target architecture, then package and run with the pre-flight
launcher, which checks audio, GPU (Vulkan), camera and JPEG support before starting the app:

```bash
fvm flutter build linux --release
tool/linux/package.sh                     # bundle + run.sh + guides + licences, and a .tar.gz
./run.sh                                  # in the unpacked bundle; ./run.sh --selftest checks every model
```

Board guides: [Raspberry Pi 5](docs/raspberry-pi.md), [NVIDIA Jetson](docs/jetson.md) (and
[jetson-check.md](docs/jetson-check.md)).

iPhone and Android: install once, open the app, put a chat model (`.litertlm`) into its models folder and choose it
on the Chat model card ([docs/android-install.md](docs/android-install.md)). Every model but the chat model is built
into the app: nothing is downloaded. For development builds, `tool/provision_ios.sh` and `tool/provision_android.sh`
copy model files to the device and print the matching `flutter run --dart-define=…` command.

All configuration goes through dart-defines (`GEMMA_MODEL_PATH`, `DETECTOR_MODEL_PATH`, `EMBEDDING_MODEL_DIR`, …).
No secrets are needed: the only download is the tester's own link (Download from URL… on the Chat model card).

## Docs

- [docs/demo-runbook.md](docs/demo-runbook.md): what each demo shows, two-minute scripts, per-platform run steps,
  every dart-define, the pre-event checklist, troubleshooting and known limitations. **Start here.**
- [docs/setup-checklist.md](docs/setup-checklist.md): platform configuration and what has been verified.
- [docs/demos.md](docs/demos.md): the original demo specs.
- Designs: [Demo 1](docs/design/demo1-voice-chat.md), [Demo 3](docs/design/demo3-live-camera.md),
  [detector](docs/design/detector-yolo26n.md), and the per-increment wiring notes in [docs/design/](docs/design/).
- [docs/upstream-issues.md](docs/upstream-issues.md): package issues found along the way, written up for the
  maintainers.

## Tests

```bash
fvm flutter analyze && fvm flutter test          # unit and widget tests
fvm flutter test integration_test/<file>.dart -d macos --dart-define=GEMMA_MODEL_PATH=…   # on-device runs
```

Each integration test's header lists its flags; [docs/demo-runbook.md](docs/demo-runbook.md) has the full list.
Integration tests on native targets run with `flutter test`, never `flutter drive`.

## Licences

The app's own code is Apache-2.0 ([LICENSE](LICENSE)); the app shows it first under Home › More › Licences.
`third_party/flutter_litert` (vendored by `tool/flutter_litert/vendor.sh` with its patch) stays under its own Apache-2.0
licence.

The YOLO26n detector and the derived raw-head file are AGPL-3.0: ship `tool/prune_yolo26n_head.py` with any
published build (see the runbook's known limitations). Gemma and EmbeddingGemma come under the Gemma terms.
