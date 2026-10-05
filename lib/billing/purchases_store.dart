import 'package:kkomkkomi/billing/revenuecat_entitlements.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// The [RevenueCatStore] of `purchases_flutter`, the one class that calls the plugin.
final class PurchasesStore implements RevenueCatStore {
  const new();

  @override
  Future<bool> isConfigured() => Purchases.isConfigured;

  @override
  Future<void> configure({required String apiKey, required String appUserId}) =>
      Purchases.configure(PurchasesConfiguration(apiKey)..appUserID = appUserId);

  @override
  Future<void> logIn(String appUserId) => Purchases.logIn(appUserId);

  @override
  Future<Iterable<String>> activeEntitlementIds() async => (await Purchases.getCustomerInfo()).entitlements.active.keys;

  @override
  void addListener(void Function(Iterable<String> activeIds) listener) =>
      Purchases.addCustomerInfoUpdateListener((customerInfo) => listener(customerInfo.entitlements.active.keys));

  @override
  Future<List<RevenueCatPackage>> currentOfferingPackages() async => [
    for (final package in (await Purchases.getOfferings()).current?.availablePackages ?? const <Package>[])
      (id: package.identifier, price: package.storeProduct.priceString, productId: package.storeProduct.identifier),
  ];

  @override
  Future<Iterable<String>> activeProductIds() async => [
    for (final entitlement in (await Purchases.getCustomerInfo()).entitlements.active.values) ...[
      entitlement.productIdentifier,
      // A Google Play subscription has base plans, and the entitlement names its base plan apart.
      if (entitlement.productPlanIdentifier case final basePlan?) '${entitlement.productIdentifier}:$basePlan',
    ],
  ];

  @override
  Future<Iterable<String>> purchasePackage(String packageId) async {
    // A purchase needs the `Package` object of the plugin, which carries the context of the offering that showed it,
    // so the store reads the offerings again.
    final package = (await Purchases.getOfferings()).current?.getPackage(packageId);
    if (package == null) throw StateError('The current offering has no package $packageId.');
    final replaced = await _googlePlaySubscriptionInUse();
    final params = PurchaseParams.package(
      package,
      productChangeInfo: replaced == null
          ? null
          : StoreProductChangeInfo(
              replaced,
              replacementMode: _replacementMode(replaced: replaced, product: package.storeProduct.identifier),
            ),
    );
    return (await Purchases.purchase(params)).customerInfo.entitlements.active.keys;
  }

  /// The replacement mode of a change from the Google Play subscription [replaced] to the store [product], which a
  /// Google Play product names as its subscription and base plan identifiers joined by a colon. Both modes take
  /// effect at once, so the purchase answers with the new plan.
  ///
  /// A change to the other subscription credits the unused time of the replaced one toward the new one. Google Play
  /// fails a change of the base plan inside one subscription to an auto-renewing plan in any mode but
  /// `CHARGE_FULL_PRICE` and `WITHOUT_PRORATION`
  /// (https://developer.android.com/google/play/billing/subscriptions, read on 2026-10-05), so that change charges
  /// the full price of the new base plan, and Google Play carries the remaining value of the old one over.
  static StoreReplacementMode _replacementMode({required String replaced, required String product}) =>
      product.split(':').first == replaced
      ? StoreReplacementMode.chargeFullPrice
      : StoreReplacementMode.withTimeProration;

  /// The identifier of the Google Play subscription in use, without its base plan, or null when none is in use.
  /// RevenueCat finds the purchase to replace by the subscription identifier alone: `purchases-android`
  /// (`PurchasesOrchestrator`, read on 2026-10-05) cuts a base plan off and logs that the identifier should not hold
  /// one.
  ///
  /// Google Play holds `basic` and `pro` as two subscriptions, so a purchase of the other plan without the one that
  /// it replaces would start a second subscription, and the person would pay for both. A change of the base plan in
  /// one subscription needs it too. The App Store changes a product inside the subscription group by itself, and only
  /// a Google Play entitlement has a base plan.
  Future<String?> _googlePlaySubscriptionInUse() async {
    for (final entitlement in (await Purchases.getCustomerInfo()).entitlements.active.values) {
      if (entitlement.productPlanIdentifier != null) return entitlement.productIdentifier;
    }
    return null;
  }

  @override
  Future<Iterable<String>> restore() async => (await Purchases.restorePurchases()).entitlements.active.keys;

  @override
  Future<String?> managementUrl() async => (await Purchases.getCustomerInfo()).managementURL;

  @override
  Future<void> invalidateCustomerInfoCache() => Purchases.invalidateCustomerInfoCache();
}
