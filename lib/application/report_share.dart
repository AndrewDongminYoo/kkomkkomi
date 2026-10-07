// 🎯 Dart imports:
import 'dart:typed_data';

/// Hands a report file to the share sheet of the device, so that tests never open one.
abstract interface class ReportShare {
  /// Opens the share sheet with a PDF file that holds [bytes] and has the name [fileName].
  ///
  /// The call completes when the share sheet is open, so it does not tell whether the person sent the file.
  /// Throws a [ReportShareException] when the share sheet did not open.
  Future<void> sharePdf({required Uint8List bytes, required String fileName});
}

/// The share sheet did not open.
final class ReportShareException implements Exception {
  const new({this.cause});

  /// What the platform reported, for the log. It is null when the platform gave no reason.
  final Object? cause;

  @override
  String toString() => 'ReportShareException(cause: $cause)';
}
