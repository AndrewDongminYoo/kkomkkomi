import 'dart:io';

final _stringLiteral = RegExp(r'''(['"])([^'"\n]*)\1''');

/// The library URIs that [source] names: every string literal that looks like one, wherever it stands.
///
/// The read is the one of `test/domain/boundary_test.dart`: the layout of a directive cannot hide a URI, and a
/// string literal in a comment counts too. A URI split over adjacent string literals is the one form that it does
/// not read.
List<String> libraryUrisIn(String source) => [
  for (final literal in _stringLiteral.allMatches(source))
    if (_isLibraryUri(literal.group(2)!)) literal.group(2)!,
];

bool _isLibraryUri(String literal) =>
    literal.startsWith('dart:') || literal.startsWith('package:') || literal.endsWith('.dart');

/// The Dart files under [directory], which is a path from the package root.
List<File> dartFilesUnder(String directory) => Directory(
  directory,
).listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart')).toList();
