import 'dart:typed_data';

import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/export/report_document.dart';
import 'package:kkomkkomi/export/report_labels.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The space around the content of a page, in points.
const double _pageMargin = 40;

/// The space between the before slot and the after slot of a zone, in points.
const double _slotGap = 12;

/// The width of a photo slot over its height, in the PDF and in a preview of the report.
///
/// A square slot shows a portrait photo and a landscape photo of a phone camera at the same size, and lets two zones
/// without a note share a page.
const double reportSlotAspectRatio = 1;

/// The most lines that a name takes. A block with a name must fit on one page, and a name has no length limit.
const _nameMaxLines = 3;

/// The most pages that one note takes in a debug build.
///
/// The `pdf` package stops a widget that goes on for more pages than this, in a build with assertions only, as a
/// guard against a layout that never ends. Its default is 20 pages, which a long note passes, and a note has no
/// length limit, so the guard stands at a count that no note of a person reaches.
const _notePageLimit = 1000;

/// The width of each heading column of the table under the title, in points.
const double _headingColumnWidth = 56;

// The colors of the theme of the app (`lib/app/view/app_theme.dart`), so that the report looks like the product.
const PdfColor _ink = PdfColor.fromInt(0xFF16243B);
const PdfColor _secondaryText = PdfColor.fromInt(0xFF4B5870);
const PdfColor _accent = PdfColor.fromInt(0xFF0F7F7A);
const PdfColor _onAccent = PdfColors.white;
const PdfColor _rule = PdfColor.fromInt(0xFFE6E0D4);
const PdfColor _emptySlotEdge = PdfColor.fromInt(0xFF7F899C);

/// Renders [document] as an A4 PDF and gives the bytes of the file.
///
/// [font] and [boldFont] are the regular and the bold weight of a TrueType font that has the glyphs of the texts,
/// and the file holds the glyphs that it uses. A character that the font does not have prints as a crossed box.
/// [photos] holds the bytes of the file of every photo in [ReportDocument.photos], as a JPEG or a PNG. A note that is
/// longer than a page goes on to the next page. The first page opens with the company name, the title, and a table
/// of the client, the visit date, and the number of zones, and each later page opens with the client name and the
/// visit date. The foot of every page holds the page number, and the footer text of [labels] when [showsFooterText]
/// is true.
///
/// Throws an [ArgumentError] when [photos] lacks a photo of the document. The image decoder throws when the bytes
/// of a photo are no image.
Future<Uint8List> renderReportPdf(
  ReportDocument document, {
  required ReportLabels labels,
  required ByteData font,
  required ByteData boldFont,
  required Map<PhotoRef, Uint8List> photos,
  bool showsFooterText = true,
}) {
  final regular = pw.Font.ttf(font);
  final bold = pw.Font.ttf(boldFont);
  final pdf = pw.Document(
    // The font has no italic, so an italic style prints upright.
    theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: regular, boldItalic: bold),
  );
  final images = {
    for (final photo in document.photos) photo: pw.MemoryImage(_bytesOf(photo, photos)),
  };
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_pageMargin),
      maxPages: _notePageLimit,
      header: (context) => context.pageNumber == 1 ? pw.SizedBox() : _runningHeader(document, labels),
      footer: (context) => _footer(context, labels, showsFooterText: showsFooterText),
      build: (context) => [
        _header(document, labels),
        for (final (index, zone) in document.zones.indexed) ..._zone(index + 1, zone, labels, images),
      ],
    ),
  );
  return pdf.save();
}

Uint8List _bytesOf(PhotoRef photo, Map<PhotoRef, Uint8List> photos) =>
    photos[photo] ??
    (throw ArgumentError.value(photo.path, 'photos', 'The bytes of a photo of the document are missing'));

/// The head of the first page: the company that sends the report, the title, and the table of the visit.
pw.Widget _header(ReportDocument document, ReportLabels labels) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    if (document.companyName case final companyName?) ...[
      pw.Text(
        companyName,
        style: const pw.TextStyle(fontSize: 14, color: _ink, fontWeight: pw.FontWeight.bold),
        maxLines: _nameMaxLines,
      ),
      pw.SizedBox(height: 2),
    ],
    pw.Text(
      labels.title,
      style: const pw.TextStyle(fontSize: 22, color: _ink, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 8),
    pw.Container(height: 2, color: _accent),
    pw.SizedBox(height: 6),
    pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(_headingColumnWidth),
        1: pw.FlexColumnWidth(),
        2: pw.FixedColumnWidth(_headingColumnWidth),
        3: pw.FlexColumnWidth(),
      },
      children: [
        pw.TableRow(
          children: [
            ..._tableCells(labels.clientHeading, document.clientName),
            ..._tableCells(labels.visitDateHeading, labels.visitDate),
          ],
        ),
        pw.TableRow(
          children: [
            ..._tableCells(labels.zoneCountHeading, '${document.zones.length}'),
            pw.SizedBox(),
            pw.SizedBox(),
          ],
        ),
      ],
    ),
    pw.SizedBox(height: 4),
    pw.Divider(height: 1, thickness: 0.5, color: _rule),
  ],
);

/// A heading cell and its value cell of the table under the title.
List<pw.Widget> _tableCells(String heading, String value) => [
  pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Text(heading, style: const pw.TextStyle(fontSize: 10, color: _secondaryText)),
  ),
  pw.Padding(
    padding: const pw.EdgeInsets.only(top: 2, bottom: 2, right: 12),
    child: pw.Text(
      value,
      style: const pw.TextStyle(fontSize: 11, color: _ink),
      maxLines: _nameMaxLines,
    ),
  ),
];

/// The head of every page after the first: the client name and the visit date over a rule.
pw.Widget _runningHeader(ReportDocument document, ReportLabels labels) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 4),
  padding: const pw.EdgeInsets.only(bottom: 4),
  decoration: const pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.5)),
  ),
  child: pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          document.clientName,
          style: const pw.TextStyle(fontSize: 9, color: _secondaryText),
          maxLines: 1,
        ),
      ),
      pw.SizedBox(width: 12),
      pw.Text(labels.visitDate, style: const pw.TextStyle(fontSize: 9, color: _secondaryText)),
    ],
  ),
);

/// The widgets of the zone with the [number] in the report. The number, the name, and the photo slots stay on one
/// page, and the note can go on to the next page.
List<pw.Widget> _zone(int number, ReportZone zone, ReportLabels labels, Map<PhotoRef, pw.ImageProvider> images) => [
  // A column spans pages when it is a direct child of the page, which would leave a name at the foot of one page
  // and its photos at the head of the next.
  pw.Inseparable(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 12),
        pw.Row(
          children: [
            _numberBadge(number),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(
                zone.name,
                style: const pw.TextStyle(fontSize: 13, color: _ink, fontWeight: pw.FontWeight.bold),
                maxLines: _nameMaxLines,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _slot(labels.beforePhoto, images[zone.beforePhoto], labels)),
            pw.SizedBox(width: _slotGap),
            pw.Expanded(child: _slot(labels.afterPhoto, images[zone.afterPhoto], labels)),
          ],
        ),
      ],
    ),
  ),
  if (zone.note.isNotEmpty) ...[
    pw.SizedBox(height: 6),
    pw.Text(labels.note, style: const pw.TextStyle(fontSize: 9, color: _secondaryText)),
    pw.SizedBox(height: 2),
    // The text is a direct child of the page and spans, so that a long note goes on to the next page. A box around
    // it would stop the span.
    pw.Text(
      zone.note,
      style: const pw.TextStyle(fontSize: 11, lineSpacing: 2, color: _ink),
      overflow: pw.TextOverflow.span,
    ),
  ],
];

/// The [number] of a zone in a circle of the accent color.
pw.Widget _numberBadge(int number) => pw.Container(
  width: 20,
  height: 20,
  alignment: pw.Alignment.center,
  decoration: const pw.BoxDecoration(color: _accent, shape: pw.BoxShape.circle),
  child: pw.Text(
    '$number',
    style: const pw.TextStyle(fontSize: 10, color: _onAccent, fontWeight: pw.FontWeight.bold),
  ),
);

/// One photo slot: [label] over the photo, or over an empty box that says that the zone has no photo there.
///
/// The photo sits on white inside a solid edge, and a slot without a photo has a dashed edge, so that the space
/// beside a photo never looks like a missing photo.
pw.Widget _slot(String label, pw.ImageProvider? image, ReportLabels labels) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _secondaryText)),
    pw.SizedBox(height: 3),
    pw.AspectRatio(
      aspectRatio: reportSlotAspectRatio,
      child: pw.Container(
        alignment: pw.Alignment.center,
        decoration: image == null
            ? pw.BoxDecoration(
                border: pw.Border.all(color: _emptySlotEdge, width: 0.75, style: pw.BorderStyle.dashed),
              )
            : pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: _rule, width: 0.5),
              ),
        child: image == null
            ? pw.Text(labels.noPhoto, style: const pw.TextStyle(fontSize: 10, color: _secondaryText))
            // The default fit shows the whole photo, because a report must not cut what the photo proves.
            : pw.Image(image),
      ),
    ),
  ],
);

pw.Widget _footer(pw.Context context, ReportLabels labels, {required bool showsFooterText}) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 8),
  padding: const pw.EdgeInsets.only(top: 6),
  decoration: const pw.BoxDecoration(
    border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.5)),
  ),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      // Without the text, an empty box keeps the page number at the end of the row.
      if (showsFooterText)
        pw.Text(labels.footer, style: const pw.TextStyle(fontSize: 9, color: _secondaryText))
      else
        pw.SizedBox(),
      pw.Text(
        '${context.pageNumber} / ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 9, color: _secondaryText),
      ),
    ],
  ),
);
