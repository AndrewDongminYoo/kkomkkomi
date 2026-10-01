import 'package:flutter_test/flutter_test.dart';

import '../helpers/helpers.dart';

const _exportDirectory = 'lib/export/';

/// The libraries of the Dart SDK that every platform has, as `test/domain/boundary_test.dart` lists them.
const _coreLibraries = {
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:developer',
  'dart:math',
  'dart:typed_data',
};

/// The packages and the units that the design allows in `lib/export/`: the unit itself, the domain, and `pdf`.
const _allowedPrefixes = ['package:kkomkkomi/export/', 'package:kkomkkomi/domain/', 'package:pdf/'];

/// What [source] names outside the libraries that `lib/export/` may import.
///
/// A Flutter library is outside them: `package:flutter/...`, a package that needs Flutter such as `printing`, and
/// an engine library such as `dart:ui`. [path] is the path of the file from the package root, and relative URIs are
/// resolved against it.
List<String> urisOutsideExport(String source, {required String path}) => [
  for (final uri in libraryUrisIn(source))
    if (!_isAllowed(uri, path: path)) uri,
];

bool _isAllowed(String uri, {required String path}) {
  final parsed = Uri.parse(uri);
  if (parsed.scheme == 'dart') return _coreLibraries.contains(uri);
  if (parsed.hasScheme) {
    final normalized = parsed.normalizePath().toString();
    return _allowedPrefixes.any(normalized.startsWith);
  }
  return Uri.parse(path).resolveUri(parsed).path.startsWith(_exportDirectory);
}

void main() {
  group('urisOutsideExport', () {
    const path = 'lib/export/report_pdf.dart';

    test('accepts the core libraries, the domain, the pdf package, and files under lib/export', () {
      const source = '''
import 'dart:typed_data';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/export/report_document.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
export 'report_labels.dart';
''';

      expect(urisOutsideExport(source, path: path), isEmpty);
    });

    test('refuses a Flutter library', () {
      const source = '''
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';
''';

      expect(urisOutsideExport(source, path: path), [
        'dart:ui',
        'package:flutter/services.dart',
        'package:flutter/widgets.dart',
        'package:material_ui/material_ui.dart',
        'package:printing/printing.dart',
      ]);
    });

    test('refuses another unit of the app, a library of one platform, and another package', () {
      const source = '''
import 'dart:io';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:intl/intl.dart';
''';

      expect(urisOutsideExport(source, path: path), [
        'dart:io',
        'package:kkomkkomi/application/application.dart',
        'package:kkomkkomi/l10n/l10n.dart',
        'package:kkomkkomi/presentation/presentation.dart',
        'package:intl/intl.dart',
      ]);
    });

    test('refuses a path that leaves lib/export', () {
      const source = '''
import '../l10n/l10n.dart';
export 'package:kkomkkomi/export/../presentation/presentation.dart';
''';

      expect(urisOutsideExport(source, path: path), [
        '../l10n/l10n.dart',
        'package:kkomkkomi/export/../presentation/presentation.dart',
      ]);
    });
  });

  test('no file under lib/export names a library outside the core libraries, the domain, and the pdf package', () {
    final files = dartFilesUnder(_exportDirectory);

    // An empty scan would pass without checking anything.
    expect(files, isNotEmpty);

    final violations = {
      for (final file in files)
        if (urisOutsideExport(file.readAsStringSync(), path: file.uri.path) case final uris when uris.isNotEmpty)
          file.path: uris,
    };

    expect(violations, isEmpty);
  });
}
