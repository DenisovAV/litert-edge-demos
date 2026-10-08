import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Deterministic pseudo-random bytes (incompressible, no accidental HTML).
Uint8List testBytes(int length, {int seed = 1}) {
  final random = Random(seed);
  return Uint8List.fromList([
    for (var i = 0; i < length; i++) random.nextInt(256),
  ]);
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
