// The domain imports only Dart core libraries, so `@immutable` from
// `package:meta` is not available here. Every field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// A photo file, named by its path relative to the application documents directory.
///
/// The absolute directory changes between iOS launches, so an absolute path must not be stored.
final class PhotoRef {
  /// Throws an [ArgumentError] when [path] is empty, absolute, or leaves the documents directory.
  new(this.path) {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'A photo path must not be empty');
    }
    if (_absolute.hasMatch(path)) {
      throw ArgumentError.value(path, 'path', 'A photo path must be relative');
    }
    if (path.split(_separator).contains('..')) {
      throw ArgumentError.value(path, 'path', 'A photo path must stay inside the documents directory');
    }
  }

  // A leading separator, or a Windows drive letter.
  static final _absolute = RegExp(r'^([/\\]|[A-Za-z]:)');
  static final _separator = RegExp(r'[/\\]');

  final String path;

  @override
  bool operator ==(Object other) => other is PhotoRef && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
