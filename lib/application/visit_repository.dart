// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';

/// Stores the visits and their zone records.
abstract interface class VisitRepository {
  /// Saves [visit] and replaces its zone records, in one transaction.
  ///
  /// Saves take effect in the order of the calls, and a read that is called after a save reads what that save
  /// stored, also when the caller does not wait for the save. A screen that saves on each change relies on that order.
  /// Throws an [ArgumentError], and saves nothing, when a record is for a zone that the client of the visit does not
  /// have.
  Future<void> save(Visit visit);

  /// The visit with [id], or null when none exists.
  Future<Visit?> visitById(String id);

  /// The visits of the client with [clientId], newest first.
  Future<List<Visit>> visitsOf(String clientId);
}
