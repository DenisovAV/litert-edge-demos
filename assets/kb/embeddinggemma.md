---
title: EmbeddingGemma-300M embedding model
source: https://huggingface.co/google/embeddinggemma-300m/blob/57c266a740f537b4dc058e1b0cda161fd15afa75/README.md ; https://huggingface.co/litert-community/embeddinggemma-300m/blob/29888fcee3216acadc7e844906e5fe0d79a61875/README.md ; https://huggingface.co/litert-community/embeddinggemma-300m/tree/29888fcee3216acadc7e844906e5fe0d79a61875 ; https://github.com/google-ai-edge/litert-samples/blob/367ddbdee22a8d73fba6e519c4a3f18d19008b05/samples/litert/semantic_similarity/build_from_source/README.md
license: Gemma Terms of Use (EmbeddingGemma model cards) ; Apache-2.0 (litert-samples semantic similarity sample)
---

# EmbeddingGemma-300M embedding model

This document describes EmbeddingGemma, Google's 300M-parameter open text embedding model: its inputs and outputs, Matryoshka embedding sizes, the task prompts for queries and documents, benchmark results, quantized and mixed-precision variants, and the LiteRT builds for Android and iOS with their CPU, GPU and NPU performance.

## What EmbeddingGemma is

EmbeddingGemma is a 300M parameter, state-of-the-art for its size, open embedding model from Google, built from Gemma 3 (with T5Gemma initialization) and the same research and technology used to create Gemini models. EmbeddingGemma produces vector representations of text, making it well-suited for search and retrieval tasks, including classification, clustering, and semantic similarity search. The model was trained with data in 100+ spoken languages.

The small size and on-device focus make it possible to deploy in environments with limited resources such as mobile phones, laptops, or desktops. Technical details are in the paper "EmbeddingGemma: Powerful and Lightweight Text Representations" (arXiv 2509.20354). The model is developed by Google DeepMind and released under the Gemma Terms of Use; on Hugging Face, access requires reviewing and agreeing to Google's usage license.

## Inputs, outputs and Matryoshka embedding sizes

- Input: a text string, such as a question, a prompt, or a document to be embedded, with a maximum input context length of 2048 tokens.
- Output: a numerical vector representation of the input text, with an output embedding dimension of 768.

Smaller options (512, 256, or 128 dimensions) are available via Matryoshka Representation Learning (MRL). MRL allows users to truncate the 768-dimensional output embedding to their desired size and then re-normalize it for efficient and accurate representation.

EmbeddingGemma activations do not support `float16`. Use `float32` or `bfloat16` as appropriate for your hardware.

## Prompt instructions for queries and documents

EmbeddingGemma can generate optimized embeddings for various use cases, such as document retrieval, question answering, and fact verification, or for specific input types, either a query or a document, using prompts that are prepended to the input strings.

Query prompts follow the form `task: {task description} | query: `, where the task description varies by use case, with the default task description being `search result`. Document-style prompts follow the form `title: {title | "none"} | text: `, where the title is either `none` (the default) or the actual title of the document. Providing a title, if available, will improve model performance for document prompts but may require manual formatting. These prompts may already be available in the EmbeddingGemma configuration of your modeling framework.

### Recommended prompt for each task

- Retrieval (query): `task: search result | query: {content}`
- Retrieval (document): `title: {title | "none"} | text: {content}`
- Question answering: `task: question answering | query: {content}`
- Fact verification: `task: fact checking | query: {content}`
- Classification: `task: classification | query: {content}`
- Clustering: `task: clustering | query: {content}`
- Semantic similarity: `task: sentence similarity | query: {content}`
- Code retrieval: `task: code retrieval | query: {content}`

The semantic similarity prompt is optimized to assess text similarity and is not intended for retrieval use cases. For code retrieval, a natural-language query such as "sort an array" retrieves code blocks whose embeddings are computed with the retrieval document prompt.

## Using EmbeddingGemma with Sentence Transformers

The original weights are designed to be used with Sentence Transformers, using the Gemma 3 implementation from Hugging Face Transformers as the backbone. Queries and documents are encoded with separate methods, and similarity scores rank the documents. A query embedding has shape (768,) and four document embeddings have shape (4, 768):

```python
from sentence_transformers import SentenceTransformer
model = SentenceTransformer("google/embeddinggemma-300m")
query_embeddings = model.encode_query("Which planet is known as the Red Planet?")
document_embeddings = model.encode_document(documents)
similarities = model.similarity(query_embeddings, document_embeddings)
```

In the model card's example, the document about Mars scores 0.6359 against the Red Planet query, while the documents about Venus, Jupiter and Saturn score 0.3011, 0.4930 and 0.4889.

## Benchmark results by embedding size and quantization

The full-precision checkpoint was evaluated on MTEB. Mean (Task) scores:

| Dimensionality | MTEB Multilingual v2 | MTEB English v2 | MTEB Code v1 |
| --- | --- | --- | --- |
| 768d | 61.15 | 69.67 | 68.76 |
| 512d | 60.71 | 69.18 | 68.48 |
| 256d | 59.68 | 68.37 | 66.74 |
| 128d | 58.23 | 66.66 | 62.96 |

Mean (TaskType) scores at 768 dimensions are 54.31 (multilingual), 65.11 (English) and 68.76 (code).

Quantization-aware-trained (QAT) checkpoints were evaluated after quantization, all at 768 dimensions. Mean (Task) scores:

| Quant config | MTEB Multilingual v2 | MTEB English v2 | MTEB Code v1 |
| --- | --- | --- | --- |
| Q4_0 | 60.62 | 69.31 | 67.99 |
| Q8_0 | 60.93 | 69.49 | 68.70 |
| Mixed precision | 60.69 | 69.32 | 68.03 |

Mixed precision refers to per-channel quantization with int4 for embeddings, feedforward, and projection layers, and int8 for attention (e4_a8_f4_p4). The LiteRT builds described below use this mixed-precision scheme.

## Training data and development of EmbeddingGemma

The model was trained on a dataset of text totaling approximately 320 billion tokens. Its components are web documents (content in over 100 languages), code and technical documents, and synthetic and task-specific data, including curated data for information retrieval, classification, and sentiment analysis. The training data was filtered for CSAM and for certain personal information and other sensitive data, and filtered on content quality and safety.

EmbeddingGemma was trained on Tensor Processing Unit hardware (TPUv5e), using JAX and ML Pathways.

## Intended uses of EmbeddingGemma

- Semantic similarity: embeddings optimized to assess text similarity, such as recommendation systems and duplicate detection.
- Classification: classifying texts according to preset labels, such as sentiment analysis and spam detection.
- Clustering: clustering texts based on their similarities, such as document organization, market research, and anomaly detection.
- Retrieval: document embeddings for indexing articles, books, or web pages; query embeddings for general search; code query embeddings for retrieving code blocks from natural-language queries.
- Question answering: embeddings for questions, optimized for finding documents that answer the question, such as a chatbot.
- Fact verification: embeddings for statements, optimized for retrieving documents that contain evidence supporting or refuting them.

## Limitations and risks of EmbeddingGemma

The quality and diversity of the training data significantly influence the model's capabilities; biases or gaps in the training data can lead to limitations, and the scope of the training dataset determines the subject areas the model can handle effectively. Natural language is inherently complex, and models might struggle to grasp subtle nuances, sarcasm, or figurative language. The card encourages continuous monitoring and de-biasing techniques, notes that prohibited uses are outlined in the Gemma Prohibited Use Policy, and encourages developers to adhere to privacy regulations with privacy-preserving techniques.

## LiteRT builds of EmbeddingGemma

The Hugging Face repo `litert-community/embeddinggemma-300m` provides EmbeddingGemma variants ready for deployment on Android and iOS using LiteRT, or on Android via the Google AI Edge RAG Library. Use the SentencePiece model (`sentencepiece.model`, about 4.7 MB) as the tokenizer for the EmbeddingGemma model.

The repo contains one generic file per maximum sequence length, `embeddinggemma-300M_seq256_mixed-precision.tflite`, `seq512`, `seq1024` and `seq2048`, plus per-SoC NPU builds of each length for Google Tensor G5 and G6, MediaTek MT6991 and MT6993, and Qualcomm SM8550, SM8650, SM8750 and SM8850. The generic `seq512` file is about 179 MB. The Google AI Edge RAG Library SDK is available from Maven, with an Android guide and a sample app. The embedding-gemma models were compiled for Google Tensor using standard configurations; no additional compilation flags are required.

## EmbeddingGemma performance on a Samsung S25 Ultra

All benchmark figures are from a Samsung S25 Ultra, with the mixed-precision models.

| Backend | Max sequence length | Init time (ms) | Inference time (ms) | Memory, RSS (MB) | Model size (MB) |
| --- | --- | --- | --- | --- | --- |
| NPU | 256 | 206 | 7.8 | 224 | 182 |
| NPU | 512 | 241 | 18 | 231 | 184 |
| NPU | 1024 | 272 | 57 | 263 | 195 |
| NPU | 2048 | 468 | 169 | 332 | 220 |
| GPU | 256 | 1175 | 64 | 762 | 179 |
| GPU | 512 | 1445 | 119 | 762 | 179 |
| GPU | 1024 | 1545 | 241 | 771 | 183 |
| GPU | 2048 | 1707 | 683 | 786 | 196 |
| CPU | 256 | 17.6 | 66 | 110 | 179 |
| CPU | 512 | 24.9 | 169 | 123 | 179 |
| CPU | 1024 | 35.4 | 549 | 169 | 183 |
| CPU | 2048 | 35.8 | 2455 | 333 | 196 |

Init time is the cost paid once per application initialization; subsequent inferences do not pay it. Memory is an indicator of peak RAM usage, and model size is the size of the `.tflite` flatbuffer. CPU inference is accelerated via the LiteRT XNNPACK delegate with 4 threads. Benchmarks ran with cache enabled and initialized; during the first run, latency may differ.

## Semantic similarity sample with EmbeddingGemma in C++

The litert-samples repository includes a C++ application that runs EmbeddingGemma with the LiteRT runtime and calculates the cosine similarity between two input sentences. It takes the tokenizer (`sentencepiece.model`), the embedder `.tflite` file, the two sentences and a sequence length, for example 256. On Linux it runs on the CPU after a Bazel build; for Android, a script builds the app, pushes the files to a connected device with `adb` and runs it, defaulting to `embeddinggemma-300M_seq256_mixed-precision.tflite` on the `cpu` accelerator. For NPU acceleration the script resolves NPU library dependencies when called with `--accelerator "npu"` and `--soc_man` set to Qualcomm (Qualcomm HTP, with `QNN_SDK_ROOT` pointing at the QAIRT SDK), MediaTek (APU) or Google (Tensor TPU). The script requires a space between a flag and its value and does not support the `--flag=value` format.
