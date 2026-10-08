/// The chat model of tests that need one present: `GEMMA_MODEL_PATH` (a
/// developer define) at a made-up path (the fake LLM never opens it). The app
/// ships no chat model, so without it the chat slot is unavailable.
const kTestChatModelPath = '/store/chat/model';
