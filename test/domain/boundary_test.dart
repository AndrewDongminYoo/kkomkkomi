// 🎯 Dart imports:
import 'dart:io';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

const _domainDirectory = 'lib/domain/';
const _domainPackagePrefix = 'package:kkomkkomi/domain/';

/// The libraries of the Dart SDK that every platform has.
///
/// The Flutter engine libraries, such as `dart:ui`, and the libraries of one platform, such as `dart:io`, are not in
/// this set.
const _coreLibraries = {
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:developer',
  'dart:math',
  'dart:typed_data',
};

final _stringLiteral = RegExp(r'''(['"])([^'"\n]*)\1''');
final _partOfLibraryName = RegExp(r'\bpart\s+of\s+[A-Za-z_][\w.]*\s*;');

/// What [source] names outside the domain.
///
/// The check reads every string literal that looks like a library URI, wherever it stands, so the layout of a
/// directive, an annotation before it, and a `part of` directive cannot hide a URI. A string literal in a comment
/// counts too. A URI split over adjacent string literals is the one form that the check does not read.
///
/// The domain may name a library in [_coreLibraries] and a file under `lib/domain/`. [path] is the path of the file
/// from the package root, and relative URIs are resolved against it.
List<String> urisOutsideDomain(String source, {required String path}) => [
  for (final literal in _stringLiteral.allMatches(source))
    if (_isLibraryUri(literal.group(2)!) && !_staysInDomain(literal.group(2)!, path: path)) literal.group(2)!,
  // A `part of` directive with a library name makes the file a part of a library that the check cannot find.
  for (final partOf in _partOfLibraryName.allMatches(source)) partOf.group(0)!,
];

bool _isLibraryUri(String literal) =>
    literal.startsWith('dart:') || literal.startsWith('package:') || literal.endsWith('.dart');

bool _staysInDomain(String uri, {required String path}) {
  final parsed = Uri.parse(uri);
  if (parsed.scheme == 'dart') return _coreLibraries.contains(uri);
  if (parsed.hasScheme) return parsed.normalizePath().toString().startsWith(_domainPackagePrefix);
  return Uri.parse(path).resolveUri(parsed).path.startsWith(_domainDirectory);
}

void main() {
  group('urisOutsideDomain', () {
    const path = 'lib/domain/visit.dart';

    test('accepts the core libraries and files under lib/domain', () {
      const source = '''
import 'dart:async';
import "dart:convert" show jsonEncode;
import 'package:kkomkkomi/domain/zone.dart';
import 'zone_record.dart';
export 'visit_date.dart';
part 'visit.part.dart';
part of 'domain.dart';
''';

      expect(urisOutsideDomain(source, path: path), isEmpty);
    });

    test('accepts a string literal that is not a library URI', () {
      expect(urisOutsideDomain("const message = 'A photo path must be relative';", path: path), isEmpty);
    });

    test('refuses a package outside the domain', () {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:kkomkkomi/application/application.dart';
export 'package:meta/meta.dart';
''';

      expect(urisOutsideDomain(source, path: path), [
        'package:flutter/widgets.dart',
        'package:kkomkkomi/application/application.dart',
        'package:meta/meta.dart',
      ]);
    });

    test('refuses a Flutter engine library and a library of one platform', () {
      const source = '''
import 'dart:ui';
export 'dart:ui_web';
import 'dart:io';
''';

      expect(urisOutsideDomain(source, path: path), ['dart:ui', 'dart:ui_web', 'dart:io']);
    });

    test('refuses a relative path that leaves lib/domain', () {
      const source = '''
import '../application/clock.dart';
part '../l10n/l10n.dart';
''';

      expect(urisOutsideDomain(source, path: path), ['../application/clock.dart', '../l10n/l10n.dart']);
    });

    test('refuses a package path that leaves lib/domain through dot segments', () {
      const uri = 'package:kkomkkomi/domain/../application/clock.dart';

      expect(urisOutsideDomain("export '$uri';", path: path), [uri]);
    });

    test('reads each URI of a conditional import that spans lines', () {
      const source = '''
import 'zone.dart'
    if (dart.library.io) 'package:path/path.dart';
''';

      expect(urisOutsideDomain(source, path: path), ['package:path/path.dart']);
    });

    test('reads a directive that shares its line with a comment, a directive, or an annotation', () {
      const source = '''
/* note */ export 'package:path/path.dart';
export 'dart:async'; export 'package:meta/meta.dart';
@Deprecated('old') import 'package:flutter/widgets.dart';
''';

      expect(urisOutsideDomain(source, path: path), [
        'package:path/path.dart',
        'package:meta/meta.dart',
        'package:flutter/widgets.dart',
      ]);
    });

    test('refuses to be a part of a library outside lib/domain', () {
      expect(urisOutsideDomain("part of '../bootstrap.dart';", path: path), ['../bootstrap.dart']);
      expect(urisOutsideDomain('part of kkomkkomi.bootstrap;', path: path), ['part of kkomkkomi.bootstrap;']);
    });
  });

  test('no file under lib/domain names a library outside the core libraries and lib/domain', () {
    final files = Directory(
      _domainDirectory,
    ).listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart')).toList();

    // An empty scan would pass without checking anything.
    expect(files, isNotEmpty);

    final violations = {
      for (final file in files)
        if (urisOutsideDomain(file.readAsStringSync(), path: file.uri.path) case final uris when uris.isNotEmpty)
          file.path: uris,
    };

    expect(violations, isEmpty);
  });
}
