# Inc 4–5 — images and knowledge base: flutter_gemma wiring

> **History:** describes the code as of increments 4 and 5 (Demo 1 Inc 4–5, 2026-10-02); see [demo1-voice-chat.md](demo1-voice-chat.md) §3 for today.

Status: spec, 2026-10-02 (`flutter-gemma-expert`). Sources: flutter_gemma 1.11.3, litertlm 1.8.5, embeddings
2.2.1, rag_sqlite 1.4.0, image_picker 1.2.3, Flutter 3.47.3 engine. **Measured** = scratch copy of this app, M4 Pro,
debug, Gemma on GPU, App Nap off (P1).

## 0. Changes to the designs

1. An image costs **~270 tokens** at any size (224–1024 px); Dart counts 257 (`chat.dart:198`).
2. **`maxNumImages: 1` is no limit:** two images per message and images across turns were accepted.
3. Image prefill **~0.95 s**; the first image after load **+1.3 s** → warm up with an image (§1.5).
4. `bool imageContextLost` → `Uint8List? imageInContext`; the repository decides re-sends.
5. **291 chunks**; golden sections are H3 headings, so H3s start sections.
6. Golden set is **19 + 12**, not 10 + 10; 19/19 and 12/12 for gates 0.25–0.525 → `kKbMinSimilarity = 0.40`.
7. 4096 tokens hold ~2–3 KB turns → budget guard (§2.7); Inc 2 should weigh 8192.
8. `pubspec.yaml` lacks `assets/kb/`.

## 1. Inc 4 — images

### 1.1 What the engine does

| | |
|---|---|
| Path | `Message(imageBytes:)` → `ffi_inference_model.dart:434` → base64 part before the text (`litert_lm_client.dart:1237-1249`) → `StbImagePreprocessor` |
| Encodings | stb_image (symbols in `libLiteRtLm.dylib`): JPEG, PNG, BMP, GIF, TGA, PSD, HDR, PIC, PNM. **No WebP or HEIC.** PNG and JPEG of the same photo: same tokens, same answer. |
| Size | No Dart-side limit; native resizes into a fixed patch budget |
| Vision backend | CPU (`litert_lm_client.dart:693,721-729`; Metal fails, LiteRT-LM#2461). `getActiveModel(preferredVisionBackend:)` (`flutter_gemma.dart:432`) is an option for Android only. |
| `supportImage` | The chat inherits it from the model (`:286,295`). Without it, images are **dropped silently** (`:434`). |
| After a stop | The rebuild replays **text only** (`:773-797, :863, :887`). Measured: without a re-send the model answers "NO IMAGE". |
| After a failure | No rebuild (`:856`); treat the image as lost |
| Tokens used | `getSessionMetrics().totalTokens` = prefill + decode of the live conversation, reset on rebuild (`litert_lm_client.dart:1966-2036`) |

### 1.2 ConversationRepository

```dart
/// [image]: PNG from normalizeForLlm. Pass the SAME object every turn while it
/// stays attached; it is sent only when the live chat cannot see it.
Stream<AssistantEvent> ask(String prompt, {Uint8List? image});
Uint8List? get imageInContext; // compared with identical()
```

In `ask`, after the busy check:
1. Image but `!chat.supportsImages` → `AssistantFailed`.
2. Run the budget guard (§2.7).
3. `sendImage = image != null && !identical(image, _imageInContext)`. On a re-send, log
   `[Conversation] image resent (lost: stop|failure|reset|budget)`.
4. `Message(text: prompt, isUser: true, imageBytes: sendImage ? image : null)`.
5. A stop or a failure sets `_imageInContext = null`. A normal end with `sendImage` stores `image`. `_rebuild`
   clears it.

`GenerationMetrics` gains `imageSent`, `contextReset`, `contextTokens`.

### 1.3 Per-turn flow

The working tree already has `TurnRequest({typed, Uint8List? image})` and `micUp/sendText/submitUtterance({image})`.
`VoiceChatViewModel` keeps a **sticky** `_attachment` (until removed or New conversation) and passes it every turn;
`ChatTurnResponder.prepare` captures `request.image` and `respond` calls `ask(prompt, image:)`.

### 1.4 Picking and normalizing

- **macOS:** gallery only. `file_selector` with `public.image` can return HEIC or WebP. The camera throws
  `StateError` (`image_picker_macos.dart:101-102`), and `maxWidth` is ignored (`:90`).
- **iOS:** `requestFullMetadata: false` skips the photo-library prompt (`FLTImagePickerPlugin.m:155-159`).
- **Android:** the plugin requests `CAMERA` itself. With ~3 GB of models resident, the activity may die while
  the camera app is open: call `retrieveLostData()` at start, or prefer the in-app `capture()` (Inc 7).

```dart
final f = await _picker.pickImage(source: src, maxWidth: 1024, maxHeight: 1024, requestFullMetadata: false);
if (f != null) return normalizeForLlm(await f.readAsBytes());   // null = cancelled

Future<Uint8List> normalizeForLlm(Uint8List encoded, {int maxSide = 1024}) async {
  final buf = await ui.ImmutableBuffer.fromUint8List(encoded);
  final d = await ui.ImageDescriptor.encoded(buf);                // EXIF-oriented size
  try {
    final s = math.min(1.0, maxSide / math.max(d.width, d.height));
    final codec = await d.instantiateCodec(targetWidth: math.max(1, (d.width * s).round()),
        targetHeight: math.max(1, (d.height * s).round()));
    final img = (await codec.getNextFrame()).image;
    try {
      return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    } finally { img.dispose(); codec.dispose(); }
  } finally { d.dispose(); buf.dispose(); }
}
```

The engine applies EXIF orientation to size and pixels (`lib/ui/painting/image_generator.cc:86-188`) and decodes
HEIC through CoreGraphics on Apple (`image_generator_registry.cc:63-70`). Output is always PNG (0.79 MB at 640×480,
1.58 MB at 1024×768).

### 1.5 Warm-up

`LlmService.warmUp` adds a second chunk: a 32×32 PNG made with `PictureRecorder`, and `maxOutputTokens: 1`.
Measured: the first image takes 2.25 s, later ones 0.95 s. The warm-up is per engine, so it survives new chats.

### 1.6 Tests

- **Unit, repository** (fake chat): repeat ask sends no image; stop, failure, `open`/`reset` and budget reset each
  force a re-send; a chat without image support fails.
- **Unit, `normalizeForLlm`:** 640×480 is unchanged; 2000×1500 becomes 1024×768; an Orientation=6 JPEG (made with
  PIL from `~/Work/models/yolo26n/.venv`) comes out with width and height swapped.
- **Integration** (built as `integration_test/image_chat_test.dart`; `-d macos --dart-define=GEMMA_MODEL_PATH=…`):
  - Asset `test_assets/cats.jpg` = `~/Work/models/yolo26n/test_images/coco_39769_cats.jpg` (640×480, 173,131 B).
  - "What animal is this?" → `/cat/i`, `imageSent`.
  - "How many are there?" → `!imageSent`, `/two|2/`.
  - "Describe this photo in great detail.", stopped at the first chunk, then "What colour is the sofa?" →
    `imageSent`, a log line `image resent`, `/pink|red/i`.

## 2. Inc 5 — knowledge base

### 2.1 Registration (the single `initialize` in `config/bootstrap.dart`)

```dart
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart'; // GemmaEmbeddingTokenizers
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart'; // SqliteVectorStore
embeddingBackends: const [LiteRtEmbeddingBackend()],   // from flutter_gemma_litertlm
embeddingTokenizers: const [GemmaEmbeddingTokenizers()],
vectorStore: SqliteVectorStore(),                      // no filterSchema needed
```

### 2.2 Embedder (`EmbedderService`, `ModelId.embeddingGemma`, `required: false`)

- **Source:** `EMBEDDING_MODEL_DIR` dart-define, absolute or Documents-relative (`resolveLocalPath`): macOS
  `$HOME/Work/models/embeddinggemma`; iPhone `devicectl` into Documents; Android `/sdcard/Android/data/<pkg>/files/…`.
- **Install:** `installEmbedder().modelFromFile('$dir/embeddinggemma-300M_seq512_mixed-precision.tflite')
  .tokenizerFromFile('$dir/sentencepiece.model').install()` (`embedding_installation_builder.dart:52,88,144`). It
  registers the path without copying.
  Without it: `modelFromNetwork`/`tokenizerFromNetwork(…/embeddinggemma-300m/resolve/main/…, token: kHfToken)`;
  without a token either: `ModelUnavailable`.
- **Load:** `getActiveEmbedder()` (`flutter_gemma.dart:690`): worker isolate, CPU forced
  (`litert_embedding_backend.dart:88`); assert `cpu` and dimension 768. Warm up with one embedding, then start
  `KnowledgeRepository.ensureIndexed()` **without blocking** `prepareAll`.

### 2.3 RAG API (`FlutterGemma.rag`, `flutter_gemma.dart:1140-1207`)

- **`initialize(dbPath)`:** reopens, re-detects the dimension (`sqlite_vector_store.dart:188`); persists.
- **`addDocumentWithEmbedding(id:, content:, embedding:, metadata:)`:** delete-then-insert (`:297`), autocommit.
- **`searchSimilar(query:, topK:, threshold:)` → `RetrievalResult(id, content, similarity, metadata)`:** query
  prefix (`flutter_gemma_desktop.dart:914`); similarity = 1 − cosine (`:216,376`). `threshold` only trims, so gate
  in app code.
- **`stats()` → `(documentCount, vectorDimension)`; `clear()`:** `clear` drops the table (`:451`).
- **Indexing:** `generateEmbeddings(batchOf8, taskType: TaskType.retrievalDocument)` gives progress per batch.
  Batching isn't faster (`common_embedding_model.dart:100`).

### 2.4 Index lifecycle (D10)

The DB lives at `getApplicationSupportDirectory()/kb/kb.db`; Documents becomes user-visible in Inc 6. A marker
`kb/index.json` holds `{hash, chunks, dim}`.
1. `hash = sha256(kChunkerVersion, model file, retrievalDocument prefix, then each sorted assets/kb/*.md path +
   bytes)`. List the files via `AssetManifest`. Make `crypto` (already resolved) a direct dependency.
2. If the hash matches and `stats().documentCount == chunks`, the KB is ready.
3. Otherwise: delete the marker, `clear()`, chunk, embed and insert with progress, then write the marker **last**
   (temp file + rename).

During indexing, turns run without the KB and show "KB indexing n%".

#### Prebuilt index (2026-10-06)

Phone indexing exceeded 60 s (a Galaxy S24: 290 chunks in **216 s** on the CPU), so the app ships the Mac-built
DB: `assets/kb_index/kb.db` (the sqlite-vec file exactly as the app's store wrote it, 3.6 MB, ~0.95 MB
compressed) and `manifest.json`.

- **Key** (`KbIndexKey`, `lib/data/services/knowledge/kb_index_key.dart`): documents hash (each `assets/kb/*.md` path +
  bytes), chunker id (`md-chunker-1/1400/300`), the `retrievalDocument` prefix, the embedder id, the SHA-256 of
  the embedder's `.tflite` and `sentencepiece.model`, dim 768. The marker (`kb/index.json`, now
  `{hash, chunks, dim, origin, prebuiltSkipped?, key}`) and the manifest both carry it; `hash` is its digest.
- **Startup**: a matching marker is reused as before. Otherwise, when the manifest's key equals the app's, its
  `kb.db` is checked against the manifest's size and SHA-256, written beside `<kb>/kb.db`, renamed over it, and
  the store reopened on it (it closes the old handle); rows and dim are checked; the marker says
  `origin: prebuilt`. Nothing is embedded: **97 ms** on the M4 Pro (debug) against 51 s embedding. Any mismatch
  (another key, a corrupt file, a copy that does not open) indexes on the device as before; the reason is logged,
  shown in the overlay ("prebuilt index not used: …") and the home tile, and kept in the marker.
- **Embedder digests without hashing 184 MB per launch** (`FileEmbedderDigests`): the built-in files take the
  build's SHA-256 (`kBundledEmbedderModel`/`Tokenizer`) where `BundledModelFiles` verified them (Android's
  `.sha256` record beside the extracted copy, or the asset in place on desktop/iOS); any other file
  (`EMBEDDING_MODEL_DIR`) is hashed once in a worker isolate and cached by path, size and mtime.
- **Why the DB and not a vectors file**: installing is one 3.6 MB copy; a vectors file would mean 290
  `addDocumentWithEmbedding` calls, each a DELETE plus an INSERT in its own autocommit transaction on the main
  isolate (867 ms on the Mac, more with phone fsyncs). The price is coupling to the store's vec0 layout, so the
  manifest records the store release and `test/data/services/knowledge/kb_prebuilt_asset_test.dart` compares it with
  `pubspec.lock`; a copy that will not open or holds the wrong rows falls back to on-device indexing, visibly.
  The file is sqlite's own format, portable across our little-endian targets.
- **Same answers** (relaxed 2026-10-07): `integration_test/kb_retrieval_test.dart` compares the golden set on an
  on-device index with the prebuilt one and requires what the app acts on to agree: the same top-1 document for
  every on-topic question, the same gate decision (top hit at or above `kKbMinSimilarity`, or not) for all 31,
  and a max |Δ score| ≤ 1e-2 (the top hit's score and every chunk both lists hold). Identical ranked lists
  (`same_top`) are printed as information only. On macOS: 31/31 identical, max |Δ| 0 (both CPU, same machine).
  On Linux arm64 the CPU kernels differ from the Mac's: `same_top=24/31 max_delta=3.90e-3` — near-equal chunks
  swapped places, which the first, exact check (identical lists, |Δ| < 1e-3) failed although no answer changed.
  There the install took **256 ms** against **432 s** of on-device indexing.

**Rebuild** after changing `assets/kb`, the chunker (`MarkdownChunker.version` or its budget), the embedder files
or `flutter_gemma_rag_sqlite` — `test/data/services/knowledge/kb_prebuilt_asset_test.dart` fails until you do:

```sh
tool/build_kb_index.sh   # macOS, ~70 s (debug, CPU); keep the test window visible
git add assets/kb_index  # kb.db + manifest.json
```

### 2.5 Chunker (D11)

1. CRLF → LF; strip the BOM.
2. **Front matter:** only a leading `---\n…\n---\n`, as flat `key: value` lines (`title`, first `source` URL).
3. **Fences:** `^\s{0,3}(`{3,}|~{3,})` opens one; it closes on the same character with at least the same length.
   The code is dropped and headings inside it are ignored. An unclosed fence throws `FormatException`.
4. **Headings:** H1 = fallback title; **H2 and H3 start sections** (H3 path `H2 › H3`); H4+ stay in the body;
   text before the first H2 is `Overview`.
5. **Blocks:** split on blank lines; table separator rows are dropped.
6. **Budget:** cost = 1 per prose character, 2 per table character (a 1121-character numeric table was 525
   tokens). A section ≤1400 is one chunk, never merged; larger ones split into `ceil(cost/1400)` balanced parts at
   block boundaries; oversized tables split into row groups repeating the header; oversized prose splits into
   sentences: `(?<!\b(?:e\.g|i\.e|vs|etc))(?<=[.!?])\s+(?=[A-Z0-9"(\[`])`.
7. **Overlap:** a part starts with the previous part's last sentence when that sentence is ≤300 characters, it
   still fits, and no table is involved.
8. **Output:** content `"$title › $path\n\n$body"`, id `doc#n`, metadata `{doc, title, section, chunk, source}`.

Prototype on the real KB with its `sentencepiece.model`: 291 chunks; 177–1451 characters; 48–446 tokens including
the prefix (p50 222); **none over 512**; every golden section present.

### 2.6 Retrieval per turn (D9)

1. `retrieve(text)` → `searchSimilar(topK: 3)`.
2. Keep the hits with **`similarity ≥ kKbMinSimilarity`**, checked per hit; if none pass, the prompt is unchanged.
3. `onSide(ChatRetrieval(passages, top, latency, outcome))`. The outcome is `used`, `belowGate`, `unavailable`
   or `failed`, and the last two show as a chip.
4. `ask(PromptBuilder.build(text, passages), image: image)`.

```
Excerpts from the knowledge base:

[1] <chunk content: "Title › Section", blank line, body>

[2] …

Answer the question. Use the excerpts only if they are relevant and cite each one you use as [1], [2] or [3].
If they do not contain the answer, say so briefly and answer without citations.

Question: <transcript>
```

- **Citations:** `\[(\d+)\]` in the final reply, kept to 1..n, become chips ("Title › Section · 0.62") opening
  the chunk and its source; uncited passages show dimmed.
- **TTS:** `SpokenSynthesizer` → `toSpokenText` already strips `[n]` (`spoken_text.dart:34`). Add ranges
  (`\[\d+(?:\s*[,–-]\s*\d+)*\]`) and replace an echoed `›` with a comma, with tests.

### 2.7 Context budget guard (in `ask`)

A KB turn adds ~650–950 tokens of excerpts, ≤384 of reply, and ~270 per image sent.

```dart
final used = math.max(chat.session.getSessionMetrics().totalTokens, chat.currentTokens);
final need = await chat.session.sizeInTokens(prompt) + (image != null ? 288 : 0)
    + profile.maxOutputTokens + 32;
if (used + need > model.maxTokens - 256) { /* recreate chat in place: contextReset, imageInContext = null */ }
```

Recreate directly, not via the open queue; the max also keeps Dart's own trim (U2) from firing.

### 2.8 Measured (M4 Pro, debug, App Nap off)

| | ms |
|---|---|
| Embedder load / first embedding | 1144 / 149 |
| Query embedding p50 (flat over 300 calls); `searchSimilar` p50 | 128; 127 |
| Chunk embedding p50 / p90 / max | 163 / 192 / 222 |
| Index 16 docs: chunk / embed 291 / insert | 46 / 47,893 / 867 |
| Index 16 docs, 290 chunks, on the device / from the prebuilt `kb.db` (2026-10-06) | 51,075 / 97 |
| The same on Linux arm64 (2026-10-07) | ~432,000 / 256 |
| Gemma load / text TTFT | 2340 / 75–119 |
| Image TTFT: first / later (224–1024 px) / 2 images in 1 message | 2252 / 928–978 / 1864 |

### 2.9 Tests

- **Chunker:** front matter; fence variants and an unclosed fence; H2/H3 paths; table splits repeat the header;
  overlap never crosses a table; `e.g.` doesn't split; CRLF/BOM; stable ids. All 16 docs ≤1400 cost and ≤512
  tokens (dev_dependency `dart_sentencepiece_tokenizer: 1.4.1`, skipped without the model); golden sections exist.
- **KnowledgeRepository** (fakes): hash match skips; mismatch re-indexes, marker last; a throw leaves no marker.
- **Prebuilt index** (`knowledge_repository_prebuilt_test.dart`, file-backed fake store): a matching manifest
  installs the build's `kb.db` byte for byte with nothing embedded and is reused next launch; other documents,
  embedder files or chunker, no prebuilt index, an unreadable manifest, a file that fails its SHA-256 or size, a
  copy with other rows, a copy that does not open → indexed on the device with the reason in the status and the
  marker; retrieval from the prebuilt index equals retrieval from an on-device one. `kb_index_key_test.dart`,
  `embedder_digests_test.dart` (no hashing for verified built-in files, cache by size+mtime);
  `kb_prebuilt_asset_test.dart` guards the shipped asset against this checkout.
- **PromptBuilder:** no passages → question unchanged; numbering.
- **`integration_test/kb_retrieval_test.dart -d macos --dart-define=EMBEDDING_MODEL_DIR=…`** on `kb_golden.json`:
  - On-topic: the expected doc in the top 3 and top-1 ≥ gate, **≥17/19**.
  - Off-topic below the gate, **≥10/12**.
  - Print the sweep 0.30–0.70 (step 0.025) and `KB index=… query_p50=…`.
  - Measured: 19/19 (expected doc ranked first every time; top-1 0.534–0.795) and 12/12 (≤0.217).
  - Since 2026-10-06 it also installs the prebuilt index into an empty directory and compares the golden set
    with the on-device index (`KB_PREBUILT install=… same_top=…/31 same_doc=…/19 same_gate=…/31
    max_delta=…`): the same top document (on-topic), the same gate decision (all) and |Δ score| ≤ 1e-2, with
    `same_top` printed only; the thresholds run on the prebuilt index. Without `EMBEDDING_MODEL_DIR` it uses the built-in files; on Android:
    `fvm flutter test integration_test/kb_retrieval_test.dart -d <device>` (the on-device reference index takes
    minutes there).

## 3. Pitfalls and upstream issues

- **P1** An unfocused macOS test app is App Nap'd after ~30 s (embeddings 130 → 1200 ms, image TTFT 1 → 10 s).
  Before latency runs: `defaults write dev.fluttergemma.litertHackathon NSAppSleepDisabled -bool YES`.
- **P2** EmbeddingGemma truncates over 512 tokens silently (`litert_embedding_forward_pass.dart:229`).
- **P3** `modelFromFile` skips the install when the file name is already registered: run `uninstallEmbedder()`
  after moving the files.
- **P4** A re-send after a failure may duplicate the image in context (+270 tokens); acceptable.

Upstream:
- **U1** (extends the `currentTokens` issue) An image counts as 257 tokens; Gemma 4 measures ~270. Message removal
  subtracts `images.length × 257` (`chat.dart:944-947`), which is 0 for `Message(imageBytes:)`.
- **U2** `_recreateSessionWithReducedChunks` (`chat.dart:936-962`) replays history through `addQueryChunk`. On FFI
  that only buffers into the next user turn (`ffi_inference_model.dart:402-445`), so all history and every earlier
  image get glued onto one message. Rebuild through `messagesJson` instead.
- **U3** `maxNumImages` isn't enforced: document what it does or enforce it.
- **U4** An image on a non-vision session should throw, not be dropped (`:434`).
- **U5** `SqliteVectorStore` has no batch insert. Each row autocommits on the caller's isolate (`:297`).
