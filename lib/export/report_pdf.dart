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
const double reportSlotAspectRatio = 4 / 3;

/// The most lines that a name takes. A block with a name must fit on one page, and a name has no length limit.
const _nameMaxLines = 3;

/// The most pages that one note takes in a debug build.
///
/// The `pdf` package stops a widget that goes on for more pages than this, in a build with assertions only, as a
/// guard against a layout that never ends. Its default is 20 pages, which a long note passes, and a note has no
/// length limit, so the guard stands at a count that no note of a person reaches.
const _notePageLimit = 1000;

const PdfColor _secondaryText = PdfColors.grey700;
const PdfColor _slotBackground = PdfColors.grey200;

/// Renders [document] as an A4 PDF and gives the bytes of the file.
///
/// [font] is a TrueType font that has the glyphs of the texts, and the file holds the glyphs that it uses. A
/// character that the font does not have prints as a crossed box. [photos] holds the bytes of the file of every
/// photo in [ReportDocument.photos], as a JPEG or a PNG. A note that is longer than a page goes on to the next page.
/// The foot of every page holds the page number, and the footer text of [labels] when [showsFooterText] is true.
///
/// Throws an [ArgumentError] when [photos] lacks a photo of the document. The image decoder throws when the bytes
/// of a photo are no image.
Future<Uint8List> renderReportPdf(
  ReportDocument document, {
  required ReportLabels labels,
  required ByteData font,
  required Map<PhotoRef, Uint8List> photos,
  bool showsFooterText = true,
}) {
  final typeface = pw.Font.ttf(font);
  final pdf = pw.Document(
    // The font file has one weight, so every style of the theme is that font.
    theme: pw.ThemeData.withFont(base: typeface, bold: typeface, italic: typeface, boldItalic: typeface),
  );
  final images = {
    for (final photo in document.photos) photo: pw.MemoryImage(_bytesOf(photo, photos)),
  };
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_pageMargin),
      maxPages: _notePageLimit,
      footer: (context) => _footer(context, labels, showsFooterText: showsFooterText),
      build: (context) => [
        _header(document, labels),
        for (final zone in document.zones) ..._zone(zone, labels, images),
      ],
    ),
  );
  return pdf.save();
}

Uint8List _bytesOf(PhotoRef photo, Map<PhotoRef, Uint8List> photos) =>
    photos[photo] ??
    (throw ArgumentError.value(photo.path, 'photos', 'The bytes of a photo of the document are missing'));

pw.Widget _header(ReportDocument document, ReportLabels labels) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    if (document.companyName case final companyName?)
      pw.Text(
        companyName,
        style: const pw.TextStyle(fontSize: 12, color: _secondaryText),
        maxLines: _nameMaxLines,
      ),
    pw.Text(labels.title, style: const pw.TextStyle(fontSize: 22)),
    pw.SizedBox(height: 6),
    pw.Text(document.clientName, style: const pw.TextStyle(fontSize: 14), maxLines: _nameMaxLines),
    pw.Text(labels.visitDate, style: const pw.TextStyle(fontSize: 11, color: _secondaryText)),
    pw.SizedBox(height: 8),
    pw.Divider(height: 1, thickness: 0.5, color: PdfColors.grey500),
  ],
);

/// The widgets of one zone. The name and the photo slots stay on one page, and the note can go on to the next page.
List<pw.Widget> _zone(ReportZone zone, ReportLabels labels, Map<PhotoRef, pw.ImageProvider> images) => [
  // A column spans pages when it is a direct child of the page, which would leave a name at the foot of one page
  // and its photos at the head of the next.
  pw.Inseparable(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 16),
        pw.Text(zone.name, style: const pw.TextStyle(fontSize: 14), maxLines: _nameMaxLines),
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
    pw.SizedBox(height: 8),
    pw.Text(labels.note, style: const pw.TextStyle(fontSize: 9, color: _secondaryText)),
    // The text is a direct child of the page and spans, so that a long note goes on to the next page.
    pw.Text(zone.note, style: const pw.TextStyle(fontSize: 11, lineSpacing: 2), overflow: pw.TextOverflow.span),
  ],
];

/// One photo slot: [label] over the photo, or over an empty box that says that the zone has no photo there.
pw.Widget _slot(String label, pw.ImageProvider? image, ReportLabels labels) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _secondaryText)),
    pw.SizedBox(height: 3),
    pw.AspectRatio(
      aspectRatio: reportSlotAspectRatio,
      child: pw.Container(
        color: _slotBackground,
        alignment: pw.Alignment.center,
        child: image == null
            ? pw.Text(labels.noPhoto, style: const pw.TextStyle(fontSize: 10, color: _secondaryText))
            // The default fit shows the whole photo, because a report must not cut what the photo proves.
            : pw.Image(image),
      ),
    ),
  ],
);

pw.Widget _footer(pw.Context context, ReportLabels labels, {required bool showsFooterText}) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 12),
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
