import 'package:shared_preferences/shared_preferences.dart';

/// Persistent key-value storage for app settings. The app uses
/// [SharedPreferencesSettingsStore]; tests use an in-memory one.
abstract interface class SettingsStore {
  Future<String?> getString(String key);
  Future<bool?> getBool(String key);
  Future<void> setString(String key, String value);
  Future<void> setBool(String key, {required bool value});
  Future<void> remove(String key);
}

/// [SettingsStore] over `SharedPreferencesAsync`. Every key gets the `app.`
/// prefix: flutter_edge_ai keeps its install records in the same preferences
/// (legacy API, `flutter.` prefix on Apple platforms), and the two must
/// never collide.
final class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static String _key(String key) => 'app.$key';

  @override
  Future<String?> getString(String key) => _preferences.getString(_key(key));

  @override
  Future<bool?> getBool(String key) => _preferences.getBool(_key(key));

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(_key(key), value);

  @override
  Future<void> setBool(String key, {required bool value}) =>
      _preferences.setBool(_key(key), value);

  @override
  Future<void> remove(String key) => _preferences.remove(_key(key));
}
