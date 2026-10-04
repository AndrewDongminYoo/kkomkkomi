import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

/// Reports the Free plan, for a flavor or a platform that does not reach RevenueCat.
final class FreeEntitlements implements Entitlements {
  const new();

  @override
  Future<Plan> currentPlan() async => Plan.free;

  /// The plan never changes, so the stream ends without an event.
  @override
  Stream<Plan> get planChanges => const Stream.empty();
}
