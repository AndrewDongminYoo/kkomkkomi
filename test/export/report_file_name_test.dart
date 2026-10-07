// 🎯 Dart imports:
import 'dart:convert';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/export/export.dart';

void main() {
  String fileName({String title = '청소 완료 보고서', String clientName = '행복빌딩', VisitDate? visitDate}) =>
      reportFileName(title: title, clientName: clientName, visitDate: visitDate ?? VisitDate(2026, 10, 1));

  group('reportFileName', () {
    test('is the title, the client name, and the visit date for a known client and date', () {
      expect(fileName(), '청소 완료 보고서_행복빌딩_2026-10-01.pdf');
      expect(
        fileName(title: 'Cleaning Report', clientName: 'Happy Tower', visitDate: VisitDate(2025, 1, 9)),
        'Cleaning Report_Happy Tower_2025-01-09.pdf',
      );
    });

    test('is the same for the same arguments', () {
      expect(fileName(), fileName());
    });

    test('puts a space in place of a character that a file name cannot hold', () {
      expect(fileName(clientName: r'A/B\C:D*E?F"G<H>I|J'), '청소 완료 보고서_A B C D E F G H I J_2026-10-01.pdf');
      expect(fileName(clientName: '1층\n로비\t\u0000앞\u007f'), '청소 완료 보고서_1층 로비 앞_2026-10-01.pdf');
    });

    test('joins a run of spaces, and takes the space and the dots from the start of a part', () {
      expect(fileName(clientName: '  행복   빌딩  '), '청소 완료 보고서_행복 빌딩_2026-10-01.pdf');
      expect(fileName(clientName: '../행복빌딩'), '청소 완료 보고서_행복빌딩_2026-10-01.pdf');
      expect(fileName(clientName: '. 행복빌딩'), '청소 완료 보고서_행복빌딩_2026-10-01.pdf');
    });

    test('leaves out a part that has no character left', () {
      expect(fileName(clientName: '///'), '청소 완료 보고서_2026-10-01.pdf');
      expect(fileName(title: '', clientName: '?'), '2026-10-01.pdf');
    });

    test('cuts a long client name at 120 bytes, between characters', () {
      // A Hangul syllable takes three bytes in UTF-8, so 40 of them take 120 bytes.
      expect(fileName(clientName: '가' * 41), '청소 완료 보고서_${'가' * 40}_2026-10-01.pdf');
      expect(fileName(clientName: '가' * 40), '청소 완료 보고서_${'가' * 40}_2026-10-01.pdf');
      // The cut would fall inside the 60th two-byte letter and inside the emoji of four bytes.
      expect(fileName(clientName: 'a${'é' * 60}'), '청소 완료 보고서_a${'é' * 59}_2026-10-01.pdf');
      expect(fileName(clientName: '${'a' * 118}😀'), '청소 완료 보고서_${'a' * 118}_2026-10-01.pdf');
      expect(fileName(clientName: '${'a' * 116}😀b'), '청소 완료 보고서_${'a' * 116}😀_2026-10-01.pdf');
    });

    test('cuts a long title at 60 bytes, and takes the space that the cut leaves at the end', () {
      expect(fileName(title: '가' * 21), '${'가' * 20}_행복빌딩_2026-10-01.pdf');
      expect(fileName(title: '${'a' * 59} b'), '${'a' * 59}_행복빌딩_2026-10-01.pdf');
    });

    test('stays under the 255 bytes of a file name for the longest parts', () {
      final longest = fileName(title: '가' * 100, clientName: '😀' * 100);

      expect(utf8.encode(longest).length, lessThanOrEqualTo(255));
      expect(utf8.encode(longest).length, 60 + 1 + 120 + 1 + 10 + 4);
    });
  });
}
