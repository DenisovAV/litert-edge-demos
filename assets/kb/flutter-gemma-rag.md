---
title: On-device RAG and embeddings with flutter_gemma
source: https://github.com/DenisovAV/flutter_gemma/blob/d9ec40701d18afcd987bacea33a96f484833d59c/packages/flutter_gemma/skills/flutter-gemma-rag/SKILL.md ; https://github.com/DenisovAV/flutter_gemma/blob/d9ec40701d18afcd987bacea33a96f484833d59c/packages/flutter_gemma_rag_sqlite/README.md ; https://github.com/DenisovAV/flutter_gemma/blob/d9ec40701d18afcd987bacea33a96f484833d59c/packages/flutter_gemma_embeddings/README.md ; https://github.com/DenisovAV/flutter_gemma/blob/d9ec40701d18afcd987bacea33a96f484833d59c/packages/flutter_gemma_rag_qdrant/README.md ; https://github.com/DenisovAV/flutter_gemma/blob/d9ec40701d18afcd987bacea33a96f484833d59c/packages/flutter_gemma/README.md
license: MIT
---

# On-device RAG and embeddings with flutter_gemma

This document explains retrieval-augmented generation (RAG) and semantic search fully on-device with flutter_gemma: the embedding models and tokenizers, the FlutterGemma.rag facade, the sqlite-vec and qdrant-edge vector stores, metadata filters, persistence, web setup and the common traps.

## The pieces of on-device RAG in flutter_gemma

On-device RAG in flutter_gemma combines an embedding model with a vector store. The packages are flutter_gemma (core), flutter_gemma_litertlm (it provides LiteRtEmbeddingBackend), flutter_gemma_embeddings (the tokenizers), and one vector store: flutter_gemma_rag_sqlite or flutter_gemma_rag_qdrant. A typical install is `flutter pub add flutter_gemma flutter_gemma_litertlm flutter_gemma_embeddings flutter_gemma_rag_sqlite path_provider`.

Use the FlutterGemma.rag facade — initialize, addDocument, searchSimilar. It embeds documents and queries with the correct task types. Add inferenceEngines to FlutterGemma.initialize as well when the app also generates answers from the results.

Two vector-store packages implement the same Dart API: flutter_gemma_rag_qdrant (qdrant-edge, native — fastest on Android, iOS and desktop) and flutter_gemma_rag_sqlite (in-SQLite sqlite-vec/vec0 KNN, portable across all six platforms including Web, since qdrant-edge can't target WASM). Code is the same on both.

## Rules for using RAG with flutter_gemma

1. Use the FlutterGemma.rag facade, which embeds with the correct task types.
2. Declare every field used in a filter in filterSchema at initialize. A condition on an undeclared field is dropped, never rejected.
3. On native, give rag.initialize an absolute path in a writable directory. A bare name resolves against the process working directory, which is not writable on Android or iOS.
4. Activate an embedding model with getActiveEmbedder() before addDocument.
5. LiteRtEmbeddingBackend comes from flutter_gemma_litertlm, not flutter_gemma_embeddings.
6. On web use WebSqliteVectorStore. SqliteVectorStore constructs there without complaint and throws UnimplementedError from the first call. flutter_gemma_rag_qdrant is native-only.
7. Android needs minSdk 30 — for the LiteRT embedding runtime, not the vector store.

## Registering the embedding backend and tokenizer

FlutterGemma.initialize takes two embedding lists: embeddingBackends, for example LiteRtEmbeddingBackend() from an engine package, and embeddingTokenizers, for example GemmaEmbeddingTokenizers() from flutter_gemma_embeddings. The same call takes the vector store, the filterSchema and an optional huggingFaceToken.

```dart
await FlutterGemma.initialize(
  embeddingBackends: [LiteRtEmbeddingBackend()],
  embeddingTokenizers: [GemmaEmbeddingTokenizers()],
  vectorStore: kIsWeb ? WebSqliteVectorStore() : SqliteVectorStore(),
);
```

There are two lists because they answer different questions. The backend is the engine that turns token ids into a vector; the tokenizer is what turns text into those ids, and which one a model needs is a property of the model — EmbeddingGemma is SentencePiece whether LiteRT or ONNX Runtime runs it. Keeping them apart is why neither engine package depends on flutter_gemma_embeddings, and why an app that never embeds anything resolves neither. Forget the second list and the first embedding throws a StateError naming the package to add — it never silently falls back to a tokenizer with the wrong convention.

## What flutter_gemma_embeddings contains

flutter_gemma_embeddings holds the embedding tokenizers for flutter_gemma: Gemma SentencePiece and BERT-family WordPiece, plus the task-type prefixing and the routing that picks between them, on Android, iOS, macOS, Linux, Windows and Web. Since 2.2.0 this is all it is. The seam an engine implements, the background-isolate worker and the pooling moved into flutter_gemma itself. The package is pure Dart with no native or FFI code; the concrete backend and its native library are owned by whichever engine package you add.

There are three tokenizer profiles, picked by the model you load, because a model's special-token convention is not negotiable and using the wrong one corrupts the vector silently rather than failing. Gemma (SentencePiece) uses BOS 2, EOS 1 and a TaskType prefix. WordPiece (BERT, MiniLM) uses [CLS] … [SEP]. The SigLIP2 text tower uses no BOS, one trailing EOS, lowercasing and a fixed 64-token width; it is not selected automatically, and the loader refuses a SigLIP2 tokenizer.json rather than embedding it wrongly.

## Installing EmbeddingGemma as the embedder

An embedding model is installed with FlutterGemma.installEmbedder(), giving the model file and its tokenizer, and activated with FlutterGemma.getActiveEmbedder():

```dart
const base = 'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main';
await FlutterGemma.installEmbedder()
    .modelFromNetwork('$base/embeddinggemma-300M_seq512_mixed-precision.tflite')
    .tokenizerFromNetwork('$base/sentencepiece.model')
    .install();
final EmbeddingModel embedder = await FlutterGemma.getActiveEmbedder();
```

EmbeddingGemma is a gated repo: the token's Hugging Face account must have accepted the Gemma licence, and the token ships inside the app — on web inside main.dart.js. seq512 in the file name is the input window in tokens; seq256, seq1024 and seq2048 variants sit in the same repo.

## Text embedding models and their sequence lengths

All embedding models generate 768-dimensional vectors. The numbers in names (64, 256, 512, 1024, 2048) indicate the maximum input sequence length in tokens, not the embedding dimension.

| Model | Parameters | Max sequence length | Size | Hugging Face token needed |
|---|---|---|---|---|
| Gecko 64 | 110M | 64 tokens | 110MB | no |
| Gecko 256 | 110M | 256 tokens | 114MB | no |
| Gecko 512 | 110M | 512 tokens | 116MB | no |
| EmbeddingGemma 256 | 300M | 256 tokens | 179MB | yes |
| EmbeddingGemma 512 | 300M | 512 tokens | 179MB | yes |
| EmbeddingGemma 1024 | 300M | 1024 tokens | 183MB | yes |
| EmbeddingGemma 2048 | 300M | 2048 tokens | 196MB | yes |

Gecko comes from litert-community/Gecko-110m-en and EmbeddingGemma from litert-community/embeddinggemma-300m.

## Gecko versus EmbeddingGemma speed and accuracy

On an Android Pixel 8, Gecko 64 took about 109 ms per document embedding and 130 ms per search — the fastest, 2.6 times faster than EmbeddingGemma. EmbeddingGemma 256 took about 286 ms per document embedding and 342 ms per search, and is more accurate, with 300M parameters against Gecko's 110M.

Suggested use cases: Gecko 64 for real-time search, mobile apps, short queries of up to 64 tokens and fast inference; Gecko 256 and 512 for balanced, general-purpose embeddings with a good speed and quality tradeoff; EmbeddingGemma 256 and 512 for high-quality embeddings, semantic search and better accuracy; EmbeddingGemma 1024 and 2048 for long documents, detailed content, research papers and articles.

## Initializing the vector store database

FlutterGemma.rag.initialize takes a database file for sqlite and a directory for qdrant. On native it persists across launches at that path. On native, pass an absolute path under getApplicationDocumentsDirectory() from path_provider, for example '<documents>/rag.db'; on web a name such as 'rag.db' is enough.

A store that fails to open on a phone is usually caused by a bare name such as 'rag.db' passed to rag.initialize on Android or iOS, because a bare name resolves against the process working directory, which is not writable there. The qdrant store treats the storage path as a shard directory in which qdrant creates files, not a single .db file, so use a distinct path from any sqlite store so they don't collide on disk.

## Indexing documents with addDocument and chunk size limits

FlutterGemma.rag.addDocument takes an id, the content text and an optional metadata JSON string, for example metadata: jsonEncode({'lang': 'en', 'year': 2024}). It auto-embeds the text with the active embedding model. addDocument with an existing id replaces that document. FlutterGemma.rag.removeDocument(id:) deletes one, and FlutterGemma.rag.clear() empties the store.

If no embedder is active, addDocument throws "No embedding model is active. addDocument(content:) and searchSimilar(query:) auto-embed text, which requires an embedding model." The fix is to install an embedder and call FlutterGemma.getActiveEmbedder() first.

For higher throughput you can batch-embed yourself with embedder.generateEmbeddings(texts, taskType: TaskType.retrievalDocument) and feed the pre-computed vectors through addDocumentWithEmbedding(id:, content:, embedding:, metadata:).

Splitting documents, chunk size and overlap are the app's to decide. Keep each chunk within the embedding model's window — 512 tokens for seq512; a longer one is truncated without an error.

## Searching with searchSimilar

FlutterGemma.rag.searchSimilar takes the question as text and embeds it itself, plus topK, an optional threshold and an optional filter. Each RetrievalResult has id, content, similarity and metadata.

```dart
final hits = await FlutterGemma.rag.searchSimilar(
  query: question,
  topK: 5,
  filter: const Filter(must: [FieldEquals(key: 'lang', value: 'en')]),
);
```

searchSimilar returns cosine similarity (1 = identical, higher = better), sorted descending and filtered by threshold. That is the same contract on the sqlite store and the qdrant store: vec0 returns a distance, and the sqlite store converts it to 1 minus distance at the boundary.

## Query and document task types

Query and document embeddings are trained asymmetrically. The FlutterGemma.rag facade embeds documents and queries with the correct task types, but when you embed by hand, generateEmbedding defaults to TaskType.retrievalQuery, so text embedded for indexing without a task type gets the query prefix and retrieval quality drops. The fix is to pass TaskType.retrievalDocument when indexing by hand and then store the vector with addDocumentWithEmbedding.

TaskType has two values, and both prefixes are non-empty, so no caller can embed without one. That is the intended contract for Gemma and Gecko. The SigLIP2 profile drops the prefix, because a CLIP-family vision side encodes an image with no prefix at all. WordPiece models such as MiniLM still concatenate it.

## Metadata filters and the filterSchema

Filter supports must, should and mustNot lists of FieldEquals, FieldRange (gte, lte) and FieldMatchAny conditions. Both vector stores honor it: qdrant-edge natively, and the sqlite-vec store on all platforms including Web.

Declare every filterable field once at initialize with filterSchema, for example FilterSchema(fields: [FilterField(name: 'lang', type: FilterFieldType.string), FilterField(name: 'year', type: FilterFieldType.number)]); field types include string, number and bool. A condition on an undeclared field is dropped, never rejected: with no schema at all the search comes back completely unfiltered, identical to filter: null, and a filter that mixes declared and undeclared fields narrows only by the declared ones. So the symptom of a missing declaration is results that ignore the filter, with no error.

The sqlite store filters KNN only on declared, typed metadata columns, not arbitrary JSON. It promotes the declared fields out of each document's metadata JSON into real columns and translates the Filter into a vec0 WHERE clause. Supported operators are =, !=, >, >=, <, <=, BETWEEN and IN, with at most 16 declared columns.

## Filter field name rules in the sqlite and qdrant stores

With flutter_gemma_rag_sqlite, a FilterField name must match ^[A-Za-z][A-Za-z0-9_]*$ and must not be a name vec0 already declares: id, embedding, content, metadata, and the hidden distance and k. configure() throws an ArgumentError otherwise. The name becomes a real vec0 column, and sqlite-vec's DDL grammar accepts no quoted identifier form, so a name outside that set is unrepresentable rather than merely unescaped. The vec0 table also caps declared metadata columns at 16; nothing checks that at initialize, so a 17th field surfaces when the table is created, on the first addDocument.

QdrantVectorStore takes free-form UTF-8 keys, minus a dot, which qdrant reads as a nested payload path. So the portable set of field names is sqlite's narrower one; a duplicate or empty name is rejected on any store.

## Embeddings run on the CPU

LiteRT embeddings always run on CPU on native, and so do ONNX ones. getActiveEmbedder(preferredBackend:) is accepted for symmetry with getActiveModel and never applied; core logs one line per isolate saying so, in debug builds only. Read EmbeddingModel.activeBackend when it matters — that answer exists in release builds too, and it is cpu on native and null on web.

CPU is the correct answer rather than a fallback: LiteRT's GPU delegate compiles and then returns all-zero vectors for EmbeddingGemma's int4 weights, and the ONNX client appends no execution provider.

On web the LiteRT embedder asks for the WebGPU accelerator and recompiles for WASM when the browser has none, and a model that is not fully accelerated can be partly delegated to WASM. window.getLiteRtEmbeddingFullyAccelerated() is known at compile time, and window.getLiteRtEmbeddingAccelerator() is known after the first embedding.

## The sqlite-vec vector store

flutter_gemma_rag_sqlite is a first-class SQLite vector store for flutter_gemma. KNN runs inside SQLite via sqlite-vec (the vec0 virtual table) — no Dart brute-force, no in-memory index. On native (Android, iOS, macOS, Linux, Windows) SqliteVectorStore uses package:sqlite3 over dart:ffi plus the per-platform vec0 loadable extension. On web, WebSqliteVectorStore uses package:sqlite3/wasm.dart driving a custom sqlite3.wasm with sqlite-vec statically linked. Both arms speak the same vec0 SQL dialect, so KNN and Filter behave identically across all six platforms. A vec0 table declares an id TEXT PRIMARY KEY, so KNN returns the document id directly — no JOIN, no rowid bridge.

## Native setup and the sqlite-vec extension download

Native needs no setup: the vec0 loadable extension is fetched per platform by the package's Native Assets hook, SHA256-verified, and loaded automatically before any database is opened. Since 1.3.0 the loadables come from the repository's native-sqlite-vec GitHub Release instead of being committed into the package, so the first build of each platform needs github.com reachable. The library is cached under ~/.cache/flutter_gemma/native/ (~/Library/Caches/… on macOS, %LOCALAPPDATA%\… on Windows), and later builds do not go out again. In an air-gapped environment, pre-populate that cache directory.

## Persisting the index with flush

Call flush() — FlutterGemma.rag.flush() — after indexing. flutter_gemma_rag_qdrant keeps new documents in memory until the store is flushed or closed, so an index built without either is lost when the process ends; an Android app killed in the background is the ordinary case.

On native flutter_gemma_rag_sqlite, flush() is a no-op: the connection autocommits, so a statement that returned is on disk. On web it drains the IndexedDB storage and waits for it. sqlite3 3.4.0 through 3.5.2 returned early over a write batch already in flight, which is why the package requires sqlite3 3.6.0 and, with it, Flutter 3.47. When neither OPFS nor IndexedDB is available the store runs in memory, and flush() throws VectorStoreException. Custom VectorStoreRepository implementations must declare flush().

## The qdrant-edge vector store

flutter_gemma_rag_qdrant is a qdrant-edge on-device RAG vector store built on the official qdrant_edge UniFFI Dart SDK, a binding over the qdrant-edge Rust crate. qdrant's HNSW index makes it the fastest native RAG store — roughly 5 to 11 times faster search than the in-SQLite sqlite-vec store at 1k to 10k documents, and further ahead as the corpus grows. It is native only: Android, iOS, macOS, Linux and Windows. For web, or when exact KNN with identical results across platforms matters more than peak speed, use flutter_gemma_rag_sqlite. You select it with FlutterGemma.initialize(vectorStore: QdrantVectorStore()) and then use the unchanged RAG API.

## RAG on the web

On web, copy web/rag/sqlite3.wasm from the flutter_gemma_rag_sqlite package into the app as web/rag/sqlite3.wasm, next to index.html — that's the URL WasmSqlite3.loadFromUrl fetches. OPFS persistence and SharedArrayBuffer require the web server to send the cross-origin isolation headers Cross-Origin-Opener-Policy: same-origin and Cross-Origin-Embedder-Policy: require-corp.

Web embeddings need four module files side by side in the app's web folder, all four from flutter_gemma_litertlm/web/: litert_embeddings.js, sentencepiece.js, litert.js and tensorflow.js. The first imports the other three by relative path, so three files alone give a 404 and an embedder that never initialises. In web/index.html, before Flutter boots, load cache_api.js first as a plain script, then litert_embeddings.js as a module.

## Upgrading an index from rag_sqlite 1.0.x

flutter_gemma_rag_sqlite 1.1.0 does not read an index written by 1.0.x. The switch to in-SQLite vec0 KNN moved the data from a plain documents table into a vec_documents virtual table. Nothing errors on upgrade: initialize() succeeds, getStats() reports 0 documents, searchSimilar() returns no hits, and the old rows sit untouched in documents. The data is intact and needs no re-embedding, because 1.0.x stored the vector as a Float32 BLOB alongside the id, content and metadata. Move it once by reading each row of the old documents table, adding it to the new store with its stored embedding, and dropping the old table only after the loop succeeds. There is no built-in migration call.

## Troubleshooting a missing native embedding library

flutter_gemma_litertlm is the sole owner of the shared native library and bundles it via its build hook. A stale Native-Assets cache after a native version bump can leave the library unbundled, surfacing as an opaque dlopen "no such file" error for libLiteRtLm on the first embedding call. Fix it with a clean rebuild: run flutter clean, delete the cached native folder (~/Library/Caches/flutter_gemma/native on macOS, ~/.cache/flutter_gemma/native on Linux, %LOCALAPPDATA%\flutter_gemma\native on Windows), then run flutter pub get.
