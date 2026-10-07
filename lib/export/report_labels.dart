// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/export/report_document.dart';

/// The fixed texts of a report, which the caller gives in the language of the app.
///
/// `lib/export/` reads no localization, so that it imports no Flutter library.
final class ReportLabels {
  const new({
    required this.title,
    required this.clientHeading,
    required this.visitDateHeading,
    required this.visitDate,
    required this.beforePhoto,
    required this.afterPhoto,
    required this.notPhotographed,
    required this.partlyDone,
    required this.notDone,
    required this.summaryOf,
    required this.note,
    required this.footer,
    required this.galleryPhoto,
    required this.captureTimeOf,
  });

  /// The heading of the report, which also starts the file name.
  final String title;

  /// The text in front of the client name in the table under the heading.
  final String clientHeading;

  /// The text in front of the visit date in the table under the heading.
  final String visitDateHeading;

  /// The date of the visit, written as the language of the app writes a date.
  final String visitDate;

  /// The text over the before photo of a zone.
  final String beforePhoto;

  /// The text over the after photo of a zone.
  final String afterPhoto;

  /// The text inside an empty photo slot of a zone that the visit cleaned, in full or in part.
  final String notPhotographed;

  /// The status of a zone that the visit cleaned in part.
  final String partlyDone;

  /// The status of a zone that the visit did not clean, which is also the text inside its empty photo slots.
  final String notDone;

  /// The summary line of the report, from the number of done zones and the number of the zones of the report.
  final String Function(int done, int total) summaryOf;

  /// The text over the note of a zone.
  final String note;

  /// The text at the foot of every page.
  final String footer;
  final String galleryPhoto;
  final String Function(DateTime) captureTimeOf;

  /// A caption only when the slot holds a photo with a known gallery source or an observed camera time.
  String photoCaptionOf(PhotoRef? photo, PhotoSource source, DateTime? capturedAt) {
    if (photo == null) return '';
    if (source == PhotoSource.gallery) return galleryPhoto;
    return source == PhotoSource.camera && capturedAt != null ? captureTimeOf(capturedAt) : '';
  }

  /// The status of [status] as the report writes it, or an empty text for [ZoneStatus.done], which the report does
  /// not write.
  String statusOf(ZoneStatus status) => switch (status) {
    ZoneStatus.done => '',
    ZoneStatus.partlyDone => partlyDone,
    ZoneStatus.notDone => notDone,
  };

  /// The line of the summary for [zone], which is not done: its name and its status, then its reason when it has one.
  String exceptionLineOf(ReportZone zone) {
    final head = '${zone.name} · ${statusOf(zone.status)}';
    return zone.reason.isEmpty ? head : '$head: ${zone.reason}';
  }

  /// The text inside an empty photo slot of a zone with [status].
  String emptySlotOf(ZoneStatus status) => status == ZoneStatus.notDone ? notDone : notPhotographed;
}
