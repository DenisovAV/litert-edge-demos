/// Outcome of an operation that can fail, in the style of the official
/// compass_app sample: services and repositories return a [Result] instead of
/// throwing across layers.
///
/// ```dart
/// switch (await repository.open()) {
///   case Ok():
///     ...
///   case Error(:final error):
///     ...
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// A successful result carrying [value].
  const factory Result.ok(T value) = Ok._;

  /// A failed result carrying [error].
  const factory Result.error(Exception error) = Error._;
}

/// A successful [Result].
final class Ok<T> extends Result<T> {
  const Ok._(this.value);

  final T value;

  @override
  String toString() => 'Result<$T>.ok($value)';
}

/// A failed [Result]. Shadows `dart:core`'s `Error` in files that import this
/// library, exactly like compass_app; catch blocks there test for `Exception`.
final class Error<T> extends Result<T> {
  const Error._(this.error);

  final Exception error;

  @override
  String toString() => 'Result<$T>.error($error)';
}

/// A non-[Exception] throwable (for example a plugin's `StateError`) carried
/// through a [Result.error].
final class UnexpectedError implements Exception {
  const UnexpectedError(this.error);

  final Object error;

  @override
  String toString() => error.toString();
}

/// [error] as an [Exception], wrapping it when it is not one already.
Exception asException(Object error) =>
    error is Exception ? error : UnexpectedError(error);
