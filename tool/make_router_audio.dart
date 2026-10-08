// Speaks every router golden question (test_assets/router_golden.json) into
// a 16 kHz mono PCM16 file with macOS `say` + ffmpeg, for the camera
// assistant integration test's real-Whisper routing step (ROUTER_AUDIO_DIR).
//
//   fvm dart run tool/make_router_audio.dart [out_dir]   # build/router_audio
//
// The out dir must be under ~/Work: the macOS debug sandbox reads only there.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final out = Directory(args.isEmpty ? 'build/router_audio' : args.first)
    ..createSync(recursive: true);
  final golden = File('test_assets/router_golden.json').readAsStringSync();
  final doc = jsonDecode(golden) as Map<String, Object?>;
  final items = (doc['items']! as List<Object?>).cast<Map<String, Object?>>();
  for (var i = 0; i < items.length; i++) {
    final question = (items[i]['q']! as String).trim();
    final aiff = '${out.path}/$i.aiff';
    await _run('say', ['-v', 'Samantha', '-o', aiff, question]);
    await _run('ffmpeg', [
      '-loglevel', 'error', '-y', '-i', aiff, //
      '-ar', '16000', '-ac', '1', '-f', 's16le', '-acodec', 'pcm_s16le',
      '${out.path}/$i.pcm',
    ]);
    File(aiff).deleteSync();
  }
  // The golden next to the audio, same order: the test reads only this dir.
  File('${out.path}/index.json').writeAsStringSync(golden);
  stdout.writeln('${items.length} questions → ${out.absolute.path}');
}

Future<void> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(executable, arguments, '${result.stderr}');
  }
}
