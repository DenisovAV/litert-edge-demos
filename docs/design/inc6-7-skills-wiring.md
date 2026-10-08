# Inc 6–7 — agent skills from Markdown and CameraWatcher (wiring spec)

Status: spec, 2026-10-02 (`flutter-gemma-expert`), from `~/.pub-cache`: flutter_gemma 1.11.3, flutter_gemma_agent
0.2.6 (`lib/src/`), flutter_gemma_litertlm 1.8.5 ("ffi" = `src/ffi/ffi_inference_model.dart`). Amends
`demo1-voice-chat.md` §3.2, Inc 6–7, D12–D15.

> **2026-10-06:** the camera watcher (Inc 7) and the timer skill were removed; the sections about them are history.
> What stands: §1–§2 (skills on `AgentSession`, runtime loading and Reload), the executor and the steps panel. See
> the amendment at the top of [demo1-voice-chat.md](demo1-voice-chat.md).

## 1. ConversationRepository on AgentSession

Skills arrive through `open`:

```dart
final class const ConversationProfile({required final String name, required final String systemInstruction,
  required final int maxOutputTokens, final String? skillsTemplate}); // contains __SKILLS__
Future<Result<void>> open(ConversationProfile profile, {List<Skill> skills = const []});
Stream<AssistantEvent> ask(String prompt, {Uint8List? image});
```

Agent path iff `skillsTemplate != null && skills.isNotEmpty`. `kCameraProfile` has no template, so Demo 3 stays
plain. `reset(ifCurrent:)` reuses the current skills; `_OpenRequest` carries them. Build in `_rebuild` with the
constructor (`fromModel` defaults `topK: 1, temperature: .8`, `agent_session.dart:133-135`):

```dart
final registry = SkillRegistry()..addAll(skills, selected: true); // default false → empty list (skill_registry.dart:25-29, :84-88)
final chat = await model.createChat(temperature: _sampler.temperature, topK: _sampler.topK, isThinking: kThinking,
  maxOutputTokens: profile.maxOutputTokens, tools: const [loadSkillTool, runIntentTool],
  supportsFunctionCalls: true, toolChoice: ToolChoice.auto, modelType: ModelType.gemma4, supportImage: true,
  systemInstruction: AgentSession.buildSystemPrompt(registry, systemPromptTemplate: profile.skillsTemplate!));
final agent = AgentSession(chat: chat, registry: registry, executors: [appIntents, TextSkillExecutor()], maxIterations: 5);
```

`maxIterations` counts generations (`chat.dart:806`). Explicit executors bypass the global registry
(`agent_session.dart:27-28`). Template:

```
You are a helpful on-device voice assistant. Replies are read aloud: a few short sentences, plain text.
If the request matches one of these skills, call loadSkill with its name, then follow its instructions:
__SKILLS__
Otherwise answer directly without calling any tool.
```

**ask** → `agent.ask(prompt, imageBytes: image, isCancelled: () => turn.cancelled)` (`agent_session.dart:180-189`):

| AgentEvent | AssistantEvent → ChatTurnResponder |
|---|---|
| `TextChunkEvent` | `AssistantTextDelta` → spoken |
| `SkillLoadEvent` | `AssistantSkillStep(SkillLoaded)` → `onSide(ChatSkillStep)` |
| `ToolCallEvent` | `…(IntentCalled(intent, parameters))` |
| `ToolResultEvent` | `…(IntentSucceeded)` / `…(IntentFailed)` |
| `AgentErrorEvent` | `IntentFailed`, unless it duplicates an `ErrorResult` (`agent_loop.dart:379-382`) |
| `MaxIterationsEvent(n)` | `AssistantFailed(SkillLoopException(n))` → `TurnFailed` |
| end without `DoneEvent` | `AssistantDone(stopped: true)` |
| stream error (`agent_loop.dart:160-169`, `chat.dart:820-858`) | `AssistantFailed` |

A Gemma 4 tool-call turn is pure JSON and is swallowed (`chat.dart:331-347`): nothing is spoken before the final
answer, so first audio comes after three generations. `GenerationMetrics` gains `toolRounds`.

**Stop**
- `stop()` sets the per-turn latch and calls `chat.stopGeneration()`. Mid-generation, partial tool-call JSON leaks
  as text (`chat.dart:630-635`); the drain drops it. Mid-executor, the tool finishes and core answers pending calls
  `cancelled` (`:807`, `:864-884`).
- **Cancelling the `agent.ask` subscription only sets a flag** (`agent_loop.dart:235`); native generation goes on.
  VoiceSession cancels after its 5 s drain, so `ask` listens internally, never cancels, calls `stop()` on an
  outer cancel, and holds `isGenerating` until the inner stream closes.
- **Stale tool tail:** a stop right after `SkillLoadEvent`/`ToolResultEvent` leaves a staged tool response that
  litertlm prepends, as text, to the next user message (ffi:`449-463`, `:485`). Rebuild the chat before the next
  `ask` (history lost, logged).
- After a stop, history replays as text, with tool rounds (ffi:`716-725`); images need the Inc 4 re-send.

## 2. SKILL.md format

- **Front matter:** `name` and `description` are required; optional `metadata.{homepage, require-secret,
  require-secret-description}`; other keys are ignored. Quote values containing `:` or `#`.
- **Type** comes from the first substring match in the body: `run_js`, `run_intent`, `run_mcp`, else textOnly
  (`skill_md_parser.dart:90-96`). `loadSkill` returns the whole body (`agent_loop.dart:448-450`).
- **`parseSkillMd(String)`** throws `SkillMdParseException(List<String> errors)` when the fence or a field is
  missing (`:48-70`). `name: 123` throws `TypeError` (`:60-61`), so catch `Object`.
- **`SkillRegistry`:** `add/addAll({selected = false})`, `remove`, `select/unselect`, `isSelected`, `all`,
  `getSelected()` (there is no `selected` getter), `clear()`. `get` normalizes case and `_`→`-` and ignores
  selection (`:58-66`). A new skill set needs a new chat.
- **Intents:** `runIntent(intent, parameters)` reaches the executor as `Skill(name: intent, type: intent)` plus
  `dataJson = parameters` (`agent_loop.dart:400-423`).
  - If the model adds a `skillName` that resolves, the registered skill is passed instead (`:332-333`, `:361`).
  - An object `parameters` arrives as Dart `{seconds: 10}` (`:453-457`).

### 2.1 Seed skills (`assets/skills/<name>/SKILL.md`; list each folder in `pubspec.yaml`)

```markdown
---
name: timer
description: "Start, cancel or list countdown timers, for example: set a timer for 10 minutes."
---
# Timer

## Instructions
Call the `run_intent` tool. Copy the numbers the user said; never convert units yourself.

Start: intent `start_timer`, parameters a JSON string with
- hours, minutes, seconds: whole numbers, each optional, at least one above 0
- label: optional short name such as "tea"
Cancel: intent `cancel_timer`, parameters {"label": "<name>"}, {"label": "all"}, or {} when one timer runs.
List: intent `list_timers`, parameters {}.

Examples:
- "Set a timer for 10 seconds" → start_timer {"seconds": 10}
- "Pasta timer, an hour and 5 minutes" → start_timer {"hours": 1, "minutes": 5, "label": "pasta"}

Then repeat the result to the user in one short sentence.
```

```markdown
---
name: device-info
description: Say which models, backends and accelerators this app is running and how much memory it uses.
---
# Device info

## Instructions
Call the `run_intent` tool with intent `device_info` and parameters {}.
Answer only from the returned facts, in at most three short sentences. Never guess hardware details.
```

```markdown
---
name: current-time
description: Get the current local time, date and day of the week.
---
# Current time

## Instructions
Call the `run_intent` tool with intent `current_time` and parameters {}.
Then tell the user the time from the result in one short sentence.
```

```markdown
---
name: camera-watch
description: Watch the camera and announce when an everyday object such as a person, cup, dog or phone appears, or stop watching.
---
# Camera watch

## Instructions
Start: call the `run_intent` tool with intent `watch_camera` and parameters a JSON string with
- label: the object in plain English, singular, e.g. "cup", "person", "dog", "phone"
- min_score: optional, 0.3 to 0.9; leave it out unless the user asks
Stop: call the `run_intent` tool with intent `stop_watching` and parameters {}.
After starting, say in one sentence what you are watching for; the app announces sightings.
If the result is an error, tell the user what it says.
```

Runtime-only example (never bundled):

```markdown
---
name: tea-timer
description: Start a three-minute tea timer when the user asks for a tea timer or says their tea is brewing.
---
# Tea timer

## Instructions
Call the `run_intent` tool with intent `start_timer` and parameters {"minutes": 3, "label": "tea"}.
Then say in one sentence that the tea timer is running.
```

## 3. AppIntentExecutor (`domain/skills/app_intent_executor.dart`)

Contract `skill_executor.dart:28-63`. Results become `{result|error, status}` (`agent_loop.dart:427-445`); throws
are caught (`:373-377`).

```dart
final class AppIntentExecutor extends SkillExecutor {
  AppIntentExecutor(Map<String, AppIntentSpec> intents); // keys == AppIntent.all
  @override String get name => 'AppIntentExecutor';
  @override int get priority => 10; // probe order: descending priority (agent_loop.dart:81-89)
  @override bool canExecuteSkill(Skill s) => s.type == SkillType.intent; // type ONLY: core probes a type-only Skill (:42-45)
  @override Future<SkillResult> execute(Skill skill, String dataJson, {String? secret}); // TextResult | ErrorResult
}
```

- **Not `NativeIntentExecutor(handlers:)`:** its `validateIntentParams` (`native_intent_executor.dart:153`) returns
  `'unknown intent.'` from `default:` (`:528-529`) for every custom handler.
- **Resolve:** `skill.name`, lowercased, `-`→`_`. Fall back to `{"intent","parameters"}` inside `dataJson`. A
  registry skill name or an unknown intent → `Call run_intent with intent set to one of: <AppIntent.all>`.
- **Parse/validate:** `''` → `{}`; numeric strings coerced; a Dart-map value → `parameters must be a JSON string,
  e.g. {"minutes": 3}`. Never throw; each `ErrorResult` says how to retry.

| Intent | Params | Result (numbers as words) |
|---|---|---|
| `start_timer` | `hours/minutes/seconds` ≥0, total 1 s–24 h; `label` ≤40 | `Started the "tea" timer for three minutes.` |
| `cancel_timer` | `label`, `all`, or absent (one timer) | `Cancelled the "tea" timer.`; ambiguous → error listing timers |
| `list_timers` | — | `Two timers: "tea", two minutes left; …` |
| `watch_camera` | `label` via `kCocoVocabulary.resolveNoun`; `min_score` 0.3–0.9 (0.5) | `Watching the camera for a cup.`; unknown label, no detector or no camera → error |
| `stop_watching` | — | `Stopped watching for a cup.` |
| `device_info` | — | loaded models, LLM `activeBackend`, `DetectorInfo.label`, RSS |
| `current_time` | — | `It is 2:03 PM on Thursday, October 2, 2026.` |

## 4. Runtime skill directory (D12) — `SkillStoreService`

| Platform | Directory | Add without a rebuild |
|---|---|---|
| macOS | Documents`/skills` | `cp -r tea-timer ~/Library/Containers/dev.fluttergemma.litertHackathon/Data/Documents/skills/` |
| iOS | Documents`/skills` | Files app; add `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` (missing) |
| Android | `getExternalStorageDirectory()`(nullable)`/skills` | `adb push tea-timer /sdcard/Android/data/dev.fluttergemma.litert_hackathon/files/skills/` |

- **Seed:** from `AssetManifest.loadFromAssetBundle(rootBundle).listAssets()`, copy each `assets/skills/*/SKILL.md`
  whose folder is absent. A `.seed-version` hash covers app updates.
- **Scan:** `skills/*/SKILL.md` and `skills/*.md`. A parse error, `TypeError`, bad UTF-8, a file over 32 KB, a
  duplicate name or an unknown intent becomes `SkillLoadError(path, message)`. The Skills sheet lists them; the
  overlay shows `skills 5 ok / 1 error`.
- **Rescan** on Reload and on `resumed`. Apply only when changed and idle: `open(kVoiceChatProfile, skills:)`, which
  drops history (the UI says so).

## 5. Timers (D14) and announcements

- **`TimerRepository`** (app-scoped):
  - API: `start(Duration, {label})`, `cancel(label)`, `active`, `Stream<TimerFired> fired`; ≤10 timers.
  - **"Now" is the app's injected `DateTime.now()` when the intent executes**, never the model's. Release time
    would fire a 10 s timer about 3 s after the confirmation.
  - A Dart `Timer` wakes each deadline; deadlines are re-checked on `resumed` (iOS suspends Dart timers).
- **`AnnouncementHub`** merges `fired` and `CameraWatcher.sightings` as `Announcement(key, text, ttl)`:
  `Your tea timer is done.` (2 min), `I can see a cup.` (5 s). It buffers ≤3 while nobody listens.
- **`VoiceAssistant(announcements:)`:**
  - Queue ≤3; same key replaces; oldest overflows; expired skipped.
  - Speaks only when idle/error: `SpeechRepository.synthesize(text)` (new; refused during a turn) → playback →
    `Announced(text)`.
  - Mic-down, Send and Stop silence it and drop it. New conversation clears the queue.

## 6. CameraWatcher (Inc 7, `domain/use_cases/camera_watcher.dart`, app-scoped)

```dart
CameraWatcher({required LiveDetectionRepository live, CocoVocabulary vocab = kCocoVocabulary, DateTime Function() now = DateTime.now});
ValueListenable<WatchSpec?> get watching;  Stream<Announcement> get sightings;
Future<Result<WatchSpec>> watch(String label, {double minScore = 0.5});  Future<void> stop();
```

- **watch:** resolve the label; fail if `live.detectorInfo == null`; `live.start(spec, owner: this)`, whose failure
  is the intent's error. One watch at a time.
- **Rule** per new `frameId`: **2 consecutive hits** (class `cls`, score ≥ `minScore`), armed, ≥10 s since the last
  sighting → `I can see ${vocab.withArticle(cls)}.` and disarm; **2 misses re-arm** (an object in view is announced
  once).
- **Pause:** `GpuArbiter` pauses detection during generation; streaks reset on `LivePaused`. Rate stays 15 fps
  (constructor-fixed): 2 frames ≈ 133 ms.
- **Lifecycle:**
  - `VoiceChatViewModel.dispose()` → `watcher.stop()` (the owner token), serialized before Demo 3's `start`.
  - A ≈160×120 PiP (`LivePreview` + `DetectionPainter(mirror: false)` + state chip) shows while watching; the chat
    camera then uses `capture()` + `encodeForLlm()`.
- **macOS** works via camera_desktop; black frames (TCC attributed to the terminal) show a warning. **iPhone:**
  GPU coexistence unverified until Inc 2. **Android:** untested.

## 7. GPU fp16 digits (LiteRT-LM#3012 Adreno, #2814 Metal)

- **Risk:** fp16 miscopies digits from long prompts (`core/domain/platform_types.dart:40-50`).
- **Mitigations:** no unit conversion by the model; numbers as words in results; args visible in the panel.
- **Detect:** a digit golden in `skills_test` (10 s, 17 s, 90 s, 25 min, 1 h 5 min).
- **Decision:** keep fp16 (the model default) unless the golden fails on macOS or iPhone. Then add
  `activationDataType: ActivationDataType.float32` to `LlmConfig`/`getActiveModelFor`:
  - The `activeBackend == gpu` check catches the silent CPU fallback.
  - Re-measure TTFT: prefill is <1.5× slower on an M3 Max and ≈3× on phones (inference skill); the GPU cache
    recompiles once.
- **Not measured here** (the local Python litert_lm 0.15 has no Metal accelerator): run `skills_test` with
  `LLM_ACTIVATION=fp32`.

## 8. Tests

**Unit**
- **Bundled skills:** every `assets/skills/*/SKILL.md` parses, `name` == folder, intents ⊆ `AppIntent.all`, folder
  listed in `pubspec.yaml`.
- **Executor:** type-only probe; `{"minutes":3}` → 180 s; `"10"` coerced; a retryable `ErrorResult` for a Dart
  map, an unknown intent, a skill name, 0 s or 25 h, and a throwing handler.
- **Store:** seeding keeps edits; bad files listed.
- **Timers and queue** (`fake_async`): fire, cancel, resume; idle-only, ≤3, coalesced, TTL, mic-down.
- **Watcher** (fake `frames`): 1 hit → nothing; 2 → one; repeated `frameId`s; cooldown; re-arm; pause; owner stop.
- **Repository:** an injectable `AgentRunner` with scripted events covers mapping, dedupe and MaxIterations; an
  outer cancel → `stopGeneration` with `isGenerating` held; the stale tail.

**Integration** (`$M` as in demo3 §8)
- `skills_test.dart -d macos $M`, which prints `SKILLS act=fp16 digits=5/5 skill_ttfa=… announce_lag=…`:
  1. "Set a timer for 10 seconds" → `SkillLoaded(timer)`, `start_timer` = 10 s, a reply, and an announcement
     10–14 s later.
  2. The digit golden.
  3. Write `tea-timer`, Reload, then "Start the tea timer" → 180 s.
  4. A malformed file is listed.
  5. `current_time` works; `device_info` contains `GPU`.
- `watcher_test.dart -d macos $M --dart-define=FRAME_SOURCE=fixture --dart-define=FIXTURE_DIR=…/coco30`: "Tell me
  when you see a cat" → "I can see a cat." ≤2 s after the turn.

## 9. Pitfalls and upstream bugs (write-ups for the maintainer)

| # | Finding | Where |
|---|---|---|
| U-A1 | Map/List args are stringified with `toString`, not `jsonEncode` | `agent_loop.dart:453-457` |
| U-A2 | Custom `NativeIntentExecutor` handlers always fail validation | `native_intent_executor.dart:153`, `:528-529` |
| U-A3 | A cancelled tool round's staged response is prepended to the next user message | `chat.dart:864-884`; ffi:`449-463`, `:485` |
| U-A4 | Selection toggles never reach the model (prompt built once; `get` ignores selection) | `agent_session.dart:140-156`; `skill_registry.dart:58-66`; `ui/skill_manager_view.dart:242-244` |
| U-A5 | Subscription cancel doesn't stop native generation | `agent_loop.dart:225-236` |
| U-A6 | A non-string name throws `TypeError` | `skill_md_parser.dart:60-61` |

Also pass `modelType: gemma4`: core defaults to `gemmaIt` (`flutter_gemma_interface.dart:407`), FFI to the installed
type (ffi:`301`).
