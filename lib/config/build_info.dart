import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../domain/models/hardware_profile.dart' show BuildInfo;

/// `version:` in pubspec.yaml. test/config/build_info_test.dart keeps it
/// honest (no package_info_plus for one string).
const kAppVersion = '0.1.2+3';

/// Resolved versions of the packages that decide where the models run, as in
/// pubspec.lock (checked by test/config/build_info_test.dart: a `pub upgrade`
/// fails that test until this map is updated).
const kPackageVersions = {
  'flutter_edge_ai': '2.1.0',
  'flutter_edge_ai_litertlm': '1.9.0',
  'flutter_litert': '3.9.3',
};

/// The LiteRT-LM native bundle flutter_edge_ai_litertlm downloads
/// (`_litertlmBundle` in its hook/build.dart; checked by the same test).
const kLiteRtLmNativeTag = 'native-v0.17.1-a';

/// Set by the flutter tool for every build (`flutter_command.dart`
/// `flutterVersionDefine`); empty when a build bypasses it.
const kFlutterVersion = String.fromEnvironment('FLUTTER_VERSION');

/// What this binary is: versions and build mode, for the diagnostics report,
/// the startup line and the self-test.
BuildInfo currentBuildInfo() => BuildInfo(
  appVersion: kAppVersion,
  buildMode: kReleaseMode
      ? 'release'
      : kProfileMode
      ? 'profile'
      : 'debug',
  flutterVersion: kFlutterVersion.isEmpty ? null : kFlutterVersion,
  dartVersion: Platform.version.split(' ').first,
  packages: kPackageVersions,
  liteRtLmNative: kLiteRtLmNativeTag,
);
