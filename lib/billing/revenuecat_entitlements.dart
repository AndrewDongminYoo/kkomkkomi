import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/billing/purchases_store.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show PurchasesErrorCode, PurchasesErrorHelper;

/// The RevenueCat adapter for [platform], or null when the platform is not iOS or Android or its key is empty.
///
/// The production build reads the keys from `config/revenuecat.json` through `--dart-define-from-file`. A build
/// without them gets empty keys, and the caller then uses the Free-only adapter.
Entitlements? revenueCatEntitlementsFor({
  required Identity identity,
  required TargetPlatform platform,
  // A default value is a constant context, so each read is a `const String.fromEnvironment` invocation, the one form
  // that the Dart documentation guarantees.
  String iosKey = const String.fromEnvironment('REVENUECAT_IOS_API_KEY'),
  String androidKey = const String.fromEnvironment('REVENUECAT_ANDROID_API_KEY'),
}) {
  final apiKey = switch (platform) {
    TargetPlatform.iOS => iosKey,
    TargetPlatform.android => androidKey,
    _ => '',
  };
  if (apiKey.isEmpty) return null;
  return RevenueCatEntitlements(identity: identity, apiKey: apiKey);
}

/// The calls of `purchases_flutter` that the adapter makes, so that a test needs no platform channel.
abstract interface class RevenueCatStore {
  /// Whether RevenueCat was configured in this process.
  Future<bool> isConfigured();

  /// Configures RevenueCat with [apiKey], for the app user [appUserId].
  Future<void> configure({required String apiKey, required String appUserId});

  /// Moves the configured RevenueCat to the app user [appUserId].
  Future<void> logIn(String appUserId);

  /// The identifiers of the active entitlements of the current app user.
  Future<Iterable<String>> activeEntitlementIds();

  /// Calls [listener] with the active entitlement identifiers each time RevenueCat reports new customer information.
  void addListener(void Function(Iterable<String> activeIds) listener);

  /// The packages of the current offering, with the price text and the product identifier of the store.
  Future<List<RevenueCatPackage>> currentOfferingPackages();

  /// The store product identifiers that grant the active entitlements. A Google Play product also appears as its
  /// subscription and base plan identifiers joined by a colon.
  Future<Iterable<String>> activeProductIds();

  /// Opens the purchase sheet of the store for the package [packageId] of the current offering, and gives the active
  /// entitlement identifiers after the purchase. On Google Play, the purchase replaces the subscription in use, so
  /// that a change of the plan or the period never starts a second subscription. Throws the `PlatformException` of
  /// the plugin when the purchase does not complete, and the error of the read when the subscription in use cannot be
  /// read, so that no purchase starts without the one that it replaces.
  Future<Iterable<String>> purchasePackage(String packageId);

  /// Restores the purchases of the store account, and gives the active entitlement identifiers after the restore.
  Future<Iterable<String>> restore();

  /// The store page where the subscriptions of the current app user are managed, or null when RevenueCat knows none.
  Future<String?> managementUrl();

  /// Makes RevenueCat forget the customer information that it keeps, so that the next read asks its server.
  Future<void> invalidateCustomerInfoCache();
}

/// A package of a RevenueCat offering: its package identifier, the price text of the store, and the product
/// identifier of the store.
typedef RevenueCatPackage = ({String id, String price, String productId});

/// The plan and the period of each package identifier that the operator sets in the RevenueCat dashboard, in the
/// order of the offers. A package with another identifier is not sold.
const Map<String, (Plan, BillingPeriod)> _packages = {
  'basic_monthly': (Plan.basic, BillingPeriod.monthly),
  'basic_annual': (Plan.basic, BillingPeriod.annual),
  'pro_monthly': (Plan.pro, BillingPeriod.monthly),
  'pro_annual': (Plan.pro, BillingPeriod.annual),
};

/// Reads the plan from RevenueCat and sells the plans through it, with the Firebase user ID as the RevenueCat app user
/// ID.
///
/// Nothing reaches RevenueCat before the first call of a method, and nothing reaches it before [Identity] gives a user
/// ID: the RevenueCat Firebase extension needs the two IDs to be equal, so the adapter never configures RevenueCat
/// with another ID.
final class RevenueCatEntitlements implements Entitlements {
  /// The `store` argument replaces the `Purchases` API of `purchases_flutter` in a test.
  new({required this._identity, required this._apiKey, this._store = const PurchasesStore()});

  final Identity _identity;
  final String _apiKey;
  final RevenueCatStore _store;

  /// The last plan that RevenueCat confirmed for [_userId], which a call gives when RevenueCat does not answer.
  Plan _plan = Plan.free;

  /// The user ID that RevenueCat is configured for, or null while no configuration or move to the current user ID
  /// worked.
  String? _userId;

  /// Whether the listener of the customer information is added. It is added once, after the first configuration.
  bool _listening = false;

  /// The read of the plan that is on its way, so that two calls at one time share one read.
  Future<Plan>? _attempt;

  /// The configuration that is on its way, so that two methods at one time configure RevenueCat once.
  Future<bool>? _configuring;

  final _changes = StreamController<Plan>.broadcast();

  @override
  bool get sellsPlans => true;

  @override
  Future<Plan> currentPlan() => _attempt ??= _read().whenComplete(() => _attempt = null);

  @override
  Stream<Plan> get planChanges => _changes.stream;

  @override
  Future<List<PlanOffer>> offers() async {
    try {
      if (!await _ensureUser()) return const [];
      final packages = await _store.currentOfferingPackages();
      final activeProducts = await _activeProducts();
      return [
        for (final MapEntry(key: id, value: (plan, period)) in _packages.entries)
          if (packages.where((package) => package.id == id).firstOrNull case final package?)
            PlanOffer(
              id: id,
              plan: plan,
              period: period,
              price: package.price,
              isActive: activeProducts.contains(package.productId),
            ),
      ];
    } on Object catch (error, stackTrace) {
      log('RevenueCat did not give the offers: $error', stackTrace: stackTrace);
      return const [];
    }
  }

  @override
  Future<PurchaseOutcome> purchase(PlanOffer offer) async {
    try {
      if (!await _ensureUser()) return PurchaseOutcome.failed;
      _onEntitlements(await _store.purchasePackage(offer.id));
      return PurchaseOutcome.purchased;
    } on PlatformException catch (error, stackTrace) {
      switch (_errorCodeOf(error)) {
        case PurchasesErrorCode.purchaseCancelledError:
          return PurchaseOutcome.cancelled;
        case PurchasesErrorCode.paymentPendingError:
          return PurchaseOutcome.pending;
        case _:
          log('RevenueCat did not complete the purchase: $error', stackTrace: stackTrace);
          return PurchaseOutcome.failed;
      }
    } on Object catch (error, stackTrace) {
      log('RevenueCat did not complete the purchase: $error', stackTrace: stackTrace);
      return PurchaseOutcome.failed;
    }
  }

  @override
  Future<RestoreOutcome> restore() async {
    try {
      if (!await _ensureUser()) return RestoreOutcome.failed;
      final activeIds = await _store.restore();
      _onEntitlements(activeIds);
      return Plan.fromEntitlements(activeIds).isPaid ? RestoreOutcome.restored : RestoreOutcome.nothingFound;
    } on Object catch (error, stackTrace) {
      log('RevenueCat did not restore the purchases: $error', stackTrace: stackTrace);
      return RestoreOutcome.failed;
    }
  }

  @override
  Future<Uri?> managementUrl() async {
    try {
      if (!await _ensureUser()) return null;
      return switch (await _store.managementUrl()) {
        final url? => Uri.tryParse(url),
        null => null,
      };
    } on Object catch (error, stackTrace) {
      log('RevenueCat did not give the management page: $error', stackTrace: stackTrace);
      return null;
    }
  }

  /// `Purchases.getCustomerInfo` normally gives the customer information that RevenueCat keeps (its documentation in
  /// `purchases_flutter` 10.14.0), so a change in the subscription management of the store could stay unseen.
  @override
  Future<void> invalidate() async {
    // Before a configuration for the current user ID, RevenueCat keeps nothing that a read would give: the
    // configuration or the move to the user ID reads the customer information again.
    if (_userId == null) return;
    try {
      await _store.invalidateCustomerInfoCache();
    } on Object catch (error, stackTrace) {
      log('RevenueCat did not forget the customer information: $error', stackTrace: stackTrace);
    }
  }

  /// The store product identifiers in use, or none when RevenueCat does not give them. The offers do not fail with
  /// them: an offer that is not marked as active still shows, and the screen then counts both periods of the current
  /// plan as in use.
  Future<Set<String>> _activeProducts() async {
    try {
      return (await _store.activeProductIds()).toSet();
    } on Object catch (error, stackTrace) {
      log('RevenueCat did not give the products in use: $error', stackTrace: stackTrace);
      return const {};
    }
  }

  Future<Plan> _read() async {
    try {
      // Without the Firebase user ID, RevenueCat would make an anonymous user of its own.
      if (!await _ensureUser()) return _plan;
      _plan = Plan.fromEntitlements(await _store.activeEntitlementIds());
    } on Object catch (error, stackTrace) {
      // The plugin fails with a `PlatformException` without a network or a store, and a platform without the plugin
      // fails with an `Error`. The port does not throw, so the clause catches every object and keeps the last plan.
      log('RevenueCat did not give the plan: $error', stackTrace: stackTrace);
    }
    return _plan;
  }

  /// Makes sure that RevenueCat is configured for the current user ID, and answers false when there is no user ID.
  Future<bool> _ensureUser() => _configuring ??= _configure().whenComplete(() => _configuring = null);

  Future<bool> _configure() async {
    final userId = await _identity.currentUserId();
    if (userId == null) return false;
    await _useUser(userId);
    return true;
  }

  Future<void> _useUser(String userId) async {
    if (_userId == userId) return;
    // The last plan belongs to the user ID before this one, so a failure from here on gives Free, not that plan.
    // Until the move works, RevenueCat can still report the plan of that user ID, and the listener ignores it.
    _userId = null;
    _plan = Plan.free;
    if (await _store.isConfigured()) {
      // RevenueCat was configured for another user ID, for example the one of an account that Delete All Data
      // removed, or by an earlier object in this process.
      await _store.logIn(userId);
    } else {
      await _store.configure(apiKey: _apiKey, appUserId: userId);
    }
    _userId = userId;
    if (!_listening) {
      _listening = true;
      _store.addListener(_onEntitlements);
    }
  }

  void _onEntitlements(Iterable<String> activeIds) {
    if (_userId == null) return;
    final plan = Plan.fromEntitlements(activeIds);
    if (plan == _plan) return;
    _plan = plan;
    _changes.add(plan);
  }
}

/// The error code of [error], or null when its code is no number, which `PurchasesErrorHelper.getErrorCode` parses.
PurchasesErrorCode? _errorCodeOf(PlatformException error) {
  try {
    return PurchasesErrorHelper.getErrorCode(error);
  } on FormatException {
    return null;
  }
}
