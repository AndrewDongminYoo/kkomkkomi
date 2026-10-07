// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import '../helpers/helpers.dart';

/// The one file that may import `printing`: the adapter of the share port.
const _printingAdapter = 'lib/presentation/adapters/printing_report_share.dart';

/// Whether [source] names a library of the `printing` package.
bool namesPrinting(String source) => libraryUrisIn(source).any((uri) => uri.startsWith('package:printing/'));

void main() {
  group('namesPrinting', () {
    test('finds an import and an export of the printing package', () {
      expect(namesPrinting("import 'package:printing/printing.dart';"), isTrue);
      expect(namesPrinting('export "package:printing/printing.dart" show Printing;'), isTrue);
      expect(namesPrinting("import 'dart:io'\n    if (dart.library.html) 'package:printing/printing.dart';"), isTrue);
    });

    test('finds none in a file that names other libraries', () {
      expect(namesPrinting("import 'package:pdf/pdf.dart';\nimport 'package:printing_helper/helper.dart';"), isFalse);
      expect(namesPrinting('/// Opens the share sheet through `printing`.'), isFalse);
    });
  });

  test('the share adapter is the one file under lib that imports printing', () {
    final importers = [
      for (final file in dartFilesUnder('lib/'))
        if (namesPrinting(file.readAsStringSync())) file.path,
    ];

    // The scan covers all of `lib/`, so a second import fails the test wherever it stands, also outside
    // `lib/presentation/`.
    expect(importers, [_printingAdapter]);
  });
}
