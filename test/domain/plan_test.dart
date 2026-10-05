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

  group('clientLimit', () {
    test('is 2 for Free, 5 for Basic, and none for Pro', () {
      expect({for (final plan in Plan.values) plan: plan.clientLimit}, {Plan.free: 2, Plan.basic: 5, Plan.pro: null});
    });
  });

  group('allowsAnotherClient', () {
    for (final (plan, activeClients, allowed) in <(Plan, int, bool)>[
      (Plan.free, 0, true),
      (Plan.free, 1, true),
      (Plan.free, 2, false),
      (Plan.free, 3, false),
      (Plan.basic, 4, true),
      (Plan.basic, 5, false),
      (Plan.basic, 6, false),
      (Plan.pro, 0, true),
      (Plan.pro, 12, true),
      (Plan.pro, 10000, true),
    ]) {
      test('is $allowed for $plan with $activeClients active clients', () {
        expect(plan.allowsAnotherClient(activeClients), allowed);
      });
    }
  });

  group('showsFooter', () {
    test('is true only for Free', () {
      expect(
        {for (final plan in Plan.values) plan: plan.showsFooter},
        {
          Plan.free: true,
          Plan.basic: false,
          Plan.pro: false,
        },
      );
    });
  });
}
