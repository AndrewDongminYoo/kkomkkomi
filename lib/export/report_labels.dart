/// The fixed texts of a report, which the caller gives in the language of the app.
///
/// `lib/export/` reads no localization, so that it imports no Flutter library.
final class ReportLabels {
  const new({
    required this.title,
    required this.visitDate,
    required this.beforePhoto,
    required this.afterPhoto,
    required this.noPhoto,
    required this.note,
    required this.footer,
  });

  /// The heading of the report, which also starts the file name.
  final String title;

  /// The date of the visit, written as the language of the app writes a date.
  final String visitDate;

  /// The text over the before photo of a zone.
  final String beforePhoto;

  /// The text over the after photo of a zone.
  final String afterPhoto;

  /// The text inside a photo slot that holds no photo.
  final String noPhoto;

  /// The text over the note of a zone.
  final String note;

  /// The text at the foot of every page.
  final String footer;
}
