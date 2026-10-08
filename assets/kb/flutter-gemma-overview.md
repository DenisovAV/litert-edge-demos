---
title: flutter_gemma overview
source: https://github.com/DenisovAV/flutter_gemma/blob/d9ec40701d18afcd987bacea33a96f484833d59c/packages/flutter_gemma/README.md ; https://github.com/DenisovAV/flutter_gemma/blob/d9ec40701d18afcd987bacea33a96f484833d59c/packages/flutter_gemma/skills/flutter-gemma-inference/SKILL.md
license: MIT
---

# flutter_gemma overview

This document explains what the flutter_gemma Flutter plugin is, which packages it is split into, which model file formats and model families it supports, where models can be installed from, how gated Hugging Face models are authenticated, and how the feature set differs between Android, iOS, web and desktop.

## What flutter_gemma is

flutter_gemma brings the power of Google's lightweight Gemma language models and other on-device LLMs directly to Flutter applications. With Flutter Gemma, you can incorporate advanced AI capabilities into your Flutter applications, all without relying on external servers. Gemma is a family of lightweight, state-of-the-art open models built from the same research and technology used to create the Gemini models.

The plugin supports not only Gemma but also other models: Gemma 4 E2B and E4B, Gemma 3n E2B and E4B, FastVLM 0.5B, Gemma 3 1B, Gemma 3 270M, FunctionGemma 270M, Qwen3 0.6B, Qwen 2.5, Phi-4 Mini, DeepSeek R1, SmolLM 135M, LFM2.5 230M, SmolLM3 3B, Phi-4 Mini Reasoning, Qwen2-VL 2B, SmolVLM2 500M, LLaVA-OneVision 0.5B and TranslateGemma 4B (CPU-only). Gemma 4 and Gemma 3n come with multimodal vision and audio support; FastVLM, Qwen2-VL, SmolVLM2 and LLaVA-OneVision support vision. Desktop platforms (macOS, Windows, Linux) require the `.litertlm` model format.

Models run locally on user devices for enhanced privacy and offline functionality. The plugin is compatible with iOS, Android, Web, macOS, Windows and Linux.

## Main inference features

- Multimodal support: text plus image input with Gemma 4, Gemma 3n, FastVLM, Qwen2-VL, SmolVLM2 and LLaVA-OneVision vision models.
- Audio input: record and send audio messages with Gemma 4 and Gemma 3n E2B/E4B models (Android, iOS device, and macOS, Windows and Linux via LiteRT-LM — not on web).
- Function calling: models can call external functions and integrate with other services (supported by select models).
- Thinking mode: view the reasoning process of Gemma 4, DeepSeek R1, Qwen3, SmolLM3 and Phi-4 Mini Reasoning models with thinking blocks.
- Stop generation: cancel text generation mid-process on Android, iOS, web and desktop.
- Backend switching: choose between CPU, GPU and NPU backends per model — CPU and GPU on Android, iOS and desktop, GPU on web.
- NPU acceleration: hardware NPU inference for `.litertlm` models on Qualcomm Snapdragon (Android) and Intel Lunar Lake and Panther Lake (Windows).
- Desktop support: native desktop apps with GPU acceleration via LiteRT-LM, called directly from Dart through `dart:ffi` — no JVM or JRE bundling.
- LoRA support: efficient fine-tuning and integration of LoRA (Low-Rank Adaptation) weights for tailored AI behaviour.

## Speech, agent skills, embeddings and RAG features

Beyond text generation, flutter_gemma offers opt-in packages for the rest of an on-device AI stack:

- On-device speech-to-text with `flutter_gemma_speech`: transcribe audio fully offline with a selectable ASR model (moonshine, Whisper, Parakeet) via the LiteRT C API. Whisper is multilingual.
- On-device text-to-speech with `flutter_gemma_speech`: synthesize speech fully offline with a selectable model (Matcha, Qwen3-TTS, Inflect-Nano-v2).
- On-device voice loop: `VoiceSession` chains STT, LLM and TTS into one push-to-talk turn with barge-in — the full on-device speech-to-speech pipeline (native only).
- On-device agent skills with `flutter_gemma_agent`: give the model `SKILL.md` skills (text, JavaScript, native intent or MCP) it invokes through the function-calling loop, fully offline. Android, iOS, macOS and Windows.
- Text embeddings: generate 768-dimensional vector embeddings with EmbeddingGemma or Gecko (all native platforms plus web) via the unified LiteRT C API.
- On-device RAG: two vector-store backends — `flutter_gemma_rag_qdrant` (qdrant-edge, native) and `flutter_gemma_rag_sqlite` (in-SQLite `sqlite-vec` / `vec0` KNN on all six platforms including web), with a payload-aware filter for semantic search.

flutter_gemma also ships agent skills for coding assistants. Running `dart run skills@ get --all` scans the app's dependencies and installs the skills they bundle where the coding agent looks; Claude Code, Codex, Cursor, Antigravity, Cline, Copilot and OpenCode are supported.

## Modular packages: a small core plus opt-in engines

As of version 1.0, `flutter_gemma` is split into a small core package plus opt-in packages for each engine or backend, so an app only pulls the native weight it actually uses. You add the core package, then the packages for the model formats and features you need:

- `flutter_gemma` — core, always required; it has no engine on its own.
- `flutter_gemma_litertlm` — `.litertlm` models (FFI; mobile, desktop and web).
- `flutter_gemma_mediapipe` — `.task` and `.bin` models (MediaPipe; mobile and web).
- `flutter_gemma_builtin_ai` — OS system models: Gemini Nano (Android), Apple Foundation Models (iOS 26+ and macOS), Windows AI Foundry, and the Chrome Prompt API (web).
- `flutter_gemma_onnx` — ONNX Runtime: ORT-GenAI text generation and ORT embeddings (FFI, native), Transformers.js and onnxruntime-web on the web.
- Further opt-in packages for RAG vector stores, agent skills, speech and memory diagnostics, listed in the table below.

Migrating from the 0.16.x monolith only requires adding the opt-in packages and the `initialize(...)` call; every model, session and RAG API is unchanged.

## Which flutter_gemma package to add for each need

| You want to | Add |
|---|---|
| Run `.litertlm` models (Gemma 4, Qwen3, FastVLM, and everything on desktop) | `flutter_gemma_litertlm` |
| Run `.task` or `.bin` models (Gemma 3n, Gemma 3, DeepSeek, Qwen 2.5, Phi-4) | `flutter_gemma_mediapipe` |
| Generate text embeddings | `flutter_gemma_litertlm` (`LiteRtEmbeddingBackend`) |
| On-device RAG on native (fastest on Android, iOS, desktop) | `flutter_gemma_rag_qdrant` |
| On-device RAG on any platform including web (portable `sqlite-vec`) | `flutter_gemma_rag_sqlite` |
| On-device agent skills (SKILL.md plus a tool-calling loop) | `flutter_gemma_agent` |
| Transcribe audio, synthesize speech, or run a voice loop | `flutter_gemma_speech` |
| Measure the memory a model costs (Android and iOS) | `flutter_gemma_diagnostics` |

## Registering engines with FlutterGemma.initialize

Call `await FlutterGemma.initialize(...)` once in `main()` and register the opt-in packages you added to `pubspec.yaml`. Core registers no engine on its own, so without this step `getActiveModel()` and `createEmbeddingModel()` throw a clear "add the engine package" error.

Each parameter comes from one package: `inferenceEngines:` takes `LiteRtLmEngine()`, `MediaPipeEngine()`, `BuiltInAiEngine()` or `OnnxEngine()`; `embeddingBackends:` and `embeddingTokenizers:` set up embeddings; `sttBackends:` and `ttsBackends:` come from `flutter_gemma_speech`; and `vectorStore:` takes a RAG store such as `SqliteVectorStore()`.

Add only the engines you ship. Passing both `LiteRtLmEngine()` and `MediaPipeEngine()` lets one app run both formats — the registry routes each model to the engine that handles its file type. Common settings are `huggingFaceToken` for gated models, `maxDownloadRetries` (default 10), and the web-only `webStorageMode`.

## Model file types and how ModelFileType selects the engine

flutter_gemma groups model file formats into two types based on how chat templates are handled.

Type 1, SDK-managed templates: `.task` files are the MediaPipe-optimized format for mobile (Android and iOS), and `.litertlm` files are the LiteRT-LM format for Android, iOS and desktop. The runtime applies the chat template — MediaPipe for `.task`, LiteRT-LM for `.litertlm` — so your code sends plain text on every platform.

Type 2, manual template formatting: `.bin` files (standard binary format) and `.tflite` files (LiteRT format, formerly TensorFlow Lite) require manual chat template formatting in your code.

`ModelFileType` is what selects the engine — it is not inferred from the file name. `installModel` defaults it to `ModelFileType.task`, so declare it explicitly: `ModelFileType.litertlm` for `.litertlm` files (omitting it routes the model to MediaPipe, which cannot read that format), `ModelFileType.task` for `.task` files, `ModelFileType.binary` for `.bin` and `.tflite` files, and `ModelFileType.builtIn` for OS-provided models such as Gemini Nano and Apple Foundation Models.

## Model file formats by platform

| Format | Android | iOS | Web | Desktop | Use case |
|---|---|---|---|---|---|
| `.task` | yes | yes | yes | no | Older models (Gemma 3n, Gemma 3, DeepSeek, Qwen 2.5, Phi-4) |
| `.litertlm` | yes | yes | preview | yes | Newer models (Gemma 4, Qwen3, FastVLM, and desktop for all) |
| `-web.task` | no | no | yes | no | Web-specific builds (for example Gemma 4, Gemma 3n) |
| `.bin` | yes | yes | yes | no | Manual chat template formatting required |
| `.tflite` | yes | yes | yes | yes | Embeddings only (EmbeddingGemma, Gecko) |

iOS `.litertlm` runs on the FFI engine, with vision and audio supported on physical devices. The Simulator stays CPU-only because the Metal simulator has a 256 MB single-allocation cap. Web `.litertlm` is an early preview via `@litert-lm/core` — text plus function calling, with no vision, audio, thinking or LoRA; for full multimodal on web use a MediaPipe `.task` build.

## Model capabilities by model family

| Model family | Best for | Function calling | Thinking | Vision | Size |
|---|---|---|---|---|---|
| Gemma 4 E2B | Next-gen multimodal chat — text, image, audio | yes | yes | yes | 2.4 GB |
| Gemma 4 E4B | Next-gen multimodal chat — text, image, audio | yes | yes | yes | 4.3 GB |
| Gemma 3n | On-device multimodal chat and image analysis | yes | no | yes | 3–6 GB |
| FastVLM 0.5B | Fast vision-language inference | no | no | yes | 0.5 GB |
| Phi-4 Mini | Advanced reasoning and instruction following | yes | no | no | 3.9 GB |
| DeepSeek R1 | High-performance reasoning and code generation | yes | yes | no | 1.7 GB |
| Qwen3 0.6B | Compact multilingual chat with function calling | yes | yes | no | 586 MB |
| Gemma 3 1B | Balanced and efficient text generation | yes | no | no | 0.5 GB |
| Gemma 3 270M | Ideal for fine-tuning (LoRA) for specific tasks | no | no | no | 0.3 GB |
| FunctionGemma 270M | Specialized for function calling on-device | yes | no | no | 284 MB |
| LFM2.5 230M | Smallest entry; no Hugging Face token needed | no | no | no | 168 MB |

TranslateGemma 4B is CPU-only for now: the community-converted `.litertlm` bundles run correctly on `PreferredBackend.cpu` but return only padding on `PreferredBackend.gpu`, tracked upstream at LiteRT-LM issue 1748.

## Choosing the right ModelType

When installing a model you specify a `ModelType`. It tells flutter_gemma how the model writes tool calls and reasoning, and on some engines it also picks the prompt format.

| Model family | ModelType |
|---|---|
| Gemma 4 (E2B, E4B — native function-call tokens) | `ModelType.gemma4` |
| Gemma 3 and Gemma 3n (Gemma 3 1B, 270M, Gemma 3n E2B/E4B) | `ModelType.gemmaIt` |
| DeepSeek R1 | `ModelType.deepSeek` |
| Qwen 2.5 | `ModelType.qwen` |
| Qwen 3 | `ModelType.qwen3` |
| FunctionGemma 270M | `ModelType.functionGemma` |
| Phi-4 Mini | `ModelType.phi` |
| FastVLM, SmolLM, LFM2.5, SmolLM3, Phi-4 Mini Reasoning, Qwen2-VL, SmolVLM2, LLaVA-OneVision | `ModelType.general` |

Gemma 3 and Gemma 3n are `ModelType.gemmaIt` — there is no `gemma3`. A wrong type still generates text; tool calls and reasoning then arrive as raw text. Gemma 4 and FunctionGemma on a `.litertlm` route their native tool-call tokens through the LiteRT-LM SDK's chat-template path.

## Installing a model from Hugging Face, the network, assets or files

Models are installed with a builder: `FlutterGemma.installModel(modelType:, fileType:)` followed by a source and `.install()`.

- `.fromHuggingFace(repo)` — the engine's resolver reads the repo (a litertlm manifest, or the ONNX file tree) at install time and installs the right variant; pass `file:` to pin an explicit file.
- `.fromNetwork(url, token:)` — downloads from an HTTP or HTTPS URL; `.litertlm` is the cross-platform default for Android, iOS and desktop.
- `.fromAsset(path)` — copies a model declared in `pubspec.yaml` assets.
- `.fromBundled(name)` — uses a native platform resource bundled with the app.
- `.fromFile(path)` — references an external file already on disk, for example one picked with a file picker.

`resolveHuggingFace(repo, fileType:)` returns the resolved identity and overridable runtime defaults without installing, so you can inspect the variant and its notes first.

## Model source types compared

| Source | Platform | Progress | Resume | Authentication | Use case |
|---|---|---|---|---|---|
| NetworkSource | All | Detailed | Server-dependent | Supported | Hugging Face, CDNs, private servers |
| AssetSource | All | End only | No | Not applicable | Models bundled in app assets |
| BundledSource | All | End only | No | Not applicable | Native platform resources |
| FileSource | Native (no web) | End only | No | Not applicable | User-selected files |

NetworkSource offers progress tracking from 0 to 100 percent, Hugging Face authentication, smart retry with exponential backoff, background downloads on mobile, cancellable downloads with a `CancelToken`, and an opt-in Android foreground service for large downloads. Resume after interruption is server-dependent and not supported by the Hugging Face CDN. A `CancelToken` cancels all files in multi-file downloads, such as an embedding model plus its tokenizer.

## Bundling a small model inside the app

BundledSource includes small models directly in the app bundle for instant availability without downloads: offline-first applications, small models such as Gemma 3 270M at about 300 MB, and core features requiring guaranteed availability. It is not for large models, because it increases app size significantly — roughly 135 MB for SmolLM 135M, about 300 MB for Gemma 3 270M and about 586 MB for Qwen3 0.6B. Consider hosting large models for download instead. For production apps, do not embed the model or LoRA weights within your assets; load them once and store them on the device.

## Handling download errors with DownloadException

`installModel(...).install()` throws a public `DownloadException` carrying a sealed `DownloadError`, so an app can react to gated Hugging Face models without matching error strings. The cases are `UnauthorizedError` (401, a missing or invalid token), `ForbiddenError` (403, the token lacks access to a gated model), `NotFoundError` (404, a bad URL — use `/resolve/main/`, not `/blob/main/`), `RateLimitedError` (429), `ServerError` (5xx), `NetworkError` (connectivity), `CanceledError` (the user cancelled) and `UnknownError`. Each `DownloadError` exposes `toUserMessage()`, `toTitle()`, `isRetryable` and `requiresUserAction` helpers for building UI.

To remove a model, call `model.close()`, then `FlutterGemma.uninstallModel(fileName)`; when it was the active model, also call `FlutterGemma.clearActiveInferenceIdentity()`.

## Hugging Face authentication for gated models

Many models require authentication to download from Hugging Face. Never commit tokens to version control. The recommended pattern is a `config.json` file holding `HUGGINGFACE_TOKEN`, listed in `.gitignore`, passed with `flutter run --dart-define-from-file=config.json`, and read in code with `String.fromEnvironment('HUGGINGFACE_TOKEN')` before passing it to `FlutterGemma.initialize(huggingFaceToken: ...)`. Pass `null` rather than an empty string, because an empty token still sends a bare `Authorization: Bearer` header.

A token read this way stays out of git, not out of the app: it is compiled into the binary, and on web into `main.dart.js`, where every visitor can read it. A shipped app should download from a repo that needs no token.

## Which models require a Hugging Face token

Common gated models are Gemma 3n E2B and E4B (the `google/` repos are gated), Gemma 3 1B and Gemma 3 270M in `litert-community/`, and EmbeddingGemma in `litert-community/`. Public models that need no authentication include DeepSeek, Qwen3, Qwen 2.5, SmolLM, SmolLM3, Phi-4, FastVLM, Qwen2-VL, SmolVLM2 and LLaVA-OneVision. Gemma 4 E2B needs no token either, and LFM2.5 230M is listed as the smallest entry with no Hugging Face token needed. To get access to a gated repo, visit the model page and use the request-access button; tokens are created at huggingface.co/settings/tokens.

## Logging and privacy of prompts

The plugin's internal logs are silent in release builds — model output, prompts and conversation history are never written to logcat or syslog. In debug builds they are shown according to `FlutterGemma.logLevel`. `GemmaLogLevel.none` prints nothing. `GemmaLogLevel.info`, the default, prints lifecycle, errors and diagnostics but no model output or prompts. `GemmaLogLevel.verbose` adds model output, prompts and conversation history. Release builds are always silent regardless of this setting, so there is no way to leak personal data into a production log.

## Feature comparison across Android, iOS, web and desktop

| Feature | Android | iOS | Web | Desktop |
|---|---|---|---|---|
| Text generation | yes | yes | yes | yes |
| Image input | yes | yes | yes | yes |
| Audio input | yes | device only | no | `.litertlm` only |
| Speech-to-text and text-to-speech | yes | yes | no | yes |
| Function calling | yes | yes | yes | yes |
| Thinking mode | yes | yes | no | yes |
| GPU acceleration | yes | yes | yes | yes (Metal, Vulkan, DirectX 12) |
| NPU acceleration | Qualcomm, `.litertlm` | no | no | Windows Intel |
| CPU backend | yes | yes | no | yes |
| LoRA | yes | yes | yes | no |
| Text embeddings and vector store | yes | yes | yes (vec0 in WASM) | yes |
| Asset and bundled loading | yes | yes | yes | no |

The web column describes the MediaPipe `.task` web path. Thinking mode is not supported on the web yet.

## Web support and the early-preview web .litertlm engine

Web `.litertlm` inference runs Gemma `.litertlm` models (verified on Gemma 4 E2B and E4B web variants) in the browser through the upstream `@litert-lm/core` package, using WebGPU and WASM. It is an early preview: it supports text generation, multi-turn chat, system instructions and serialized concurrent sessions, on the GPU only — there is no CPU backend on web. Vision, audio, thinking mode and LoRA are not yet supported there. MediaPipe `.task` on web remains fully supported and always runs on the GPU; for vision, audio or thinking on web today, use MediaPipe `.task` web models.

## Troubleshooting multimodal and performance issues

Multimodal issues: make sure you are using a multimodal model (Gemma 4 E2B/E4B, Gemma 3n E2B/E4B, FastVLM, Qwen2-VL, SmolVLM2 or LLaVA-OneVision), set `supportImage: true` when creating the model and the chat, and check device memory, because multimodal models require more RAM.

Performance: use the GPU backend for better performance with multimodal models, and consider the CPU backend for text-only models on lower-end devices. Larger models, such as 7B, might be too resource-intensive for on-device inference.

Reasoning text: the chat API automatically strips reasoning blocks such as `<think>...</think>` (DeepSeek, Qwen) and Gemma's thought channel from the answer; `ModelThinkingFilter.cleanResponse` exposes the same cleanup for custom inference code.
