// Fixture devices for the integration tests: a microphone that plays a
// recording (wav.dart reads it) and an image picker that returns a file.

import 'dart:async';
import 'dart:typed_data';

import 'package:litert_hackathon/data/services/audio/mic_service.dart';
import 'package:litert_hackathon/data/services/images/image_input_service.dart';
import 'package:litert_hackathon/domain/models/llm_image.dart';

/// Streams [pcm] in 64 ms chunks at real-time pace from each start, then
/// nothing until stopped: a deterministic microphone (no TCC prompt). Set
/// [pcm] between turns to ask another question.
final class FixtureMicService implements MicService {
  FixtureMicService(this.pcm);

  Uint8List pcm;

  /// How long the next start takes before it plays (then back to zero): a
  /// capture that starts late, as behind a cold audio warm-up.
  Duration startDelay = Duration.zero;
  static const _chunkBytes = 2048; // 64 ms at 16 kHz mono PCM16
  StreamController<Uint8List>? _stream;
  Timer? _timer;

  /// Starts that have begun playing.
  int starts = 0;

  /// When the last start began playing.
  DateTime? startedAt;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startPcm16({
    required int sampleRate,
    required void Function(String actual) onFormatChanged,
  }) async {
    final delay = startDelay;
    startDelay = Duration.zero;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    starts++;
    startedAt = DateTime.now();
    await stop();
    _stream = StreamController<Uint8List>();
    var offset = 0;
    final source = pcm;
    _timer = Timer.periodic(const Duration(milliseconds: 64), (_) {
      if (offset >= source.length) return;
      final end = (offset + _chunkBytes).clamp(0, source.length);
      _stream?.add(Uint8List.sublistView(source, offset, end));
      offset = end;
    });
    return _stream!.stream;
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    // Not awaited: a stream nobody listened to would never report done.
    unawaited(_stream?.close());
    _stream = null;
  }

  @override
  Future<void> dispose() => stop();
}

/// The image picker played by a file: every gallery pick returns [encoded]
/// (the real normalization still runs). No camera, like macOS.
final class FixtureImageInputService implements ImageInputService {
  FixtureImageInputService(this._encoded);

  final Uint8List _encoded;
  int picks = 0;

  @override
  bool supports(ImageSourceKind source) => source == ImageSourceKind.gallery;

  @override
  Future<Uint8List?> pick(ImageSourceKind source) async {
    if (!supports(source)) throw UnsupportedImageSourceException(source);
    picks++;
    return _encoded;
  }
}
