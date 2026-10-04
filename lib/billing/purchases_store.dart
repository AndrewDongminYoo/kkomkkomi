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
}
