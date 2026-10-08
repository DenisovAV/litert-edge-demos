import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/wav.dart';

void main() {
  group('C6: pcm16FromWav (any header size, never a fixed offset)', () {
    test("afconvert's 4096-byte header (test_assets/q_cats.wav)", () {
      final wav = File('test_assets/q_cats.wav').readAsBytesSync();
      final pcm = pcm16FromWav(wav);
      // 1.33 s spoken (as Demo 3 logged it): the data chunk, not the header.
      expect(pcm.length, greaterThan(40000));
      expect(pcm.length, lessThan(wav.length - 4000));
      expect(pcm.offsetInBytes, greaterThanOrEqualTo(4096));
    });

    test('a plain 44-byte header', () {
      final samples = Uint8List.fromList(List.generate(64, (i) => i));
      final pcm = pcm16FromWav(_wav(samples));
      expect(pcm, samples);
    });

    test('anything but 16 kHz mono PCM16 is refused', () {
      expect(
        () => pcm16FromWav(_wav(Uint8List(8), channels: 2)),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => pcm16FromWav(_wav(Uint8List(8), rate: 44100)),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => pcm16FromWav(Uint8List.fromList('RIFF0000WAVE'.codeUnits)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Uint8List _wav(Uint8List samples, {int channels = 1, int rate = 16000}) {
  final b = BytesBuilder();
  void u32(int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) =>
      b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  b.add('RIFF'.codeUnits);
  u32(36 + samples.length);
  b.add('WAVE'.codeUnits);
  b.add('fmt '.codeUnits);
  u32(16);
  u16(1);
  u16(channels);
  u32(rate);
  u32(rate * channels * 2);
  u16(channels * 2);
  u16(16);
  b.add('data'.codeUnits);
  u32(samples.length);
  b.add(samples);
  return b.toBytes();
}
