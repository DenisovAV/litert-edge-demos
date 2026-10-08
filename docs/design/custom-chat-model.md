# The chat model from a file (a tester's `.litertlm`, e.g. a Qualcomm NPU build)

Status: built 2026-10-06 (macOS-verified; NPU unverified until a Snapdragon device is available). Since
2026-10-07 (8b4ecb8) it is the **only** chat model: the app neither ships nor downloads one. Every other model
is built in (distribution.md, "Built-in models").
Goal: testers bring a Gemma `.litertlm` — compiled for their phone's Qualcomm NPU, or Gemma 4 E2B for the GPU —
and run it as the chat LLM of Demo 1 and Demo 3.

## Decisions

- **C1 One chat slot, filled from a file.** `ModelId.chat` is the chat slot. `ChatModelRepository` owns the
  choice and the settings (`TypedSettings` keys `chat.model` = `none|custom`, `chat.custom` = strict
  versioned JSON) and answers `ModelRepository` with a `ChatModelPlan`:
  - `NoChatModelPlan`: nothing chosen. The developer define `GEMMA_MODEL_PATH` loads with `kDefineChatModel`
    (Gemma 4 E2B's settings) when set; otherwise the slot is `ChatModelNotChosen` and the demos stay off with
    "No chat model yet: choose a .litertlm below".
  - `CustomChatPlan`: the verified path plus the saved settings. A chosen file wins over `GEMMA_MODEL_PATH`.
  - `ChatPlanBlocked(reason)`.

  The file comes from one of three sources (`CustomModelSource`):
  - `LocalModelSource`: used **in place**, no copy. It is a file in a models folder, or any path typed into
    **Path…**. The folders are listed on the card with **Copy the folder path** and **Rescan**
    (`ModelsFolder`, `defaultModelsFolders()`):
    - Android: `/sdcard/Android/data/<app id>/files/models` and `/data/local/tmp/litert-models`;
    - Linux: `~/litert-demos/models`;
    - macOS and iOS: the app's `Documents/models` (on iOS, visible in Files).
  - `ImportedModelSource`: desktop and iOS only. The file is cloned or copied into `<store>/custom/<name>`.
  - `UrlModelSource`: downloaded into `<store>/custom/<name>`.
- **C2 Never silently another model.** The slot fails with the reason (`ChatPlanBlocked`, which counts as
  present so setup shows it) in these cases:
  - the saved choice or settings cannot be read;
  - the file is missing, unreadable or changed (C13).

  The way out is on the card: pick the file again, choose another, or **Run on GPU / Run on CPU** after a
  failed load. Before the saved choice has been read, the slot is blocked rather than loading anything.
- **C3 Exactly the chosen backend.** `LlmService.load(ChatModelConfig)`:
  - **NPU gate first.** An NPU request where flutter_edge_ai would not offer the NPU fails before loading
    (`NpuUnavailableException`, with the package's own reason text). The gate is mirrored in
    `npu_availability.dart` from the litertlm package's `backend_preference.dart`.
  - **Load.** The package's prints during the build are captured in a zone. These are its fallback notices, the
    only place where a failed NPU attempt's reason shows up.
  - **Errors.** If `activeBackend` ≠ requested, the error is `BackendMismatchException`; a throw is
    `ChatModelLoadException`. Both name the model, the requested backend, and those native lines. The model is
    closed.
  - **After a failure.** The card offers **Run on GPU** and **Run on CPU** (`ChatModelAction`).
- **C4 Install type, not chat type.** The custom `ModelType` goes to `installModel` only. The native session takes
  its tool format from the installed type, so chats pass no `modelType`. Otherwise a Gemma 3 file installed as
  `gemmaIt` would silently lose its tools.
- **C5 Close before switching.** The package reuses a loaded model with the same file name and arguments (the
  path and type are not compared). So:
  - `LlmService.load` and `ModelRepository.reloadChatModel` close the old model first;
  - the open chat is released first (`ConversationRepository.release`).
- **C6 Capabilities.**
  - **Images off** (`supportImage: false` at load and in every chat):
    - Demo 1's photo buttons are disabled, with a label.
    - Demo 3's detailed path is disabled, with a label; detailed questions get the detection list instead
      (`DetailedUnavailable`).
  - **Tools off:**
    - Chats are plain, with `tools: const []`. `supportsFunctionCalls: false` alone would still send the
      declarations on `gemma4`.
    - Skills that need tool calls are disabled, with a label.
    - The app's direct intents (the time, device facts) keep working.
- **C7 Context.**
  - NPU: the value is passed through untouched. Bundles are compiled for one length (≤ 896 for 4-head
    Gemma 3, LiteRT-LM#3508).
  - GPU/CPU: ≥ 1024, which the engine would raise to anyway.
  - The defaults are in C12.
- **C8 Files.**
  - **Import** (desktop/iOS) clones or copies into `custom/<name>`, then computes and records the SHA-256.
  - **URL download** uses the store's resume, HTML check and verification. The tester may enter a size and a
    SHA-256; without a size, a one-byte Range probe finds it.
  - **Android import stays off.** `file_selector` reads the file into one Java `byte[]` (distribution.md).
    Android uses a models folder or the URL download.
  - **A file in place** must exist, be readable and start with the `LITERTLM` header. Its SHA-256 is computed in
    the background afterwards and never blocks a load. The plan checks its size; the load reads it.
  - **Replacing a file** keeps its settings. Review fixes (2026-10-06):
    - Apply compares the draft with what the chat slot runs (SHA-256 and settings). A replacement adopted while
      the old file runs can therefore be applied, and the card says the old one still runs.
    - The previous store file is kept while it may be running and pruned after the next reload
      (`pruneUnused`).
    - A link without a file name (Google Drive) is stored as `custom-model-<8 hex of the URL's SHA-256>.litertlm`,
      so another link never lands on the running file.
- **C9 Self-test.** The in-app **Run self-test** (Models screen) runs the CLI's runner:
  - It releases the chat and unloads the app's chat model.
  - It loads the active chat model on its backend, then reloads the app's model.
  - `--gemma-backend=npu` exists on the CLI. On desktop it fails with the gate's reason.

  Its model follows the app's precedence: an explicit `--gemma` (with Gemma 4 E2B's settings), else the chosen
  file with its saved settings (not overridden by `GEMMA_MODEL_PATH`), else `GEMMA_MODEL_PATH`, else "No chat
  model yet". The headless `--selftest` reads the settings and never writes them (C11).
- **C10 One owner of the engine (review, 2026-10-06).** `ChatModelSwitcher.exclusive` runs these one after the
  other:
  - reloads and unloads;
  - the whole self-test (unload → steps → reload);
  - each Apply / Run on GPU|CPU (choice and reload together);
  - the Models screen's setup.

  Its `busy` turns true at the call. Apply, Use this model, import, download, the setup after a download and Run
  self-test are all off while one runs, with no window after a tap.
- **C11 Upgrades from a build that downloaded Gemma (2026-10-07).** Earlier builds saved `chat.model = bundled`
  and kept the download at `<store>/gemma4E2b/gemma-4-E2B-it.litertlm`.
  - **Adopted in place.** It is adopted when three checks pass:
    - its length is the manifest pin's 2 538 799 104 B;
    - its `.sha256` record matches the pinned SHA-256 (`kRetiredGemma*` in `model_catalog.dart`);
    - its header reads.

    It becomes the chosen file (`LocalModelSource`, `Gemma 4 E2B`, type `gemma4`, GPU, 8192 tokens, images
    and tools on: the old built-in settings). The card says once: "Using the Gemma 4 E2B you downloaded
    earlier, where it is: the app no longer downloads it."
  - **Without a verified download**, the retired choice reads as none with a one-time note to choose a
    `.litertlm`, and `none` is saved.
  - The headless self-test (`persistMigration: false`) migrates in memory only. Its report shows the same
    model, and the app's settings stay as they were.
  - **Orphans: `pruneOldModelFolders`.** After a setup succeeds (`SetupViewModel` →
    `ProvisioningRepository.pruneOldModelFolders`, once per app run → `ModelStore.pruneOldModelFolders(keepPaths:)`),
    the store deletes the folders earlier builds downloaded models into. The list is fixed in the code, with no
    manifest read: one folder per `ModelId` (`<ModelId.name>/`) plus the retired `gemma4E2b/`
    (`kRetiredGemmaFolder`). Examples: the old Whisper, moonshine and embedder downloads.
    - A folder holding the chosen file (a file used in place there) is kept; `custom/`, `bundled/` and files at the
      store's root are never touched.
    - Nothing is pruned while the chat model is blocked (its file may be in one of them) or while a download or
      import runs.
- **C12 Defaults for a first file** (`defaultsFor`, from the device, the file name and, in place, the header):
  - **Backend:** the NPU where flutter_edge_ai offers it, but for a file in place only when the header marks an
    NPU build (`backend_constraint: npu`); otherwise the GPU.
  - **Type:** from the name (`modelTypeFromFileName`): `qwen3.5+` → qwen35, `qwen3` → qwen3, `qwen` → qwen,
    `functiongemma`, `gemma3` → gemmaIt, `gemma` → gemma4, then llama, phi, deepseek and hammer; anything else is
    gemma4.
  - **Context:** the length an NPU build's name announces (`…_ekv1280_…`). Otherwise 4096 on the NPU (the
    official Gemma 4 Qualcomm builds are compiled for 4096) and 8192 on GPU/CPU.
  - **Images:** on only when the header has a vision section.
  - **Tools:** on only for the Gemma types (`kToolsByDefaultTypes`: gemma4, gemmaIt). The file must be in place,
    with a header that was read, and not an NPU build. Other types, NPU builds ("NPU build → 4096, tools off")
    and files whose header was not read start off, until the tester knows the file has them.
- **C13 Missing is not denied.** `exists()` / `existsSync()` say false for a file the app may not search. The
  app therefore never asks them; it reads the error of the open (`inspectLitertlm`, with an injectable opener)
  or of the length (`_quickLocalProblem`, with an injectable length):
  - ENOENT → "… is not there any more (moved, renamed or deleted?)";
  - EACCES/EPERM → "… cannot be read (Permission denied)", plus the folder's advice. Android's own folder:
    "a folder or file pushed before the app created this folder belongs to the shell…", with the way out:
    launch the app first, or push to `/data/local/tmp/litert-models/`. This was measured on Test Lab with a
    Galaxy S26.

- **C14 A self-test that does not end keeps the engine (review, 2026-10-07).** The in-app run has a time limit
  (`SelfTestOptions.timeout`, 30 min by default). Past it, the report so far is shown, the runner is asked to stop
  and gets `kSelfTestStopGrace` (10 s) to close its own models. If it still has not ended:
  - the launcher is `stuck`: no other run starts until the app restarts;
  - when the runner may still hold its chat model engine (`SelfTestRunner.chatEngineMayBeLoaded`: its chat load
    started and that model was not closed), the app's chat model is not loaded again, because flutter_edge_ai holds
    one engine per process. `ChatModelOps.refuseLoads` → `ModelRepository.refuseChatModelLoads(reason)`: from then
    on `prepareAll` fails the chat slot and `reloadChatModel` refuses (`ChatModelBlockedException`), and the slot
    shows "the self-test is still running; restart the app before using the chat model" without a Retry;
  - when it hung before its chat load or after closing that model, the app's chat model loads again as usual
    (`kSelfTestStillRunningNoChatModel`).
- **C15 No release under a running reply (review, 2026-10-07).** `ConversationRepository.release()` refuses new
  opens, stops the turn and waits the stop timeout for it. A native turn that ignores the stop is still generating:
  the release fails with `ConversationNotReadyException` and closes nothing. `ChatModelSwitcher` then refuses the
  reload or unload with `ReplyStillStoppingException` ("The previous reply is still stopping; try again in a
  moment"), and the chat and the engine stay as they are: closing either under a running native generation is never
  safe. The Chat model card shows that text for Apply and Run on GPU|CPU (the old file still runs, nothing is
  pruned), and the in-app self-test returns it without unloading or loading anything.

## Unverified without a Snapdragon device

See the hand-off report. In short:
- Whether the bundled QNN stack loads the tester's build (SoC and Hexagon version).
- Whether `activeBackend == npu` means it runs on the HTP.
- How an NPU-only build behaves when its NPU attempt fails (it falls back to the GPU, then the CPU: three
  loads, or a crash).
- What `supportImage: true` does on a file without a vision section.
- `maxTokens` above the compiled length.
- The Gemma 3 NPU prefill-chunk drop.
