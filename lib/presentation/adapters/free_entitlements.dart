import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

/// Reports the Free plan and sells nothing, for a flavor or a platform that does not reach RevenueCat.
final class FreeEntitlements implements Entitlements {
  const new();

  @override
  bool get sellsPlans => false;

  @override
  Future<Plan> currentPlan() async => Plan.free;

  /// The plan never changes, so the stream ends without an event.
  @override
  Stream<Plan> get planChanges => const Stream.empty();

  @override
  Future<List<PlanOffer>> offers() async => const [];

  @override
  Future<PurchaseOutcome> purchase(PlanOffer offer) async => PurchaseOutcome.failed;

  @override
  Future<RestoreOutcome> restore() async => RestoreOutcome.failed;

  @override
  Future<Uri?> managementUrl() async => null;

  /// Nothing comes from a store, so nothing is kept.
  @override
  Future<void> invalidate() async {}
}
