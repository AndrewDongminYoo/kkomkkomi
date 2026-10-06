import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/gen/assets.gen.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'helpers.dart';

void main() {
  /// A file of the `pdf` package with [pages] pages in the A5 size, each with two texts and the fixture photo.
  Future<Uint8List> pdf({int pages = 2}) {
    final font = pw.Font.ttf(ByteData.sublistView(File(Assets.fonts.notoSansKRRegular).readAsBytesSync()));
    final document = pw.Document(theme: pw.ThemeData.withFont(base: font));
    for (var page = 1; page <= pages; page++) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          build: (context) => pw.Column(
            children: [
              pw.Text('$page쪽 첫 줄'),
              pw.Image(pw.MemoryImage(fixturePhotoBytes()), width: 40),
              pw.Text('second line'),
            ],
          ),
        ),
      );
    }
    return document.save();
  }

  /// The file with [change] applied to its text, which has one character for each byte.
  Uint8List changed(Uint8List file, String Function(String text) change) =>
      Uint8List.fromList(latin1.encode(change(latin1.decode(file))));

  /// The text with zeros in place of the first bytes of the stream of the object that [pattern] names.
  String withBrokenStream(String text, RegExp pattern) {
    final number = pattern.firstMatch(text)!.group(1)!;
    final object = RegExp('(?:^|\\n)$number 0 obj\\b').firstMatch(text)!;
    expect(text.substring(object.end, text.indexOf('stream\n', object.end)), contains('/Filter/FlateDecode'));
    final stream = text.indexOf('stream\n', object.end) + 'stream\n'.length;
    return text.replaceRange(stream, stream + 8, '\x00' * 8);
  }

  Matcher refusesWith(String message) =>
      throwsA(isA<FormatException>().having((exception) => exception.message, 'message', contains(message)));

  group('PdfSummary.read', () {
    test('reads the size, the text, and the images of each page of a file of the pdf package', () async {
      final summary = PdfSummary.read(await pdf());

      expect(summary.pageCount, 2);
      expect(summary.pages[0].text, '1쪽 첫 줄 second line');
      expect(summary.pages[1].text, '2쪽 첫 줄 second line');
      expect(summary.text, '1쪽 첫 줄 second line 2쪽 첫 줄 second line');
      for (final page in summary.pages) {
        expect(page.width, closeTo(PdfPageFormat.a5.width, 0.01));
        expect(page.height, closeTo(PdfPageFormat.a5.height, 0.01));
        expect(page.images, [(width: 8, height: 6)]);
      }
    });

    test('reads where the drawing of each text starts', () async {
      final font = pw.Font.ttf(ByteData.sublistView(File(Assets.fonts.notoSansKRRegular).readAsBytesSync()));
      final document = pw.Document(theme: pw.ThemeData.withFont(base: font))
        ..addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a5,
            margin: const pw.EdgeInsets.all(20),
            build: (context) => pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [pw.Text('left'), pw.Text('right')],
            ),
          ),
        );

      final [left, right] = PdfSummary.read(await document.save()).pages.single.texts;

      expect(left, (text: 'left', x: 20));
      expect(right.text, 'right');
      expect(right.x, greaterThan(PdfPageFormat.a5.width / 2));
    });

    test('refuses a file without the PDF header', () async {
      final file = changed(await pdf(), (text) => text.replaceFirst('%PDF-1.', '%PDX-1.'));

      expect(() => PdfSummary.read(file), refusesWith('no PDF header'));
    });

    test('refuses a file that does not end with a cross-reference offset', () async {
      final file = await pdf();

      expect(
        () => PdfSummary.read(Uint8List.sublistView(file, 0, file.length - 10)),
        refusesWith('does not end with a cross-reference offset'),
      );
    });

    test('refuses a cross-reference offset that points at no object', () async {
      final file = await pdf();
      final nowhere = changed(
        file,
        (text) => text.replaceFirstMapped(
          RegExp(r'startxref\n(\d+)'),
          (match) => 'startxref\n${'0' * match.group(1)!.length}',
        ),
      );
      final beyond = changed(
        file,
        (text) => text.replaceFirstMapped(
          RegExp(r'startxref\n(\d+)'),
          (match) => 'startxref\n${'9' * match.group(1)!.length}9',
        ),
      );

      expect(() => PdfSummary.read(nowhere), refusesWith('does not point at an object'));
      expect(() => PdfSummary.read(beyond), refusesWith('does not point at an object'));
    });

    test('refuses a cross-reference stream whose entries are zeros', () async {
      final file = changed(await pdf(), (text) {
        final offset = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!);
        final stream = text.indexOf('stream\n', offset) + 'stream\n'.length;
        final end = text.indexOf('\nendstream', stream);
        return text.replaceRange(stream, end, '\x00' * (end - stream));
      });

      // The `pdf` package compresses the stream only when that makes it shorter, so the zeros are either a
      // stream that does not decode or a list of entries that name no object.
      expect(
        () => PdfSummary.read(file),
        throwsA(
          isA<FormatException>().having(
            (exception) => exception.message,
            'message',
            anyOf(contains('does not decode'), contains('names no object')),
          ),
        ),
      );
    });

    test('refuses an object that is not at the offset that the cross-reference stream names', () async {
      // One more byte before the first object moves every object, and the offset at the end is moved with them.
      final file = changed(
        await pdf(),
        (text) => text
            .replaceFirst('\n1 0 obj', '\n\n1 0 obj')
            .replaceFirstMapped(RegExp(r'startxref\n(\d+)'), (match) => 'startxref\n${int.parse(match.group(1)!) + 1}'),
      );

      expect(() => PdfSummary.read(file), refusesWith('is not at the offset'));
    });

    test('refuses a page whose content does not decode', () async {
      final file = changed(await pdf(), (text) => withBrokenStream(text, RegExp(r'/Contents (\d+) 0 R')));

      expect(() => PdfSummary.read(file), refusesWith('does not decode'));
    });

    test('refuses a font whose character map does not decode', () async {
      final file = changed(await pdf(), (text) => withBrokenStream(text, RegExp(r'/ToUnicode (\d+) 0 R')));

      expect(() => PdfSummary.read(file), refusesWith('does not decode'));
    });

    test('refuses a page tree that names an object that is no page', () async {
      final file = changed(await pdf(), (text) => text.replaceFirst('/Type/Page/', '/Type/Pagx/'));

      expect(() => PdfSummary.read(file), refusesWith('which is no page'));
    });

    test('refuses a page tree that counts other pages than it names', () async {
      final file = changed(await pdf(), (text) => text.replaceFirst('/Count 2', '/Count 3'));

      expect(() => PdfSummary.read(file), refusesWith('counts other pages than it names'));
    });

    test('refuses a file whose root is no catalog', () async {
      final file = changed(await pdf(), (text) => text.replaceFirst('/Type/Catalog', '/Type/Catalox'));

      expect(() => PdfSummary.read(file), refusesWith('no catalog'));
    });
  });
}
