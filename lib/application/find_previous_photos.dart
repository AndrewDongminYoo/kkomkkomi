import 'package:kkomkkomi/application/visit_repository.dart';
import 'package:kkomkkomi/domain/domain.dart';

/// Finds the previous photos of each zone of a visit.
final class FindPreviousPhotos {
  const new({required this._visits});

  final VisitRepository _visits;

  /// The previous photos of each zone of [visit], by zone identifier, as [previousPhotosByZone] defines them.
  Future<Map<String, PreviousPhotos>> call(Visit visit) async =>
      previousPhotosByZone(visit, await _visits.visitsOf(visit.clientId));
}
