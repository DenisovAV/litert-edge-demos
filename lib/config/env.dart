/// Compile-time configuration. Pass values with `--dart-define=KEY=value` or
/// `--dart-define-from-file=.env` (gitignored). Anything here is compiled into
/// the binary.
library;

/// Local Gemma `.litertlm` file: an absolute path, or a path relative to the
/// app's documents directory. Empty means "the chat model chosen in the Chat
/// model card" (or none). Set, it fills the chat slot while no model is
/// chosen there (dev only).
const kGemmaModelPath = String.fromEnvironment('GEMMA_MODEL_PATH');

/// Directory holding EmbeddingGemma's `.tflite` and `sentencepiece.model`:
/// an absolute path, or a path relative to the documents directory.
/// Set, it wins over the files built into the app (dev only). Empty means
/// "the built-in EmbeddingGemma" (docs/design/distribution.md, "Bundled
/// models"). No model needs a Hugging Face token: every download is from a
/// public repo or the tester's own URL.
const kEmbeddingModelDir = String.fromEnvironment('EMBEDDING_MODEL_DIR');

/// Local YOLO26n raw-head `.tflite` (detector doc §2.2): an absolute path, or a
/// path relative to the documents directory. Set, it wins over the detector
/// built into the app (dev only). Empty means "the built-in detector".
const kDetectorModelPath = String.fromEnvironment('DETECTOR_MODEL_PATH');

/// `gpu` or `cpu`; empty (the default) leaves it to Demo 3's Detector
/// setting (GPU unless the user chose CPU). Set, it wins over the setting,
/// which Demo 3 then shows locked. `cpu` is an explicit, labelled mode, never
/// a fallback (AGENTS.md rule 2). Validated at the detector's load.
const kDetectorBackend = String.fromEnvironment('DETECTOR_BACKEND');

/// Where Demo 3's frames come from: `camera` (default) is the user's
/// choice in Demo 3's settings (the device camera, or a network camera);
/// `fixture` and `network` are fixed by the build and lock that choice.
const kFrameSource = String.fromEnvironment(
  'FRAME_SOURCE',
  defaultValue: 'camera',
);

/// The MJPEG URL for `FRAME_SOURCE=network`, e.g.
/// `http://192.168.1.23:8080/video` (a phone running IP Webcam).
const kNetworkCameraUrl = String.fromEnvironment('NETWORK_CAMERA_URL');

/// Directory of still images for `FRAME_SOURCE=fixture`.
const kFixtureDir = String.fromEnvironment('FIXTURE_DIR');

/// Silence gate in dBFS (default −45): a 20 ms frame must be at least this
/// loud to count as speech. Tune for a loud venue; validated at startup.
const kVoiceGateDbfs = String.fromEnvironment('VOICE_GATE_DBFS');

/// A measurement knob, not a switch: Gemma's GPU activation type,
/// `fp32` or `fp16`; empty (the default) leaves LiteRT-LM's own choice
/// (float16 on the GPU). float32 is the documented fix for GPUs that copy
/// digits wrongly from long prompts (LiteRT-LM #3012/#2814); it needs more
/// GPU memory and rebuilds the GPU program cache once.
const kGemmaActivation = String.fromEnvironment('GEMMA_ACTIVATION');
