import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  group('Plan.fromEntitlements', () {
    for (final (activeIds, plan) in <(List<String>, Plan)>[
      (['basic', 'pro'], Plan.pro),
      (['pro'], Plan.pro),
      (['basic'], Plan.basic),
      ([], Plan.free),
      (['team'], Plan.free),
    ]) {
      test('gives $plan for the active entitlements $activeIds', () {
        expect(Plan.fromEntitlements(activeIds), plan);
      });
    }

    test('ignores an identifier that it does not know beside one that it knows', () {
      expect(Plan.fromEntitlements(['team', 'basic']), Plan.basic);
    });
  });

  group('isPaid', () {
    test('is false for Free and true for Basic and Pro', () {
      expect({for (final plan in Plan.values) plan: plan.isPaid}, {Plan.free: false, Plan.basic: true, Plan.pro: true});
    });
  });
}
