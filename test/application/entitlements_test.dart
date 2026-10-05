import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  group('PlanOffer', () {
    const offer = PlanOffer(id: 'basic_monthly', plan: Plan.basic, period: BillingPeriod.monthly, price: 'price');

    test('is not active unless the store says so', () {
      expect(offer.isActive, isFalse);
    });

    test('equals an offer with the same values, and no offer that differs in one of them', () {
      expect(
        offer,
        const PlanOffer(id: 'basic_monthly', plan: Plan.basic, period: BillingPeriod.monthly, price: 'price'),
      );
      expect(
        offer.hashCode,
        const PlanOffer(id: 'basic_monthly', plan: Plan.basic, period: BillingPeriod.monthly, price: 'price').hashCode,
      );
      for (final other in const [
        PlanOffer(id: 'basic_annual', plan: Plan.basic, period: BillingPeriod.monthly, price: 'price'),
        PlanOffer(id: 'basic_monthly', plan: Plan.pro, period: BillingPeriod.monthly, price: 'price'),
        PlanOffer(id: 'basic_monthly', plan: Plan.basic, period: BillingPeriod.annual, price: 'price'),
        PlanOffer(id: 'basic_monthly', plan: Plan.basic, period: BillingPeriod.monthly, price: 'other'),
        PlanOffer(id: 'basic_monthly', plan: Plan.basic, period: BillingPeriod.monthly, price: 'price', isActive: true),
      ]) {
        expect(offer, isNot(other));
      }
    });

    test('names its values in its text', () {
      expect('$offer', 'PlanOffer(basic_monthly, Plan.basic, BillingPeriod.monthly, price, isActive: false)');
    });
  });
}
