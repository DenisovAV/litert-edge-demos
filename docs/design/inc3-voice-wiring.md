# Inc 3 — flutter_gemma voice wiring (push-to-talk)

> **History:** describes the code as of increment 3 (Demo 1 Inc 3, 2026-10-02); see [demo1-voice-chat.md](demo1-voice-chat.md) §3–§4 for today.

Status: spec, 2026-10-02 (`flutter-gemma-expert`). Verified in `~/.pub-cache`: flutter_gemma 1.11.3,
flutter_gemma_speech 0.5.2 (same as monorepo main), record 7.1.1, flutter_soloud 4.1.7, audio_session 0.2.4.
Citations are `file:line` inside each package. "Est." means not measured.

## 1. Initialization

Add to the existing call in `config/bootstrap.dart`, importing `package:flutter_gemma_speech/flutter_gemma_speech.dart`:
`sttBackends: const [LiteRtSttBackend()], ttsBackends: const [LiteRtTtsBackend()]`.

- Registering loads nothing (models load in `getActiveStt/Tts`), so loading later than the LLM is fine.
- A second `initialize` would register the backends too, but `ServiceRegistry.initialize` returns early
  (`service_registry.dart:435-447`) and silently ignores its `huggingFaceToken`/`vectorStore`. Keep one call.
- Types like `SpeechRecognizer` and `SttModelType` come from `flutter_gemma.dart` (keep `hide ModelSpec`), not from
  the speech package.

## 2. Models

| | Whisper base int8 | moonshine-tiny f32 (fallback) | Inflect-nano-v2 |
|---|---|---|---|
| Builder | `installStt().modelFromNetwork(M).tokenizerFromNetwork(T).ofType(SttModelType.whisper)` | same, `.moonshine` | `installTts().fromNetwork(B).ofType(TtsModelType.inflect)` |
| URLs under `huggingface.co/` | M `litert-community/whisper-base/resolve/main/whisper_base_30s_i8.tflite`, T `openai/whisper-base/resolve/main/tokenizer.json` | M `litert-community/moonshine-tiny/resolve/main/moonshine_tiny_5s_f32.tflite`, T `UsefulSensors/moonshine/resolve/main/ctranslate2/tiny/tokenizer.json` | B `sasha-denisov/inflect-nano-v2-litert/resolve/main/`; 4 G2P files come from Matcha automatically (`tts_model_spec.dart:115-160`) |
| Bytes (HEAD check, ungated) | 77,012,960 + 2,480,466 | 109,373,140 + 1,985,534 | ≈35.7 MB, 6 files |
| Audio | in: 16 kHz PCM16, fixed 30 s window | fixed 5 s window | out: 24 000 Hz (`inflect_tts_core.dart:46`) |
| Load | `getActiveStt(preferredBackend: PreferredBackend.cpu, language: 'en')` | no `language`: any value throws (`litert_speech_recognizer.dart:52-62`) | `getActiveTts(preferredBackend: PreferredBackend.cpu)` |

- Progress: STT `withModelProgress`/`withTokenizerProgress`; TTS `withProgress` counts files.
- **Install on every launch.** It skips existing files and restores the active spec, which is kept only in memory.
  Without it, `getActiveStt` throws `StateError` (`core/api/flutter_gemma.dart:778`).
- Backend: the CPU you request is what runs, with nothing below it to fall back to (`litert_graph.dart:37-41`). There
  is no backend getter (`flutter_gemma_interface.dart:667-733`), so the overlay shows `cpu (requested)`. The objects
  are singletons keyed by model, not by backend (`desktop/flutter_gemma_desktop.dart:586`,
  `mobile/flutter_gemma_mobile.dart:643,825`). Each service calls its getter once.
- Local files: STT can install from `modelFromFile`/`tokenizerFromFile` (`stt_installation_builder.dart:57,85`). TTS:
  **confirmed** `fromNetwork` only (`tts_installation_builder.dart:31`), and a local server doesn't help because the
  G2P URLs are absolute. After one download, installs work offline (`:132`).

## 3. `VoiceSession.custom`

`VoiceSession.custom({required recognizer, required responder, required synthesizer, bool streamAudio = false})`
(`voice_session.dart:33-38`).

- `SpeechRecognizer`: `Future<String> transcribe(Uint8List pcm16kMono, {String? language})`,
  `abstract String? language`, `addCloseListener`, `close`.
- `SpeechSynthesizer`: `Future<Uint8List> synthesize(String)` (PCM16 LE mono), `int get sampleRate`,
  `addCloseListener`, `close` (`flutter_gemma_interface.dart:667-733`).
- `VoiceResponder({required Stream<String> Function(String) respond, required Future<void> Function() stop})`. The
  contract: `stop` must end the `respond` stream (`voice_responder.dart:5-19`).
- The only methods are `runTurn(Uint8List)` (:201) and `interrupt()` (:224). **There is no `startTurn`**: that name is
  our SpeechRepository's. A second `runTurn` while one is in flight throws `StateError`.
- Events with `streamAudio: true`:
  1. `VoiceTranscriptEvent(text, isFinal: true)`
  2. `VoiceReplyTextEvent` per token, interleaved with `VoiceReplyAudioEvent(isFinal: false)` per clause
  3. a zero-byte `VoiceReplyAudioEvent(isFinal: true)`
  4. `VoiceTurnCompleteEvent(transcript, replyText)`

  An empty transcript gives `Complete('', '')` with no LLM call (:324); an empty reply gives no audio (:500). An
  interrupt ends with `VoiceTurnInterruptedEvent(transcript, partialReplyText)`. Any stage failure is a **stream
  error** with no terminal event, and it beats an interrupt (:469-490, :538-548). `VoiceErrorEvent` is never emitted.
- `interrupt()` runs `responder.stop().timeout(5 s)`, then a 5 s bounded drain, then waits for the terminal
  (:224-273). **Worst case ≈10 s.** A forced drain detaches the generation and lets it keep running. Calling
  `interrupt()` again, or when idle, is a no-op.
- Clauses: the internal splitter breaks on `[.!?]+\s+|\n+` and needs at least 8 characters
  (`clause_splitter.dart:12,21`). It never splits on commas, flushes the tail only at the end, and cannot be configured.
- Threads: the session runs on the main isolate, and STT and TTS each run on one worker isolate
  (`tts_worker.dart:441-466`). An interrupt waits for at most one `synthesize`, which can't be cancelled.

Skeleton for (a) PCM and (b) typed turns; a typed turn swaps the recognizer.

```dart
VoiceTurn startTurn({Uint8List? pcm, String? typedText, required VoiceResponder responder, required bool speak}) {
  final s = VoiceSession.custom(
    recognizer: typedText != null ? TypedTextRecognizer(typedText) : _stt, // InstrumentedRecognizer
    responder: responder,
    synthesizer: speak ? _tts : const SilentSynthesizer(24000),           // SpokenSynthesizer(Instrumented…)
    streamAudio: true);
  return VoiceTurn(s.runTurn(pcm ?? Uint8List(0)), s.interrupt);
}

final class TypedTextRecognizer implements SpeechRecognizer {
  TypedTextRecognizer(this._text);
  final String _text;
  @override String? language;
  @override Future<String> transcribe(Uint8List _, {String? language}) async => _text;
  @override void addCloseListener(void Function() _) {}
  @override Future<void> close() async {}
}

// VoiceAssistant: listen in the same synchronous block as runTurn (P1).
try {
  await for (final e in turn.events) {
    if (id != _turnId) continue; // stale after barge-in
    switch (e) {
      case VoiceTranscriptEvent(:final text): if (text.trim().isNotEmpty) _commitUser(text);
      case VoiceReplyTextEvent(:final chunk): _partial.value += chunk;
      case VoiceReplyAudioEvent(:final pcm, :final sampleRate, :final isFinal):
        if (pcm.isNotEmpty) { if (!playing) { playing = true; _audio.beginPlayback(sampleRate); } _audio.enqueuePcm(pcm); }
        if (isFinal && playing) _audio.endPlayback();
      case VoiceTurnCompleteEvent(:final replyText): if (playing) await _audio.playbackDrained; _commit(replyText);
      case VoiceTurnInterruptedEvent(:final partialReplyText): _commit(partialReplyText, interrupted: true);
      case VoiceErrorEvent(): // reserved
    }
  }
} catch (e, st) { await _audio.stopPlayback(); _fail(e, st); }
```

Barge-in: `await _audio.stopPlayback(); _turnId++; _pending = _turn?.interrupt(); startCapture()`. Before the next
`startTurn`, `await _pending` and wait for `conversation.isGenerating == false` (P2).

## 4. Responder over `ConversationRepository`

```dart
VoiceResponder build({required void Function(TurnSideEvent) onSide /*, Uint8List? image (Inc 4) */}) {
  var cancelled = false; // per-turn latch
  return VoiceResponder(
    respond: (text) async* {
      if (cancelled) return;
      await for (final e in _conversation.ask(text /*, image: image */)) {
        switch (e) {
          case AssistantTextDelta(:final text) when !cancelled: yield text;
          case AssistantTextDelta(): break;
          case AssistantDone(:final metrics): onSide(TurnMetrics(metrics));
          case AssistantFailed(:final error): throw error;
        }
      }
    },
    stop: () async { cancelled = true; await _conversation.stop(); });
}
```

- `stop` reaches `chat.stopGeneration()` and waits up to 5 s for the turn to end
  (`conversation_repository_gemma.dart:147-169`), which meets the contract. Don't `break` out of the loop, or the
  final `AssistantDone(stopped: true)` and its stop latency are lost.
- **Rethrow `AssistantFailed`.** `ask` reports failures as events (`conversation_repository.dart:21-25`). If one is
  dropped, VoiceSession sees an empty reply and ends with `Complete(transcript, '')`, a silent failure.
- Inc 4: `respond` receives only text, so the image comes in through the `build(image:)` closure.
- `agent_voice_responder.dart`. Copy the per-turn cancel token and its `stop` (:41-57). Avoid speaking only the
  `DoneEvent` (:20-26), which defeats `streamAudio`; in Inc 6, speak `TextChunkEvent`s. Also avoid `main.dart`'s
  one-shot WAV playback and its `default: break` (:333-383).

## 5. Audio I/O

**Mic (`record`):**

```dart
await rec.ios?.manageAudioSession(false); // null off iOS; per recorder; dispose() resets it
await rec.setOnConfigChanged((c) => _failCapture('mic forced to ${c.sampleRate} Hz'));
final stream = await rec.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000,
    numChannels: 1, androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition)));
```

- `manageAudioSession(false)` exists (`record.dart:235`; `Recorder.swift:29-32,112`), but record still sets the
  shared session's preferred sample rate to 16000 (`RecorderSessionExtension.swift:8-17`). **iPhone check
  (`swift-architect`):** playback after a capture may sound muffled.
- macOS resamples from 48 kHz itself (`AudioStreamProcessor.swift:13-29`).
- Gate and meter: RMS per chunk in Dart. `onAmplitudeChanged` is peak dBFS, not RMS.
- Cap: a `BytesBuilder` of at most window × 32 000 bytes, plus a `Timer(window)`. After `stop()`, wait for `onDone`.

**Player (`flutter_soloud`, names verified):**

```dart
await SoLoud.instance.init(); // once; iOS: after setActive(true)
_src = SoLoud.instance.setBufferStream(bufferingType: BufferingType.released, bufferingTimeNeeds: 0.2,
    sampleRate: rate, channels: Channels.mono, format: BufferType.s16le);   // soloud.dart:1174
SoLoud.instance.addAudioDataStream(_src, pcm); _h ??= SoLoud.instance.play(_src); // :1426, :1996
SoLoud.instance.setDataIsEnded(_src); _drained = _src.allInstancesFinished.first;  // :1464
await SoLoud.instance.stop(_h); await SoLoud.instance.disposeSource(_src);         // stopNow: :2544, :2599
```

- `bufferingTimeNeeds` **defaults to 2 s** (:1178). An underrun between clauses pauses playback until 2 more seconds
  arrive (`audiobuffer.cpp:418-443`).
- `allInstancesFinished` fires on a natural end and on `stop` (:740). Also complete `drained` when nothing played.
  Adding after `setDataIsEnded` throws (:1413), so guard every add by turn id.

**Session (`audio_session`)**, configured once: `playAndRecord`, options `defaultToSpeaker | allowBluetoothA2dp`,
`AVAudioSessionMode.defaultMode`; on Android, `AndroidAudioAttributes(contentType: speech, usage: assistant)` and
`AndroidAudioFocusGainType.gainTransient`. Then `setActive(true)`.

- iOS order: configure, `setActive(true)`, `SoLoud.init`, `manageAudioSession(false)`. Miniaudio never activates the
  session (`soloud_miniaudio.cpp:352-354,475-477`).
- macOS: `configure`, `setActive` and `rec.ios` are all no-ops (`AudioSessionPlugin.m`, `core.dart:223`). The
  entitlements and the usage string are already present; nothing else is needed.

## 6. Warm-up and latency (macOS)

After the LLM is ready, ModelRepository:
1. STT: install, `getActiveStt`, `transcribe(Uint8List(16000))` (0.5 s of silence; ignore the text).
2. TTS: install, `getActiveTts`, assert `sampleRate == 24000`, `synthesize('Ready.')` must be non-empty (not played).

Whisper always pads to 30 s (`stt_core.dart:71`), so warm-up time equals per-turn STT time.

| Stage | Est. (Apple silicon) |
|---|---|
| Whisper base | 0.3–0.8 s |
| Gemma time to first token (GPU) | 0.2–0.5 s |
| First clause, 10–20 tokens | 0.3–0.7 s |
| Inflect first clause (~90× real time) | 0.03–0.1 s |
| soloud start | <0.05 s |
| **Time to first audio after release** | **≈0.9–2.1 s** |
| Barge-in to silence | one FFI call, ≪150 ms |

## 7. Tests

**Unit** (`test/domain/use_cases/voice_assistant_test.dart`): a real `VoiceSession.custom` with fakes.
`FakeRecognizer` and `RecordingSynth` can gate or throw. The existing `FakeConversationRepository` sits behind the
real TurnResponder. `FakeAudioRepository` records calls, and the test drives its `playbackDrained`. The speech
package's `test/voice_session_test.dart` shows the patterns. Add `fake_async`.

Cases:
- Happy path: correct phases; `beginPlayback(24000)` runs once, on the first non-empty chunk; idle only after the
  audio drains.
- Silent or short capture, or an empty transcript: no `ask`.
- Barge-in while thinking and while speaking: playback stops before `interrupt`; stale chunks are dropped; the partial
  reply is marked interrupted; the next `ask` waits for the interrupt and for `isGenerating` to be false.
- A repository, recognizer or synthesizer error leads to the error phase.
- Typed turn: no STT call. Speech off: no playback.
- A stop that never ends the stream: `interrupt` still resolves within 2 × `drainTimeout`.

**Integration** (`integration_test/voice_loop_test.dart -d macos --dart-define=GEMMA_MODEL_PATH=…`). Load
`test_assets/france_16k.pcm` as a pubspec asset and feed it through VoiceAssistant's PCM entry point, the one that mic
release calls. Assert that the transcript contains "france", the reply contains "paris" and the first chunk is at
24 kHz. Print `VOICE stt= ttft= ttfa= tts1=`. Then barge in on a long typed reply and run a follow-up turn.

Fixture: verified on this Mac (`sox` is absent), giving 52,462 bytes, 1.64 s:

```sh
say -v Samantha -o /tmp/france.aiff "What is the capital of France?"
ffmpeg -loglevel error -y -i /tmp/france.aiff -ar 16000 -ac 1 -f s16le -acodec pcm_s16le test_assets/france_16k.pcm
```

`afconvert -d LEI16@16000` writes a **4096-byte** WAV header. Parse the `data` chunk; never skip 44 bytes.

## 8. Pitfalls and upstream issues

- **P1** The driver starts on `onListen` (`voice_session.dart:210-213`). An `interrupt()` that arrives before anyone
  listens waits forever (:241-266).
- **P2** After a forced drain the next `ask` fails as busy (`conversation_repository_gemma.dart:80-85`).
- **P3** Zero-byte audio is normal: Inflect returns one for a non-speech clause (`tts_worker.dart:449-452`). Switch to
  `speaking` only on a non-empty chunk.
- **P4** Prompt for short sentences; decorators delegate `language`.

Upstream, for the maintainer:
- **U1** No STT/TTS backend getter; singleton reuse ignores `preferredBackend`.
- **U2** TTS install has no `fromFiles`.
- **U3** The clause splitter can't be injected (`voice_session.dart:342`).
- **U4** The 2 × `drainTimeout` worst case is undocumented; an interrupt before listen hangs.
- **U5** The example `main.dart:196-197` says "Inflect (Metal)", but the default is the CPU.
