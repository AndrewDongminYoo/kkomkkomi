import 'package:kkomkkomi/domain/domain.dart';

/// Tells which plan the company has, so that tests never reach a store.
abstract interface class Entitlements {
  /// The plan that the store last confirmed. Without an answer of the store it is the last plan that this object
  /// knew, and [Plan.free] before any answer. The call does not throw.
  Future<Plan> currentPlan();

  /// Each plan that the store reports after the first answer, for example after a renewal or an expiry.
  Stream<Plan> get planChanges;
}
