# M3-02: the Entitlements port and the RevenueCat adapter

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app knows the plan of the company (Free, Basic, or Pro) from RevenueCat in the production flavor, and from a Free-only adapter in every other case, without any screen yet.

**Architecture:** A domain enum `Plan`, an application port `Entitlements`, and a new unit `lib/billing/` that is the one directory allowed to import `purchases_flutter`. The production entry point reads the RevenueCat public SDK keys from `--dart-define` values and falls back to the Free-only adapter when a key is empty. `bootstrap()` takes the adapter of the flavor and `App` provides it.

**Tech Stack:** Flutter, `purchases_flutter` 10.14.0 (Play Billing Library 8.3.0, iOS 13 and later through Swift Package Manager, Android `minSdkVersion` 21), `bloc`'s `RepositoryProvider`, `mocktail`.

**Spec:** [`docs/specs/2026-10-04-m3-subscriptions-design.md`](../specs/2026-10-04-m3-subscriptions-design.md), sections "Products", "Device rules", "Units", and "Accounts and restore". The split is [`2026-10-05-m3-subscriptions.md`](2026-10-05-m3-subscriptions.md). Refs #36.

## Global Constraints

- RevenueCat entitlement identifiers: `basic` and `pro`. A Pro product grants both. Any other identifier is ignored.
- The RevenueCat app user ID is the Firebase user ID from `Identity.currentUserId()`. The adapter never configures RevenueCat with another ID and never makes a purchase before it has that ID.
- The public SDK keys are never tracked (operator, 2026-10-05). `config/revenuecat.json` holds them, git ignores it, and the production build reads it with `--dart-define-from-file`. A tracked `config/revenuecat.example.json` shows its two keys with empty values.
- An empty key, a platform other than iOS and Android, and the development and staging flavors all use the Free-only adapter.
- `lib/billing/` is the one directory under `lib/` that may import `purchases_flutter`, and `lib/main_production.dart` is the one file outside it that may import it, as `test/firebase/boundary_test.dart` enforces for FlutterFire.
- Coverage of `lib` stays at 100%, and `merry run check` passes.
- This pull request adds no screen, no purchase, no restore, and no client limit. PR 4 adds them to the port together with their screens.
- Nothing in this pull request calls `currentPlan()` or `planChanges`, `bootstrap()` included, so no build of this pull request configures RevenueCat or sends anything to it. PR 3 is the first caller, and it updates the privacy pages and the store answers for RevenueCat as a processor in the same pull request.
- Read each key with `const String.fromEnvironment(...)`. The Dart documentation guarantees the constructor only when it is invoked as `const`, and an empty key builds a Free-only app without an error, so a non-const read would fail silently.
- Name no price, billing term, or fee: the repository is public.

## Review Focus

1. No user ID yet (offline first launch): `currentPlan()` answers `Plan.free` without configuring RevenueCat, and a later call configures it once the ID exists.
2. RevenueCat fails or the device is offline after a paid answer: `currentPlan()` answers the last plan it knew, not Free, and never throws.
3. Two calls at one time: RevenueCat is configured once.
4. Active entitlements `["basic", "pro"]`, `["pro"]`, `["basic"]`, `[]`, `["team"]`: Pro, Pro, Basic, Free, Free.
5. A release build without `config/revenuecat.json`: the release check stops and names the file, so a build never silently lacks the keys by accident, while a file with empty keys builds a Free-only app on purpose.

---

### Task 1: `Plan` and the `Entitlements` port

**Files:**

- Create: `lib/domain/plan.dart`, export it from `lib/domain/domain.dart`
- Create: `lib/application/entitlements.dart`, export it from `lib/application/application.dart`
- Test: `test/domain/plan_test.dart`

**Interfaces:**

- Produces:

```dart
/// The plan of a company, from the entitlements that the store confirmed.
enum Plan {
  free,
  basic,
  pro;

  /// The plan that the active entitlement identifiers grant. `pro` wins over `basic`, and other identifiers grant
  /// nothing.
  static Plan fromEntitlements(Iterable<String> activeIds) => ...;

  /// Whether the plan is one that the company pays for.
  bool get isPaid => this != Plan.free;
}

/// Tells which plan the company has, so that tests never reach a store.
abstract interface class Entitlements {
  /// The plan that the store last confirmed. Without an answer of the store it is the last plan that this object
  /// knew, and [Plan.free] before any answer. The call does not throw.
  Future<Plan> currentPlan();

  /// Each plan that the store reports after the first answer, for example after a renewal or an expiry.
  Stream<Plan> get planChanges;
}
```

- [ ] **Step 1:** Write `test/domain/plan_test.dart` with the five cases of Review Focus 4 and `isPaid` for each value. Run `flutter test test/domain/plan_test.dart` and see it fail.
- [ ] **Step 2:** Implement `Plan`. `test/domain/boundary_test.dart` must still pass.
- [ ] **Step 3:** Add the port. Run the test and `flutter analyze`.
- [ ] **Step 4:** Commit `feat(domain): add the plan of a company and the entitlements port`.

### Task 2: The Free-only adapter and the wiring

**Files:**

- Create: `lib/presentation/adapters/free_entitlements.dart` (exported like `unavailable_identity.dart`)
- Modify: `lib/bootstrap.dart` (a `required Entitlements entitlements` argument, passed to the builder; `bootstrap()` does not call it)
- Modify: `lib/app/view/app.dart` (a required `entitlements` field, provided through `RepositoryProvider<Entitlements>`)
- Modify: `lib/main_development.dart`, `lib/main_staging.dart` (give `const FreeEntitlements()`)
- Modify: `test/helpers/pump_app.dart`, `test/helpers/fakes.dart` (a `FakeEntitlements` whose plan a test sets and whose `planChanges` a test drives)
- Test: `test/presentation/adapters/free_entitlements_test.dart`, `test/bootstrap_test.dart`, `test/app/view/app_test.dart`

**Interfaces:**

- Consumes: `Plan`, `Entitlements` (Task 1).
- Produces: `final class FreeEntitlements implements Entitlements` with `const new();`, `currentPlan()` → `Plan.free`, and `planChanges` → an empty stream. The builder of `bootstrap()` gets `Entitlements entitlements` as a new argument after `identity`. `App` has no default entitlements, because the flavor decides them, as it has no default identity.

- [ ] **Step 1:** Write the adapter test, and extend the bootstrap and App tests: the builder receives the given entitlements, `App` provides them to a descendant, and neither `bootstrap()` nor `App` calls `currentPlan()` (a fake that records calls proves it).
- [ ] **Step 2:** Implement until `merry run check` and `merry run coverage` pass.
- [ ] **Step 3:** Commit `feat(app): provide the entitlements of the flavor`.

### Task 3: The RevenueCat adapter

**Files:**

- Modify: `pubspec.yaml` (`purchases_flutter: ^10.14.0`) and `pubspec.lock` (from `flutter pub get`, in the same commit)
- Create: `lib/billing/billing.dart` (barrel), `lib/billing/revenuecat_entitlements.dart`
- Create: `test/billing/revenuecat_entitlements_test.dart`, `test/billing/boundary_test.dart`

**Interfaces:**

- Consumes: `Identity`, `Entitlements`, `Plan`.
- Produces:

```dart
/// Reads the plan from RevenueCat, with the Firebase user ID as the RevenueCat app user ID.
final class RevenueCatEntitlements implements Entitlements {
  /// [store] replaces the `Purchases` API of `purchases_flutter` in a test.
  new({required Identity identity, required String apiKey, RevenueCatStore store = const PurchasesStore()});
}

/// The calls of `purchases_flutter` that the adapter makes, so that a test needs no platform channel.
abstract interface class RevenueCatStore {
  Future<bool> isConfigured();
  Future<void> configure({required String apiKey, required String appUserId});
  Future<void> logIn(String appUserId);
  Future<Iterable<String>> activeEntitlementIds();
  void addListener(void Function(Iterable<String> activeIds) listener);
}
```

`PurchasesStore` is the one implementation that calls `purchases_flutter` 10.14.0, whose names were read from the package source: the getter `static Future<bool> get isConfigured`, `static Future<void> configure(PurchasesConfiguration)` with the field `appUserID`, `static Future<LogInResult> logIn(String appUserID)`, `static Future<CustomerInfo> getCustomerInfo()` (read `customerInfo.entitlements.active.keys`, `active` is a `Map<String, EntitlementInfo>`), and `static void addCustomerInfoUpdateListener(...)`.
The plugin talks to its native side through `MethodChannel('purchases_flutter')`, so `test/billing/purchases_store_test.dart` covers `PurchasesStore` with `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler` on that channel. Read the method names that the plugin invokes from its source in the pub cache before writing the fake answers.

A tested function in `lib/billing/` picks the adapter, so that `lib/main_production.dart` stays one call:

```dart
/// The RevenueCat adapter for [platform], or null when the platform is not iOS or Android or its key is empty.
Entitlements? revenueCatEntitlementsFor({
  required Identity identity,
  required TargetPlatform platform,
  String iosKey = const String.fromEnvironment('REVENUECAT_IOS_API_KEY'),
  String androidKey = const String.fromEnvironment('REVENUECAT_ANDROID_API_KEY'),
});
```

Behavior:

- `currentPlan()` asks `identity.currentUserId()`. Null gives the last known plan (Free at first) and configures nothing.
- With an ID, it configures RevenueCat once (calls at one time share one attempt, as in `FirebaseIdentity`), or calls `logIn` when RevenueCat was configured for another ID, then reads the active entitlement IDs.
- Any failure is logged with `dart:developer` `log` and gives the last known plan.
- `planChanges` is a broadcast stream fed by the listener, which the adapter adds once, after the first configure. It emits only when the plan differs from the last one.

- [ ] **Step 1:** Write `test/billing/revenuecat_entitlements_test.dart` for every case of Review Focus 1–4 and for the `logIn` case, with a fake `RevenueCatStore` and `FakeIdentity`. See it fail.
- [ ] **Step 2:** Add the dependency with `flutter pub add purchases_flutter:^10.14.0`, implement, and pass the tests.
- [ ] **Step 2a:** The repository tracks `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Regenerate them with `flutter build ios --config-only --flavor development --target lib/main_development.dart` and then `xcodebuild -resolvePackageDependencies -workspace ios/Runner.xcworkspace -scheme development`, and commit them with `pubspec.lock`. If the files do not change, say so in the pull request body.
- [ ] **Step 3:** Write `test/billing/boundary_test.dart` in the shape of `test/firebase/boundary_test.dart`: no file under `lib/` outside `lib/billing/` and `lib/main_production.dart` names `package:purchases_flutter` or `package:kkomkkomi/billing/`, and the check finds a planted import in a sample string.
- [ ] **Step 4:** Run `merry run check` and `merry run coverage`. Commit `feat(billing): read the plan from RevenueCat` with `pubspec.yaml` and `pubspec.lock`.

### Task 4: The production entry point and the keys

**Files:**

- Modify: `lib/main_production.dart`
- Create: `config/revenuecat.example.json` with `{"REVENUECAT_IOS_API_KEY": "", "REVENUECAT_ANDROID_API_KEY": ""}`
- Modify: `.gitignore` (ignore `config/revenuecat.json`, keep the example tracked)
- Modify: `merry.yaml` (the production `build apk`, `build aab`, and `build ipa` scripts add `--dart-define-from-file=config/revenuecat.json`)
- Modify: `tool/release_check.dart` and its test (a missing `config/revenuecat.json` is a problem that names the example file; a file with empty values passes, because a Free-only build is allowed)

**Interfaces:**

- `lib/main_production.dart` makes one `FirebaseIdentity`, gives it to `bootstrap()` as `identity`, and gives `entitlements: revenueCatEntitlementsFor(identity: identity, platform: defaultTargetPlatform) ?? const FreeEntitlements()`.

- [ ] **Step 1:** Extend the release check test with the missing-file case, see it fail, implement, and pass.
- [ ] **Step 2:** Edit the entry point, the ignore file, and the scripts. `git check-ignore config/revenuecat.json` succeeds and `git check-ignore config/revenuecat.example.json` fails.
- [ ] **Step 3:** Run `merry run check` and `merry run coverage`. Commit `build(billing): read the RevenueCat keys from an ignored file`.

### Task 5: Records

**Files:**

- Modify: `CLAUDE.md`: "Units" (the `billing/` unit and the `Entitlements` port), "Entry points" (the builder argument and the flavor's adapter), "Release" (the keys file and the release check), and "Current state" (the app reads the plan, and no screen uses it yet).
- Modify: `docs/notes/2026-10-02-first-test-distribution.md`:
  - Before the first Play subscription can be created, Play needs a published build that holds the Play Billing Library ("Once you've set up a developer account, you must publish a version of your app that includes the Google Play Billing Library", https://developer.android.com/google/play/billing/getting-ready, read on 2026-10-05). State as an assumption, not as a fact, that a rollout on the internal testing track counts as publishing.
  - The operator creates `config/revenuecat.json` from the example before a release build.
  - The App Privacy draft: the privacy manifest of `purchases-ios` 5.92.0, which `purchases_flutter` 10.14.0 bundles, declares Purchase History, not linked to the user, not for tracking, for App Functionality (https://raw.githubusercontent.com/RevenueCat/purchases-ios/5.92.0/Sources/PrivacyInfo.xcprivacy, read on 2026-10-05). Add that row as the existing Diagnostics row follows the Firebase manifests (operator decision, 2026-10-02), and add the SDK to the list of manifests in the "Privacy manifest" section.
- Modify: `web/privacy/index.html` and `web/privacy/en/index.html`, section 10, which names the data that the bundled manifests declare: add Purchase History as the RevenueCat manifest declares it, in both languages together, and keep `test/web/privacy.test.mjs` passing. Do not describe RevenueCat as a processor that receives data yet: PR 3 does that when the app first contacts it.
- Modify: `docs/plans/2026-10-05-m3-subscriptions.md`: the privacy pages and the store answers for RevenueCat as a processor move from PR 5 to PR 3, the first pull request that calls `currentPlan()`.

- [ ] **Step 1:** cspell and `trunk check` on the changed Markdown.
- [ ] **Step 2:** Commit `docs: describe the entitlements port and the RevenueCat keys`.

The pull request body lists the Hosting deploy that the merge makes due for the privacy pages, with the operator's approval.
