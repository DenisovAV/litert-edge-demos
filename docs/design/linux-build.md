# Linux build (distribution Phase C)

Status: research, 2026-10-05, from the resolved packages (`pubspec.lock`) and the Linux prebuilts inspected with
`xcrun llvm-objdump -p/-T`. **No `flutter build linux` was run**: the podman build hit a full host disk (§3). Runtime
claims still need §5.

## 1. Native prebuilts

| Package | Linux arch | Source (build-time download) | GPU | Needs |
|---|---|---|---|---|
| flutter_gemma_litertlm 1.8.5 | x86_64, arm64 | `github.com/DenisovAV/flutter_gemma/releases/download/native-v0.17.1-a/litertlm-linux_<arch>.tar.gz` (37/34 MB; sha256 matches `hook/build.dart:215-219`), cached in `~/.cache/flutter_gemma/native/linux_<arch>` (`hook:377-388`) | WebGPU through Dawn (`libwebgpu_dawn.so`), then Vulkan (`hook:237-241`) | glibc 2.34, GLIBCXX_3.4.30 (`libLiteRtLm.so`) |
| flutter_gemma_speech 0.5.2, _embeddings 2.2.1 | same | no hook; they use litertlm's `libLiteRt.so` (`litert_bindings.dart:283`) | same | same |
| flutter_gemma_rag_sqlite 1.4.0 | x86_64, arm64 | `native-sqlite-vec-v0.1.9/sqlite-vec-linux_<arch>.tar.gz` (`hook:69-99`), plus sqlite3 3.7.0's prebuilt `libsqlite3.so` from `simolus3/sqlite3.dart` release `sqlite3-3.7.0` | — | glibc 2.14/2.17 |
| flutter_litert 3.9.3 | **x86_64 only** | `libtensorflowlite_c-linux.so` and `libLiteRt.so` (2.1.5 wheel) ship in the package; `libLiteRtWebGpuAccelerator.so` is fetched by CMake from `hugocornellier/flutter_litert` `litert-desktop-gpu-v1.0.0` (`linux/CMakeLists.txt:35-59`) | WebGPU, then Vulkan | tflite_c: **glibc 2.38**, GLIBCXX_3.4.32 |

**B1: `libLiteRt.so` collides (Linux only). Resolved 2026-10-05 by patching flutter_litert: one LiteRT (flutter_gemma's) and the ABI chosen per library, see [detector-linux.md](detector-linux.md).** Both packages put `libLiteRt.so` and `libLiteRtWebGpuAccelerator.so`
into `bundle/lib/`. The runner template installs plugin libraries first and native assets second
(`templates/app/linux.tmpl/CMakeLists.txt.tmpl:107-117`). Native assets keep their file names
(`native_assets.dart:770`), so **flutter_gemma's copies overwrite flutter_litert's**. Unlike Android, `libLiteRtLm.so`
has `NEEDED libLiteRt.so`. So the detector's `CompiledModel` runs on flutter_gemma's LiteRT pin, not 2.1.5; `live_detection_test` COEX must prove it (§5). A renamed second copy isn't safe: flutter_gemma
preloads `libLiteRt.so` with `RTLD_GLOBAL` (`DESKTOP_SUPPORT.md`, Linux).
`verifyCompiledModel` builds a reference `Interpreter` from tflite_c (`backend_verification.dart:120-154`). Where
tflite_c can't load (arm64, glibc < 2.38) that check comes back *skipped*, and the UI must say so.

**Runtime:** glibc ≥ 2.34 with libstdc++ ≥ GCC 12 (Ubuntu 22.04+, Debian 12+, Fedora 36+). GPU needs `libvulkan1` and a
vendor ICD: Mesa radv/anv on AMD/Intel, the proprietary driver on NVIDIA.

**llvmpipe:** Mesa caps lavapipe's `maxStorageBufferRange` at `max_shader_buffer_size` =
`LP_MAX_TGSI_SHADER_BUFFER_SIZE` = `1 << 27`, i.e. 128 MiB. (mesa main `lvp_device.c:993`, `lp_screen.c:350`,
`gallivm/lp_bld_limits.h:57`; same in 24.0.9). That Gemma 4 needs more is upstream's claim, not re-run here. Also, `PreferredBackend.gpu` expands to `[gpu, cpu]` (`backend_preference.dart:130-132`), so on
llvmpipe the package quietly lands on CPU. The app compares `activeBackend` (`llm_service.dart:170`,
`embedder_service.dart:214`) and must turn that into the D6 "Use CPU (slower)" prompt. **CPU mode:** upstream lists
Linux CPU as supported (`DESKTOP_SUPPORT.md:75-76`); not verified here.

## 2. Plugins and system packages

- **record_linux 2.1.2:** streams by spawning `parecord`, lists devices with `pactl`, and needs `ffmpeg` only for file
  encoding (`capture_pipeline.dart:10-65`). Install `pulseaudio-utils`; it works on PipeWire. `hasPermission` is always
  true (`record_linux.dart:40`). A missing `parecord` throws `ProcessException` on start; show it as a mic error.
  `echoCancel` maps to a non-standard parecord property (`process_args.dart:16`); fine, the app is half-duplex.
  Its `listInputDevices` keys devices on `node.name`, a PipeWire-only property (`pactl_devices.dart:98`), so on plain
  PulseAudio it lists nothing; the app runs `pactl` itself. **Done (2026-10-06):** when a voice demo opens,
  `LinuxAudioDeviceService` runs `parecord --version`, `pactl info` and `pactl list sources|sinks` (C locale) and the
  mic errors say what to do: "Microphone unavailable: install pulseaudio-utils (parecord)" (also for the
  `ProcessException` at start), "No recording device: … lists no microphone, only monitors of outputs", "No sound
  server: PulseAudio/PipeWire is not running (pactl info: …). Start it: …". A press after a failed check checks once
  more. When `parecord` exits mid-session, record 7.1.1 keeps the app's stream open (its wrapper forwards no `onDone`,
  `record_stream.dart:11-22`), so a Linux press of 0.5 s or more that delivered no bytes is diagnosed by a fresh check
  instead of "no audio arrived". The default
  source's description is the mic name on the overlay, the card and in Copy diagnostics.
- **flutter_soloud 4.1.7:** miniaudio 0.11.25 tries PulseAudio, then ALSA, then JACK, then **Null**, loading
  `libpulse.so.0` / `libasound.so.2` at runtime (`miniaudio.h:6723-6739`). With no audio server, playback is silent and
  nothing reports it. **B2:** the bundled Xiph libs are x86_64-only (CHANGELOG 4.0.0-pre.0, #421) and have odd sonames
  (`libFLAC.so.14`, `libvorbis.so.0.4.9`), while only the plugin's own `.so` gets bundled (`linux/CMakeLists.txt:154`).
  On arm64 the link fails. On x86_64 I expect those libs to be missing on a tester's machine, unverified (§3 `ldd`
  step). Fix: build with **`NO_XIPH_LIBS=1`** (`CMakeLists.txt:38`; guard fixed in 4.1.5, #528). The app plays
  PCM s16le only (`pcm_player_service.dart:63-68`).
  **Null check, done (2026-10-06).** After `init`, `prepare()` lists `SoLoud.listPlaybackDevices()` and checks the
  default device (else the first: iOS routes and AAudio mark none, `miniaudio.h:34752-34770, 39560-39575`). The Null
  device is named `"NULL Playback Device"` (`miniaudio.h:21062`, enumerate; `:21091`, device info); it, or an empty
  list, fails on every platform that lists (Null is compiled everywhere but the web, `miniaudio.h:6648-6651`). iOS
  and Android do not list: on iOS the listing's default-config context sets and activates the AVAudioSession
  (`miniaudio.h:36527-36566`), which `audio_session` owns; Android's soloud opens AAudio/OpenSL only
  (`soloud_miniaudio.cpp:519`). On Linux the list
  is not proof: `Player::listPlaybackDevices` uses `ma_context_init(NULL…)`, the first backend whose *context*
  starts, while soloud's Linux `ma_device_init(NULL…)` (`soloud_miniaudio.cpp:553`) takes the first backend whose
  *device* opens (`ma_device_init_ex`, `miniaudio.h:44015-44090`). Without a sound server the list is ALSA's, and
  ALSA's configured `default` PCM shows (marked default) even with no card behind it while the device lands on Null.
  So on Linux: a server answering `pactl info` → its default sink (the `auto_null` dummy flagged); `pactl` did not run
  (not installed, or no answer in 5 s) → the server is unknown: with a card "PulseAudio or ALSA", flagged, without one
  "cannot be verified"; a server that is down but cards in `/proc/asound/cards` → ALSA, inferred and flagged (miniaudio tries `default`, `dmix`, `hw:0`,
  `miniaudio.h:28708-28750`); neither → "No audio output (no PulseAudio/PipeWire/ALSA device): …". A failed check
  shuts the engine down so the next `prepare` starts over. **macOS** opens Core Audio on an explicit context and
  fails `init` when Core Audio's device does not open (`soloud_miniaudio.cpp:479-488`): no Null fallback unless Core
  Audio's context itself fails, which the name check covers.
- **camera_desktop 2.0.0:** GStreamer with `v4l2src [! jpegdec] ! videoconvert … appsink`. It uses `pipewiresrc` only
  inside Flatpak (`pipewire_portal.cc:53-60`, `camera.cc:114-170`). Frames are BGRA (`camera.cc:357-362`), which matches
  the app's `bgra8888` (`camera_frame_source.dart:26-29`). Build needs `libgstreamer1.0-dev
  libgstreamer-plugins-base1.0-dev`. Runtime needs `gstreamer1.0-plugins-base gstreamer1.0-plugins-good` and `/dev/video*`
  access (desktop session, else the `video` group).
- **image_picker_linux 0.2.2:** uses file_selector_linux's `GtkFileChooserNative` (`file_selector_plugin.cc:60`). The
  camera source isn't supported, so `supportsImageSource` is false and the app already hides the button
  (`image_input_service.dart:45`).
- **flutter_local_notifications_linux 8.0.1:** pure Dart over D-Bus `org.freedesktop.Notifications`
  (`notifications_manager.dart:374`). It comes in through flutter_gemma_agent, and the app never calls it.
- **audio_session 0.2.4 does *not* throw on Linux.** `instance` and `configure` catch the missing plugin
  (`core.dart:28-41, 207-212`), and `setActive` returns `true` everywhere except iOS and Android. So the app logs
  `active=true` for a session that doesn't exist. Make the no-op explicit (**done 2026-10-06**,
  `audioSessionServiceFor`, logs `[AudioSession] none on Linux (PulseAudio/PipeWire)`):

  ```dart
  // audio_session_service.dart
  final class NoAudioSessionService implements AudioSessionService {
    const NoAudioSessionService();
    @override
    Future<void> configureHalfDuplex() async =>
        debugPrint('[AudioSession] none on Linux (PulseAudio/PipeWire)');
  }
  // dependencies.dart:108
  session: defaultTargetPlatform == TargetPlatform.linux
      ? const NoAudioSessionService()
      : const PlatformAudioSessionService(),
  ```
- **flutter_inappwebview 6.1.5:** no Linux implementation. Only `JsSkillExecutor`/`SkillResultView` reach it; the app
  uses neither and rejects js/mcp skills (`skill_store_service.dart:319`). No guard needed.
- **flutter_scene (avatar branch):** Impeller is on by default on Linux in 3.47.3 (`fl_dart_project.cc:65`); Flutter
  GPU needs `fl_dart_project_set_enable_flutter_gpu(project, TRUE)` in `my_application.cc` (`fl_engine.cc:847-855`).
  Not tried.

## 3. Building

Flutter builds Linux desktop apps only on a Linux host, so cross-compiling from macOS is out. To add the platform:
`fvm flutter create --platforms=linux --org dev.fluttergemma .`, which sets `APPLICATION_ID
dev.fluttergemma.litert_hackathon`.

**Before every first build of a checkout** (2026-10-08): `tool/flutter_litert/vendor.sh`, then `tool/fetch_models.sh`.
The built-in models are not in git; the script fetches them into `assets/models/` from `tool/models.lock` and verifies
each SHA-256. It needs `HF_TOKEN` (environment or `.env`) for the gated EmbeddingGemma. YOLO26n is derived in a venv
under `build/fetch_models/`: python3 3.10–3.14 with `python3-venv`; `ai-edge-litert` has Linux wheels for x86_64 and
aarch64 (manylinux_2_27). Without the models `flutter build linux` stops with "No file or variants found for asset:
assets/models/…". `tool/linux/package.sh` checks the bundle's copy (`data/flutter_assets/assets/models`) against the
lock and refuses to package unverified models.

**(a) podman on this Mac.** Podman 5.6.2, `podman-machine-default` (applehv, 4 CPUs, 8 GiB, Rosetta enabled).
- `podman build --platform linux/arm64` (ubuntu:24.04, deps below, Flutter 3.47.3 clone): apt, clone and linux-arm64
  Dart SDK/engine artifacts took ~5 min, then the **host disk hit ENOSPC** (121 MiB free, 30 GB swap used); aborted.
  An apt-only image rebuilt in 86 s (1.41 GB).
- Cleaned up: images removed, `fstrim`, VM stopped (disk 38 GB allocated).
- Feasibility: arm64-native builds work once B2 is fixed, but they only prove compilation. B1 and tflite_c make arm64
  a poor target to ship. amd64 under Rosetta is untested.
- To retry: free ≥ 20 GB, `podman machine set --memory 4096`, mount the SDK and pub cache from the host.

**(b) GitHub Actions, x86_64 (recommended).** Build deps are in the apt line below; the hooks only need HTTPS to
github.com (prebuilts, nothing compiled). `.github/workflows/linux.yml`:

```yaml
name: linux-bundle
on: { workflow_dispatch: {}, push: { tags: ['v*'] } }
jobs:
  build:
    runs-on: ubuntu-24.04   # ubuntu-22.04 → glibc 2.35 floor for 22.04 testers (untested)
    timeout-minutes: 45
    env: { NO_XIPH_LIBS: '1' }   # B2
    steps:
      - uses: actions/checkout@v4
      - run: |
          sudo apt-get update
          sudo apt-get install -y clang cmake ninja-build pkg-config lld libgtk-3-dev \
            liblzma-dev libstdc++-12-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
            libasound2-dev \
            libturbojpeg   # shipped as lib/libturbojpeg.so.0: the network camera's JPEG decoder (§3.1)
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.47.3', channel: stable, cache: true }
      - uses: actions/cache@v4
        with: { path: ~/.cache/flutter_gemma, key: "fg-native-${{ hashFiles('pubspec.lock') }}" }
      - run: tool/flutter_litert/vendor.sh && tool/fetch_models.sh   # the models are not in git
        env: { HF_TOKEN: '${{ secrets.HF_TOKEN }}' }                # the gated EmbeddingGemma
      - run: flutter pub get && flutter build linux --release
      - name: Bundle checks
        run: |
          B=build/linux/x64/release/bundle
          if LD_LIBRARY_PATH=$B/lib ldd $B/litert_hackathon $B/lib/*.so* | grep 'not found'; then exit 1; fi
          test -e $B/lib/libturbojpeg.so.0   # the fast JPEG decoder is in the bundle
          objdump -T $B/litert_hackathon $B/lib/*.so | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1
          sha256sum $B/lib/libLiteRt.so ~/.cache/flutter_gemma/native/linux_x86_64/libLiteRt.so  # B1
      - run: |
          D=litert_hackathon-linux-x64-$(grep '^version:' pubspec.yaml | cut -d' ' -f2 | tr + -)
          cp -r build/linux/x64/release/bundle $D && cp tool/linux/run.sh $D/
          tar czf $D.tar.gz $D && sha256sum $D.tar.gz > $D.tar.gz.sha256
      - uses: actions/upload-artifact@v4
        with: { name: linux-x64, path: 'litert_hackathon-linux-x64-*' }
```

### 3.1 The network camera's JPEG decoder (libturbojpeg)

On Pi and Jetson the network camera (an Android phone running IP Webcam) is *the* camera, and the engine's image
codec is far too slow there: under Xvfb with software GL one 640×480 JPEG took ~900 ms (decode, then a GPU read-back
to RGBA), so the detector saw 2 fps. The app decodes network frames with libjpeg-turbo's TurboJPEG API over FFI on a
worker isolate instead (`lib/data/services/frames/turbojpeg.dart`, `jpeg_decoder.dart`; design demo3 §15): about 1–2 ms
per 640×480 frame on an M-series Mac.

- **Shipped:** `linux/CMakeLists.txt` copies the build machine's `libturbojpeg.so.0` into `bundle/lib/` (the
  Debian/Ubuntu package `libturbojpeg`; it needs only libc, so a copy built on Ubuntu 22.04 runs there and on newer
  systems of the same architecture). Install the package on the build machine (and the CI job above) before
  `flutter build linux`; CMake prints `Bundling … as lib/libturbojpeg.so.0`, or warns when it is missing. Licences:
  IJG + BSD-3-Clause, in the app's licence page and in `licenses/` of the package (`tool/linux/package.sh` copies the
  Debian copyright file).
- **Looked up at run time:** the bundle's `lib/libturbojpeg.so.0`, then the system's (`libturbojpeg` on Ubuntu and
  JetPack 6, `libturbojpeg0` on Raspberry Pi OS and Debian).
- **Neither:** the engine codec, with `[NetworkCamera] SLOW JPEG decoder: …` in the log and "· slow JPEG decoder" on
  the live chip and the overlay; `run.sh` warns before start.

## 4. Packaging

**Recommendation: a `tar.gz` of the bundle with a launcher.** The bundle is self-locating (RUNPATH `$ORIGIN/lib`,
`data/` beside the binary), needs no tooling, and runs on any distro at or above the glibc floor. Rejected:
- **AppImage:** needs FUSE2, which Ubuntu 24.04 doesn't install (`libfuse2t64`), and it still depends on the host's
  Vulkan driver, GStreamer and `parecord`.
- **.deb:** package names differ between 22.04 and 24.04 (the t64 rename), and it installs as root. Worth it only if
  testers standardise on one release.

`tool/linux/run.sh` (shellcheck-clean, Bash 3.2 compatible; `test/tool/run_sh_test.dart` runs shellcheck and dry
runs against stub tools) checks, warns with an install or start hint, then `exec`s the app with every argument:
`pactl info` (a sound server), `parecord`, at least one microphone and one sink (`pactl list short sources|sinks`,
monitors and `auto_null` not counted), `vulkaninfo --summary` (a software device such as llvmpipe flagged), GStreamer's
`v4l2src` (`gst-inspect-1.0`, else the plugin file), `/dev/video*` (readable and writable) and `libturbojpeg.so.0`
(shipped in `lib/`, else the system's; §3.1). Everything also goes to
`run.log` next to it (or `~/.local/state/litert_hackathon/run.log` when the bundle is read-only; `RUN_LOG=` turns it
off). `RUN_SH_DRY_RUN=1` runs the checks and prints the command instead.

Tester steps: `tar xzf litert_hackathon-linux-x64-*.tar.gz && cd litert_hackathon-linux-x64-* && ./run.sh`.

**Models:** app support is `${XDG_DATA_HOME:-~/.local/share}/dev.fluttergemma.litert_hackathon`
(`path_provider_linux.dart:47-61`). flutter_gemma installs into `<support>/flutter_gemma/`
(`platform_file_system_service.dart:262-268`), and Phase A's `ModelStore` will use `<support>/models/`. Linux
imports in place (D4). `--dart-define`s are compile-time (`String.fromEnvironment`); CI passes none, so the setup
screen drives everything.

## 5. Verification on a real Linux GPU machine (rule 3)

Ubuntu 24.04 x86_64, Intel/AMD (Mesa) or NVIDIA GPU, webcam, headset.

1. Preflight: `vulkaninfo --summary` should show `deviceType = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU` or `DISCRETE_GPU`.
   `llvmpipe` alone means GPU will fail. `pactl info | grep 'Server Name'` and `v4l2-ctl --list-devices` (v4l-utils)
   cover audio and camera; `./run.sh` prints all of these.
2. Tester bundle, `./run.sh`:
   - setup: import the models folder;
   - overlay: Gemma on **GPU**;
   - Demo 1: a voice turn; transcript, spoken reply, mic reopens;
   - Demo 3: the camera shows boxes at the overlay's fps;
   - an image pick from the gallery;
   - on a llvmpipe-only machine: the GPU error, then "Use CPU" works.

   - the self-test's audio step: `./run.sh --selftest` → `6a audio output (tone → sink monitor)` PASS with the
     monitor's loudest 100 ms (a virtual null sink works: its monitor is recorded), `6b microphone` PASS or WARN
     (silence) naming the default source; with the sound server stopped both fail with "No sound server: …".

   Keep `run.log`.
3. Developer checks (repo + `fvm`, built with `NO_XIPH_LIBS=1`):

```sh
M=$HOME/models
fvm flutter test integration_test/model_smoke_test.dart -d linux --dart-define=GEMMA_MODEL_PATH=$M/gemma-4-E2B-it.litertlm             # SMOKE backend=gpu … paris
fvm flutter test integration_test/model_smoke_test.dart -d linux --dart-define=GEMMA_MODEL_PATH=$M/gemma-4-E2B-it.litertlm --dart-define=GEMMA_BACKEND=cpu
fvm flutter test integration_test/voice_loop_test.dart -d linux --dart-define=GEMMA_MODEL_PATH=$M/gemma-4-E2B-it.litertlm              # VOICE …, BARGE …
fvm flutter test integration_test/live_detection_test.dart -d linux --dart-define=GEMMA_MODEL_PATH=$M/gemma-4-E2B-it.litertlm \
  --dart-define=DETECTOR_MODEL_PATH=$M/yolo26n_fp16_rawhead.tflite --dart-define=FRAME_SOURCE=fixture --dart-define=FIXTURE_DIR=$M/coco30  # COEX identical=true (B1)
fvm flutter test integration_test/camera_source_test.dart -d linux --dart-define=GEMMA_MODEL_PATH=$M/gemma-4-E2B-it.litertlm \
  --dart-define=DETECTOR_MODEL_PATH=$M/yolo26n_fp16_rawhead.tflite                                                                      # CAMERA src=camera_desktop … bgra
```

Debug `engine_create` failures log to `/tmp/litertlm_native.log` (`litert_lm_client.dart:654-660`). Record GPU,
driver, glibc (`ldd --version`) and each printed line here.

## 6. Audio on Linux, verified 2026-10-06

Release bundle on Ubuntu 22.04 arm64 (GCP t2a), PulseAudio 15.99.1 started in the SSH session, `run.sh --selftest`
under `xvfb-run`. Virtual devices: a null sink `vspk` as the default speaker, and a remapped monitor of a second null
sink as the default microphone `vmic`, fed a 300 Hz tone with `paplay`.

| Run | 6a output (tone → sink monitor) | 6b microphone | Result |
|---|---|---|---|
| virtual speaker + mic | PASS: monitor loudest 100 ms −12.0 dBFS (threshold −40) | PASS: VirtualMic, RMS −15.0 dBFS | PASS, exit 0 |
| sound server stopped | FAIL: "No audio output (no PulseAudio/PipeWire/ALSA device): no sound server answers and /proc/asound/cards lists no card, so the audio engine plays into miniaudio's silent Null device" | FAIL: "No sound server: PulseAudio/PipeWire is not running … Start it: systemctl --user start pipewire pipewire-pulse (or pulseaudio --start)" | FAIL, exit 1 |
| server stopped, `--skip-audio` | — | — | PASS, exit 0 |

The report lists the server and every device (`audio in VirtualMic · default`, `audio out VirtualSpeaker · default`).
`shellcheck run.sh` is clean. Not yet covered: real hardware (USB speakerphone on a Jetson), PipeWire instead of
PulseAudio, and the voice loop through the app's UI (STT → Gemma → TTS) on Linux.
