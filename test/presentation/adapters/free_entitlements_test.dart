import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

void main() {
  group('FreeEntitlements', () {
    test('is entitlements that give the Free plan, at each call', () async {
      const Entitlements entitlements = FreeEntitlements();

      expect(await entitlements.currentPlan(), Plan.free);
      expect(await entitlements.currentPlan(), Plan.free);
    });

    test('reports no change of the plan', () async {
      const Entitlements entitlements = FreeEntitlements();

      await expectLater(entitlements.planChanges, emitsDone);
    });
  });
}
