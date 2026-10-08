# YOLO26n on Linux (x86_64 and arm64)

Status: implemented 2026-10-05; **verified on Linux x86_64 with an NVIDIA T4 (GPU) and on Linux arm64 (CPU)**,
2026-10-06. Contract of the detector itself: [detector-yolo26n.md](detector-yolo26n.md).

## Why it did not work

1. **Two LiteRT copies, one file name.** flutter_litert 3.9.3 and flutter_gemma_litertlm 1.8.5 both put
   `libLiteRt.so` and `libLiteRtWebGpuAccelerator.so` into `bundle/lib/`. The Linux runner installs plugin libraries
   first and native assets second, so flutter_gemma's copies silently replace flutter_litert's
   ([linux-build.md](linux-build.md) B1). ELF has one flat namespace, and flutter_gemma preloads `libLiteRt.so` with
   `RTLD_GLOBAL`, so the detector always ran on flutter_gemma's LiteRT pin (`9fe5be45`), not on 2.1.5.
2. **That pin has a newer model-loading ABI.** Since LiteRT 2.1.6, `LiteRtCreateModelFromBuffer/FromFile` take an
   environment first; the symbol names did not change. flutter_litert uses the new signature only on Android. On
   Linux it called the newer library with the old signature and the process crashed in `CompiledModel.fromBuffer`.
   Every other symbol flutter_litert binds (39) has the same signature on GCC/Clang in both versions (the
   `LiteRtLayout` bit-field change only affects MSVC).
3. **The load check needed the TFLite Interpreter.** Step 4 of the load (detector doc §4.3) compares the GPU output
   with `verifyCompiledModel`'s delegate-free TFLite Interpreter. flutter_litert's `libtensorflowlite_c-linux.so` is
   x86_64 only and needs GLIBC_2.38, so on Ubuntu 22.04 and on arm64 the check came back *skipped*, which the app
   treats as a failed load.

On macOS, iOS and Android there is no clash: Apple platforms keep the two LiteRT copies in separate images with
two-level symbol binding, and on Android flutter_gemma links LiteRT statically into `libLiteRtLm.so` while
flutter_litert's own `libLiteRt.so` (2.2.0) already uses the new ABI.

## Fix

- **One LiteRT on Linux: flutter_gemma's.** It exists for x86_64 and arm64 and needs glibc 2.35 (Ubuntu 22.04+,
  JetPack 6). The patched flutter_litert no longer bundles its own `libLiteRt.so` or WebGPU accelerator on Linux,
  and bundles the TFLite C library only on x86_64.
- **ABI by library, not by platform.** `_hasEnvironmentModelAbi(dylib)` is true on Android or when the library
  exports `LiteRtCreateModelFromFd` (introduced in 2.1.6 together with the environment argument).
- **How the patch is carried:** `tool/flutter_litert/flutter_litert-3.9.3.patch` (2 files, ~60 lines);
  `tool/flutter_litert/vendor.sh` builds `third_party/flutter_litert` (gitignored) from the pub.dev package plus the
  patch, and `pubspec.yaml` points `dependency_overrides` there. Run the script once per checkout and in CI, before
  `pub get`. Upstream write-up: [upstream-issues.md](../upstream-issues.md), FL-1 and FL-2.
- **Fallback verification reference** (`lib/data/services/detector/detector_verification.dart`). If `verifyCompiledModel`
  reports that its Interpreter could not be built, the detector is compared against LiteRT's CPU `CompiledModel` on
  the same ramp input, with the same 1%-of-range rule. `DetectorInfo.verifyReference` records which reference was
  used (`vs TFLite interpreter` / `vs LiteRT CPU` in the log and diagnostics). This is not a silent fallback: the
  detector backend is unchanged, the check still runs, and the reference is shown.

## Evidence (macOS host, M4 Pro)

`test/manual/litert_pin_compat_test.dart` (opt-in, see its header) with `LITERT_LIB_PATH` set to flutter_gemma's
`libLiteRtLm.dylib`, which exports the same C API from the same pin:

| Run | Result |
|---|---|
| unpatched flutter_litert, flutter_gemma's LiteRT | process dies after the CPU accelerator registers, before the model is created |
| patched, flutter_gemma's LiteRT, CPU | builds and runs; output sum `10824521.620584637` |
| patched, flutter_litert's own 2.1.5, CPU | the same sum, bit for bit |
| 2.1.5, GPU (Metal) vs CPU | max \|Δ\| 0.0019 over a range of 865 |
| patched, flutter_gemma's LiteRT, Interpreter made unavailable (`TFLITE_LIB_PATH` → a non-TFLite library) | `TFLite interpreter unavailable …; verifying against LiteRT CPU`, then `loaded DetectorInfo(CPU (explicit), … vs LiteRT CPU)` |

The GPU half could not run on the host against flutter_gemma's build: its Metal accelerator is located through the
app bundle's `Frameworks/` directory. On Linux the runtime finds `libLiteRtWebGpuAccelerator.so` next to
`libLiteRt.so` in `bundle/lib`.

## Evidence on Linux (2026-10-06)

`integration_test/detector_coex_test.dart` (detector + Gemma in one process, no UI), debug build under
`xvfb-run -a`, models from local files. Both hosts run Ubuntu 22.04.5 with glibc 2.35, so the TFLite interpreter
cannot load and the detector is checked `vs LiteRT CPU` on both.

| Host | Detector | Cats vs golden | Gemma 4 E2B | After Gemma |
|---|---|---|---|---|
| GCP n1-standard-4 + **Tesla T4** (driver 580, Vulkan 1.4), Flutter 3.47.5 | **GPU fp32 full**, verify 2.4e-6 of range; **25–27 ms/frame** warm (46 ms cold); create 0.83 s warm (4.6 s cold: shader compile) | 4 golden classes, max box error 0.04 px, max Δscore 0.0004 | **GPU**, **79–80 tok/s** warm (3.2 tok/s on the very first run) | bit-identical |
| GCP t2a-standard-4 (**arm64**, Ampere Altra, 4 cores), Flutter 3.47.3 | CPU (explicit), 196 ms/frame | the same 0.04 px | CPU, 20 tok/s | bit-identical |

- **The adapter is the T4, not llvmpipe.** Vulkan lists both (`vulkaninfo --summary`). With all ICDs visible the T4
  peaks at 89% utilisation and 1 GB during the run; with only `nvidia_icd.json` visible the speeds are the same
  (25 ms / 80 tok/s). The slow first run was cold caches (GPU programs, weight caches), not the adapter. Tester docs
  must say that the first launch on Linux is slow.
- **Two LiteRT environments in one LiteRT copy work**: the detector's and Gemma's WebGPU devices coexist; the app
  still pauses detection while Gemma generates (design demo3), so they are not run concurrently.
- **arm64 bundle:** all 17 libraries in `bundle/lib` are aarch64; no TFLite C library, no x86_64 leftovers.
- **arm64 GPU path, functionally** (the t2a VM has no GPU; Mesa llvmpipe 15.0.7 as the only Vulkan device):
  `DETECTOR_BACKEND=gpu` gives `GPU fp32 full`, verify 2.3e-6 of range vs LiteRT CPU, the cats within 0.04 px, and
  bit-identical output after Gemma (CPU, 18 tok/s). So the aarch64 WebGPU accelerator, Dawn, Vulkan and the patched
  binding work together; only the Tegra driver is left for a real Jetson. Speed is meaningless here (8.4 s/frame on
  a software rasteriser). **The first, cold run failed once** in the verify step:
  `LiteRtLockTensorBuffer output[0] failed with kLiteRtStatusErrorRuntimeFailure` (the app refused the detector with
  that message; no fallback). The immediate rerun passed. Probably the first readback while llvmpipe was still
  compiling shaders; watch for it on the first launch on a slow GPU (Jetson Orin Nano) and retry before concluding.
- **The T4 is ~4× slower than the M4 Pro's Metal path for YOLO26n** (25 ms vs 4–8 ms): enough for the live boxes
  (~37 fps), not investigated further.
- **Build dependency found on the VMs:** `libasound2-dev` (flutter_soloud's ALSA backend), now in
  [linux-build.md](linux-build.md).
- VM notes: the T4 VM boots a mainline 6.16 kernel by default with no NVIDIA module; the run used a one-time
  `grub-reboot` into `6.8.0-1069-gcp`. Org policy forbids external IPs: new VMs need `--no-address` (Cloud NAT
  `flutter-nat` provides egress, SSH goes through IAP). C4A had no capacity in us-central1; T2A did.

## Still open

1. The full app on Linux (UI, camera via camera_desktop/GStreamer, audio): Phase C in
   [distribution.md](distribution.md).
2. A real Jetson: the Tegra GPU driver and Vulkan on Orin, and the 8 GB memory budget of an Orin Nano. arm64 CPU and
   the arm64 GPU code path (on llvmpipe) are covered above. Rentable: CloudJetson (AGX Orin); or an Orin Nano dev kit.
