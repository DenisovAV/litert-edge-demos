import 'package:path_provider/path_provider.dart';

/// A model path from a `--dart-define`: absolute as given, otherwise relative
/// to the app's documents directory.
Future<String> resolveLocalPath(String path) async {
  if (path.startsWith('/')) return path;
  final docs = await getApplicationDocumentsDirectory();
  return '${docs.path}/$path';
}
