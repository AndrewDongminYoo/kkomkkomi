import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/helpers.dart';

/// The one directory under `lib/` that may import `purchases_flutter`.
const _billingDirectory = 'lib/billing/';

/// The one file outside [_billingDirectory] that may import it: the entry point of the production flavor.
const _productionEntryPoint = 'lib/main_production.dart';

/// Whether [source] names `purchases_flutter`, or `purchases_ui_flutter`, which it ships beside.
///
/// The check reads the raw text and not the directives, so a comment that names the package counts too, and no
/// layout of a directive can hide one.
bool namesPurchasesPackage(String source) => source.contains(RegExp('package:purchases_(?:ui_)?flutter'));

/// A string literal that is a relative path to a file in a directory named `billing`.
///
/// It plays the part that the same pattern plays in `test/firebase/boundary_test.dart`: it reads a directive that
/// follows a comment with an apostrophe on the same line.
final _relativeBillingPath = RegExp(r'''['"](?:\.{1,2}/)*(?:[\w.]+/)*billing/[\w./]*\.dart['"]''');

/// Whether [source] names a file under `lib/billing/`. [path] is the path of the file from the package root, and
/// relative URIs are resolved against it.
bool namesBillingDirectory(String source, {required String path}) =>
    source.contains('package:kkomkkomi/billing/') ||
    _relativeBillingPath.hasMatch(source) ||
    libraryUrisIn(source).any((uri) {
      final parsed = Uri.parse(uri);
      return !parsed.hasScheme && Uri.parse(path).resolveUri(parsed).path.startsWith(_billingDirectory);
    });

/// The paths of the Dart files under `lib/` whose text passes [test].
List<String> _libFilesWhere(bool Function(String source, String path) test) => [
  for (final file in dartFilesUnder('lib/'))
    if (test(file.readAsStringSync(), file.path)) file.path,
];

void main() {
  group('namesPurchasesPackage', () {
    test('finds an import, an export, a conditional import, and a comment that name the package', () {
      expect(namesPurchasesPackage("import 'package:purchases_flutter/purchases_flutter.dart';"), isTrue);
      expect(namesPurchasesPackage('export "package:purchases_flutter/models/store.dart" show Store;'), isTrue);
      expect(
        namesPurchasesPackage("import 'a.dart'\n    if (dart.library.io) 'package:purchases_flutter/x.dart';"),
        isTrue,
      );
      expect(namesPurchasesPackage("import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';"), isTrue);
      expect(namesPurchasesPackage('/// See package:purchases_flutter/purchases_flutter.dart.'), isTrue);
    });

    test('finds none in a file that names the billing unit of the app and other packages', () {
      expect(namesPurchasesPackage("import 'package:kkomkkomi/billing/billing.dart';"), isFalse);
      expect(namesPurchasesPackage("import 'package:in_app_purchase/in_app_purchase.dart';"), isFalse);
      expect(namesPurchasesPackage('/// Reads the plan through `purchases_flutter`.'), isFalse);
    });
  });

  group('namesBillingDirectory', () {
    test('finds a package URI and a relative URI that lead into lib/billing', () {
      expect(
        namesBillingDirectory("import 'package:kkomkkomi/billing/billing.dart';", path: 'lib/main_staging.dart'),
        isTrue,
      );
      expect(namesBillingDirectory("import 'billing/purchases_store.dart';", path: 'lib/bootstrap.dart'), isTrue);
      expect(namesBillingDirectory("export '../billing/billing.dart';", path: 'lib/app/app.dart'), isTrue);
    });

    test('finds a relative directive that follows a comment with an apostrophe on the same line', () {
      expect(namesBillingDirectory("/* it's */ import 'billing/billing.dart';", path: 'lib/bootstrap.dart'), isTrue);
    });

    test('finds none in a file that names other units', () {
      expect(
        namesBillingDirectory("import 'package:kkomkkomi/presentation/presentation.dart';", path: 'lib/bootstrap.dart'),
        isFalse,
      );
      expect(namesBillingDirectory("import 'billing_helper.dart';", path: 'lib/bootstrap.dart'), isFalse);
    });
  });

  test('lib/billing is the one directory under lib that imports purchases_flutter', () {
    final importers = _libFilesWhere((source, _) => namesPurchasesPackage(source));

    // A rule that no file meets would pass without checking anything.
    expect(importers, isNotEmpty);
    expect(importers.where((path) => !path.startsWith(_billingDirectory)), isEmpty);
  });

  test('the production entry point is the one file outside lib/billing that imports it', () {
    final importers = _libFilesWhere(
      (source, path) => !path.startsWith(_billingDirectory) && namesBillingDirectory(source, path: path),
    );

    expect(importers, [_productionEntryPoint]);
  });

  // No test runs an entry point, so these tests read the text of the entry points, as the Firebase boundary test
  // does, and they are what pins which flavor gives `bootstrap` which entitlements.
  group('the entry points', () {
    // The formatter may break a long argument over lines, so the read joins each run of white space into a space.
    String sourceOf(String flavor) => File('lib/main_$flavor.dart').readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

    test('production gives bootstrap the RevenueCat adapter, and the Free-only adapter without one', () {
      final source = sourceOf('production');

      expect(
        source,
        contains(
          'entitlements: revenueCatEntitlementsFor(identity: identity, platform: defaultTargetPlatform) ?? '
          'const FreeEntitlements(),',
        ),
      );
      // The RevenueCat app user ID is the Firebase user ID, so the adapter and bootstrap share one identity.
      expect(source, contains('final identity = FirebaseIdentity();'));
      expect(source, contains('identity: identity,'));
    });

    for (final flavor in ['development', 'staging']) {
      test('$flavor gives bootstrap the Free-only entitlements and no RevenueCat', () {
        final source = sourceOf(flavor);

        expect(source, contains('entitlements: const FreeEntitlements(),'));
        expect(source, isNot(contains('RevenueCat')));
      });
    }
  });
}
