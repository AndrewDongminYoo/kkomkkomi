// Every field of `PlanOffer` is final, and `package:meta`, which has `@immutable`, is not a dependency.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';

/// Tells which plan the company has, and sells the paid plans, so that tests never reach a store.
abstract interface class Entitlements {
  /// Whether this build can sell a plan. A build without a store, such as the development and staging flavors and a
  /// production build without keys, cannot, and its [offers] are always empty.
  bool get sellsPlans;

  /// The plan that the store last confirmed. Without an answer of the store it is the last plan that this object
  /// knew, and [Plan.free] before any answer. The call does not throw.
  Future<Plan> currentPlan();

  /// Each plan that the store reports after the first answer, for example after a renewal, an expiry, a purchase, or
  /// a restore.
  Stream<Plan> get planChanges;

  /// The offers for sale, in the order Basic monthly, Basic annual, Pro monthly, Pro annual, or empty when the store
  /// does not answer or nothing is for sale. The call does not throw.
  Future<List<PlanOffer>> offers();

  /// Opens the store's purchase sheet for [offer]. The call does not throw.
  ///
  /// The outcome does not grant a plan: the plan comes from [currentPlan] and [planChanges] after the store answers.
  Future<PurchaseOutcome> purchase(PlanOffer offer);

  /// Asks the store for the purchases of its account. The call does not throw.
  ///
  /// As with [purchase], the plan comes from [currentPlan] and [planChanges].
  Future<RestoreOutcome> restore();

  /// The store page where the subscription is managed, as a known answer, which has no URL when the store knows none,
  /// or as [ManagementLink.unknown] when the store did not answer. The call does not throw.
  Future<ManagementLink> managementUrl();

  /// Makes the next reads of [currentPlan] and [offers] ask the store, and not give an answer that was kept from
  /// before. The store can change the subscription outside the app, for example a switch of the period in its
  /// subscription management. The call does not throw.
  Future<void> invalidate();
}

/// One product that the store sells, with the price text that the store gives for the device's storefront.
final class PlanOffer {
  const new({required this.id, required this.plan, required this.period, required this.price, this.isActive = false});

  /// The RevenueCat package identifier.
  final String id;

  final Plan plan;

  final BillingPeriod period;

  /// The price, localized by the store. The app never computes it.
  final String price;

  /// Whether the store reported this product as the one that grants the current plan, when the offers were read.
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      other is PlanOffer &&
      other.id == id &&
      other.plan == plan &&
      other.period == period &&
      other.price == price &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, plan, period, price, isActive);

  @override
  String toString() => 'PlanOffer($id, $plan, $period, $price, isActive: $isActive)';
}

/// The answer of [Entitlements.managementUrl]: a known answer, with or without a URL, or no answer of the store.
final class ManagementLink {
  /// The store answered, with [url] as its management page, or with no page when [url] is null.
  const new(this.url) : isKnown = true;

  /// The store did not answer, so nothing is known of the management page.
  const new unknown() : url = null, isKnown = false;

  /// The store page where the subscription is managed, or null when the store knows none or did not answer.
  final Uri? url;

  /// Whether the store answered. A caller keeps the page that it knew when the store did not.
  final bool isKnown;

  @override
  bool operator ==(Object other) => other is ManagementLink && other.url == url && other.isKnown == isKnown;

  @override
  int get hashCode => Object.hash(url, isKnown);

  @override
  String toString() => isKnown ? 'ManagementLink($url)' : 'ManagementLink.unknown()';
}

/// What became of a purchase.
enum PurchaseOutcome {
  /// The store took the payment.
  purchased,

  /// The person closed the purchase sheet.
  cancelled,

  /// The purchase waits for an approval, for example of Ask to Buy, or for a payment that is not complete.
  pending,

  /// The purchase did not work, or the build cannot sell.
  failed,
}

/// What became of a restore.
enum RestoreOutcome {
  /// The store found a paid plan for its account.
  restored,

  /// The store answered and found no paid plan.
  nothingFound,

  /// The store did not answer, or the build cannot restore.
  failed,
}
