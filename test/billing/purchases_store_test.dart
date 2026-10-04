import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/billing/billing.dart';

const _channel = MethodChannel('purchases_flutter');

/// An entitlement as the native side of `purchases_flutter` 10.14.0 sends it, with the keys that
/// `EntitlementInfo.fromJson` reads without a null check.
Map<String, Object?> _entitlement(String id) => {
  'identifier': id,
  'isActive': true,
  'willRenew': true,
  'latestPurchaseDate': '2026-10-05T00:00:00Z',
  'originalPurchaseDate': '2026-10-05T00:00:00Z',
  'productIdentifier': '$id.product',
  'isSandbox': true,
};

/// Customer information as the native side sends it, with the keys that `CustomerInfo.fromJson` reads without a
/// null check, and [activeIds] as the active entitlements.
Map<String, Object?> _customerInfo(List<String> activeIds) => {
  'entitlements': {
    'all': {for (final id in activeIds) id: _entitlement(id)},
    'active': {for (final id in activeIds) id: _entitlement(id)},
    'verification': 'NOT_REQUESTED',
  },
  'allPurchaseDates': <String, Object?>{},
  'activeSubscriptions': <String>[],
  'allPurchasedProductIdentifiers': <String>[],
  'nonSubscriptionTransactions': <Object?>[],
  'firstSeen': '2026-10-05T00:00:00Z',
  'originalAppUserId': 'user-1',
  'allExpirationDates': <String, Object?>{},
  'requestDate': '2026-10-05T00:00:00Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'isConfigured' => true,
        'setupPurchases' => null,
        'logIn' => {'customerInfo': _customerInfo([]), 'created': false},
        'getCustomerInfo' => _customerInfo(['basic', 'pro']),
        _ => throw MissingPluginException(call.method),
      };
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  group('PurchasesStore', () {
    const store = PurchasesStore();

    test('asks the plugin whether RevenueCat is configured', () async {
      expect(await store.isConfigured(), isTrue);
      expect(calls.single.method, 'isConfigured');
    });

    test('configures RevenueCat with the key and the app user ID', () async {
      await store.configure(apiKey: 'appl_key', appUserId: 'user-1');

      expect(calls.single.method, 'setupPurchases');
      expect(calls.single.arguments, containsPair('apiKey', 'appl_key'));
      expect(calls.single.arguments, containsPair('appUserId', 'user-1'));
    });

    test('moves RevenueCat to the app user ID', () async {
      await store.logIn('user-2');

      expect(calls.single.method, 'logIn');
      expect(calls.single.arguments, {'appUserID': 'user-2'});
    });

    test('reads the identifiers of the active entitlements', () async {
      expect(await store.activeEntitlementIds(), unorderedEquals(['basic', 'pro']));
      expect(calls.single.method, 'getCustomerInfo');
    });

    test('calls the listener with the active entitlements of each update of the customer information', () async {
      final reports = <List<String>>[];
      store.addListener((activeIds) => reports.add(activeIds.toList()));
      // The plugin sets its handler of native calls at its first call to the native side.
      await store.isConfigured();

      await messenger.handlePlatformMessage(
        _channel.name,
        _channel.codec.encodeMethodCall(MethodCall('Purchases-CustomerInfoUpdated', _customerInfo(['basic']))),
        (_) {},
      );

      expect(reports, [
        ['basic'],
      ]);
    });
  });
}
