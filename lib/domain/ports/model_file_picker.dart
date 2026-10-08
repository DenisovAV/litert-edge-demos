// A port: an interface that the domain and the view models depend on and an
// outer layer implements. Every port lives in lib/domain/ports/;
// function-typed dependencies stay next to their one consumer.

/// How this platform imports a model file the user already has (the custom
/// chat model's "Import file…").
sealed class const ImportSupport();

/// Desktop: the picker returns the user's own file, cloned or copied from
/// where it is; a models folder can also be scanned.
final class const ImportFromFolder() extends ImportSupport;

/// iOS: the document picker hands over a temporary copy, which the store
/// moves instead of copying again (or deletes once copied).
final class const ImportFromFiles() extends ImportSupport;

/// Not possible here; [reason] is shown instead of the button.
final class const ImportUnsupported(final String reason) extends ImportSupport;

/// Shows the platform's picker. The app uses `FileSelectorModelFilePicker`
/// (data/services); tests use a fake.
abstract interface class ModelFilePicker {
  ImportSupport get support;

  /// One `.litertlm` (the custom chat model); null when the user cancelled.
  /// Desktop filters by extension; iOS shows every file (no UTI exists for
  /// `.litertlm`), and the store rejects any other extension.
  Future<String?> pickModelFile();

  /// Where the picker's temporary copies live (moved, not copied); null
  /// when the picker returns the user's own files.
  Future<String?> temporaryCopiesDirectory();
}
