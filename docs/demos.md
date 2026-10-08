# Demo specifications (as given)

## 1. Multimodal voice chat with skills

A voice chat in which the user talks to the assistant and can attach images — a photo
from the camera or the gallery. Speech is recognized on the device, Gemma 4 E2B
processes the request together with the image, and the reply is spoken by speech
synthesis: it starts playing from the first finished sentence and appears in the chat
feed at the same time.

The assistant has access to a knowledge base loaded in advance. The documents are split
into chunks and indexed with EmbeddingGemma 2 in sqlite-vec; for a question on the
knowledge base's topic, the model retrieves the relevant chunks, answers from them, and
shows the source.

Beyond answering, the assistant takes actions through agent skills: it decides which
skill to call, runs it, and reports the result. The skill set grows without rebuilding
the app — each skill is described in its own Markdown file.

- Voice input — ASR (Moonshine / Whisper / Parakeet).
- Spoken replies — TTS (Qwen-TTS), starting from the first finished sentence.
- Camera or gallery photos in the chat; questions about the photo — Gemma 4 E2B.
- Pre-loaded knowledge base: retrieval with EmbeddingGemma 2 and sqlite-vec; answers
  cite their source.
- Agent skills: a camera watcher (a classical LiteRT model detects the event, the
  assistant announces it by voice), timers, device and accelerator info.
  *(2026-10-06: the camera watcher and timers were dropped from Demo 1 — see
  [design/demo1-voice-chat.md](design/demo1-voice-chat.md); the built-in skills are the
  current time and device and accelerator info.)*
- New skills are added as Markdown files, with no app rebuild.

## 3. Live camera assistant

An assistant with an always-on camera and no chat. A classical object-detection model
from litert-community analyzes every frame and marks the detected objects with bounding
boxes in real time.

The user asks questions by voice. Simple questions about what is in the frame are
answered immediately from the list of detected objects, without passing the image to
the language model, so the reply comes fast. When a detailed answer is needed —
describing the scene, reading text, judging where things are — the current frame is
passed to Gemma 4 E2B in full. Replies are spoken by speech synthesis.

- Continuous object detection — a classical model from litert-community.
- Voice input (ASR) and spoken replies (TTS).
- Fast answers from the list of detected objects, with no image processing by the model.
- Detailed frame description — Gemma 4 E2B, on request.
