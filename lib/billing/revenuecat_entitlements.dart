import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/billing/purchases_store.dart';
import 'package:kkomkkomi/domain/domain.dart';

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
}

/// Reads the plan from RevenueCat, with the Firebase user ID as the RevenueCat app user ID.
///
/// Nothing reaches RevenueCat before the first call of [currentPlan], and nothing reaches it before [Identity] gives
/// a user ID: the RevenueCat Firebase extension needs the two IDs to be equal, so the adapter never configures
/// RevenueCat with another ID.
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

  /// The attempt that is on its way, so that two calls at one time configure RevenueCat once.
  Future<Plan>? _attempt;

  final _changes = StreamController<Plan>.broadcast();

  @override
  Future<Plan> currentPlan() => _attempt ??= _read().whenComplete(() => _attempt = null);

  @override
  Stream<Plan> get planChanges => _changes.stream;

  Future<Plan> _read() async {
    try {
      final userId = await _identity.currentUserId();
      // Without the Firebase user ID, RevenueCat would make an anonymous user of its own.
      if (userId == null) return _plan;
      await _useUser(userId);
      _plan = Plan.fromEntitlements(await _store.activeEntitlementIds());
    } on Object catch (error, stackTrace) {
      // The plugin fails with a `PlatformException` without a network or a store, and a platform without the plugin
      // fails with an `Error`. The port does not throw, so the clause catches every object and keeps the last plan.
      log('RevenueCat did not give the plan: $error', stackTrace: stackTrace);
    }
    return _plan;
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
