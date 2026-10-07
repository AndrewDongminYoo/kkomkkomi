// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
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

  group('ManagementLink', () {
    final page = Uri.parse('https://apps.apple.com/account/subscriptions');

    test('is known with or without a page, and unknown without an answer of the store', () {
      expect(ManagementLink(page).isKnown, isTrue);
      expect(ManagementLink(page).url, page);
      expect(const ManagementLink(null).isKnown, isTrue);
      expect(const ManagementLink(null).url, isNull);
      expect(const ManagementLink.unknown().isKnown, isFalse);
      expect(const ManagementLink.unknown().url, isNull);
    });

    test('equals an answer with the same values only', () {
      final links = [ManagementLink(page), const ManagementLink(null), const ManagementLink.unknown()];
      for (final (index, link) in links.indexed) {
        for (final (otherIndex, other) in links.indexed) {
          expect(link == other, index == otherIndex, reason: '$index and $otherIndex');
        }
      }
      expect(ManagementLink(page).hashCode, ManagementLink(Uri.parse(page.toString())).hashCode);
    });

    test('names its values in its text', () {
      expect('${ManagementLink(page)}', 'ManagementLink(https://apps.apple.com/account/subscriptions)');
      expect('${const ManagementLink(null)}', 'ManagementLink(null)');
      expect('${const ManagementLink.unknown()}', 'ManagementLink.unknown()');
    });
  });
}
