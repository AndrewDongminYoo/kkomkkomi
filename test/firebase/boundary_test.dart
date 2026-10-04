import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/helpers.dart';

/// The one directory under `lib/` that may import a Firebase package.
const _firebaseDirectory = 'lib/firebase/';

/// The one file outside [_firebaseDirectory] that may import it: the entry point of the production flavor.
const _productionEntryPoint = 'lib/main_production.dart';

/// The file that `flutterfire configure` generates. Git ignores it, so only a checkout that ran the tool has it,
/// and it is not tracked code. It imports `firebase_core`, so the scans leave it out.
const _generatedOptions = 'lib/firebase_options.dart';

final _firebasePackage = RegExp('package:(?:firebase|cloud)_');

/// Whether [source] names a FlutterFire package: `firebase_*`, or `cloud_*` such as `cloud_firestore`.
///
/// The check reads the raw text and not the directives, so a comment that names such a package counts too, and no
/// layout of a directive can hide one.
bool namesFirebasePackage(String source) => _firebasePackage.hasMatch(source);

/// A string literal that is a relative path to a file in a directory named `firebase`.
///
/// The read of `libraryUrisIn` pairs the quotes from the left, so an apostrophe in a comment before a directive on
/// the same line makes it read the text between that apostrophe and the quote of the directive. This pattern reads
/// the directive itself, and it also finds a path that does not lead to `lib/firebase/`, which only makes the test
/// stricter.
final _relativeFirebasePath = RegExp(r'''['"](?:\.{1,2}/)*(?:[\w.]+/)*firebase/[\w./]*\.dart['"]''');

/// Whether [source] names a file under `lib/firebase/`. [path] is the path of the file from the package root, and
/// relative URIs are resolved against it.
bool namesFirebaseDirectory(String source, {required String path}) =>
    source.contains('package:kkomkkomi/firebase/') ||
    _relativeFirebasePath.hasMatch(source) ||
    libraryUrisIn(source).any((uri) {
      final parsed = Uri.parse(uri);
      return !parsed.hasScheme && Uri.parse(path).resolveUri(parsed).path.startsWith(_firebaseDirectory);
    });

/// Whether [source] names the generated options file.
bool namesGeneratedOptions(String source) => source.contains('firebase_options');

/// The paths of the tracked Dart files under `lib/` whose text passes [test].
List<String> _trackedLibFilesWhere(bool Function(String source, String path) test) => [
  for (final file in dartFilesUnder('lib/'))
    if (file.path != _generatedOptions && test(file.readAsStringSync(), file.path)) file.path,
];

void main() {
  group('namesFirebasePackage', () {
    test('finds an import, an export, a conditional import, and a comment that name a FlutterFire package', () {
      expect(namesFirebasePackage("import 'package:firebase_core/firebase_core.dart';"), isTrue);
      expect(namesFirebasePackage('export "package:firebase_auth/firebase_auth.dart" show User;'), isTrue);
      expect(
        namesFirebasePackage("import 'a.dart'\n    if (dart.library.io) 'package:firebase_storage/x.dart';"),
        isTrue,
      );
      expect(namesFirebasePackage("import 'package:cloud_firestore/cloud_firestore.dart';"), isTrue);
      expect(namesFirebasePackage("/* it's */ import 'package:firebase_core/firebase_core.dart';"), isTrue);
      expect(namesFirebasePackage('/// See package:firebase_auth/firebase_auth.dart.'), isTrue);
    });

    test('finds none in a file that names the Firebase unit of the app and other packages', () {
      expect(namesFirebasePackage("import 'package:kkomkkomi/firebase/firebase.dart';"), isFalse);
      expect(namesFirebasePackage("import 'package:firebaseless/firebaseless.dart';"), isFalse);
      expect(namesFirebasePackage('/// Starts Firebase through `firebase_core`.'), isFalse);
    });
  });

  group('namesFirebaseDirectory', () {
    test('finds a package URI and a relative URI that lead into lib/firebase', () {
      expect(
        namesFirebaseDirectory("import 'package:kkomkkomi/firebase/firebase.dart';", path: 'lib/main_staging.dart'),
        isTrue,
      );
      expect(namesFirebaseDirectory("import 'firebase/firebase_identity.dart';", path: 'lib/bootstrap.dart'), isTrue);
      expect(namesFirebaseDirectory("export '../firebase/firebase.dart';", path: 'lib/app/app.dart'), isTrue);
    });

    test('finds a relative directive that follows a comment with an apostrophe on the same line', () {
      expect(
        namesFirebaseDirectory("/* it's */ import 'firebase/firebase.dart';", path: 'lib/bootstrap.dart'),
        isTrue,
      );
      expect(namesFirebaseDirectory("// it's\nimport './firebase/firebase.dart';", path: 'lib/bootstrap.dart'), isTrue);
    });

    test('finds none in a file that names other units', () {
      expect(
        namesFirebaseDirectory(
          "import 'package:kkomkkomi/presentation/presentation.dart';",
          path: 'lib/bootstrap.dart',
        ),
        isFalse,
      );
      expect(namesFirebaseDirectory("import 'firebase_helper.dart';", path: 'lib/bootstrap.dart'), isFalse);
    });
  });

  group('namesGeneratedOptions', () {
    test('finds a package URI and a relative URI of the generated options file', () {
      expect(namesGeneratedOptions("import 'package:kkomkkomi/firebase_options.dart';"), isTrue);
      expect(namesGeneratedOptions("import '../firebase_options.dart';"), isTrue);
    });

    test('finds none in a file that names the Firebase unit', () {
      expect(namesGeneratedOptions("import 'package:kkomkkomi/firebase/firebase.dart';"), isFalse);
    });
  });

  test('lib/firebase is the one directory under lib that imports a Firebase package', () {
    final importers = _trackedLibFilesWhere((source, _) => namesFirebasePackage(source));

    // A rule that no file meets would pass without checking anything.
    expect(importers, isNotEmpty);
    expect(importers.where((path) => !path.startsWith(_firebaseDirectory)), isEmpty);
  });

  test('the production entry point is the one file outside lib/firebase that imports it', () {
    final importers = _trackedLibFilesWhere(
      (source, path) => !path.startsWith(_firebaseDirectory) && namesFirebaseDirectory(source, path: path),
    );

    expect(importers, [_productionEntryPoint]);
  });

  test('no tracked file under lib names the generated options file', () {
    expect(_trackedLibFilesWhere((source, _) => namesGeneratedOptions(source)), isEmpty);
  });

  // No test runs an entry point: `main` would start the real plugin. So these tests read the text of the entry
  // points, and they are what pins which flavor gives `bootstrap` which adapters.
  group('the entry points', () {
    String sourceOf(String flavor) => File('lib/main_$flavor.dart').readAsStringSync();

    test('production gives bootstrap the Firebase identity and publisher and no other', () {
      final source = sourceOf('production');

      expect(source, contains('final identity = FirebaseIdentity();'));
      expect(source, contains('identity: identity,'));
      expect(source, contains('publisher: FirebasePublisher(),'));
      expect(source, isNot(contains('UnavailableIdentity')));
      expect(source, isNot(contains('UnavailablePublisher')));
    });

    for (final flavor in ['development', 'staging']) {
      test('$flavor gives bootstrap the unavailable identity and publisher and no Firebase', () {
        final source = sourceOf(flavor);

        expect(source, contains('identity: const UnavailableIdentity(),'));
        expect(source, contains('publisher: const UnavailablePublisher(),'));
        expect(source, isNot(contains('FirebaseIdentity')));
        expect(source, isNot(contains('FirebasePublisher')));
      });
    }
  });
}
