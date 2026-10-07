// 🎯 Dart imports:
import 'dart:typed_data';

// 📦 Package imports:
import 'package:printing/printing.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';

/// What the adapter calls of `Printing.sharePdf`: the two arguments that it gives, and the answer.
typedef SharePdf = Future<bool> Function({required Uint8List bytes, String filename});

/// Opens the share sheet of the device with a PDF file through `printing`.
///
/// This is the one file under `lib/` that imports `printing`, and `test/presentation/printing_import_test.dart`
/// fails when a second file imports it.
final class PrintingReportShare implements ReportShare {
  /// The `sharePdf` argument replaces the plugin in a test.
  const new({this._sharePdf = Printing.sharePdf});

  final SharePdf _sharePdf;

  @override
  Future<void> sharePdf({required Uint8List bytes, required String fileName}) async {
    final bool isOpen;
    try {
      isOpen = await _sharePdf(bytes: bytes, filename: fileName);
    } on Exception catch (error, stackTrace) {
      Error.throwWithStackTrace(ReportShareException(cause: error), stackTrace);
    }
    // On Android and iOS the plugin answers true as soon as it asked for the share sheet, also when the person
    // then sends nothing. It answers false only where it had no window or no directory for the file.
    if (!isOpen) throw const ReportShareException();
  }
}
