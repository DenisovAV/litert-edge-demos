import 'package:litert_hackathon/data/services/settings/settings_store.dart';

/// [SettingsStore] in memory; [failWith] makes every call throw.
final class InMemorySettingsStore implements SettingsStore {
  final Map<String, Object> values = {};
  Exception? failWith;

  /// Keys whose writes (set and remove) throw; reads still work.
  final Set<String> failWritesOf = {};

  void _check() {
    if (failWith case final error?) throw error;
  }

  void _checkWrite(String key) {
    _check();
    if (failWritesOf.contains(key)) throw Exception('cannot write $key');
  }

  @override
  Future<String?> getString(String key) async {
    _check();
    return values[key] as String?;
  }

  @override
  Future<bool?> getBool(String key) async {
    _check();
    return values[key] as bool?;
  }

  @override
  Future<void> setString(String key, String value) async {
    _checkWrite(key);
    values[key] = value;
  }

  @override
  Future<void> setBool(String key, {required bool value}) async {
    _checkWrite(key);
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _checkWrite(key);
    values.remove(key);
  }
}
