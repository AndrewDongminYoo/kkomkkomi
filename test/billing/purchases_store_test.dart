// 🐦 Flutter imports:
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/billing/billing.dart';

const _channel = MethodChannel('purchases_flutter');

/// An entitlement as the native side of `purchases_flutter` 10.14.0 sends it, with the keys that
/// `EntitlementInfo.fromJson` reads without a null check.
/// [basePlan] is the base plan identifier that the native side sends for a Google Play product.
Map<String, Object?> _entitlement(String id, {String? basePlan}) => {
  'identifier': id,
  'isActive': true,
  'willRenew': true,
  'latestPurchaseDate': '2026-10-05T00:00:00Z',
  'originalPurchaseDate': '2026-10-05T00:00:00Z',
  'productIdentifier': '$id.product',
  'isSandbox': true,
  'productPlanIdentifier': ?basePlan,
};

/// Customer information as the native side sends it, with the keys that `CustomerInfo.fromJson` reads without a
/// null check, [activeIds] as the active entitlements, and [managementUrl] as the management page.
Map<String, Object?> _customerInfo(List<String> activeIds, {String? managementUrl, String? basePlan}) => {
  'entitlements': {
    'all': {for (final id in activeIds) id: _entitlement(id, basePlan: basePlan)},
    'active': {for (final id in activeIds) id: _entitlement(id, basePlan: basePlan)},
    'verification': 'NOT_REQUESTED',
  },
  'managementURL': ?managementUrl,
  'allPurchaseDates': <String, Object?>{},
  'activeSubscriptions': <String>[],
  'allPurchasedProductIdentifiers': <String>[],
  'nonSubscriptionTransactions': <Object?>[],
  'firstSeen': '2026-10-05T00:00:00Z',
  'originalAppUserId': 'user-1',
  'allExpirationDates': <String, Object?>{},
  'requestDate': '2026-10-05T00:00:00Z',
};

/// A package as the native side sends it, with the keys that `Package.fromJson` and `StoreProduct.fromJson` read
/// without a null check. The price is no amount, because the repository names none. [productId] replaces the
/// product identifier, as a Google Play product names its subscription and base plan identifiers joined by a colon.
Map<String, Object?> _package(String id, {String? productId}) => {
  'identifier': id,
  'packageType': 'CUSTOM',
  'product': {
    'identifier': productId ?? '$id.product',
    'description': '',
    'title': '',
    'price': 0,
    'priceString': 'price of $id',
    'currencyCode': 'XXX',
  },
  'presentedOfferingContext': {'offeringIdentifier': 'default'},
};

/// The offerings as the native side sends them, with [packageIds] in the current offering, or no current offering,
/// and the product identifier of a package from [productIds] when it holds one.
Map<String, Object?> _offerings(List<String>? packageIds, Map<String, String> productIds) {
  final offering = {
    'identifier': 'default',
    'serverDescription': '',
    'metadata': <String, Object?>{},
    'availablePackages': [
      for (final id in packageIds ?? const <String>[]) _package(id, productId: productIds[id]),
    ],
  };
  return {
    'all': {'default': offering},
    'current': packageIds == null ? null : offering,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  /// The package identifiers of the current offering, or null for no current offering.
  late List<String>? currentPackages;

  /// The product identifiers of the packages that do not use the default one.
  late Map<String, String> packageProducts;

  /// The customer information that a read gives.
  late Map<String, Object?> customerInfo;

  /// What a purchase throws while it is set.
  late PlatformException? purchaseFailure;

  /// What a read of the customer information throws while it is set.
  late PlatformException? customerInfoFailure;

  setUp(() {
    calls = [];
    currentPackages = ['basic_monthly', 'pro_annual'];
    packageProducts = {};
    customerInfo = _customerInfo(['basic', 'pro']);
    purchaseFailure = null;
    customerInfoFailure = null;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'isConfigured' => true,
        'setupPurchases' => null,
        'logIn' => {'customerInfo': _customerInfo([]), 'created': false},
        'getCustomerInfo' when customerInfoFailure != null => throw customerInfoFailure!,
        'getCustomerInfo' => customerInfo,
        'getOfferings' => _offerings(currentPackages, packageProducts),
        'purchasePackage' when purchaseFailure != null => throw purchaseFailure!,
        'purchasePackage' => {
          'customerInfo': _customerInfo(['basic']),
          'transaction': {'productIdentifier': 'basic_monthly.product', 'purchaseDate': '2026-10-05T00:00:00Z'},
        },
        'restorePurchases' => _customerInfo(['pro']),
        'invalidateCustomerInfoCache' => null,
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

    test('reads the packages of the current offering with the price text and the product of the store', () async {
      expect(await store.currentOfferingPackages(), [
        (id: 'basic_monthly', price: 'price of basic_monthly', productId: 'basic_monthly.product'),
        (id: 'pro_annual', price: 'price of pro_annual', productId: 'pro_annual.product'),
      ]);
      expect(calls.single.method, 'getOfferings');
    });

    test('reads no packages without a current offering', () async {
      currentPackages = null;

      expect(await store.currentOfferingPackages(), isEmpty);
    });

    test('reads the products of the active entitlements, with the base plan of a Google Play product', () async {
      expect(await store.activeProductIds(), unorderedEquals(['basic.product', 'pro.product']));

      customerInfo = _customerInfo(['basic'], basePlan: 'monthly');

      expect(await store.activeProductIds(), ['basic.product', 'basic.product:monthly']);
    });

    test('buys the package of the current offering, and gives the active entitlements after the purchase', () async {
      expect(await store.purchasePackage('pro_annual'), ['basic']);

      expect(calls.map((call) => call.method), ['getOfferings', 'getCustomerInfo', 'purchasePackage']);
      final arguments = calls.last.arguments as Map<Object?, Object?>;
      expect(arguments['packageIdentifier'], 'pro_annual');
      expect(arguments['presentedOfferingContext'], containsPair('offeringIdentifier', 'default'));
      // No Google Play subscription is in use, so the purchase replaces none.
      expect(arguments['googleOldProductIdentifier'], isNull);
      expect(arguments['storeReplacementMode'], isNull);
    });

    test(
      'replaces the Google Play subscription in use with the other subscription, by its subscription identifier, and '
      'credits its unused time',
      () async {
        customerInfo = _customerInfo(['basic'], basePlan: 'monthly');
        packageProducts = {'pro_annual': 'pro.product:annual'};

        await store.purchasePackage('pro_annual');

        final arguments = calls.last.arguments as Map<Object?, Object?>;
        expect(calls.last.method, 'purchasePackage');
        expect(arguments['googleOldProductIdentifier'], 'basic.product');
        expect(arguments['storeReplacementMode'], 'WITH_TIME_PRORATION');
      },
    );

    test(
      'changes the base plan inside the Google Play subscription in use at the full price, the one mode of time '
      'credit that Google Play takes for that change',
      () async {
        customerInfo = _customerInfo(['basic'], basePlan: 'monthly');
        currentPackages = ['basic_monthly', 'basic_annual'];
        packageProducts = {'basic_monthly': 'basic.product:monthly', 'basic_annual': 'basic.product:annual'};

        await store.purchasePackage('basic_annual');

        final arguments = calls.last.arguments as Map<Object?, Object?>;
        expect(calls.last.method, 'purchasePackage');
        expect(arguments['packageIdentifier'], 'basic_annual');
        expect(arguments['googleOldProductIdentifier'], 'basic.product');
        expect(arguments['storeReplacementMode'], 'CHARGE_FULL_PRICE');
      },
    );

    test('starts no purchase when the subscription in use cannot be read', () async {
      customerInfoFailure = PlatformException(code: '10');

      await expectLater(store.purchasePackage('pro_annual'), throwsA(isA<PlatformException>()));
      expect(calls.map((call) => call.method), isNot(contains('purchasePackage')));
    });

    test('fails without a purchase for a package that the current offering does not hold', () async {
      await expectLater(store.purchasePackage('team_monthly'), throwsStateError);

      currentPackages = null;

      await expectLater(store.purchasePackage('basic_monthly'), throwsStateError);
      expect(calls.map((call) => call.method), isNot(contains('purchasePackage')));
    });

    test('fails with the platform error of the plugin when the purchase does not complete', () async {
      purchaseFailure = PlatformException(code: '1');

      await expectLater(
        store.purchasePackage('basic_monthly'),
        throwsA(isA<PlatformException>().having((error) => error.code, 'code', '1')),
      );
    });

    test('restores the purchases and gives the active entitlements after the restore', () async {
      expect(await store.restore(), ['pro']);
      expect(calls.single.method, 'restorePurchases');
    });

    test('reads the management page of the customer, or none', () async {
      expect(await store.managementUrl(), isNull);

      customerInfo = _customerInfo([], managementUrl: 'https://apps.apple.com/account/subscriptions');

      expect(await store.managementUrl(), 'https://apps.apple.com/account/subscriptions');
      expect(calls.map((call) => call.method), ['getCustomerInfo', 'getCustomerInfo']);
    });

    test('makes RevenueCat forget the customer information that it keeps', () async {
      await store.invalidateCustomerInfoCache();

      expect(calls.single.method, 'invalidateCustomerInfoCache');
    });
  });
}
