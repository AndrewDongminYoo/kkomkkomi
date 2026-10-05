import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

void main() {
  group('FreeEntitlements', () {
    const Entitlements entitlements = FreeEntitlements();
    const offer = PlanOffer(id: 'basic_monthly', plan: Plan.basic, period: BillingPeriod.monthly, price: 'price');

    test('is entitlements that give the Free plan, at each call', () async {
      expect(await entitlements.currentPlan(), Plan.free);
      expect(await entitlements.currentPlan(), Plan.free);
    });

    test('reports no change of the plan', () async {
      await expectLater(entitlements.planChanges, emitsDone);
    });

    test('sells nothing: no offers, a failed purchase, a failed restore, and no management page', () async {
      expect(entitlements.sellsPlans, isFalse);
      expect(await entitlements.offers(), isEmpty);
      expect(await entitlements.purchase(offer), PurchaseOutcome.failed);
      expect(await entitlements.restore(), RestoreOutcome.failed);
      expect(await entitlements.managementUrl(), isNull);
    });

    test('drops nothing at an invalidation, and still gives the Free plan', () async {
      await entitlements.invalidate();

      expect(await entitlements.currentPlan(), Plan.free);
    });
  });
}
