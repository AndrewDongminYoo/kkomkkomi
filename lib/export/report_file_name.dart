import 'package:kkomkkomi/domain/domain.dart';

/// The most bytes that the title takes in a file name, in UTF-8.
const _titleByteLimit = 60;

/// The most bytes that the client name takes in a file name, in UTF-8.
const _clientNameByteLimit = 120;

/// The characters that a file system or a share target does not take in a file name, and the control characters.
final _unsafeCharacter = RegExp(r'[/\\:*?"<>|\x00-\x1f\x7f]');
final _spaceRun = RegExp(r'\s+');
final _leadingDots = RegExp(r'^\.+');

/// The name of the PDF file of a report: [title], [clientName], and [visitDate], for example
/// `청소 완료 보고서_행복빌딩_2026-10-01.pdf`.
///
/// The same arguments always give the same name. A character that a file system does not take becomes a space, and
/// each part is cut to a byte limit, so that the name stays under the 255 bytes that the file systems of Android and
/// iOS allow. A share fails without a message when the name is longer. A part with no character left is left out.
String reportFileName({required String title, required String clientName, required VisitDate visitDate}) {
  final parts = [
    _fileNamePart(title, byteLimit: _titleByteLimit),
    _fileNamePart(clientName, byteLimit: _clientNameByteLimit),
    '$visitDate',
  ];
  return '${parts.where((part) => part.isNotEmpty).join('_')}.pdf';
}

String _fileNamePart(String text, {required int byteLimit}) {
  final safe = text.replaceAll(_unsafeCharacter, ' ').replaceAll(_spaceRun, ' ').trim().replaceFirst(_leadingDots, '');
  final kept = StringBuffer();
  var bytes = 0;
  // The cut is between code points, so that it leaves no half of a surrogate pair.
  for (final rune in safe.runes) {
    bytes += _utf8Length(rune);
    if (bytes > byteLimit) break;
    kept.writeCharCode(rune);
  }
  return kept.toString().trim();
}

int _utf8Length(int rune) => switch (rune) {
  < 0x80 => 1,
  < 0x800 => 2,
  < 0x10000 => 3,
  _ => 4,
};
