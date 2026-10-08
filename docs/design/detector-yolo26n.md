# Detector contract — YOLO26n on LiteRT (`flutter_litert` 3.9.3)

Status: verified on 2026-10-02 by `litert-expert` on an Apple M4 Pro (macOS 26.5.1) with three runtimes:
`ai-edge-litert` 2.2.0, `ai-edge-litert` 2.1.5, and `flutter_litert` 3.9.3 itself (`flutter test` on the macOS host).
Nothing here has run on a phone yet. Every on-device claim is marked **unverified** and assigned to Inc 2.

Files, scripts and fixtures live outside the repo, in `~/Work/models/yolo26n/`. Never commit model files.

| Path | What |
|---|---|
| `fp16/`, `int8w/` | both Hugging Face packages as downloaded (`shasum -c SHA256SUMS` passes), plus `annotated_*.jpg` |
| `fp16/yolo26n_fp16_rawhead.tflite` | **the file the app uses** (derived, §2.3) |
| `inspect_model.py`, `run_yolo26n.py` | signature/op census; preprocessing experiments and annotated images |
| `bench_compiled.py`, `bench_rawhead.py`, `bisect_gpu.py`, `prune_head.py` | CompiledModel CPU/GPU benchmarks; GPU op bisection; head pruning |
| `dart_probe/` | scratch Flutter project: `lib/yolo26n_codec.dart` (a reference Dart implementation of §3), `test/*.dart` (flutter_litert probes), `bin/bench_pre.dart` (AOT preprocessing benchmark), `fixtures/` |
| `.venv` (2.2.0), `.venv215` (2.1.5) | Python environments |

## 0. Decisions

1. **Variant: `Arm/yolo26n-fp16-litert`**, used through the derived file `yolo26n_fp16_rawhead.tflite`. Do not use
   int8w (§5.2).
2. **The Arm file cannot run fully on the GPU.** Its NMS-free selection head (TopK, GatherND, int64 Cast/Select/Less)
   never goes to the GPU. On `flutter_litert`'s Apple runtime (LiteRT Next **2.1.5**), the GPU takes only 54 of 461 ops,
   because the GPU delegate also rejects `ADD` version 4. As a result:
   - `CompiledModel.fromFile(arm, accelerators: {Accelerator.gpu})` **throws** (this is the call in the design doc's Inc 2).
   - `{gpu, cpu}` builds, but runs at CPU speed. That is a silent fallback.
3. **Fix: cut the head off, and set the shared `ADD` opcode to v1.** The result is
   `yolo26n_fp16_rawhead.tflite`. It has a single output `[1, 8400, 84]`, and top-k selection runs in Dart (0.75 ms).
   - Results on the Mac: strict `{gpu}` builds, `isFullyAccelerated == true`, `verifyCompiledModel` agrees, and
     detections match the CPU reference within 0.1 px.
   - Speed: 4.1 ms per run versus 22.8 ms on the CPU (`flutter_litert`, M4 Pro).
4. **Accelerator for Inc 2 and Inc 7:** strict `{Accelerator.gpu}`, `Precision.fp32`, `TensorBufferMode.managed`.
   - If the GPU fails, show an error. Never retry quietly on the CPU.
   - The explicit fallback chosen at the Inc 2 decision gate is `{Accelerator.cpu}` with the **same file and the same
     decode**, and the overlay shows "CPU".
5. **Input:** NCHW `[1,3,640,640]` float32, **RGB**, **/255**, letterbox, pad 114/255. A 640×480 frame maps 1:1, with
   80 px bars.
6. **Thresholds:** decode floor 0.25 (from the manifest). Overlay ≥ 0.35. Watcher default `min_score` 0.5, clamped to
   [0.3, 0.9]. Demo 3 counting ≥ 0.4. No NMS (§3.4).

## 1. What the packages contain (inspected, not from the README)

| | `yolo26n_conv2d_f16_weights.tflite` ("fp16") | `yolo26n_conv_fc_f16_int8w.tflite` ("int8w") |
|---|---|---|
| Size / SHA-256 prefix | 10,363,712 B / `474db10fde475b40` | 3,349,280 B / `7e38138140fada47` |
| Weights | **float32** Conv2D weights plus one unused fp16 constant, which is a marker for Arm's runtime to force XNNPACK FP16. Stock LiteRT runs it as FP32: it has no `reduced_precision_support` metadata, and `flutter_litert` exposes no XNNPACK flags. | per-channel int8 Conv2D filters with **float input**. That makes them hybrid ops: XNNPACK quantizes activations dynamically, while the GPU dequantizes the weights to float. |
| Input | `serving_default_args_0`, `[1,3,640,640]`, float32, **NCHW**. Op 0 is `TRANSPOSE`, which converts NCHW to NHWC inside the graph. | same |
| Output | `serving_default_output_0_output`, `[1,300,6]`, float32 | same |
| Ops (461) | CONV_2D 94, MUL 90, LOGISTIC 88, RESHAPE 31, SLICE 28, CONCATENATION 27, ADD 24, TRANSPOSE 20, CAST 9, DEPTHWISE_CONV_2D 8, PAD 7, BATCH_MATMUL 4, SELECT_V2 4, MAX_POOL_2D 3, LESS 3, GATHER_ND 3, SOFTMAX 2, RESIZE_NEAREST_NEIGHBOR 2 (v3), SUB 2, TOPK_V2 2, NOT_EQUAL 2, FLOOR_MOD 2, SELECT 2, REDUCE_MAX 1, DIV 1, SIGN 1, LOGICAL_AND 1 | same graph |
| Tensor types | float32 630, int32 71, **int64 25**, bool 8, float16 1 | plus int8 94 |
| Opcode versions | every opcode v1, except **ADD v4** and RESIZE_NEAREST_NEIGHBOR v3 | same |
| Graph structure | ops 0–410 are the backbone plus the Detect head, ending in `[1,8400,84]` (op 410). Ops 411–460 are the one-to-one selection: REDUCE_MAX → TOPK(300 anchors) → GatherND → TOPK(300 of 24000) → `//80`, `%80` in int64 → GatherND of the boxes → concat. | same |
| Manifest | `confidence_threshold` 0.25, `nms_threshold` 0.4, `is_nms_exported` false, `max_detections_per_image` 300, `are_coordinates_normalized` false | same |

Class names (`assets/class_names.json`, identical in both packages) use the **Darknet spellings**, which differ from
Ultralytics: `motorbike, aeroplane, sofa, pottedplant, diningtable, tvmonitor`. The JSON maps each name to an id from
0 to 79. Invert it to build the `List<String>` used by the decoder. `watch_camera {label}` needs aliases: `couch→sofa`,
`tv|television|monitor→tvmonitor`, `plant→pottedplant`, `table→diningtable`, `phone|smartphone→cell phone`,
`motorcycle→motorbike`, `airplane|plane→aeroplane`.

## 2. Model file for the app

### 2.1 Why the Arm file fails on the GPU (delegate log, verbatim)

`flutter_litert` 3.9.3 on macOS reported the following for the Arm fp16 file:

```
CAST: Tensor type(INT64) is not supported.            (×9)
GATHER_ND: Operation is not supported.
LESS / RESHAPE / SELECT: Tensor type(INT64) is not supported.
ADD: Max version supported: 2. Requested version 4.
54 operations will run on the GPU, and the remaining 407 operations will run on the CPU.
strict {gpu}: LiteRtCreateCompiledModel failed with LiteRtStatus=504 (kLiteRtStatusErrorCompilation)
```

- The `ADD` line is the expensive one. The converter emits one ADD opcode for all 24 ADDs, at the version the int64 head
  ADDs need (v4).
- LiteRT 2.1.5's Metal delegate accepts ADD only up to v2. So the first ADD in the backbone (op 19) cuts off GPU
  placement. The bisection (`bisect_gpu.py`) found it.
- With the 2.2.0 runtime (`ai-edge-litert` 2.2.0, Metal), the same file places 415 of 461 ops on the GPU. Only the head
  stays on the CPU.
- `flutter_litert` 3.9.3 bundles LiteRT Next **2.2.0 only on Android**. macOS uses 2.1.5: the Metal dylib is
  byte-identical to the `ai-edge-litert==2.1.5` wheel's (SHA-256 `de67ec2e…`). iOS uses the `litert-ios-v1.0.1` build,
  per the package README table and CHANGELOG 3.9.1.

### 2.2 Derived file: `yolo26n_fp16_rawhead.tflite`

- Ops 0–410 are kept unchanged, with the same weights.
- New single output `detections_raw`: `[1,8400,84]` float32. The signature output name stays `output_0`.
- The ADD opcode is set to v1. The script asserts that every remaining ADD is float32, which makes this exact.
- Size 10,361,332 B. SHA-256 `5ddd5eebad18587d56500a30b0995c07c9e1a241640750f568e4a974f66ed80a`. Two runs of the
  script give the same hash.
- Recipe: `~/Work/models/yolo26n/.venv/bin/python prune_head.py fp16/yolo26n_conv2d_f16_weights.tflite out.tflite`
  (script reproduced in Appendix A).
- Licence: the derived file stays AGPL-3.0. Ship the script with any published build.

### 2.3 Equivalence check (derived file vs. Arm file)

| Check | Result |
|---|---|
| CPU: derived file plus Dart/numpy selection vs. Arm file with its in-graph head (4 images) | identical detections, box error **0.0 px**, Δscore **0.000** |
| GPU fp32, strict, LiteRT 2.2.0 and 2.1.5 (Python) | `fully_accelerated = true`; matched 100%; max box error ≤ 0.1 px; Δscore 0.000 |
| `flutter_litert` 3.9.3, strict `{gpu}`, fp32 | builds; `isFullyAccelerated = true`; `verifyCompiledModel` agrees (abs dev 0.0018 of a 864 range); cats fixture identical to the golden |
| `flutter_litert` 3.9.3, strict `{gpu}`, **fp16** | `isFullyAccelerated = true`, but `verifyCompiledModel` **fails** (1.47% of range, above the 1% tolerance); boxes ≤ 0.84 px, Δscore ≤ 0.018 → use fp32 |

## 3. I/O and processing contract

### 3.1 Input tensor

| Field | Value |
|---|---|
| Shape / layout | `[1, 3, 640, 640]`, **NCHW** (planes R, G, B; each plane row-major, 640×640) |
| Dtype | float32. CompiledModel I/O is float32 only, and that matches. |
| Channel order | **RGB** |
| Normalization | `value / 255.0`, giving [0, 1]. No mean or std. |
| Resize | **letterbox**: `ratio = min(640/W, 640/H)` on the *upright* frame; new size `round(W·ratio) × round(H·ratio)`; centred; `padX = (640 − newW) ~/ 2`, `padY = (640 − newH) ~/ 2` |
| Pad value | 114/255 = 0.447 (Ultralytics). Pad 0 changed scores by ≤ 0.014, so the value is not critical, but use 114. |
| Rotation | rotate the frame upright *before* letterboxing (fold it into the index map, §7.3). `rotationForFrame(...)` from `flutter_litert` gives the rotation. |
| Interpolation | nearest neighbour is enough. For 640×480 the ratio is 1.0, so the copy is exact. |

### 3.2 Preprocessing evidence (`run_yolo26n.py`, CPU, fp16 file)

Columns give detections at score ≥ 0.25 / sum of scores, and the share of reference detections (column A) found again
(IoU ≥ 0.5, same class).

| Image | A: RGB, /255, letterbox 114 | B: BGR | C: 0–255 | D: stretch | E: letterbox pad 0 |
|---|---|---|---|---|---|
| `samples/sample.jpg` 853×1280 | 10 / 6.28 | 9 / 6.21, 90% | 300 / 299.8 (**every score 1.00**) | 10 / 6.44, 80% | 9 / 6.07, 90% |
| COCO 39769 cats 640×480 | 4 / 2.96 | 4 / 2.95, 100% | 300, garbage | 3 / 2.41, 75% | 4 / 2.93 |
| COCO 397133 kitchen | 9 / 4.05 | 10 / 4.46, 100% | garbage | 8 / 4.18, 67% | 10 / 4.31 |
| COCO 37777 fruit (colour-sensitive) | 10 / 5.83 | 10 / 5.25; oven 0.74→0.62, orange 0.61→0.54 | garbage | 11 / 4.98; refrigerator 0.91→0.78 | 10 / 5.87 |
| 35 COCO val2017 images | 175 dets / 105.85 | 174 / 104.04 (RGB ahead on 19 of 35) | — | 156 / 96.44 (letterbox ahead on 25 of 35) | — |

- **0–255 is unambiguous:** every score saturates.
- **BGR still "works".** It costs about 2% of confidence overall and up to −0.12 on colour-defined classes. Nobody would
  notice it by eye, so the choice rests on the Ultralytics convention (the training loader and predictor convert
  BGR→RGB) plus the fruit-image evidence.
- **Stretch** loses about 11% of detections.
- **Visual check:** `fp16/annotated_sample.jpg` and `fp16/annotated_coco_*.jpg` (and the same under `int8w/`). Boxes sit
  on the people, cats, remote, fridge and oranges.

### 3.3 Output tensor (derived file)

`detections_raw`: `[1, 8400, 84]` float32, read as `Float32List(705600)`. Row `a` (anchor) = `[x1, y1, x2, y2, s0 … s79]`.

- `x1, y1, x2, y2` are corners in **640×640 model-input pixels**. They are not normalized (the manifest says
  `are_coordinates_normalized: false`) and not centre/size, and the strides are already applied. The values overshoot
  slightly (−9.6 … 651 was seen), so **clamp** after unletterboxing.
- `s0 … s79` are per-class **sigmoid** probabilities (op 408 is LOGISTIC). No further activation is needed.
- The anchors are 80×80 + 40×40 + 20×20 = 8400. The decoder never needs grid or stride arithmetic.

For reference, the Arm file's output `[1,300,6]` is `[x1, y1, x2, y2, score, classId]`, with scores sorted descending
and the class id as an integral float. It is not used by the app.

### 3.4 Decode (replaces the pruned head)

```
selectRaw(raw: Float32List[8400*84], thr = 0.25, maxDet = 100) -> List<Det>
  for a in 0..8399:
    base = a*84
    for c in 0..79:
      s = raw[base + 4 + c]
      if s >= thr: add Det(raw[base], raw[base+1], raw[base+2], raw[base+3], s, c)
  sort by score desc; take maxDet
```

- **Equivalence:** this keeps every (anchor, class) pair above the threshold, which is what the in-graph two-stage TopK
  does for any thr ≥ the 300th score. On the CPU the result was identical on all 4 images.
- **Cost:** 0.75 ms AOT on the M4 Pro (`bin/bench_pre.dart`), and 0.8–1.0 ms under JIT.
- **No NMS.** YOLO26 is trained one-to-one, so it is NMS-free. Same-class duplicates with IoU > 0.4 above 0.25 appeared
  **once** in 8 image×model runs: an int8w "sofa" pair at 0.28/0.27 with IoU 0.94.
- **Optional de-dupe:** at IoU > 0.7 per class it is cheap and harmless. The manifest's 0.4 is Arm's runtime setting: it
  would merge overlapping people in a crowd, so do not use it.

### 3.5 Inverse transform (model input → preview)

1. **Unletterbox to upright-frame pixels:** `x' = clamp((x − padX) / ratio, 0, uprightW)`, and the same for y with
   `padY` and `uprightH`.
2. **Rotation:** already applied in preprocessing, so boxes come out upright and the painter does no rotation.
3. **Preview:** `CoverFitTransform.cover(sourceWidth: uprightW, sourceHeight: uprightH, viewWidth, viewHeight, mirror:
   isFrontCamera)` (`flutter_litert`). `map(x, y)` mirrors and then scales/offsets. The preview widget must use the same
   cover fit.

## 4. GPU suitability and fallback detection

### 4.1 Measured placement

| Runtime | Arm file, strict GPU | Arm file, GPU+CPU | Derived file, strict GPU |
|---|---|---|---|
| `ai-edge-litert` 2.2.0 (Metal) | throws ("415 ops on GPU, 46 on CPU") | builds, 415/461 on GPU, 4.05 ms | builds, fully accelerated, 3.2–3.5 ms |
| `ai-edge-litert` 2.1.5 (Metal) = `flutter_litert` macOS | throws (54 on GPU) | 54/461 on GPU | builds, fully accelerated (after ADD v1), 3.2–3.7 ms |
| `flutter_litert` 3.9.3 macOS (measured) | **throws** 504 | builds, 21.6 ms (= CPU speed) | **builds, `isFullyAccelerated` true, 4.1 ms** |
| `flutter_litert` iOS (LiteRT `litert-ios-v1.0.1`) | expected to throw — **unverified** | **unverified** | iOS 26.5 simulator, 2026-10-08: throws 504 (expected: flutter_litert's Metal accelerator cannot register next to LiteRT-LM's, [upstream-issues.md](../upstream-issues.md)). **CPU** builds: verify 2.4e-6 of range, cats box 0.04 px, 25 ms (`integration_test/detector_bundled_test.dart`). iPhone 17 Pro (iOS 26.5.2, release, 2026-10-08): GPU throws 504 the same way; **CPU runs Demo 3** (switched in the app, boxes live) |
| `flutter_litert` Android (LiteRT 2.2.0 OpenCL/GL) | throws (int64/GatherND are GPU-unsupported in ML Drift) — expected | partial — expected | **unverified**. Risk ops: BATCH_MATMUL (4, attention), 3-D TRANSPOSE and SLICE, RESIZE_NEAREST v3. Check on the first Android device. |

### 4.2 What `flutter_litert` 3.9.3 reports (read from `compiled_model_native.dart`)

- `accelerators`: the *effective* set the model was compiled with. On Apple it equals the requested set unless NPU was
  dropped.
- `requestedAccelerators`, `didFallback`, `requestedConfig`: `didFallback` is true only after a whole-model CPU retry. It
  never reports op-level placement.
- `isFullyAccelerated`: true means the selected delegates took the whole graph. **False is ambiguous:** a pure-CPU run is
  also false here (XNNPACK leaves some ops to builtin kernels), and so is any `{gpu,cpu}` partial graph.
- `CompiledModelPolicy.auto` and `gpuWithCpuFallback` (and the legacy `fromBufferWithGpuFallback`,
  `compiledModelFromBufferAuto`) **retry silently on the CPU**. The only notice is an optional `onFallback` callback.
  Never use them here.
- `verifyCompiledModel(bytes, model)` compares one run on a ramp input against a plain-CPU `Interpreter`, with a
  tolerance of 1% of the output range. Do not run it on the Arm file: a top-k list reorders under float noise and showed a
  90% "deviation" even though the image results were identical.
- No GPU priority, OpenCL/GL backend choice, CPU thread count or XNNPACK flags are exposed (`_createOptions` sets only the
  accelerator mask, plus `precision = fp32` as opaque `gpu_options`).
- `runAsync` runs the call on a per-model helper isolate. It is safe for Metal; with Android GL/CL it is "unvalidated"
  (README).

### 4.3 The app's fail-fast checks, in order, at detector load

1. Build with `CompiledModel.fromFile(path, accelerators: {Accelerator.gpu}, precision: Precision.fp32)`.
   - A throw (504 = an op cannot be placed, or no GPU) becomes
     `Result.error(DetectorUnavailableException('GPU rejected YOLO26n: …'))`.
   - Show it in the UI and the overlay. No retry.
2. Check `model.isFullyAccelerated`. If it is false, close the model and return an error. With a strict `{gpu}` mask
   this should never happen; it is defence in depth.
3. Check `model.inputByteSizes == [3*640*640*4]` and `outputByteSizes == [8400*84*4]`. A mismatch means the wrong file
   (for example the Arm original): error.
4. Run `verifyCompiledModel(bytes, model)`. If `!agrees`, error.
   - Log `absoluteDeviation`. On the Mac it is about 1.8e-3. Exactly 0.0 under a GPU request is suspicious, so log it as
     a warning; it is not a gate.
   - It costs one plain-CPU reference run (about 0.3–1 s on a phone, **unverified**), once at load.
5. Warm-up: one run on the zero-pad frame. Record `createMs` and `firstRunMs` for the overlay.
6. The overlay shows `det: GPU fp32 full · 4.1 ms · 3.0 fps`, or `det: CPU (explicit) · …`.

If the Inc 2 gate moves the detector to the CPU, steps 1–2 become `{Accelerator.cpu}` with no full-acceleration check.
It is the same file and the same decode, chosen explicitly and labelled "CPU".

## 5. Latency

### 5.1 Model run, M4 Pro, macOS 26.5.1

Median / p90 over 100 runs (Python) or 60 runs (Dart), after 10 warm-up runs.

| Configuration | Arm fp16 file | Arm int8w file | Derived fp16 file |
|---|---|---|---|
| CPU XNNPACK, 1 thread (Py 2.2.0) | 23.9 / 32.7 ms | **37.5** / 38.6 | — |
| CPU XNNPACK, 4 threads (Py 2.2.0) | 13.0 / 15.5 | 16.8 / 21.0 | 13.8 / 18.7 (11.5 on 2.1.5) |
| CPU, forced XNNPACK FP16 flag, 1 / 4 threads (Py) | 27.9 / 13.3 (no gain) | 29.6 / 14.2 | — |
| GPU + CPU, partial (Py 2.2.0) | 4.05 fp16 / 4.30 fp32 | 3.86 | — |
| GPU strict fp32 (Py 2.2.0 / 2.1.5) | throws | throws | 3.47 / 3.65 |
| `flutter_litert` `run()` CPU (default threads) | 21.6 (gpu+cpu, 54 ops) | — | 22.8 / 25.8 |
| `flutter_litert` `run()` strict GPU fp32, including the 4.9 MB input and 2.8 MB output copies | throws | — | **4.11 / 4.79** |
| `flutter_litert` `runAsync()` plus `selectRaw` (JIT) | — | — | 7.6 / 9.6 |
| `flutter_litert` end to end (JIT): BGRA gather + `run` + `selectRaw`, managed buffers | — | — | 9.3 / 11.0 |
| The same with `TensorBufferMode.hostMemory` (zero-copy) | — | — | 12.7 / 14.8 (slower on Metal) |
| `CompiledModel` create, strict GPU (`flutter_litert`) | — | — | 296 ms cold (first in process, with environment), about 50 ms warm |

**Arm's own numbers** (Vivo X300, one core, LiteRT 2.2.0 + KleidiAI + SME2, end to end): FP32 33.0 ms; their forced FP16
17.9 ms; int8w 21.1 ms. Neither of their speed-ups is reachable through `flutter_litert`, which has no XNNPACK flag
plumbing.

### 5.2 Is int8w worth it on a phone? No.

- Its only win is file size (3.3 vs 10.4 MB), which is noise next to Gemma's 2.6 GB.
- On the GPU it computes in float after dequantizing, so it is no faster (3.6 vs 3.7 ms).
- On a stock CPU it is slower on this Mac (37.5 vs 23.9 ms, one thread). Its CPU path quantizes activations dynamically,
  so CPU and GPU disagree. On one image, 2 of 11 detections changed between the int8w CPU and GPU runs (Δscore up to
  0.07), which would make CPU-vs-GPU parity checks noisy.
- Accuracy is −0.35 mAP (39.90 vs 40.25).
- On this machine's CPU it matched 100% of the fp16 file's detections (mean |Δscore| 0.008–0.030), so it is not broken,
  just pointless here.

### 5.3 Preprocessing cost, Dart AOT

`dart compile exe`, M4 Pro, 200 runs. Phones are likely 1.5–3× slower (**unverified**).

| Path (640×480 camera frame) | Median |
|---|---|
| BGRA (iOS) → NCHW 640², RGB/255, rot 0 / 90 (ratio 1, a 1:1 copy) | 1.38 / 1.52 ms |
| BGRA → NCHW 640² through the precomputed `GatherPlan`, rot 90 | 1.34 ms |
| YUV420 / NV21 (Android) → NCHW 640², naive float math | 10.3–12.8 ms |
| YUV420 → NCHW 640², integer BT.601 + `/255` LUT (`GatherPlan`), rot 90, random-pixel worst case | 3.9 ms (720×480 flat frame 1.5 ms) |
| Previous YOLOX-nano path: BGRA → NHWC 416², BGR 0–255, rot 0 / 90 | 1.30 / 1.42 ms |
| `GatherPlan` build (once per stream: size, strides, rotation) | 2.0 ms |
| Pure-Dart `image`-package resize of 1080p (AGENTS.md figure) | about 82 ms (avoid) |

- **640² vs 416² costs the same in Dart.** At 640², a 640×480 frame needs no resampling: about 307k pixels are written
  1:1, against about 130k resampled pixels at 416².
- The real cost is tensor size: 4.9 MB vs 2.1 MB. The extra copy is about 0.5 ms and is already inside the 4.1 ms
  `run()` figure.
- YUV costs 2.5–3× BGRA, so request `ImageFormatGroup.bgra8888` on iOS. `camera_android_camerax` 0.7.5+1 offers only
  `yuv420` and `nv21`, so Android needs the integer YUV path.
- Android `ResolutionPreset.medium` is a 720×480 *bound* with closest-lower fallback, so the ratio need not be 1. The
  `GatherPlan` handles any size, stride and rotation.
- At 3 fps the whole pipeline is about 6–8 ms per frame on the Mac (preprocess + run + decode). Native preprocessing is
  **not** needed.

## 6. Recommendation

| Item | Inc 2 (coexistence) | Inc 7 (camera watcher) |
|---|---|---|
| File | `yolo26n_fp16_rawhead.tflite` (SHA-256 `5ddd5eeb…`), via `--dart-define=DETECTOR_MODEL_PATH=…` and copied to the device like Gemma | same; the delivery decision is in §9 |
| Accelerator | strict `{Accelerator.gpu}`, `Precision.fp32`, managed buffers | the same, or `{cpu}` if the Inc 2 gate fails (explicit, shown in the overlay) |
| Where it runs | the test isolate | **one long-lived detector worker isolate** that owns the `CompiledModel` and calls `run()` (not `runAsync`: no second hop, and the 4.9 MB input never crosses isolates) |
| Thresholds | decode 0.25; the fixture golden (§8) | decode 0.25 → overlay ≥ 0.35 → watcher rule `score ≥ min_score` (default 0.5, clamped to [0.3, 0.9]) for 2 consecutive frames. Demo 3 counting ≥ 0.4. All are constants in one place, tuned on the device. |
| Max detections | 100 | 100 (the painter draws at most 50) |
| GPU sharing with Gemma | measure (§8) | paused while the LLM generates (design §5). `flutter_litert` has no GPU priority knob. |

**Why 0.5 for the watcher:** the clearly visible objects scored 0.86–0.92 (cats, remote, fridge, people facing the
camera), while small or occluded true objects sat at 0.25–0.45 (cup 0.37–0.45 and spoon 0.27 in a kitchen; handbag
0.26). A cup held up to the camera should clear 0.5 easily, and the 2-frame debounce absorbs single-frame spikes. Tune it
with real cups in Inc 7.

## 7. Dart implementation spec (for `flutter-coder`)

`dart_probe/lib/yolo26n_codec.dart` is a working reference for every function below. Its outputs were checked against
the Python pipeline: `maxAbsDiff 0.0` on the input tensor, and identical detections.

### 7.1 Constants (`config/model_catalog.dart` or `domain/models/detector_spec.dart`)

```dart
const kDetInput = 640;            // input is [1, 3, 640, 640] NCHW float32
const kDetAnchors = 8400, kDetClasses = 80, kDetRawStride = 84;   // output is [1, 8400, 84]
const kDetPad = 114 / 255.0;
const kDetDecodeScore = 0.25, kDetDisplayScore = 0.35, kWatchDefaultMinScore = 0.5, kDetMaxDet = 100;
const kDetModelSha256 = '5ddd5eebad18587d56500a30b0995c07c9e1a241640750f568e4a974f66ed80a';
const kDetModelBytes = 10361332;  // cheap identity check before hashing
const kCocoNames = <String>[/* index 0..79, inverted from class_names.json, Darknet spelling */];
```

### 7.2 `DetectorService` (`data/services/detector/detector_service.dart`)

```dart
Future<Result<DetectorInfo>> load({required String modelPath, required DetectorBackend backend}); // spawns the worker
Future<DetectionFrame> detect(FrameMessage f);   // one in flight: WatcherRepository holds the latest-frame-wins slot
Future<void> close();                            // await the in-flight detect, then close the model, kill the isolate
```

Worker `init(modelPath, backend)` (all steps from §4.3):

```
bytes  = File(modelPath).readAsBytesSync(); require length == kDetModelBytes (optionally sha256)
model  = CompiledModel.fromBuffer(bytes, accelerators: backend.gpu ? {gpu} : {cpu}, precision: fp32)  // throw -> error
require backend.cpu || model.isFullyAccelerated
require model.inputByteSizes == [1*3*640*640*4] && model.outputByteSizes == [1*8400*84*4]
v = verifyCompiledModel(bytes, model); require v.agrees
input  = Float32List(1*3*640*640)        // reused for every frame
warm-up run; reply DetectorInfo(backend, fully, v.absoluteDeviation, createMs, firstRunMs)
```

`FrameMessage` (main → worker) carries:
- `TransferableTypedData`: BGRA bytes, or the Y/U/V planes.
- `width`, `height`, `bytesPerRow`, `uvRowStride`, `uvPixelStride`.
- `format` (`bgra8888 | yuv420 | nv21`), `rotationDeg` (0/90/180/270), `frameId`, `captureTime`.

Worker `detect(f)`, with shapes:

```
plan  = plans[(w, h, strides, format, rot)] ??= GatherPlan(Letterbox(w, h, rot))   // ~2 ms once per stream
plan.toNchw(f.planes, input)              // input: Float32List[1*3*640*640], RGB /255, pad 114/255
t1; raw = model.run([input])[0]            // raw: Float32List[8400*84]
t2; dets = selectRaw(raw, kDetDecodeScore, maxDet: kDetMaxDet)   // List<Det> in 640 input px
     .map((d) => unletterbox(d, plan.lb))                        // upright frame px, clamped
reply DetectionFrame(frameId, uprightW, uprightH, boxes: Float32List[n*6] (x1,y1,x2,y2,score,cls),
                     preMs, runMs, postMs, backend)              // a small message, under 3 KB
```

### 7.3 `Letterbox` and `GatherPlan`

- **`Letterbox(srcW, srcH, rot)`**:
  - Upright size: `rot % 180 == 0 ? (srcW, srcH) : (srcH, srcW)`.
  - `ratio = min(640/uW, 640/uH)`; `newW/H = round(uW/H · ratio)`; `padX/Y = (640 − newW/H) ~/ 2`.
- **Upright → source pixel** (`rot` = clockwise degrees that make the buffer upright):
  - 0: `(ux, uy)`
  - 90: `(sx = uy, sy = srcH−1−ux)`
  - 180: `(srcW−1−ux, srcH−1−uy)`
  - 270: `(sx = srcW−1−uy, sy = ux)`
- **`GatherPlan`** builds three `Int32List(newW*newH)` tables once:
  - `dstOffset` = `(y + padY)·640 + x + padX`.
  - `yIdx`: for BGRA, `sy·bytesPerRow + sx·4`; for YUV, `sy·yRowStride + sx`.
  - `uvIdx` = `(sy>>1)·uvRowStride + (sx>>1)·uvPixelStride`.
  - Nearest neighbour: `ux = min(uW−1, floor((x+0.5)/ratio))`.
- **Per frame:** `dst.fillRange(0, 3·640², 114/255)`, then one loop over the tables:
  - BGRA: `dst[o] = lut[b[i+2]]` (R), `dst[plane+o] = lut[b[i+1]]` (G), `dst[2·plane+o] = lut[b[i]]` (B).
  - YUV (BT.601, integer): `R = (Y·1024 + 1436·V') >> 10`, `G = (Y·1024 − 352·U' − 731·V') >> 10`,
    `B = (Y·1024 + 1815·U') >> 10`, where `U' = U − 128` and `V' = V − 128`; clamp to 0–255, then `lut[x] = x/255`.
  - This matches the float reference to within 1 LSB for all 4 rotations.
- **No per-frame allocation** except the 2.8 MB output copy that `run()` makes. That is about 8 MB/s at 3 fps, which is
  acceptable. Revisit `hostMemory` only if the iPhone measures it faster: on the Mac it was slower.

### 7.4 Main isolate

- **Camera:** `CameraController(..., ResolutionPreset.medium, imageFormatGroup: Platform.isIOS ?
  ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21)`.
- **Rotation:** `rotationForFrame(width:, height:, sensorOrientation:, isFrontCamera:, deviceOrientation:)` gives
  `CameraFrameRotation?`, mapped to degrees.
- **Throttle:** latest-frame-wins with a 3 fps throttle (`FrameThrottle` or the design's busy flag released in `finally`).
  Copy the plane bytes into `TransferableTypedData` *inside* the stream callback, because `CameraImage` buffers are
  recycled.
- **Painter:** `DetectionPainter(repaint: ValueNotifier<DetectionFrame>)` builds
  `CoverFitTransform.cover(sourceWidth: uprightW, sourceHeight: uprightH, viewWidth/Height, mirror: front)` once per
  size and draws boxes with score ≥ 0.35 as `label score`.

## 8. Inc 2 test (planned as `gpu_coexistence_test.dart`), detector part

Built as `integration_test/detector_coex_test.dart`: the cats image from `FIXTURE_DIR/../coco_39769_cats.jpg`, the
golden classes with box ≤ 3 px and |Δscore| ≤ 0.03 over 10 identical runs, Gemma on `GEMMA_BACKEND` next to the
loaded detector, then a bit-identical detection (`DETCOEX …`). The plan below is the original.

- **Fixture:**
  - Use `dart_probe/fixtures/cats_640x480_rgba.u8`: raw RGBA, 640×480, 1.2 MB, SHA-256 `9e0d4266…`, decoded by PIL from
    COCO val2017 `000000039769.jpg`.
  - Copy it to `test_assets/` (git-tracked, small) or push it with the model.
  - Raw RGBA avoids JPEG-decoder differences between ImageIO and libjpeg. The test swaps R and B, or uses an RGBA
    variant of the gather.
- **Golden** (`fixtures/cats_golden.json`, frame pixels, decode 0.25):
  - cat 0.912 `[344.0, 24.5, 640.0, 374.8]`
  - cat 0.899 `[6.9, 55.1, 317.3, 466.1]`
  - remote 0.857 `[40.4, 74.0, 175.9, 118.6]`
  - sofa 0.297 `[0.8, 0.6, 640.0, 480.0]`
- **Assertions:**
  1. The §4.3 load checks pass with strict GPU fp32.
  2. The same 4 classes appear, with box error ≤ 0.5 px and |Δscore| ≤ 0.005. This passed on the Mac at 0.00 px.
  3. 20 runs before and 20 runs after a 64-token Gemma generation. Report median/p90 of `run()`, and assert that the
     results after the generation are bit-identical to those before. That catches corruption from a shared GPU.
  4. Footprint after detector load, minus before.
- **Print line:**
  `COEX llm=gpu det=gpu-fp32 full=true verify=1.8e-3 det_ms=<median>/<p90> create_ms=… footprint=… headroom=…`.
- **Negative control (keep it, it documents the trap):** strict `{gpu}` on the Arm original must throw. If it ever
  builds, the runtime changed: re-read §2.1.

## 9. Corrections for other docs (not edited here)

| Doc | Says | Should say |
|---|---|---|
| `demo1-voice-chat.md` §6 | YOLO26n "~5 MB (verify)", "XNNPACK FP16 CPU (its packaged target)" | 10.36 MB. The "FP16 path" needs Arm's runtime; through `flutter_litert` it runs as FP32 on the CPU (§1, §5.1). |
| `demo1-voice-chat.md` Inc 2 step 2 and verify command | `CompiledModel.fromFile(det, {gpu}, fp32)` with `yolo26n_conv2d_f16_weights.tflite` | that call **throws** with the Arm file. Use `yolo26n_fp16_rawhead.tflite` (§2.2). |
| `AGENTS.md` Detector row | YOLOX-nano, BGR 0–255, 416², host decode + NMS | YOLO26n (derived raw-head file), RGB /255, 640² NCHW letterbox, top-k in Dart, no NMS, strict GPU fp32 |
| `AGENTS.md` / agent notes | `flutter_litert` = LiteRT 2.2.0 | 2.2.0 on Android only. macOS is LiteRT Next 2.1.5; iOS is `litert-ios-v1.0.1`. |
| `demo1-voice-chat.md` Inc 7 | `watch_camera {label}` "checked against COCO classes" | against the Darknet spellings, plus the aliases in §1 |

**Model delivery (decide before Inc 8):**
- (a) Recommended for the hackathon: generate the file with `prune_head.py` and push it to the device like Gemma
  (`DETECTOR_MODEL_PATH`).
- (b) Bundle it as a gitignored Flutter asset, filled in by a `tool/` script.
- (c) Re-host it on your own Hugging Face repo as AGPL-3.0 together with the script, and download it at setup.
- In every case, the app checks the SHA-256 or the size.

## 10. Not yet verified (each has a named check)

| Item | Check | When |
|---|---|---|
| iOS Metal (LiteRT `litert-ios-v1.0.1`) builds the derived file strict-GPU, fully accelerated, with verify agreeing | §8 test on the iPhone 17 Pro | Inc 2 |
| iPhone latency (expect a few ms GPU, about 20–35 ms CPU), create time, verify time, footprint (Arm's CPU process peak was 82 MB) | §8 print line, plus `--profile` | Inc 2 |
| Two LiteRT copies (Gemma's LiteRtLm and `flutter_litert`) on the GPU together: no corruption, no `CL_INVALID_COMMAND_QUEUE`, no jetsam | §8 assertion 3, plus memory snapshots | Inc 2 |
| Detector compiled and run inside a spawned worker isolate on iOS (FFI only; the Metal shim registers through `RTLD_DEFAULT`) | worker variant of the §8 test | Inc 2 / Inc 7 |
| Android 2.2.0 OpenCL/GL places all 411 ops (BATCH_MATMUL, 3-D TRANSPOSE/SLICE, RESIZE_NEAREST v3) | the same test on the first Android device | Inc 8 |
| Android GL/CL thread affinity with a Dart worker isolate, which is not pinned to one OS thread | 5-minute run on Android | Inc 8 |
| Real `camera` frame orientation and strides (iOS BGRA in portrait; Android NV21 at 720×480 vs 640×480) | log `width/height/bytesPerRow/pixelStride/rotation` once, plus the box overlay on a known object | Inc 7 |
| Watcher threshold 0.5 against real cups and phones at 0.5–2 m | manual run with a threshold sweep in the overlay | Inc 7 |
| Phone CPU fallback speed if the gate fails (`flutter_litert` CPU uses default threads, which cannot be changed) | §8 with `{cpu}` | Inc 2 |

## Appendix A — `prune_head.py` (Python, `ai-edge-litert` ≥ 2.1.5)

```python
from ai_edge_litert.tools import flatbuffer_utils as fu
import sys
m = fu.read_model(sys.argv[1]); sg = m.subgraphs[0]
names = [t.name.decode() if isinstance(t.name, bytes) else t.name for t in sg.tensors]
cut = next(i for i, n in enumerate(names) if n.endswith("head.Detect_23;45"))   # op 410 output
assert list(sg.tensors[cut].shape) == [1, 8400, 84]
last = next(k for k, op in enumerate(sg.operators) if cut in list(op.outputs))
sg.operators = sg.operators[: last + 1]; sg.outputs = [cut]; sg.tensors[cut].name = b"detections_raw"
for sd in m.signatureDefs or []:
    for o in sd.outputs: o.tensorIndex = cut; o.name = b"output_0"
for k, oc in enumerate(m.operatorCodes):            # shared ADD opcode is v4 only because of the int64 head
    if fu.opcode_to_name(m, k) == "ADD":
        assert all(sg.tensors[i].type == 0 for op in sg.operators if op.opcodeIndex == k for i in op.inputs if i >= 0)
        oc.version = 1                               # LiteRT 2.1.5 Metal accepts ADD <= v2
fu.write_model(m, sys.argv[2])                       # expect sha256 5ddd5eeb…ed80a for the fp16 package
```

## Appendix B — reproduce

```sh
cd ~/Work/models/yolo26n
.venv/bin/python inspect_model.py fp16/yolo26n_conv2d_f16_weights.tflite     # signature, op census, metadata
.venv/bin/python run_yolo26n.py fp16/samples/sample.jpg test_images/*.jpg    # preprocessing variants, annotated_*.jpg
.venv/bin/python bench_compiled.py cpu4|gpu|gpu_cpu_f32 ...                   # Arm files, CompiledModel 2.2.0
.venv/bin/python bench_rawhead.py gpu_f32 fp16 ; .venv215/bin/python bench_rawhead.py gpu_f32 fp16
.venv215/bin/python bisect_gpu.py fp16/yolo26n_conv2d_f16_weights.tflite    # finds the ADD v4 rejection
cd dart_probe && fvm flutter test test/probe_test.dart test/hostmem_test.dart test/create_time_test.dart
fvm dart compile exe bin/bench_pre.dart -o /tmp/bench_pre && /tmp/bench_pre  # Dart preprocessing (AOT)
```
