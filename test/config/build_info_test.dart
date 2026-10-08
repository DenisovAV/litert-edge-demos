import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/build_info.dart';

/// `version: "x"` of [package] in pubspec.lock.
String? _lockedVersion(String lock, String package) => RegExp(
  '^  $package:\\n(?:    .*\\n)*?    version: "([^"]+)"',
  multiLine: true,
).firstMatch(lock)?.group(1);

void main() {
  test('kAppVersion is pubspec.yaml\'s version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(kAppVersion, version);
  });

  test('kPackageVersions match pubspec.lock (update the map after a pub '
      'upgrade)', () {
    final lock = File('pubspec.lock').readAsStringSync();
    for (final MapEntry(key: package, value: version)
        in kPackageVersions.entries) {
      expect(_lockedVersion(lock, package), version, reason: package);
    }
  });

  test(
    'kLiteRtLmNativeTag is the bundle flutter_edge_ai_litertlm downloads',
    () {
      final config = jsonDecode(
        File('.dart_tool/package_config.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final packages = (config['packages']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final root =
          packages.firstWhere(
                (p) => p['name'] == 'flutter_edge_ai_litertlm',
              )['rootUri']!
              as String;
      final hook = File.fromUri(
        Uri.parse(root.endsWith('/') ? root : '$root/')
            .resolve('hook/build.dart'),
      ).readAsStringSync();
      final bundle = RegExp(
        r"const _litertlmBundle = _NativeBundle\([\s\S]*?version: '([^']+)',"
        r"[\s\S]*?releaseTagPrefix: '([^']+)'",
      ).firstMatch(hook);
      expect(bundle, isNotNull, reason: 'hook/build.dart layout changed');
      expect(kLiteRtLmNativeTag, '${bundle!.group(2)}${bundle.group(1)}');
    },
  );
}
