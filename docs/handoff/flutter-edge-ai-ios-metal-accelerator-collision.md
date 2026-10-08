# Handoff: iOS — `LiteRtMetalAccelerator.framework` name collision with flutter_litert

For the agent working on the `flutter_edge_ai` package family (`~/Work/flutter_gemma`). Found on 2026-10-08 on a real
iPhone 17 Pro (iOS 26.5.2) running `litert_hackathon` (release build, `flutter_edge_ai_litertlm` 1.9.0, native bundle
`native-v0.17.1-a`, `flutter_litert` 3.9.3). Everything below is **verified** on that device unless marked otherwise.

## Symptom

An app that uses both `flutter_edge_ai_litertlm` (LLM) and `flutter_litert` ≥ 3.4.0 (a `CompiledModel` on the GPU) on
iOS: the LLM runs on Metal, but every `flutter_litert` GPU model fails. Its LiteRT runtime logs:

```
INFO: [gpu_registry.cc:101] Attempting to load GPU accelerator(…/Runner.app/Frameworks/libLiteRtGpuAccelerator.dylib).
INFO: [gpu_registry.cc:101] Attempting to load GPU accelerator(…/Runner.app/Frameworks/libLiteRtMetalAccelerator.dylib).
INFO: [gpu_registry.cc:101] Attempting to load GPU accelerator(…/Runner.app/Frameworks/libLiteRtWebGpuAccelerator.dylib).
WARNING: [gpu_registry.cc:131] GPU accelerator could not be loaded and registered.
```

and the ObjC runtime warns about ~40 classes (`SRLRegistry`, `GTMLogger`, `GIPLogMessage`, …) "implemented in both
…/LiteRtMetalAccelerator.framework/LiteRtMetalAccelerator and …/LiteRt.framework/LiteRt".

## Cause

Both packages ship a framework **with the same name**, and an app bundle holds only one:

| Framework in `Runner.app/Frameworks` | `flutter_litert` 3.9.3 (SwiftPM binary target, `litert-ios-v1.0.1`, LiteRT 2.1.5) | `flutter_edge_ai_litertlm` 1.9.0 (Native Assets) | What the app kept |
|---|---|---|---|
| `LiteRt.framework` | 7 631 136 B | — (LiteRT is inside `LiteRtLm.framework`) | flutter_litert's |
| `LiteRtMetalAccelerator.framework` | 6 775 920 B | 5 466 256 B | **flutter_edge_ai_litertlm's** (5 466 480 B after signing) |

Flutter embeds the Native Assets frameworks in its own build phase, after Xcode embedded the SwiftPM ones, so the
LiteRT-LM accelerator silently overwrites flutter_litert's: no "Multiple commands produce" error. flutter_litert's
LiteRT 2.1.5 then cannot register a Metal accelerator built for another LiteRT revision; LiteRT-LM finds its own and
works.

History: `flutter_litert` < 3.4.0 shipped bare `libLiteRt.dylib` / `libLiteRtMetalAccelerator.dylib`, so the names did
not clash (that is why `~/Work/litert_demo`, on flutter_litert 3.3.1, found no collision, and it tested iOS only on
the simulator, on the CPU). 3.4.0 switched to framework-wrapped `LiteRt.framework` + `LiteRtMetalAccelerator.framework`
because App Store validation rejects loose dylibs (ITMS-90426, flutter_litert issue #15). Going back is not an option
for apps.

## Where the name comes from in flutter_edge_ai_litertlm

- `hook/build.dart:241` — `companions:` lists `'LiteRtMetalAccelerator'` (iOS + macOS); Native Assets turns
  `libLiteRtMetalAccelerator.dylib` into `LiteRtMetalAccelerator.framework` on iOS.
- `native/litert_lm/patch_c_api.sh:339` — patches LiteRT's `litert/runtime/accelerators/gpu_registry.cc` with
  `FLUTTER_GEMMA_METAL_FW_PATH` = `@executable_path/Frameworks/LiteRtMetalAccelerator.framework/LiteRtMetalAccelerator`
  (iOS) and `@executable_path/../Frameworks/LiteRtMetalAccelerator.framework/LiteRtMetalAccelerator` (macOS).
- The native release tarballs (`litertlm-ios_arm64.tar.gz`, `litertlm-ios_sim_arm64.tar.gz`, `hook/build.dart:232-235`)
  carry the dylib under that name; the comment at `hook/build.dart:815-835` documents the hash over the child names.

## Proposed fix

Give LiteRT-LM's Metal accelerator its own name, for example `LiteRtLmMetalAccelerator`:
1. Build/rename the dylib to `libLiteRtLmMetalAccelerator.dylib` with a matching install name (`-install_name` /
   `install_name_tool -id`), in the native release for iOS (device + simulator) and macOS.
2. `patch_c_api.sh:339`: point `FLUTTER_GEMMA_METAL_FW_PATH` at `LiteRtLmMetalAccelerator.framework/LiteRtLmMetalAccelerator`.
3. `hook/build.dart`: the companion `'LiteRtLmMetalAccelerator'`; the macOS Podfile post-install copy (see the
   comment near `hook/build.dart:250`) and the example app likewise.
4. Check that nothing else loads it by the old name (`grep -rn LiteRtMetalAccelerator`), and do the same for
   `LiteRtTopKMetalSampler` if flutter_litert ever ships one.
5. Optional but cheap: a build-time check in the hook that warns when the app's `Frameworks/` already holds a
   `LiteRt*.framework` of another origin.

The duplicate ObjC classes between the two accelerator copies will remain (two LiteRT builds), but each copy then
loads only its own accelerator; two-level namespaces keep the C symbols apart (that part was verified in
`~/Work/litert_demo/CONCLUSIONS.md`).

## How to verify

- `litert_hackathon` on an iPhone, release build with the patched package (`dependency_overrides`):
  - `Runner.app/Frameworks/` holds `LiteRtMetalAccelerator.framework` at flutter_litert's size (6 775 920 B before
    signing) **and** `LiteRtLmMetalAccelerator.framework`;
  - the device console (`xcrun devicectl device process launch --console --device <id> dev.fluttergemma.litertHackathon`)
    shows Gemma registering `GPU Metal` from the new framework path, and the detector's runtime no longer prints
    `GPU accelerator could not be loaded and registered`;
  - in the app: Demo 3's settings → Detector **GPU** loads ("fully accelerated" on the This device card), Gemma on GPU
    still answers.
- macOS: `integration_test/macos_check_test.dart` still passes (detector GPU fp32 fully accelerated, Gemma on GPU).

## In litert_hackathon meanwhile (for us, not for you)

The detector's standard backend on iOS is the CPU (`standardDetectorBackend()` in `lib/config/live_camera_config.dart`);
GPU chosen in Demo 3's settings still fails visibly. After the package fix: make the GPU the standard on iOS again and
add the iOS rows to `docs/design/detector-yolo26n.md`.
