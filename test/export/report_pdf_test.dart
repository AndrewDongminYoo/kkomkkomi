import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/export/export.dart';
import 'package:kkomkkomi/gen/assets.gen.dart';
import 'package:pdf/pdf.dart';

import '../helpers/helpers.dart';

void main() {
  final labels = ReportLabels(
    title: '청소 완료 보고서',
    clientHeading: '거래처',
    visitDateHeading: '방문일',
    visitDate: '2026년 10월 1일',
    beforePhoto: '청소 전',
    afterPhoto: '청소 후',
    notPhotographed: '촬영하지 않음',
    partlyDone: '일부 완료',
    notDone: '못 함',
    summaryOf: (done, total) => '$total곳 중 $done곳 완료',
    note: '메모',
    footer: '꼼꼬미로 만든 보고서',
  );

  final font = ByteData.sublistView(File(Assets.fonts.notoSansKRRegular).readAsBytesSync());
  final boldFont = ByteData.sublistView(File(Assets.fonts.notoSansKRBold).readAsBytesSync());

  /// A photo that is wider than it is high, and a photo that is higher than it is wide.
  const wide = (width: 8, height: 6);
  const tall = (width: 6, height: 8);
  final wideBytes = fixturePhotoBytes();
  final tallBytes = File('test/fixtures/photo_tall.jpg').readAsBytesSync();

  PhotoRef photo(String name) => PhotoRef('photos/visit-1/$name.jpg');

  ReportDocument document(List<ReportZone> zones, {String? companyName = '깔끔클린', String clientName = '행복빌딩'}) =>
      ReportDocument(companyName: companyName, clientName: clientName, visitDate: VisitDate(2026, 10, 1), zones: zones);

  /// Renders [document]. A photo whose name starts with `tall` is the tall photo, and each other photo is the wide
  /// one, unless [photos] is given.
  Future<PdfSummary> render(
    ReportDocument document, {
    Map<PhotoRef, Uint8List>? photos,
    bool showsFooterText = true,
  }) async => PdfSummary.read(
    await renderReportPdf(
      document,
      labels: labels,
      font: font,
      boldFont: boldFont,
      photos:
          photos ?? {for (final photo in document.photos) photo: photo.path.contains('/tall') ? tallBytes : wideBytes},
      showsFooterText: showsFooterText,
    ),
  );

  /// What the renderer prints to the console while [body] runs, which is its notice of a missing glyph.
  Future<List<String>> printedBy(Future<void> Function() body) async {
    final lines = <String>[];
    await runZoned(body, zoneSpecification: ZoneSpecification(print: (_, _, _, line) => lines.add(line)));
    return lines;
  }

  /// Expects that [text] holds each of [parts] after the one before it.
  void expectInOrder(String text, List<String> parts) {
    var from = 0;
    for (final part in parts) {
      final index = text.indexOf(part, from);
      expect(index, isNonNegative, reason: '"$part" is not after the parts before it in "$text"');
      from = index + part.length;
    }
  }

  int countOf(String part, String text) => part.allMatches(text).length;

  group('renderReportPdf', () {
    test('prints the business phone between the company name and title', () async {
      final summary = await render(
        ReportDocument(
          companyName: '깔끔클린',
          companyPhone: '02-1234-5678',
          clientName: '행복빌딩',
          visitDate: VisitDate(2026, 10, 1),
          zones: [],
        ),
      );
      expectInOrder(summary.text, ['깔끔클린', '02-1234-5678', '청소 완료 보고서']);
      expect(summary.pageCount, 1);
    });
    test('renders a full visit as A4 pages that parse, with the header table and each zone in order', () async {
      final summary = await render(
        document([
          ReportZone(name: '로비', beforePhoto: photo('wide-1'), afterPhoto: photo('tall-1'), note: '바닥 왁스'),
          ReportZone(name: '화장실', beforePhoto: photo('tall-2'), afterPhoto: photo('wide-2'), note: '세면대 물때 제거'),
        ]),
      );

      for (final page in summary.pages) {
        expect(page.width, closeTo(PdfPageFormat.a4.width, 0.01));
        expect(page.height, closeTo(PdfPageFormat.a4.height, 0.01));
      }
      expectInOrder(summary.pages.first.text, [
        '깔끔클린',
        '청소 완료 보고서',
        '거래처',
        '행복빌딩',
        '방문일',
        '2026년 10월 1일',
        '2곳 중 2곳 완료',
      ]);
      expectInOrder(summary.text, [
        '로비',
        '청소 전',
        '청소 후',
        '메모',
        '바닥 왁스',
        '화장실',
        '청소 전',
        '청소 후',
        '메모',
        '세면대 물때 제거',
      ]);
      // The before photo of each zone is drawn before its after photo, which is the slot on its right.
      expect(summary.pages.expand((page) => page.images), [wide, tall, tall, wide]);
      expect(countOf('촬영하지 않음', summary.text), 0);
    });

    test('numbers the zones from one, left of the name of each zone', () async {
      final summary = await render(
        document([
          for (final name in ['로비', '화장실', '복도'])
            ReportZone(name: name, beforePhoto: null, afterPhoto: null, note: '메모 있음'),
        ]),
      );

      final texts = summary.pages.expand((page) => page.texts).toList();
      for (final (index, name) in ['로비', '화장실', '복도'].indexed) {
        final nameAt = texts.indexWhere((text) => text.text == name);
        expect(nameAt, isPositive, reason: '$name is missing');
        expect(texts[nameAt - 1].text, '${index + 1}', reason: 'the number of $name');
        expect(texts[nameAt - 1].x, lessThan(texts[nameAt].x));
      }
    });

    test('repeats the client name and the visit date at the head of every page after the first', () async {
      final longNote = List.generate(400, (line) => '$line번째 줄: 바닥을 닦고 유리를 닦았어요.').join('\n');

      final summary = await render(
        document([ReportZone(name: '로비', beforePhoto: photo('a'), afterPhoto: photo('b'), note: longNote)]),
      );

      expect(summary.pageCount, greaterThan(5));
      expect(countOf('행복빌딩', summary.pages.first.text), 1);
      expect(countOf('청소 완료 보고서', summary.text), 1);
      for (final page in summary.pages.skip(1)) {
        expectInOrder(page.text, ['행복빌딩', '2026년 10월 1일']);
      }
    });

    test('prints the footer and the page number on every page', () async {
      final longNote = List.generate(400, (line) => '$line번째 줄: 바닥을 닦고 유리를 닦았어요.').join('\n');

      final summary = await render(
        document([ReportZone(name: '로비', beforePhoto: photo('a'), afterPhoto: photo('b'), note: longNote)]),
      );

      expect(summary.pageCount, greaterThan(5));
      for (final (index, page) in summary.pages.indexed) {
        expect(page.text, contains('꼼꼬미로 만든 보고서 ${index + 1} / ${summary.pageCount}'));
        expect(page.width, closeTo(PdfPageFormat.a4.width, 0.01));
      }
    });

    test('leaves the footer text out of every page and keeps the page number when the text is not shown', () async {
      final longNote = List.generate(400, (line) => '$line번째 줄: 바닥을 닦고 유리를 닦았어요.').join('\n');

      final summary = await render(
        document([ReportZone(name: '로비', beforePhoto: photo('a'), afterPhoto: photo('b'), note: longNote)]),
        showsFooterText: false,
      );

      expect(summary.pageCount, greaterThan(5));
      for (final (index, page) in summary.pages.indexed) {
        expect(page.text, contains('${index + 1} / ${summary.pageCount} '));
      }
      expect(summary.text, isNot(contains('꼼꼬미로 만든 보고서')));
    });

    test('keeps the page number at the right end of the footer row when the text is not shown', () async {
      final zones = [ReportZone(name: '로비', beforePhoto: photo('a'), afterPhoto: photo('b'), note: '')];

      /// Where the drawing of the page number of the first page starts, after the footer text when it is shown.
      Future<double> pageNumberX({required bool showsFooterText}) async {
        final page = (await render(document(zones), showsFooterText: showsFooterText)).pages.first;
        return page.texts.firstWhere((text) => text.text == '1').x;
      }

      final withText = await pageNumberX(showsFooterText: true);
      final withoutText = await pageNumberX(showsFooterText: false);

      expect(withoutText, withText);
      expect(withoutText, greaterThan(PdfPageFormat.a4.width / 2));
    });

    test('goes on to the next pages for a note that is longer than a page, and prints all of it', () async {
      final lines = List.generate(400, (line) => '$line번째 줄: 바닥을 닦고 유리를 닦았어요.');

      final summary = await render(
        document([ReportZone(name: '로비', beforePhoto: photo('a'), afterPhoto: photo('b'), note: lines.join('\n'))]),
      );

      expectInOrder(summary.text, lines);
      // The header and the photos are on the first page alone.
      expect(countOf('청소 완료 보고서', summary.text), 1);
      expect(summary.pages.first.images, [wide, wide]);
      expect(summary.pages.skip(1).expand((page) => page.images), isEmpty);
    });

    test(
      'renders a note that is longer than the 20 pages at which the pdf package stops a widget by default',
      () async {
        final lines = List.generate(1200, (line) => '$line번째 줄');

        final summary = await render(
          document([ReportZone(name: '로비', beforePhoto: null, afterPhoto: null, note: lines.join('\n'))]),
        );

        expect(summary.pageCount, greaterThan(21));
        expect(summary.pages.last.text, endsWith('1199번째 줄'));
      },
    );

    test('prints an empty slot for the photo that a zone lacks, and no note block for a zone without a note', () async {
      final summary = await render(
        document([
          ReportZone(name: '로비', beforePhoto: photo('wide'), afterPhoto: null, note: ''),
          ReportZone(name: '화장실', beforePhoto: null, afterPhoto: photo('tall'), note: ''),
          const ReportZone(name: '복도', beforePhoto: null, afterPhoto: null, note: '공사 중이라 청소하지 못함'),
        ]),
      );

      final text = summary.text;
      expectInOrder(text, ['로비', '청소 전', '청소 후', '촬영하지 않음', '화장실', '청소 전', '촬영하지 않음', '청소 후', '복도']);
      expectInOrder(text, ['복도', '청소 전', '촬영하지 않음', '청소 후', '촬영하지 않음', '메모', '공사 중이라 청소하지 못함']);
      expect(countOf('촬영하지 않음', text), 4);
      expect(countOf('메모', text), 1);
      expect(summary.pages.expand((page) => page.images), [wide, tall]);
    });

    test('prints the summary, then each exception with its status and reason, before the zones', () async {
      final summary = await render(
        document([
          ReportZone(name: '로비', beforePhoto: photo('a'), afterPhoto: photo('b'), note: ''),
          ReportZone(
            name: '탕비실',
            beforePhoto: photo('c'),
            afterPhoto: null,
            note: '',
            status: ZoneStatus.partlyDone,
            reason: '전자레인지는 다음 방문에',
          ),
          const ReportZone(name: '창고', beforePhoto: null, afterPhoto: null, note: '', status: ZoneStatus.notDone),
        ]),
      );

      expectInOrder(summary.text, [
        '3곳 중 1곳 완료',
        '탕비실 · 일부 완료: 전자레인지는 다음 방문에',
        '창고 · 못 함',
        '로비',
        '탕비실',
        '일부 완료',
        '촬영하지 않음',
        '창고',
        '못 함',
        '못 함',
        '못 함',
      ]);
      // The exception line of a zone without a reason ends at its status.
      expect(summary.text, isNot(contains('창고 · 못 함:')));
      // Each status shows in the exception line and the badge of its zone, and a done zone shows none. The two empty
      // slots of the zone that is not done say so too.
      expect(countOf('일부 완료', summary.text), 2);
      expect(countOf('못 함', summary.text), 4);
    });

    test('goes on to the next pages for a summary of more exceptions and a longer reason than a page holds', () async {
      final reason = List.generate(60, (line) => '$line번째 줄: 다음 방문에 처리할 일').join('\n');
      final zones = [
        for (var index = 0; index < 40; index++)
          ReportZone(
            name: '구역$index',
            beforePhoto: null,
            afterPhoto: null,
            note: '',
            status: ZoneStatus.notDone,
            reason: index == 0 ? reason : '잠김',
          ),
      ];

      final summary = await render(document(zones));

      expect(summary.pageCount, greaterThan(2));
      expectInOrder(summary.text, [
        '40곳 중 0곳 완료',
        for (final line in reason.split('\n')) line,
        for (var index = 1; index < 40; index++) '구역$index · 못 함: 잠김',
      ]);
    });

    test('prints the same photo in two slots', () async {
      final summary = await render(
        document([ReportZone(name: '로비', beforePhoto: photo('tall'), afterPhoto: photo('tall'), note: '')]),
      );

      expect(summary.pages.single.images, [tall, tall]);
    });

    test('renders a report without a zone and without a company name', () async {
      final summary = await render(document([], companyName: null));

      expect(summary.pageCount, 1);
      // A report without a zone has no summary line.
      expect(summary.pages.single.text, '꼼꼬미로 만든 보고서 1 / 1 청소 완료 보고서 거래처 행복빌딩 방문일 2026년 10월 1일');
      expect(summary.pages.single.images, isEmpty);
    });

    test('keeps the name of a zone on the page of its photos', () async {
      const names = ['첫째', '둘째', '셋째', '넷째', '다섯째', '여섯째', '일곱째'];

      final summary = await render(
        document([
          for (final name in names) ReportZone(name: name, beforePhoto: photo('a'), afterPhoto: photo('b'), note: ''),
        ]),
      );

      // Some page breaks between two zones, so a name that went to the foot of a page would show there.
      expect(summary.pageCount, greaterThan(1));
      for (final page in summary.pages) {
        final namesOnPage = page.texts.where((text) => names.contains(text.text)).length;
        expect(page.images, hasLength(2 * namesOnPage));
      }
      expect(summary.pages.expand((page) => page.texts).where((text) => names.contains(text.text)), hasLength(7));
    });

    test('lays out two zones without a note on each page, the first page with the heading included', () async {
      final summary = await render(
        document([
          for (var index = 0; index < 7; index++)
            ReportZone(name: '구역$index', beforePhoto: photo('a'), afterPhoto: photo('b'), note: ''),
        ]),
      );

      // Seven zones fill three pages with two each, and the last page holds the zone that is left.
      expect(summary.pageCount, 4);
      expect([for (final page in summary.pages) page.images.length], [4, 4, 4, 2]);
    });

    test('renders names that are longer than a page holds, cut to a few lines', () async {
      final summary = await render(
        document(
          [ReportZone(name: '구역 ' * 2000, beforePhoto: photo('a'), afterPhoto: null, note: '')],
          companyName: '회사 ' * 2000,
          clientName: '거래처 ' * 2000,
        ),
      );

      expect(summary.pageCount, 1);
      expect(countOf('구역', summary.text), inInclusiveRange(10, 200));
      expect(countOf('회사', summary.text), inInclusiveRange(10, 200));
      expect(countOf('거래처', summary.text), inInclusiveRange(10, 200));
    });

    test('breaks a note without a space into lines, and prints all of it', () async {
      final summary = await render(
        document([ReportZone(name: '로비', beforePhoto: photo('a'), afterPhoto: null, note: '가' * 500)]),
      );

      expect(summary.pageCount, 1);
      expect(countOf('가', summary.text), 500);
    });

    test('prints a crossed box for a character that the font does not have, and says so on the console', () async {
      late PdfSummary summary;
      final printed = await printedBy(() async {
        summary = await render(
          document([ReportZone(name: '로비', beforePhoto: photo('a'), afterPhoto: null, note: '깨끗해요 😀 漢字')]),
        );
      });

      expect(printed.single, contains('Unable to find a font to draw "😀"'));
      expectInOrder(summary.text, ['깨끗해요', '漢字']);
    });

    test('prints the line breaks and the tabs of a note without a missing character', () async {
      late PdfSummary summary;
      final printed = await printedBy(() async {
        summary = await render(
          document([
            ReportZone.fromRecord(
              ZoneRecord(zoneId: 'zone-1', zoneName: '로비', note: '첫 줄\r\n둘째 줄\r셋째 줄\n넷째\t줄'),
            ),
          ]),
        );
      });

      expect(printed, isEmpty);
      expectInOrder(summary.text, ['첫 줄', '둘째 줄', '셋째 줄', '넷째', '줄']);
    });

    test('refuses a document with a photo whose bytes it is not given', () async {
      final withPhoto = document([ReportZone(name: '로비', beforePhoto: photo('a'), afterPhoto: null, note: '')]);

      await expectLater(
        render(withPhoto, photos: {}),
        throwsA(isA<ArgumentError>().having((error) => error.name, 'name', 'photos')),
      );
    });

    test('fails for a photo whose bytes are no image', () async {
      final withPhoto = document([ReportZone(name: '로비', beforePhoto: photo('a'), afterPhoto: null, note: '')]);

      // The image decoder of the `pdf` package fails with an `Error`, so a caller that must not stop on a broken
      // photo file catches more than `Exception`.
      await expectLater(
        render(
          withPhoto,
          photos: {
            photo('a'): Uint8List.fromList([1, 2, 3]),
          },
        ),
        throwsA(isA<Error>()),
      );
    });
  });
}
