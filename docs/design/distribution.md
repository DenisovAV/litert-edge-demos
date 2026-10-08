# Distribution to testers: builds without models (Linux, Android, iOS)

**Removed on 2026-10-07:** the manifest download described here (the bundled and remote manifest, `MODEL_MANIFEST_URL`,
"Manifest URL…", "Download all" and import for manifest models); the model store now holds only the custom chat model.

Status: plan, 2026-10-05; Phase A built the same day. **Superseded in part on 2026-10-06/07** (user decisions): every
model but the chat model is now built into the app, and the chat model comes only from a file the tester chooses
(custom-chat-model.md). Nothing is downloaded on first launch. See "Built-in models" below; the original goal was to
hand testers one build per platform that **contains no models**, with models on Google Drive and/or Hugging Face.

## What the app did on 2026-10-05 (gap analysis, historical)

| Model | How it is found today | Problem for a tester build |
|---|---|---|
| Gemma 4 E2B (2.6 GB) | `GEMMA_MODEL_PATH` (compile-time) → `fromFile`, else `fromNetwork(HF)` | path is baked at build time; no Drive; no checksum |
| Whisper base / moonshine-tiny | `modelFromNetwork(HF)` only | no local/Drive option |
| Inflect-nano-v2 (TTS) | `fromNetwork(baseUrl)` only — flutter_gemma 1.11.3 has no file installer (upstream U2) | must stay on a path-structured host (HF) |
| EmbeddingGemma-300M | `EMBEDDING_MODEL_DIR` (compile-time) or gated HF + token | token in the binary; dir baked at build time |
| YOLO26n raw-head (derived) | `DETECTOR_MODEL_PATH` (compile-time) only | no download at all → Demo 3 unavailable (since 2026-10-06: built in, see "Bundled models") |

Other gaps:
- **Backends are compile-time.** Gemma is GPU-only (`kLlmConfig`); the detector's CPU mode is a dart-define. On an
  unknown tester machine (Linux without Vulkan, weak phone GPU) the app just fails.
- **No Linux platform** (`linux/` runner missing). Plugins: all key ones support Linux (flutter_gemma family,
  flutter_litert, record, flutter_soloud, image_picker, flutter_scene, camera_desktop); **`audio_session` has no
  Linux implementation** (needs a no-op path); `flutter_inappwebview` has none (unused: JS skills only).
- **No persisted settings** (`shared_preferences` not a dependency).
- **Release signing:** Android release uses debug keys; iOS/macOS signing not set up for distribution.
- **No tester docs** (install + models + troubleshooting).

## Decisions (defaults; change before Phase A lands if needed)

- **D1 Manifest-driven models.** A versioned JSON manifest lists every model: id, files (name, url, size, sha256),
  required flag. Per file the URL can be Hugging Face or a Google Drive direct link
  (`https://drive.usercontent.google.com/download?id=<ID>&export=download&confirm=t`). Default split: public large
  models from HF (no quota), **Drive for the derived YOLO26n file and EmbeddingGemma** (gated on HF). All-Drive works
  by editing the manifest, with Drive's per-file download-quota risk for the 2.6 GB file.
- **D2 Where the manifest lives.** A copy is bundled (`assets/models/manifest.json`); an optional remote override URL
  (`--dart-define=MODEL_MANIFEST_URL`, plus a field in Settings) lets us change links without rebuilding.
- **D3 TTS exception.** Inflect keeps flutter_gemma's network installer from an HF base URL (no file installer).
- **D4 Local import.** "I already downloaded them": desktop picks a folder (macOS: copy into the app container
  because of the sandbox; Linux: use in place), Android/iOS import files and copy into app storage. Every file is
  verified (size + sha256) before use.
- **D5 Dev overrides stay.** If a `*_MODEL_PATH` / `EMBEDDING_MODEL_DIR` dart-define is set, it wins (dev loop
  unchanged).
- **D6 Runtime backend choice.** GPU by default; when a GPU load fails the setup row shows the error with an explicit
  **"Use CPU (slower)"** action, persisted per device and labelled in the UI/overlay (AGENTS.md rule 2: explicit,
  never silent).
- **D7 Linux x86_64**, built on Linux (no cross-compile from macOS): podman `--platform linux/amd64` locally or a CI
  runner; shipped as a `tar.gz` bundle (+ AppImage later). Requires a Vulkan driver for Gemma on GPU, CPU mode
  otherwise.
- **D8 Android:** release keystore (not committed), arm64 APK via Firebase App Distribution or a link.
- **D9 iOS:** TestFlight preferred (internal testers, no review) else ad hoc via App Distribution; **iOS 26+** until
  the flutter_inappwebview dyld issue is fixed upstream.

## Phases

**Phase A — Model provisioning (start now; macOS-testable).**
- `ModelManifest` (parse + validate), bundled manifest + optional remote override.
- `ModelStore` in app support `models/`: download with HTTP Range resume, progress, size + sha256 verification,
  atomic rename, free-space check, Drive interstitial detection (HTML instead of bytes → clear error), cancel.
- Local import (desktop folder / mobile files) with verification.
- Services install from `ModelStore` paths (`fromFile` / `modelFromFile` / `tokenizerFromFile`); TTS stays network.
- Setup screen "Models": per-model rows (size, status, %, error, retry), "Download all", "Import…", total size and
  free space, Wi-Fi note; models already present skip straight to home.
- `shared_preferences` for settings (manifest override, backend choices; later the avatar toggle).
- Tests: manifest parsing, resume/verify/corrupt/interstitial with a fake HTTP server, import, setup VM; integration
  test on macOS downloading the small models from a local HTTP server and Gemma from a local file.

**Phase B — Runtime backend choice (D6).** Gemma + detector GPU/CPU at runtime, persisted, labelled.

**Phase C — Linux.** `flutter create --platforms=linux .`, audio_session no-op on Linux, camera_desktop/record
checks, Vulkan check + CPU path, build container/CI, `tar.gz` packaging, run on a real Linux GPU machine.

**Phase D — Android release.** Keystore + signing config, versioning, App Distribution upload script, FTL smoke via
`tool/run_android_ftl.sh` adapted to provisioning, a real-device run.

**Phase E — iOS.** Team/profile with the memory entitlement, TestFlight or ad hoc, Files import of models, device run.

**Phase F — Tester package.** Drive folder layout + `SHA256SUMS`, `docs/testers.md` (install per platform, models,
requirements, troubleshooting), manifest pointing at the Drive files.

## Phase A as built (2026-10-05)

**Code, then.** `assets/models/manifest.json` (schema 1) → `ModelManifest.parse` (strict: every problem reported) →
`ProvisioningRepository` (manifest source, presence, Download all plan) over `ModelStore` (files) and
`TypedSettings` (`SharedPreferencesAsync`, keys `app.*`). `ModelRepository` asked the store for verified paths
(`ModelFileLookup`); the Models screen (`SetupViewModel`/`SetupScreen`, `/` and `/models`) drove it all.

**Code now** (2026-10-08): the manifest, `ModelManifest`, `ModelFileLookup` and Download all are gone. Every model
but the chat model is built into the app (`assets/models/`, fetched by `tool/fetch_models.sh` from
`tool/models.lock`); the chat model is the tester's own `.litertlm` (`ChatModelRepository`,
custom-chat-model.md); `ProvisioningRepository.presenceOf` reports what is there by the rule below. The
**Manifest** and **Gemma pin** paragraphs further down describe the retired manifest.

**Where a model comes from** (one rule, `ModelSourceResolver` in `lib/domain/models/model_source_resolver.dart`,
which `ModelRepository`, `ProvisioningRepository.presenceOf`, the Chat model card and the self-test all ask; as of
2026-10-08):
- **The chat model:** the tester's chosen `.litertlm` (custom-chat-model.md), or its blocked choice, which never
  falls back to another file → with nothing chosen, `GEMMA_MODEL_PATH` (run with Gemma 4 E2B's settings,
  `kDefineChatModel`) → nothing ("No chat model yet"). A chosen file wins over the define.
- **The detector and the embedder:** their define (`DETECTOR_MODEL_PATH`, `EMBEDDING_MODEL_DIR`) → the files built
  into the app.
- **Whisper, moonshine and Inflect:** always the built-in files (they have no define).

On 2026-10-05 the rule was a developer define → verified store files → missing; the store now holds only the chat
model's file, and no model needs a Hugging Face token. flutter_gemma loaded the active spec's `FileSource` path
(`getModelFilePaths`), so an older registration of the same file name did not redirect it.

**Dev-loop change** (superseded 2026-10-07: both are built in): Whisper and moonshine had no define, so they came from
the store too: run the app once and press Download all (~190 MB) before the other integration tests.

**Manifest.** Per model `id`, `required` (must equal the build's), `files[]` with `role` (model/tokenizer),
`name` (unique: one flat import folder), `url` (https; http only for loopback), `sizeBytes`, `sha256`; Inflect is
`"source": "network-installer"` with `baseUrl` + `approxBytes`. Keys starting with `_` are comments; any other unknown
key fails. A URL containing `REPLACE_ME` is a placeholder: import-only. Sources: saved URL (Models screen) >
`MODEL_MANIFEST_URL` > bundled; a remote manifest that cannot be fetched uses its last saved copy with a warning,
otherwise fails with Retry and an explicit "Use the bundled manifest" (this session only).

**Gemma pin.** The manifest pins the bytes every measurement here used: HF rev `a039dc0b`, file
`gemma-4-2p3b-it.litertlm` (2 538 799 104 B, sha256 `2c902a8c…587a`), stored as `gemma-4-E2B-it.litertlm`. HF `main`
now has a different `gemma-4-E2B-it.litertlm` (2 588 147 712 B, sha256 `18193810…a63c`, uploaded 2026-05-04);
switching = edit the entry and re-measure. Since 2026-10-07 the manifest lists no Gemma: the pin (`kRetiredGemma*`)
only recognizes an earlier build's verified download, which is adopted in place as the chat model
(custom-chat-model.md C11).

**Store.** `<app support>/models/<id>/<name>`; downloads to `.part` (Range resume across manual redirects, each
checked: HTTP(S) only, never HTTPS down to HTTP; 3 attempts per file, 30 s stall watchdog, cancel), imports to `.import`; size + SHA-256 in a worker isolate; on a
checksum mismatch the bytes are deleted (resuming them could never fix it), on network/disk-full/cancel the part is
kept. Verified files get a `.sha256` record (written after the rename), so a relaunch hashes nothing. HTML instead
of bytes (Drive virus-scan or quota page; by Content-Type or by sniffing) fails with "download it in a browser, then
Import". Import: desktop folder (name, then exact size; links followed), iOS files (the picker's temp copies are
moved); APFS `clonefile` on macOS/iOS (instant, no extra disk), otherwise a hashing copy; the mtime is kept so
LiteRT-LM's GPU program cache (`<name>_<mtime>_<size>`) is reused. Linux copies too (one code path; the original can
be deleted after).

**Not done / limits.** No free-space pre-check (`dart:io` has none; disk full is caught at write time, ENOSPC). Android
import is off: `file_selector_android` 0.5.2+11 reads a picked file into one int-sized Java `byte[]` (overflows at 2 GB)
→ needs a native SAF stream copy (Phase D, android-coder). iOS: Application Support is backed up; exclude
`models/` from iCloud backup in Phase E. iOS/Android import and download are unit-tested only.

**Verified on macOS** (M4 Pro, debug, `integration_test/model_provisioning_test.dart`, deleted with the manifest in
68d2ef8; `build/dist-a-logs/`): empty store → Gemma imported from `~/Work` by APFS clone + SHA-256 in 16.4 s →
Download all of the other 7 files from a local server in 7.0 s, the moonshine model dropped at 33 MB and resumed with
`Range: bytes=33000000-` → 8 files verified → setup 10.3 s (Gemma loaded from the store path on the GPU in 3.1 s,
reusing the existing program cache) → home with both tiles ready. `PROVISION downloaded=7 imported=1 verified=8
resumed=1 total_ms=36573`.

**To upload to Drive** (then replace each `REPLACE_ME` with the file id):

| File | Bytes | SHA-256 |
|---|---|---|
| `yolo26n_fp16_rawhead.tflite` | 10 361 332 | `5ddd5eebad18587d56500a30b0995c07c9e1a241640750f568e4a974f66ed80a` |
| `embeddinggemma-300M_seq512_mixed-precision.tflite` | 179 132 472 | `ad09e81557203cb0e177abf9bf8727dfe138a7d394aa0f70f0b2ed16432e121a` |
| `sentencepiece.model` | 4 683 319 | `d6daa52d93d7aad10e8388bd526c4e501d914b47177398d1d9621f1fe48438c7` |

## Built-in models (2026-10-06/07, user decisions)

**Not in git since 2026-10-08 (user decision):** `tool/fetch_models.sh` fetches every built-in file into
`assets/models/` from `tool/models.lock` (repo, commit, size, SHA-256) before a build; only `NOTICE.md` is tracked.

**Where every model comes from now:**
- **Built in** (assets, nothing to download): YOLO26n, EmbeddingGemma with a prebuilt knowledge-base index
  (inc4-5-images-rag-wiring.md), and since 2026-10-07 (8b4ecb8) Whisper base, moonshine-tiny and Inflect-nano-v2.
- **From a file:** the chat model only (custom-chat-model.md): a `.litertlm` in a models folder or at any
  path, imported (desktop/iOS) or downloaded from a link the tester enters.
- There is no model manifest any more (removed 2026-10-07, see the top): the Models screen shows the five as
  "Built in" rows, with nothing to download or import. After the first successful setup,
  `ProvisioningRepository.pruneOldModelFolders` deletes the store folders earlier builds downloaded models into
  (the old Gemma, Whisper, moonshine and embedder downloads), keeping a folder that holds the chosen chat model
  (custom-chat-model.md C11).

**YOLO26n is built into the app.** The derived `yolo26n_fp16_rawhead.tflite` is a Flutter asset at
`assets/models/`: 10 361 332 B, sha256 `5ddd5eeb…ed80a`.
- **Git.** Not in git since 2026-10-08: `tool/fetch_models.sh` derives it from Arm's file (pinned ai-edge-litert).
- **Licence.** It is AGPL-3.0, derived by `tool/prune_yolo26n_head.py` from `Arm/yolo26n-fp16-litert`.
  - Notice: `assets/models/NOTICE.md`.
  - In-app entry: `registerModelLicenses`, under Home › More › Licences.
- **Loading.** The detector reads the bytes from the asset bundle on the main isolate and moves them to
  its worker as `TransferableTypedData`. `CompiledModel.fromBuffer` then loads them, with no copy on
  disk. The size check (`kDetModelBytes`) and the strict GPU load are unchanged.
- **Precedence.** `DETECTOR_MODEL_PATH` wins; otherwise the asset.
- **Models screen.** A "Built in" row, with nothing to download or import (on 2026-10-06 the manifest listed
  it as `"source": "bundled"`; the manifest is gone since 2026-10-07).
- **Demo 3.** It still needs the detector *loaded*, not downloaded.
- **Self-test.** Without `--detector` it uses the asset (`detector (bundled)` in the report).

**EmbeddingGemma is built in** (the same day): `embeddinggemma-300M_seq512_mixed-precision.tflite` (179 132 472 B)
and `sentencepiece.model` (4 683 319 B).
- **Git.** Not in git since 2026-10-08: `tool/fetch_models.sh` fetches both (gated: `HF_TOKEN`).
- **Licence.** Gemma Terms of Use, redistributed unmodified with the notice: `NOTICE.md` and the in-app licence
  entry.
- **Loading.** flutter_gemma's embedder installs from files, so the app resolves real paths
  (`BundledModelFiles`).
  - **Desktop and iOS:** the assets are plain files in the app bundle, found from `Platform.resolvedExecutable`
    and used in place.
    - macOS: `Contents/Frameworks/App.framework/Resources/flutter_assets`.
    - iOS: `Frameworks/App.framework/flutter_assets`.
    - Linux: `data/flutter_assets`.

    They are checked by size; the bundle is signed.
  - **Android:** the assets live inside the APK, stored uncompressed (`noCompress` for `tflite` and `model`).
    Each is extracted once into `<store>/bundled/`:
    - a streaming copy with large_file_handler (`AssetManager.open` on `Dispatchers.IO`) to `.extract`;
    - the SHA-256 checked in an isolate;
    - an atomic rename and a `.sha256` record, so later launches skip the copy;
    - an interrupted copy is started again and never used.
  - flutter_gemma's `modelFromAsset` would copy on every platform (into memory first on desktop) and verify
    nothing (`asset_source_handler.dart:44-71`).
- **Precedence.** `EMBEDDING_MODEL_DIR` wins; otherwise the built-in files. No download, no token.
- **Models screen.** A "Built in" row.

**Speech is built in** (2026-10-07):
- **Files.**
  - Whisper base: `whisper_base_30s_i8.tflite`, 77 MB, plus its tokenizer.
  - moonshine-tiny: `moonshine_tiny_5s_f32.tflite`, 109 MB, plus its tokenizer.
  - Inflect-nano-v2's bundle: six files, 34 MB, under `assets/models/inflect/` (the two Inflect models and
    the four Matcha G2P files it reuses).
  - Licences are in `NOTICE.md` and the in-app list.
- **Loading.** The same `BundledModelFiles` as the embedder: in place on desktop and iOS, extracted once and
  verified on Android.
  - The recognizers install with `modelFromFile`.
  - Inflect installs with `installTts().fromFile(<directory>)`. flutter_edge_ai 2.1.0 has the file installer
    that flutter_gemma 1.11.3 lacked (D3/U2), so no TTS bytes come from the network.
- **Failures.** A built-in speech file that cannot be found, extracted or verified (`BundledFileException`)
  fails its row with Retry (`ModelFailed`), even for the optional moonshine (3b94f8d): a broken build or a
  full disk is not "not provisioned". `ModelUnavailable` stays for `ModelNotProvisionedException`.

## Open questions (defaults in parentheses)
1. Testers: how many, inside our Apple team? (internal TestFlight if yes, else ad hoc)
2. Linux: distro and GPU of the testers; a Linux GPU machine for verification? (Ubuntu 24.04 x86_64, Vulkan)
3. Hosting split: HF for big public models + Drive for the rest, or all on Drive? (split, D1)
