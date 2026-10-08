# Hardware visibility

Status: proposal 2026-10-05; **first cut implemented 2026-10-06 for Linux and macOS** (§5: what exists, the
self-test, what is confirmed vs inferred). Goal: one screenshot or **Copy diagnostics** from any tester build shows
the chip, GPU + API, RAM, OS, and requested → actual backend for each model. Rule 2: anything unconfirmed is labelled
*inferred* or *requested*, never plain "GPU".

## 1. What the runtimes expose

| Model (runtime) | Backend truth | GPU API / adapter |
|---|---|---|
| Gemma 4 E2B (litertlm 1.8.5) | `InferenceModel.activeBackend`, after the gpu→cpu fallback (`flutter_gemma_interface.dart:236-243`, `litert_lm_engine.dart:184-187`); the app rejects a mismatch (`llm_service.dart:149`) | not in the API, so the native log |
| Gemma's vision encoder | **CPU**: a null `preferredVisionBackend` means `'cpu'` (`backend_preference.dart:155`), and the app sets none | — |
| YOLO26n (flutter_litert 3.9.3) | `accelerators`, `didFallback`, `isFullyAccelerated` (`compiled_model_native.dart:140,154,178`), plus the strict-GPU and CPU-reference checks in `detector_engine.dart` | not reported. The shipped library implies Metal on Apple and ClGl on Android. On Linux it runs on flutter_gemma's LiteRT/WebGPU (`detector-linux.md:29-30`) |
| EmbeddingGemma | `EmbeddingModel.activeBackend`, always CPU on native (`flutter_gemma_interface.dart:618-642`) | — |
| Whisper, moonshine, Inflect | not queryable (U1) → "CPU (requested)" | — |

**Tester builds get no native log from the package.** The stderr redirect runs only under `kDebugMode`, on iOS,
Linux and macOS (`litert_lm_client.dart:653-655`). Its content is printed at verbose level (:456), `gemmaLog` is silent
in release (`gemma_log.dart:27`), and the file is truncated after every dump (:462). The container's `tmp/` on this
Mac is empty. Android's libraries log to logcat (they import `__android_log_*`).

Real lines, macOS/Metal: a scratch FFI probe ran `litert_lm_engine_create` on `gemma-4-E2B-it.litertlm`, M4 Pro,
11.8 s:

```
INFO: [accelerator_registry.cc:54] RegisterAccelerator: ptr=0xb648246c0, name=GPU Metal
INFO: [gpu_registry.cc:144] Dynamically loaded GPU accelerator(@executable_path/../Frameworks/LiteRtMetalAccelerator.framework/LiteRtMetalAccelerator) registered.
I0000 00:00:1791234424.051954 18396043 delegate_metal.mm:89] Created a Metal device.
INFO: [gpu_environment.cc:367] Failed to create OpenCL context.
INFO: [gpu_environment.cc:374] Created Metal device from provided device id
INFO: Created TensorFlow Lite XNNPACK delegate for CPU.
```

- **macOS:** no GPU name (none in the accelerator's strings either). With the accelerator missing, `engine_create`
  fails; there is no silent CPU fallback inside the engine.
- **iOS:** same accelerator, so expect the same lines (not run yet).
- **WebGPU/Dawn (Linux, Windows), from earlier sessions:**
  `environment.cc:526] Selected adapter: Tesla T4, arch=turing, vendor=nvidia, backend=Vulkan, adapterType=Discrete GPU`.
- **Android:** `Selected adapter:` exists only in the WebGPU code. `gpu_environment` tries OpenCL first, and the OpenCL
  path logs only failures. Whether an OpenCL success prints anything is **unverified**: there is no device.

**Parser** (`parseNativeLog` in `lib/domain/hardware/native_log_parser.dart`, pure). Patterns are matched as substrings, so glog, `INFO: [f:l]` and logcat
prefixes all work:

| Pattern | Meaning |
|---|---|
| `Selected adapter: (.+?), arch=([^,]*), vendor=([^,]*), backend=([^,]*), adapterType=(.+?)\s*$` | adapter, confirmed |
| `RegisterAccelerator: ptr=\S+, name=(GPU [\w ]+)` / `Dynamically loaded GPU accelerator\((.+?)\) registered` | the API |
| `Created (a )?Metal device` / `Created a WebGPU environment` | confirms the API |
| `GPU accelerator could not be loaded` | no GPU |
| `XNNPACK delegate for CPU` | part of the load runs on the CPU |
| `GPU sampler unavailable` | sampling on the CPU (upstream-issues.md:71) |
| `adapterType=CPU`, or a name matching `llvmpipe\|lavapipe\|SwiftShader\|softpipe` | **software GPU: error** |

`Failed to create OpenCL context` is harmless on Apple.

**Capture** (`NativeLogTap`). Loads run one after another (`ModelRepository._prepareAll`), so each load gets its own
window: `mark()` before it, `since(mark)` after it.
- **Release on Linux, macOS, iOS:** `StderrFileTap`. In `main()`, before `AppDependencies.create()`, call libc over
  FFI: `open(<appSupport>/logs/native.log, O_WRONLY|O_CREAT|O_APPEND)`, then `dup2(fd, 2)`. This is what
  `stream_proxy.c:182-186` does, but leaves fd 1 alone. Print the path first.
- **Debug on those platforms:** `PackageLogPollTap`. Poll `${Directory.systemTemp.path}/litertlm_native.log` every
  100 ms during a load, and restart from offset 0 when the file shrinks.
- **Android:** `LogcatTap`. Before the load, `debugPrint('[HWMARK] <id> <n>')`. After it, run
  `logcat -d --pid=<pid>` and keep the lines after the marker. Reading your own log needs no permission.
- **Nothing matched:** take the API from the platform's only shipped accelerator (Metal on Apple,
  `hook/build.dart:233`; OpenCL on Android when the §2 probe finds a GPU; Vulkan on Linux) and the adapter from §2.
  Label both **inferred**.

## 2. Hardware identity

| Platform | Sources | Status |
|---|---|---|
| macOS | FFI `sysctlbyname`: `machdep.cpu.brand_string`=`Apple M4 Pro`, `hw.model`=`Mac16,8`, `hw.memsize`, `hw.perflevel0/1.physicalcpu`=10/4. GPU: `MTLCreateSystemDefaultDevice().name`=`Apple M4 Pro`, IOKit `AGXAccelerator` `gpu-core-count`=20 | **verified inside an App-Sandbox bundle** |
| iOS | `utsname.machine` (`iPhone18,1`). Chip: `MTLDevice.name` (expected `Apple A19 Pro GPU`), with a fallback table: 16,1-2 A17 Pro; 17,1-2 A18 Pro; 17,3-5 A18; 18,1-2 and 18,4 A19 Pro; 18,3 A19. RAM: `physicalMemory`. Headroom: `os_proc_available_memory()` | not run yet |
| Android | `getprop ro.soc.manufacturer` / `ro.soc.model` (= `Build.SOC_*`, API 31+; on API 30, `ro.board.platform` / `ro.hardware`). GPU: OpenCL `clGetDeviceInfo` (`CL_DEVICE_NAME`, `CL_DEVICE_VERSION`, `CL_DRIVER_VERSION`) over FFI on `libOpenCL.so`, `-pixel` or `-car`. These are declared in flutter_gemma's manifest (:32-34), and it is the default device ML Drift opens; no GL context needed. RAM: `/proc/meminfo` | getprop, table GPU and RAM implemented (§6), OpenCL not; unverified on a phone |
| Linux | CPU: `/proc/cpuinfo` `model name` (device tree on arm64). NVIDIA: `/proc/driver/nvidia/gpus/*/information` `Model:` and `…/nvidia/version`. Any GPU: `/sys/bus/pci/devices/*/{class,vendor,device}` (works without nvidia-drm), named from `pci.ids` or a table (10de:1eb8 T4, 10de:27b8 L4). Vulkan: ICDs in `/usr/share/vulkan/icd.d` (only `lvp_icd*` = software), `vulkaninfo --summary` if installed; when nothing above finds a GPU (an SoC's platform GPU has no PCI/DRM ids, e.g. the Adreno 623 of the VENTUNO Q under Mesa turnip), each hardware Vulkan device is the GPU, inferred from `vulkaninfo` (`gpusFromVulkan`, API `Vulkan`; llvmpipe/lavapipe/SwiftShader never count). Jetson: `/proc/device-tree/model`, `/etc/nv_tegra_release`. glibc: FFI `gnu_get_libc_version()`; below 2.35 LiteRT fails, below 2.38 the detector's CPU check can't run (`detector-linux.md:20,29`) | v0.1.1 run on an Arduino VENTUNO Q (2026-10-08), which found the Vulkan-only GPU gap |

**NPU hints** (info only): Apple Neural Engine on all Apple Silicon; Qualcomm SM8550/8650/8750/8850 (Hexagon
V73/75/79/81, matching flutter_litert's `libQnnHtpV*`) when `libcdsprpc.so` opens; Linux `/dev/accel/accel*`.

**`device_info_plus` 13.3.0** (2026-10-01) has no Android SoC fields, and nothing on Linux beyond os-release. It does
give Android `hardware`/`board`/`physicalRamSize`, iOS `modelName` (`iPhone18,1` → `iPhone 17 Pro`), and macOS
`modelName`/`memorySize`. Add it only for marketing names and `isPhysicalDevice` (on a simulator: "LLM on CPU").

## 3. UI and UX

A "This device" card on home and on the Models screen (`lib/ui/core/device_card.dart`):

```
THIS DEVICE                                     [Copy diagnostics]
MacBook Pro (14-inch, 2024) · Mac16,8 · macOS 26.5.1
Chip  Apple M4 Pro · 14 cores (10P+4E) · RAM 24 GB
GPU   Apple M4 Pro · 20 cores · Metal       NPU  ANE (not used)
Gemma 4 E2B     GPU → GPU · Metal · Apple M4 Pro      inferred
                vision encoder CPU (default) · sampler CPU
YOLO26n         GPU → GPU · Metal fp32 · full · CPU check ✓
EmbeddingGemma  CPU (fixed by flutter_gemma)
Whisper base    CPU (requested · not reportable)
```

- **Linux example:** `GPU NVIDIA L4 · Vulkan · driver 550.x · glibc 2.39`; Gemma
  `GPU → GPU · WebGPU/Vulkan · NVIDIA L4 (Discrete)  log ✓`.
- **Colours:** green = API or log confirmed; amber = requested or inferred; red = mismatch or software GPU.

**Copy diagnostics** builds a plain-text report (golden-tested). It contains:
- timestamp, app version (`package_info_plus` 10.2.2), build mode
- `String.fromEnvironment('FLUTTER_VERSION')` (`flutter_command.dart:184`) and `Platform.version`
- package versions, parsed from a bundled `pubspec.lock` asset
- LiteRT-LM native tag `native-v0.17.1-a` (`hook/build.dart:177`), a constant kept honest by a test reading the hook
- the device block
- per model: file, manifest sha256 (12 hex) marked verified or "dev override", requested → actual, API, adapter,
  evidence source, load/warm-up times
- the last 20 matched native lines

**Startup line** (`debugPrint`):
```
[Hardware] macOS 26.5.1 · Mac16,8 · Apple M4 Pro 10P+4E · GPU Apple M4 Pro 20c Metal · 24 GB · app 0.1.0+1 · flutter_gemma 1.11.3 · litertlm 1.8.5/native-v0.17.1-a
```
After each load, one line:
```
[Hardware] gemma4E2b req=gpu act=gpu api=Metal adapter="Apple M4 Pro" src=inferred
```

**Overlay:** an `hw` line; `_modelLine` (`debug_overlay/overlay_lines.dart`) gains API, adapter, source.

**`device_info` skill:** `describeDevice` (`app_intent_handlers.dart:239`) adds chip, GPU API and RAM. It speaks the
adapter only when it is confirmed.

## 4. Implementation plan

**Files**
- `lib/domain/models/hardware_profile.dart`: `HardwareProfile`, `GpuInfo`, `NpuHint`,
  `AcceleratorEvidence{api, adapter, softwareGpu, cpuPart, samplerOnCpu, source: log|api|inferred|requested, lines}`.
- `lib/data/services/hardware/hardware_info_service.dart`: `abstract interface class HardwareInfoService {
  Future<HardwareProfile> probe(); }`. Implementations:
  - Apple: sysctl over FFI, plus a MethodChannel `dev.fluttergemma/hardware` to ~60 lines of Swift (by `swift-coder`)
    for `MTLDevice.name`, the IOKit core count and `os_proc_available_memory`.
  - Android: getprop, OpenCL FFI, `/proc/meminfo`. No Kotlin.
  - Linux: injected `SystemFiles` and `ProcessRunner` (`system_access.dart`) and a libc probe, `glibcVersion()`
    (`libc.dart`) by default.
  - Fake.
- `native_log_tap.dart` (three taps and a no-op) and `lib/domain/hardware/native_log_parser.dart`.
- `lib/data/repositories/hardware_repository.dart`: probes once, logs, exposes `profile` (the `HardwareProfile`, null
  until the probe ends) and `changes` (a `Listenable` over the probe, the model states and the audio devices).
- `ModelRepository` wraps each `_prepare*` in `mark()`/`since()` and fills a new optional `LoadedModelInfo.evidence`.
  Coordinate with the Phase A coder.
- `lib/domain/hardware/diagnostics_report.dart`: a pure formatter.
- The Home and Models view models expose the report; the view calls `Clipboard.setData`.

**Tests**
- Parser fixtures: the real lines above, plus llvmpipe, CRLF and logcat prefixes.
- Linux service on fake `/proc` and `/sys` trees: a T4 VM without drm, L4, Jetson Orin, an AMD iGPU, no GPU, musl, an
  Arduino VENTUNO Q (QCS8275) whose Adreno only Vulkan names.
- Taps: file shrink (poll), marker slicing (logcat).
- Widget test: card states (confirmed, inferred, software GPU, mismatch); Copy writes the report.
- Golden reports: `test/goldens/diagnostics_macos.txt`, `diagnostics_linux_l4.txt`.
- Device runs: macOS release; iPhone 17 Pro (record `MTLDevice.name`); an Android phone (record the logcat lines,
  finish the parser); Linux T4/L4.

**Effort** ≈6.5 dev-days: parser + taps 1.5, services 2, Swift 0.5, wiring 0.5, UI/report/overlay/skill 1, device
runs 1. A macOS-only first cut takes ≈1.5 d.

**Upstream asks**
1. `InferenceModel.acceleratorInfo` (API, adapter, adapterType, sampler, encoders) in every build mode, Android
   included. Still absent on `origin/main` (`flutter_edge_ai_litertlm`).
2. U1: report the STT/TTS backend.
3. flutter_litert: report the loaded accelerator.

## 5. First cut (2026-10-06): Linux, macOS and the self-test

**Code.** `lib/data/services/hardware/` (Linux and macOS probes, `MemoryProbe`, `NativeLogTap`, FFI helpers),
`lib/domain/hardware/` (`parseNativeLog`, `inferEvidence`, card summary), `lib/domain/hardware/diagnostics_report.dart`,
`lib/data/repositories/hardware_repository.dart`, `lib/ui/core/device_card.dart` (Home and Models), `lib/selftest/`.
Startup logs `[Hardware] <os> · <machine> · <chip> …` and one `[Hardware] <model> req=… act=…(<source>)
api=…(<source>) adapter="…"(<source>)` per load (every hardware log line is tagged `[Hardware]`). Release builds on
Linux and macOS redirect native stderr into
`<app support>/logs/native.log` (previous run kept as `.prev`); each Gemma/detector load keeps its own window of it.

**Self-test.** `--selftest` (or `SELFTEST=1`) in `main(args)`; the Linux runner passes argv after the binary name
(`my_application.cc`), macOS passes `NSProcessInfo.arguments` by default. No runner change was needed.

```
# Linux, release bundle, headless (x64 or arm64; add --skip-audio without a sound session):
xvfb-run -a build/linux/x64/release/bundle/litert_hackathon --selftest \
  --gemma=$HOME/models/gemma-4-E2B-it.litertlm \
  --detector=$HOME/models/yolo26n/yolo26n_fp16_rawhead.tflite \
  [--gemma-backend=cpu] [--detector-backend=cpu] [--detector-cpu-retry] [--allow-software-gpu] \
  [--skip-audio] [--image=PATH] [--out=selftest.txt] [--timeout=1800]
# or through the bundle's launcher (pre-flight checks first): ./run.sh --selftest …
# macOS release (sandboxed: reads only the container, so the model-store paths, no --gemma/--detector):
build/macos/Build/Products/Release/litert_hackathon.app/Contents/MacOS/litert_hackathon --selftest
```

Steps: 1 hardware probe; 2 detector on exactly the requested backend (2b: an explicit CPU attempt, information only);
3 the bundled cats (`test_assets/cats.jpg`) against the coex golden, ten identical runs; 4a Gemma with the app's
`kLlmConfig` (8192 tokens, image on) on the requested backend + warm-up, no fallback; 4b 64 tokens timed; 5 the
detector again, bit-identical; 6 audio, unless `--skip-audio`: 6a 1 s of 440 Hz (−9.1 dBFS) through the app's audio
repository (session, soloud, the output-device check of linux-build.md §2, the reply player); on Linux the default
sink's monitor is recorded meanwhile (`parecord -d @DEFAULT_MONITOR@`) and the step passes when its loudest 100 ms
reaches −40 dBFS, else FAIL "played but nothing reached the sound server" (below −80 dBFS or all zeros) or "… too
quietly"; a device the output check flags (the `auto_null` dummy sink, an inferred ALSA output) makes it a WARN; macOS
has no monitor source, so the step is titled "played, not measured". 6b 1 s of audio from the default input through `record` with the app's input check,
independent of 6a: the device and the level in dBFS; silence is WARN (does not fail the run), no microphone FAIL.
Each audio step fails after 15 s instead of hanging. The hardware probe also lists Linux's sound server, microphones
and sinks (`pactl`) and the ALSA card count. Available memory (Linux `MemAvailable`, macOS free + inactive pages), RSS and
peak RSS around every step. One `===== SELFTEST BEGIN/END =====` block on stdout and in `--out` (default
`<app support>/selftest/selftest-<time>.txt`, native log next to it). Exit 0 only when every step passed; a confirmed
mismatch fails the step; so does a software GPU (llvmpipe & co., from the log, a Vulkan list with only software
devices, or only lavapipe/SwiftShader ICDs installed) and, on Linux, an adapter nothing can name (no adapter line, no
`vulkaninfo`, no GPU found), unless `--allow-software-gpu` (the result line then says "software GPU allowed").
Unhandled Dart errors are echoed to stdout (the tap moves fd 2) and fail the run. A watchdog (`--timeout`) and a crash guard always print a FAIL block and exit 1.

**Confirmed vs inferred.**

| | Backend | GPU API | Adapter |
|---|---|---|---|
| macOS, Gemma + detector | confirmed: API | confirmed: native log in release (`RegisterAccelerator … GPU Metal`, `Created a Metal device`); inferred (Metal) in debug | inferred: the chip name (no Metal device query yet) |
| Linux, Gemma + detector | confirmed: API | confirmed: native log in release when `Selected adapter: … backend=Vulkan` appears; else inferred WebGPU/Vulkan | the same line confirms it; else inferred from `vulkaninfo` (discrete, then integrated), NVIDIA proc, Jetson SoC, PCI |
| Gemma vision encoder | requested (CPU, flutter_gemma default) | — | — |
| EmbeddingGemma | confirmed: API (CPU) | — | — |
| Whisper, moonshine, Inflect | requested (not reportable, U1) | — | — |

Debug builds have no tap (flutter_gemma redirects stderr itself and truncates it), so they stay *inferred*. Whether
the detector's LiteRT environment and Gemma's each print `Selected adapter:` in a release build on Linux is not
verified yet (no Linux run of this code; the T4 line in §1 is from an earlier debug session).

## 6. Android probe (2026-10-06)

A Galaxy S24 showed "Chip: unknown · 8 cores", "GPU: none found": Android had only the OS and core count.

- **Properties, read once** (`android_props.dart`): one `/system/bin/sh -c` runs `getprop` per key and prints the
  dump format (`[key]: [value]`, the same parser reads a pasted `adb shell getprop`). Keys: `ro.soc.manufacturer`,
  `ro.soc.model`, `ro.board.platform`, `ro.hardware`, `ro.product.manufacturer`, `ro.product.model`,
  `ro.build.version.release`, `ro.build.version.sdk`. Per key, not a full dump: SELinux would log a denial for every
  property area an app may not read. The NPU gate (`probeNpu`'s SoC) and the hardware probe share the one read, so
  `getprop` runs once per process, on a worker isolate at startup (timed in the log: `[Hardware] getprop … in N ms
  (worker isolate)`), so the main isolate finds it cached. If `sh` cannot start, or every value comes back empty
  (`getprop` missing or denied: the script still exits 0), the reason with its stderr is a note and the chip stays
  "unknown".
- **SoC table** (`lib/domain/hardware/soc_table.dart`): Qualcomm SM8250–SM8850 (name, Adreno, Hexagon version),
  Exynos 2100/2200/2400/2500 (`s5e*`), Tensor through G5 (by name or board). Android 11 has no `ro.soc.*`: an
  unambiguous Qualcomm board (`kona`, `kalama`, `pineapple`, `sun`) stands for its part, and the chip is then tagged
  *inferred*; `taro` (SM8450 and SM8475) and `lahaina` (SM8350, but 778G/780G phones report it too) are reported raw.
  SM8250 is named "Snapdragon 865/865+/870" (one code for all three). A part the table does not know is shown as
  Android names it, without a GPU.
- **GPU**: named from the table and labelled *inferred* (no OpenCL `clGetDeviceInfo` query yet). Gemma's adapter is
  then inferred too (`GPU → GPU · OpenCL · Adreno 750`), and `device_info` says so ("… GPU (inferred from the
  chip)"). An unknown SoC shows "GPU not identified" (card) / "gpu not identified" (report), not "none found".
- **RAM**: `/proc/meminfo` (also the memory probe's `MemAvailable`, as on Linux).
- **NPU hint**: "Qualcomm Hexagon V75 · libcdsprpc.so opens" when the NPU gate's FastRPC check passes; on Exynos and
  Tensor the vendor NPU is listed as not used; a Qualcomm SoC whose FastRPC does not open gets a note with the reason.
- Shown on the card (title `Samsung SM-S921U · Android 14 (API 34)`, chip `Snapdragon 8 Gen 3 (SM8650) · 8 cores ·
  RAM …`), in Copy diagnostics and the self-test report (a `soc` row with its source), and in `device_info`.

**Unverified on a phone:** that `sh -c getprop` runs from the app's SELinux domain (it is the documented way apps read
`ro.*`; `Build.SOC_*` reads the same properties), the Exynos and Tensor `ro.soc.model` spellings, and the Adreno 840
(press coverage, not a device).

**Phase 2 (not done).** Android OpenCL FFI and `LogcatTap`, iOS and the Swift MethodChannel (Metal device name, GPU
core count, `os_proc_available_memory`), the debug-build `PackageLogPollTap` and the overlay `hw` line.
