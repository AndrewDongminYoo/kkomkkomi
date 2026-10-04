import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/billing/billing.dart';
import 'package:kkomkkomi/domain/domain.dart';

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
