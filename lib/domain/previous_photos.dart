// The domain imports only Dart core libraries, so `@immutable` from
// `package:meta` is not available here. Every field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

// 🌎 Project imports:
import 'package:kkomkkomi/domain/photo_ref.dart';
import 'package:kkomkkomi/domain/visit.dart';
import 'package:kkomkkomi/domain/visit_date.dart';

/// The photos that an earlier visit took for one zone.
///
/// A photo is null when that visit did not take it.
final class PreviousPhotos {
  const new({required this.visitId, required this.visitDate, this.beforePhoto, this.afterPhoto});

  final String visitId;
  final VisitDate visitDate;
  final PhotoRef? beforePhoto;
  final PhotoRef? afterPhoto;

  @override
  bool operator ==(Object other) =>
      other is PreviousPhotos &&
      other.visitId == visitId &&
      other.visitDate == visitDate &&
      other.beforePhoto == beforePhoto &&
      other.afterPhoto == afterPhoto;

  @override
  int get hashCode => Object.hash(visitId, visitDate, beforePhoto, afterPhoto);
}

/// The previous photos of each zone of [current], by zone identifier.
///
/// The previous photos of a zone are the photos of the newest visit in [history] that is earlier than [current] and
/// holds a record for that zone. A zone that no earlier visit recorded has no entry.
///
/// A visit in [history] with the identifier of [current] is [current] itself in an older state, so it is not an
/// earlier visit.
Map<String, PreviousPhotos> previousPhotosByZone(Visit current, Iterable<Visit> history) {
  final newestFirst =
      history.where((visit) => visit.id != current.id && visit.compareChronologically(current) < 0).toList()
        ..sort((a, b) => b.compareChronologically(a));
  final previous = <String, PreviousPhotos>{};
  for (final record in current.zoneRecords) {
    for (final visit in newestFirst) {
      final earlier = visit.recordFor(record.zoneId);
      if (earlier == null) continue;
      previous[record.zoneId] = PreviousPhotos(
        visitId: visit.id,
        visitDate: visit.visitDate,
        beforePhoto: earlier.beforePhoto,
        afterPhoto: earlier.afterPhoto,
      );
      break;
    }
  }
  return previous;
}
