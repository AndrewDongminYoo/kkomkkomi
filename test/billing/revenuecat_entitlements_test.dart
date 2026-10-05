import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/billing/billing.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show PurchasesErrorCode;

import '../helpers/helpers.dart';

/// Records the calls of the adapter, and answers as a test sets it.
class _FakeStore implements RevenueCatStore {
  /// Whether RevenueCat counts as configured. A configuration sets it.
  bool configured = false;

  /// The active entitlement identifiers that a read gives.
  Iterable<String> activeIds = const [];

  /// What a read of the entitlements throws while it is set.
  Object? readFailure;

  /// What a configuration throws while it is set.
  Object? configureFailure;

  /// What a move to another user ID throws while it is set.
  Object? logInFailure;

  /// A configuration waits for this completer while it is set.
  Completer<void>? configureGate;

  final calls = <String>[];
  final listeners = <void Function(Iterable<String>)>[];

  @override
  Future<bool> isConfigured() async {
    calls.add('isConfigured');
    return configured;
  }

  @override
  Future<void> configure({required String apiKey, required String appUserId}) async {
    calls.add('configure $apiKey $appUserId');
    await configureGate?.future;
    if (configureFailure case final failure?) Error.throwWithStackTrace(failure, StackTrace.current);
    configured = true;
  }

  @override
  Future<void> logIn(String appUserId) async {
    calls.add('logIn $appUserId');
    if (logInFailure case final failure?) Error.throwWithStackTrace(failure, StackTrace.current);
  }

  @override
  Future<Iterable<String>> activeEntitlementIds() async {
    calls.add('activeEntitlementIds');
    if (readFailure case final failure?) Error.throwWithStackTrace(failure, StackTrace.current);
    return activeIds;
  }

  @override
  void addListener(void Function(Iterable<String> activeIds) listener) {
    calls.add('addListener');
    listeners.add(listener);
  }

  /// The packages of the current offering that a read gives.
  List<RevenueCatPackage> packages = const [];

  /// The product identifiers of the active entitlements that a read gives.
  Iterable<String> activeProducts = const [];

  /// What a read of the packages throws while it is set.
  Object? offersFailure;

  /// What a read of the active products throws while it is set.
  Object? activeProductsFailure;

  /// The active entitlement identifiers that a purchase gives.
  Iterable<String> purchasedIds = const [];

  /// What a purchase throws while it is set.
  Object? purchaseFailure;

  /// The active entitlement identifiers that a restore gives.
  Iterable<String> restoredIds = const [];

  /// What a restore throws while it is set.
  Object? restoreFailure;

  /// The management page that a read gives.
  String? management;

  /// What a read of the management page throws while it is set.
  Object? managementFailure;

  @override
  Future<List<RevenueCatPackage>> currentOfferingPackages() async {
    calls.add('currentOfferingPackages');
    if (offersFailure case final failure?) Error.throwWithStackTrace(failure, StackTrace.current);
    return packages;
  }

  @override
  Future<Iterable<String>> activeProductIds() async {
    calls.add('activeProductIds');
    if (activeProductsFailure case final failure?) Error.throwWithStackTrace(failure, StackTrace.current);
    return activeProducts;
  }

  @override
  Future<Iterable<String>> purchasePackage(String packageId) async {
    calls.add('purchasePackage $packageId');
    if (purchaseFailure case final failure?) Error.throwWithStackTrace(failure, StackTrace.current);
    return purchasedIds;
  }

  @override
  Future<Iterable<String>> restore() async {
    calls.add('restore');
    if (restoreFailure case final failure?) Error.throwWithStackTrace(failure, StackTrace.current);
    return restoredIds;
  }

  @override
  Future<String?> managementUrl() async {
    calls.add('managementUrl');
    if (managementFailure case final failure?) Error.throwWithStackTrace(failure, StackTrace.current);
    return management;
  }

  /// What a call of [invalidateCustomerInfoCache] throws while it is set.
  Object? invalidateFailure;

  @override
  Future<void> invalidateCustomerInfoCache() async {
    calls.add('invalidateCustomerInfoCache');
    if (invalidateFailure case final failure?) Error.throwWithStackTrace(failure, StackTrace.current);
  }

  /// Reports [activeIds] to each listener, as RevenueCat does after a renewal or an expiry.
  void report(Iterable<String> activeIds) {
    for (final listener in listeners) {
      listener(activeIds);
    }
  }
}

void main() {
  late FakeIdentity identity;
  late _FakeStore store;
  late RevenueCatEntitlements entitlements;

  setUp(() {
    identity = FakeIdentity(userId: 'user-1');
    store = _FakeStore();
    entitlements = RevenueCatEntitlements(identity: identity, apiKey: 'test_key', store: store);
  });

  group('RevenueCatEntitlements', () {
    test('gives Free without a user ID and does not reach RevenueCat, then configures it once the ID exists', () async {
      identity.userId = null;
      store.activeIds = ['basic'];

      expect(await entitlements.currentPlan(), Plan.free);
      expect(store.calls, isEmpty);

      identity.userId = 'user-1';

      expect(await entitlements.currentPlan(), Plan.basic);
      expect(store.calls, ['isConfigured', 'configure test_key user-1', 'addListener', 'activeEntitlementIds']);
    });

    test('gives the last plan that it knew without a user ID', () async {
      store.activeIds = ['pro'];
      await entitlements.currentPlan();
      identity.userId = null;

      expect(await entitlements.currentPlan(), Plan.pro);
    });

    for (final (ids, plan) in <(List<String>, Plan)>[
      (['basic', 'pro'], Plan.pro),
      (['pro'], Plan.pro),
      (['basic'], Plan.basic),
      ([], Plan.free),
      (['team'], Plan.free),
    ]) {
      test('gives $plan for the active entitlements $ids', () async {
        store.activeIds = ids;

        expect(await entitlements.currentPlan(), plan);
      });
    }

    test('configures RevenueCat once and only reads the entitlements at a later call', () async {
      await entitlements.currentPlan();
      store.calls.clear();

      await entitlements.currentPlan();

      expect(store.calls, ['activeEntitlementIds']);
    });

    test('configures RevenueCat once for two calls at one time', () async {
      store
        ..activeIds = ['pro']
        ..configureGate = Completer<void>();

      final first = entitlements.currentPlan();
      final second = entitlements.currentPlan();
      await pumpEventQueue();
      store.configureGate!.complete();

      expect(await Future.wait([first, second]), [Plan.pro, Plan.pro]);
      expect(identity.calls, 1);
      expect(store.calls.where((call) => call.startsWith('configure')), hasLength(1));
    });

    test('moves RevenueCat to the user ID when it was configured for another', () async {
      store.configured = true;

      await entitlements.currentPlan();

      expect(store.calls, ['isConfigured', 'logIn user-1', 'addListener', 'activeEntitlementIds']);
    });

    test('moves RevenueCat to a new user ID, and adds its listener only once', () async {
      await entitlements.currentPlan();
      store.calls.clear();
      identity.userId = 'user-2';

      await entitlements.currentPlan();

      expect(store.calls, ['isConfigured', 'logIn user-2', 'activeEntitlementIds']);
      expect(store.listeners, hasLength(1));
    });

    test('gives Free, not the plan of the user ID before, when the move to a new user ID fails', () async {
      store.activeIds = ['pro'];
      expect(await entitlements.currentPlan(), Plan.pro);
      identity.userId = 'user-2';
      store.logInFailure = Exception('offline');

      expect(await entitlements.currentPlan(), Plan.free);

      store
        ..logInFailure = null
        ..calls.clear();

      expect(await entitlements.currentPlan(), Plan.pro);
      expect(store.calls, ['isConfigured', 'logIn user-2', 'activeEntitlementIds']);
    });

    test('ignores a report of RevenueCat while the move to a new user ID has not worked', () async {
      store.activeIds = ['basic'];
      expect(await entitlements.currentPlan(), Plan.basic);
      final changes = <Plan>[];
      final subscription = entitlements.planChanges.listen(changes.add);
      addTearDown(subscription.cancel);
      identity.userId = 'user-2';
      store.logInFailure = Exception('offline');
      expect(await entitlements.currentPlan(), Plan.free);

      store.report(['pro']);
      await pumpEventQueue();

      expect(await entitlements.currentPlan(), Plan.free);
      expect(changes, isEmpty);
    });

    test('gives Free, not the plan of the user ID before, when the read after a new user ID fails', () async {
      store.activeIds = ['pro'];
      expect(await entitlements.currentPlan(), Plan.pro);
      identity.userId = 'user-2';
      store.readFailure = Exception('offline');

      expect(await entitlements.currentPlan(), Plan.free);
      expect(store.calls, contains('logIn user-2'));
    });

    for (final (kind, failure) in <(String, Object)>[
      ('an exception', Exception('offline')),
      ('an error', StateError('no plugin')),
    ]) {
      test('gives the last plan that it knew, not Free, when the read throws $kind', () async {
        store.activeIds = ['pro'];
        expect(await entitlements.currentPlan(), Plan.pro);

        store.readFailure = failure;

        expect(await entitlements.currentPlan(), Plan.pro);
      });

      test('gives the last plan that it knew when the identity throws $kind', () async {
        store.activeIds = ['basic'];
        await entitlements.currentPlan();
        identity.failure = failure;

        expect(await entitlements.currentPlan(), Plan.basic);
      });
    }

    test('gives Free when the configuration fails before any answer, and configures again at the next call', () async {
      store
        ..activeIds = ['pro']
        ..configureFailure = Exception('offline');

      expect(await entitlements.currentPlan(), Plan.free);
      expect(store.listeners, isEmpty);

      store.configureFailure = null;

      expect(await entitlements.currentPlan(), Plan.pro);
      expect(store.calls.where((call) => call.startsWith('configure')), hasLength(2));
      expect(store.listeners, hasLength(1));
    });

    test('reports each plan that RevenueCat reports, only when it differs from the last one', () async {
      store.activeIds = ['basic'];
      await entitlements.currentPlan();
      final changes = <Plan>[];
      final subscription = entitlements.planChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      store
        ..report(['basic'])
        ..report(['basic', 'pro'])
        ..report(['pro'])
        ..report([]);
      await pumpEventQueue();

      expect(changes, [Plan.pro, Plan.free]);
    });

    test('gives the plan of the last report when RevenueCat then fails', () async {
      await entitlements.currentPlan();
      store
        ..report(['pro'])
        ..readFailure = Exception('offline');

      expect(await entitlements.currentPlan(), Plan.pro);
    });

    test('adds no listener before the first configuration', () async {
      identity.userId = null;

      await entitlements.currentPlan();

      expect(store.listeners, isEmpty);
    });
  });

  group('RevenueCatEntitlements, selling', () {
    const basicMonthly = PlanOffer(id: 'basic_monthly', plan: Plan.basic, period: BillingPeriod.monthly, price: 'p1');

    /// A platform error of the plugin with [code] as its code, as `PurchasesErrorHelper.getErrorCode` reads it.
    PlatformException platformError(PurchasesErrorCode code) => PlatformException(code: '${code.index}');

    test('sells plans', () {
      expect(entitlements.sellsPlans, isTrue);
    });

    test('gives the four known packages in the order of the plans, and ignores an unknown one', () async {
      store.packages = [
        (id: 'pro_annual', price: 'p4', productId: 'pro.annual'),
        (id: 'lifetime', price: 'p5', productId: 'lifetime'),
        (id: 'basic_annual', price: 'p2', productId: 'basic.annual'),
        (id: 'pro_monthly', price: 'p3', productId: 'pro.monthly'),
        (id: 'basic_monthly', price: 'p1', productId: 'basic.monthly'),
      ];

      expect(await entitlements.offers(), const [
        PlanOffer(id: 'basic_monthly', plan: Plan.basic, period: BillingPeriod.monthly, price: 'p1'),
        PlanOffer(id: 'basic_annual', plan: Plan.basic, period: BillingPeriod.annual, price: 'p2'),
        PlanOffer(id: 'pro_monthly', plan: Plan.pro, period: BillingPeriod.monthly, price: 'p3'),
        PlanOffer(id: 'pro_annual', plan: Plan.pro, period: BillingPeriod.annual, price: 'p4'),
      ]);
      expect(store.calls, [
        'isConfigured',
        'configure test_key user-1',
        'addListener',
        'currentOfferingPackages',
        'activeProductIds',
      ]);
    });

    test('marks the offer whose product grants the active entitlement', () async {
      store
        ..packages = [
          (id: 'basic_monthly', price: 'p1', productId: 'basic:monthly'),
          (id: 'basic_annual', price: 'p2', productId: 'basic:annual'),
        ]
        ..activeProducts = ['basic', 'basic:annual'];

      expect((await entitlements.offers()).map((offer) => (offer.id, offer.isActive)), [
        ('basic_monthly', false),
        ('basic_annual', true),
      ]);
    });

    test('gives no offers without a user ID, and does not reach RevenueCat', () async {
      identity.userId = null;
      store.packages = [(id: 'basic_monthly', price: 'p1', productId: 'basic.monthly')];

      expect(await entitlements.offers(), isEmpty);
      expect(store.calls, isEmpty);
    });

    for (final (kind, failure) in <(String, Object)>[
      ('an exception', PlatformException(code: '10')),
      ('an error', StateError('no plugin')),
    ]) {
      test('gives no offers when the read throws $kind', () async {
        store.offersFailure = failure;

        expect(await entitlements.offers(), isEmpty);
      });

      test('gives the offers, none of them active, when the read of the products in use throws $kind', () async {
        store
          ..packages = [(id: 'basic_monthly', price: 'p1', productId: 'basic.monthly')]
          ..activeProducts = ['basic.monthly']
          ..activeProductsFailure = failure;

        expect(await entitlements.offers(), [basicMonthly]);
      });
    }

    test('configures RevenueCat once for a read of the plan and of the offers at one time', () async {
      store.configureGate = Completer<void>();

      final plan = entitlements.currentPlan();
      final offers = entitlements.offers();
      await pumpEventQueue();
      store.configureGate!.complete();
      await Future.wait([plan, offers]);

      expect(identity.calls, 1);
      expect(store.calls.where((call) => call.startsWith('configure')), hasLength(1));
    });

    test('buys the package of the offer, and reports the plan that the store then grants', () async {
      store.purchasedIds = ['basic'];
      final changes = <Plan>[];
      final subscription = entitlements.planChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      expect(await entitlements.purchase(basicMonthly), PurchaseOutcome.purchased);
      await pumpEventQueue();

      expect(store.calls, contains('purchasePackage basic_monthly'));
      expect(changes, [Plan.basic]);
      // The plan that the purchase granted is the last plan that the adapter knows.
      store.readFailure = Exception('offline');
      expect(await entitlements.currentPlan(), Plan.basic);
    });

    test('reports no change after a purchase that grants the plan that it knew', () async {
      store
        ..activeIds = ['basic']
        ..purchasedIds = ['basic'];
      await entitlements.currentPlan();
      final changes = <Plan>[];
      final subscription = entitlements.planChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      expect(await entitlements.purchase(basicMonthly), PurchaseOutcome.purchased);
      await pumpEventQueue();

      expect(changes, isEmpty);
    });

    for (final (code, outcome) in <(PurchasesErrorCode, PurchaseOutcome)>[
      (PurchasesErrorCode.purchaseCancelledError, PurchaseOutcome.cancelled),
      (PurchasesErrorCode.paymentPendingError, PurchaseOutcome.pending),
      (PurchasesErrorCode.storeProblemError, PurchaseOutcome.failed),
      (PurchasesErrorCode.networkError, PurchaseOutcome.failed),
      (PurchasesErrorCode.productAlreadyPurchasedError, PurchaseOutcome.failed),
    ]) {
      test('gives $outcome for the error code $code, and keeps the plan', () async {
        store.purchaseFailure = platformError(code);
        final changes = <Plan>[];
        final subscription = entitlements.planChanges.listen(changes.add);
        addTearDown(subscription.cancel);

        expect(await entitlements.purchase(basicMonthly), outcome);
        await pumpEventQueue();

        expect(changes, isEmpty);
        expect(await entitlements.currentPlan(), Plan.free);
      });
    }

    for (final (kind, failure) in <(String, Object)>[
      ('a platform error whose code is no number', PlatformException(code: 'channel-error')),
      ('another exception', Exception('offline')),
      ('an error', StateError('The current offering has no package basic_monthly.')),
    ]) {
      test('gives failed for $kind', () async {
        store.purchaseFailure = failure;

        expect(await entitlements.purchase(basicMonthly), PurchaseOutcome.failed);
      });
    }

    test('gives failed for a purchase without a user ID, and does not reach RevenueCat', () async {
      identity.userId = null;

      expect(await entitlements.purchase(basicMonthly), PurchaseOutcome.failed);
      expect(store.calls, isEmpty);
    });

    test('restores a paid plan and reports it', () async {
      store.restoredIds = ['basic', 'pro'];
      final changes = <Plan>[];
      final subscription = entitlements.planChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      expect(await entitlements.restore(), RestoreOutcome.restored);
      await pumpEventQueue();

      expect(store.calls, contains('restore'));
      expect(changes, [Plan.pro]);
    });

    test('gives nothingFound for a restore without an active entitlement, and reports the Free plan', () async {
      store
        ..activeIds = ['basic']
        ..restoredIds = [];
      await entitlements.currentPlan();
      final changes = <Plan>[];
      final subscription = entitlements.planChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      expect(await entitlements.restore(), RestoreOutcome.nothingFound);
      await pumpEventQueue();

      expect(changes, [Plan.free]);
    });

    for (final (kind, failure) in <(String, Object)>[
      ('an exception', PlatformException(code: '10')),
      ('an error', StateError('no plugin')),
    ]) {
      test('gives failed when the restore throws $kind', () async {
        store.restoreFailure = failure;

        expect(await entitlements.restore(), RestoreOutcome.failed);
      });
    }

    test('gives failed for a restore without a user ID, and does not reach RevenueCat', () async {
      identity.userId = null;

      expect(await entitlements.restore(), RestoreOutcome.failed);
      expect(store.calls, isEmpty);
    });

    test('gives the management page that RevenueCat knows', () async {
      store.management = 'https://apps.apple.com/account/subscriptions';

      expect(await entitlements.managementUrl(), Uri.parse('https://apps.apple.com/account/subscriptions'));
    });

    test('gives no management page when RevenueCat knows none or gives no URL', () async {
      expect(await entitlements.managementUrl(), isNull);

      store.management = 'http://[';

      expect(await entitlements.managementUrl(), isNull);
    });

    test('gives no management page without a user ID or when the read throws', () async {
      identity.userId = null;
      store.management = 'https://apps.apple.com/account/subscriptions';

      expect(await entitlements.managementUrl(), isNull);
      expect(store.calls, isEmpty);

      identity.userId = 'user-1';
      store.managementFailure = Exception('offline');

      expect(await entitlements.managementUrl(), isNull);
    });

    test('makes RevenueCat forget the customer information that it keeps', () async {
      await entitlements.currentPlan();
      store.calls.clear();

      await entitlements.invalidate();

      expect(store.calls, ['invalidateCustomerInfoCache']);
    });

    test('does not reach RevenueCat at an invalidation before it is configured for the user ID', () async {
      await entitlements.invalidate();
      identity.userId = null;
      await entitlements.currentPlan();
      await entitlements.invalidate();

      expect(store.calls, isEmpty);
    });

    for (final (kind, failure) in <(String, Object)>[
      ('an exception', Exception('offline')),
      ('an error', StateError('no plugin')),
    ]) {
      test('answers without throwing when the invalidation throws $kind', () async {
        await entitlements.currentPlan();
        store.invalidateFailure = failure;

        await expectLater(entitlements.invalidate(), completes);
        expect(store.calls.last, 'invalidateCustomerInfoCache');
      });
    }
  });

  group('revenueCatEntitlementsFor', () {
    test('gives the adapter with the key of iOS on iOS and the key of Android on Android', () {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        expect(
          revenueCatEntitlementsFor(identity: identity, platform: platform, iosKey: 'appl_key', androidKey: 'goog_key'),
          isA<RevenueCatEntitlements>(),
        );
      }
    });

    // The keys that a test does not give are empty, because the test runner gets no `--dart-define`.
    test('gives null when the key of the platform is empty, also when the other key is set', () {
      expect(
        revenueCatEntitlementsFor(identity: identity, platform: TargetPlatform.iOS, androidKey: 'goog_key'),
        isNull,
      );
      expect(
        revenueCatEntitlementsFor(identity: identity, platform: TargetPlatform.android, iosKey: 'appl_key'),
        isNull,
      );
    });

    test('gives null on a platform other than iOS and Android, also with keys', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          revenueCatEntitlementsFor(identity: identity, platform: platform, iosKey: 'appl_key', androidKey: 'goog_key'),
          isNull,
        );
      }
    });

    test('reads empty keys from a build without the keys file', () {
      // The test runner gets no `--dart-define`, as a build without `config/revenuecat.json` would not.
      expect(revenueCatEntitlementsFor(identity: identity, platform: TargetPlatform.iOS), isNull);
      expect(revenueCatEntitlementsFor(identity: identity, platform: TargetPlatform.android), isNull);
    });
  });
}
