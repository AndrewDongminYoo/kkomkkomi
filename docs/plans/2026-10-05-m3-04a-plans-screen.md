# M3-04a: the plans screen, purchase, restore, and the RevenueCat disclosure

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A company sees its plan, buys Basic or Pro monthly or annually, restores a purchase, and reaches the store's subscription management, from a plans screen that the company profile screen opens. The privacy pages and the store answers disclose RevenueCat in the same pull request, because this is the first build that contacts it.

**Architecture:** The `Entitlements` port gets the offers, a purchase, a restore, and the management link. `RevenueCatEntitlements` implements them through `RevenueCatStore`, and `FreeEntitlements` answers that nothing is for sale. A new `ExternalLinks` port opens a URL, with a `url_launcher` adapter. A new screen folder `lib/presentation/plans/` follows the Very Good CLI layout with a Cubit.

**Tech Stack:** Flutter, `purchases_flutter` 10.14.0, `url_launcher`, `bloc`, `mocktail`, `bloc_test`.

**Spec:** [`docs/specs/2026-10-04-m3-subscriptions-design.md`](../specs/2026-10-04-m3-subscriptions-design.md), sections "Products", "Units", "Accounts and restore", and "Deletion and legal requirements". The split is [`2026-10-05-m3-subscriptions.md`](2026-10-05-m3-subscriptions.md), where the operator split PR 4 into 4a (this) and 4b (the client limit and the PDF footer) on 2026-10-05. Refs #36.

## Global Constraints

- The operator decided on 2026-10-05: the terms of use link is Apple's standard EULA, `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/` (answered 200 on 2026-10-05), and the plans screen opens from the company profile screen. PR 4b adds the second entry, at the client limit.
- Apple's subscriptions page (https://developer.apple.com/app-store/subscriptions/, read on 2026-10-05) lists what the purchase screen shows: the subscription name and period, the full renewal price shown clearly and localized, and a way to restore purchases, and it says: "Please note that your app and App Store metadata must include links to your Terms of Use and Privacy Policy." The screen shows each of these, and the price is only the `priceString` that the store gives. No price is written anywhere in the repository.
- Plan contents on the screen: Free: 2 active clients and the footer text. Basic: 5 active clients and no footer. Pro: no client limit and no footer. The screen promises no M2 feature, so it never shows a feature that the app does not have.
- RevenueCat packages are told apart by their package identifiers `basic_monthly`, `basic_annual`, `pro_monthly`, and `pro_annual`, which the operator sets in the RevenueCat dashboard. An unknown identifier is ignored.
- A purchase never grants a plan by itself: the plan comes from `currentPlan()` and `planChanges` after the store answers. A cancelled purchase changes nothing and shows nothing; a pending purchase (for example Ask to Buy) shows that the purchase waits for approval; a failure shows that it did not work.
- Each method of the port answers without throwing, as `currentPlan()` does.
- No release build is made between the merges of 4a and 4b. The plans screen describes the client limits and the footer of each plan, and 4b ships the client limit and the PDF footer, so a build of 4a alone would describe behavior that it does not have (`CLAUDE.md` copy rule; App Store Review Guideline 3.1.2(c) "clearly describe what the user will get"). The split plan, the console note, and the pull request body each say so.
- `url_launcher`: call `launchUrl` directly and treat false or an exception as a failure; never gate on `canLaunchUrl`, which answers false for https on Android 11 and later without a `<queries>` entry in the manifest. Read the README of `url_launcher` in the pub cache to confirm before writing the adapter.
- Heavy jobs on this machine: before `flutter build ios`, `xcodebuild -resolvePackageDependencies`, or any Gradle build, run `uptime` and `pgrep -fl qemu-system`. If another heavy job runs, defer the step and say so in the pull request body. First check whether `url_launcher_ios` is already in the tracked `Package.resolved` files; if adding the dependency changes them, regenerate them as PR 2 did.
- The development and staging flavors and a build without keys show that subscriptions are not available in this build, with no offer and no purchase button.
- This build calls `currentPlan()` from the plans screen, so it is the first that contacts RevenueCat: the privacy pages (Korean and English) and the App Privacy and Data safety drafts in `docs/notes/2026-10-02-first-test-distribution.md` change in this pull request, from RevenueCat's own guidance, quoted with URL and date: Apple (https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy): Purchases (Purchase History) for App Functionality and Analytics, and User ID because the app sets the Firebase user ID as the RevenueCat app user ID; Google Play (https://www.revenuecat.com/docs/platform-resources/google-platform-resources/google-plays-data-safety): Financial info, Purchase history. App Store Connect takes one answer per data type, so the existing "Purchases: Purchase History" row of PR 2 is replaced, not joined by a second row: Collected Yes, Linked Yes (the RevenueCat app user ID is the Firebase user ID, which the "Identifiers: User ID" row already declares as linked; RevenueCat's page says to select 'Yes' when the app user ID "can be tied to ... other contact information via your own server", and the operator decides whether the company name counts, so the pull request body flags this row for review), Tracking No, purposes App Functionality and Analytics (RevenueCat: "All RevenueCat users must select these two options"). Section 10 of the privacy pages states the same answer as that row, not the manifest-only wording of PR 2. The section on transfers abroad adds RevenueCat as a recipient with what the code sends and why; any clause that the code cannot show is marked for the operator's review in the pull request body.
- User-facing Korean text follows the `user-facing-copy` skill (Toss-style 해요체), and every string is an ARB key in both `app_en.arb` and `app_ko.arb`. Screens use `KeepAllText` and pass `tester.useNarrowScreenWithLargestText()` without overflow.
- `url_launcher` is a new direct dependency: `purchases_flutter` 10.14.0 has no call that opens the subscription management page (its `CustomerInfo.managementURL` is a URL), and the terms and privacy links need the same. Only the adapter under `lib/presentation/adapters/` imports it. Commit `pubspec.lock` and any tracked `Package.resolved` change with it.
- Coverage of `lib` stays at 100%, and `merry run check` passes. Name no price, billing term, or fee: the repository is public.

## Review Focus

1. Offers fail to load (offline, no products configured yet): the screen shows the current plan, a retry, restore, and the links, and no purchase button.
2. The user cancels the store sheet: nothing changes and no error shows.
3. A purchase is pending: the screen says it waits for approval and does not show the plan as changed.
4. A restore finds nothing: the screen says that no purchase was found; a restore that finds Pro shows Pro after `planChanges` reports it.
5. Two taps on a purchase button: one store sheet, because the screen takes no touch while a purchase is on its way.
6. The plan and period that the company already has: its button says that it is in use ("이용 중") and buys nothing, so a second purchase of the same product never reaches the store.

---

### Task 1: The port grows offers, purchase, restore, and the management link

**Files:**

- Modify: `lib/application/entitlements.dart`, `lib/domain/plan.dart` (a `BillingPeriod` enum if it belongs with `Plan`)
- Modify: `lib/presentation/adapters/free_entitlements.dart`, `test/helpers/fakes.dart` (`FakeEntitlements` with settable offers and outcomes)
- Test: `test/presentation/adapters/free_entitlements_test.dart`

**Interfaces:**

```dart
enum BillingPeriod { monthly, annual }

/// One product that the store sells, with the price text that the store gives for the device's storefront.
final class PlanOffer {
  const new({required this.id, required this.plan, required this.period, required this.price});
  final String id; // the RevenueCat package identifier
  final Plan plan;
  final BillingPeriod period;
  final String price; // store-localized, never computed by the app
}

enum PurchaseOutcome { purchased, cancelled, pending, failed }
enum RestoreOutcome { restored, nothingFound, failed }

// added to Entitlements:
  /// The offers for sale, in the order Basic monthly, Basic annual, Pro monthly, Pro annual, or empty when the store
  /// does not answer or nothing is for sale. The call does not throw.
  Future<List<PlanOffer>> offers();
  /// Opens the store's purchase sheet for [offer]. The call does not throw.
  Future<PurchaseOutcome> purchase(PlanOffer offer);
  /// Asks the store for the purchases of its account. The call does not throw.
  Future<RestoreOutcome> restore();
  /// The store page where the subscription is managed, or null when none is known. The call does not throw.
  Future<Uri?> managementUrl();
```

`FreeEntitlements`: no offers, `failed`, `failed`, null.

- [ ] **Step 1:** Tests for `FreeEntitlements` and the value types; see them fail; implement; commit `feat(billing): describe offers, purchase, and restore in the entitlements port`.

### Task 2: RevenueCat implements them

**Files:**

- Modify: `lib/billing/revenuecat_entitlements.dart`, `lib/billing/purchases_store.dart`
- Test: `test/billing/revenuecat_entitlements_test.dart`, `test/billing/purchases_store_test.dart`

**Interfaces:**

- `RevenueCatStore` adds `Future<List<({String id, String price})>> currentOfferingPackages()`, `Future<Iterable<String>> purchasePackage(String packageId)` (the active entitlement IDs after the purchase), `Future<Iterable<String>> restore()`, and `Future<String?> managementUrl()`. `PurchasesStore` implements them with `Purchases.getOfferings()` (`offerings.current?.availablePackages`, `package.identifier`, `package.storeProduct.priceString`), `Purchases.purchase(PurchaseParams.package(...))`, `Purchases.restorePurchases()`, and `Purchases.getCustomerInfo()` (`managementURL`). Read each name from the package source in the pub cache before writing it, as the project memory `webfetch-identifier-case` requires for vendor identifiers.
- `PurchasesErrorCode.purchaseCancelledError` gives `cancelled`, `PurchasesErrorCode.paymentPendingError` gives `pending` (both names read on 2026-10-05 from `lib/src/generated/error_codes.dart` of `purchases_flutter` 10.14.0), and every other failure gives `failed`. Read how a `PlatformException` becomes a code (`PurchasesErrorHelper.getErrorCode`) from the package source.
- Every call first makes sure RevenueCat is configured for the current Firebase user ID, as `currentPlan()` does; without a user ID, offers are empty and the others answer `failed` or null.
- After a purchase or a restore, the adapter updates its known plan from the answer and emits on `planChanges` when it changed.

- [ ] **Step 1:** Tests for each mapping, each error code, the no-user-ID case, and the channel calls of `PurchasesStore`; see them fail; implement; `merry run check`; commit `feat(billing): sell, restore, and manage subscriptions through RevenueCat`.

### Task 3: `ExternalLinks`

**Files:**

- Create: `lib/application/external_links.dart` (port: `Future<bool> open(Uri uri)`, never throws), `lib/presentation/adapters/url_launcher_external_links.dart` (`launchUrl` with `LaunchMode.externalApplication`)
- Modify: `pubspec.yaml`, `pubspec.lock`, `lib/app/view/app.dart` (provide it), `test/helpers/pump_app.dart`, `test/helpers/fakes.dart` (`FakeExternalLinks` records the opened URIs)
- Test: the adapter through the `url_launcher` platform interface's test double or its method channel, and the App provider test

- [ ] **Step 1:** Tests, implement, `merry run check`, commit `feat(app): open external links through a port`.

### Task 4: The plans screen

**Files:**

- Create: `lib/presentation/plans/` (`plans.dart`, `cubit/plans_cubit.dart`, `cubit/plans_state.dart`, `view/plans_page.dart`, `view/plans_view.dart`)
- Modify: `lib/presentation/company_profile/view/...` (a "요금제" entry that shows the current plan name and opens `PlansPage.route()`), `lib/l10n/arb/app_en.arb`, `lib/l10n/arb/app_ko.arb`
- Test: `test/presentation/plans/cubit/plans_cubit_test.dart`, `test/presentation/plans/view/plans_view_test.dart`, `test/presentation/plans/view/plans_page_test.dart`, and the company profile tests

**Interfaces:**

- `PlansCubit({required Entitlements entitlements})`: loads the plan and the offers, follows `planChanges`, and exposes `purchase(PlanOffer)`, `restore()`, `retry()`, and `openManagement()` (through `ExternalLinks`). The state carries the current plan, the offers, a load status, the outcome of the last action for a one-time `Notice`, and whether an action is on its way.
- The view shows, top to bottom: the current plan and its contents; for each paid plan its contents and one button per period with the store price and the period; restore; manage subscription when `managementUrl()` gives a URL; the auto-renewal sentence; the terms of use (Apple EULA) and privacy policy (`https://kkomkkomi.web.app/privacy/`) links. While an action is on its way the screen takes no touch (`SaveGuard` or the same pattern), so Review Focus 5 holds.
- Load the `user-facing-copy` skill before writing the Korean and English strings. Plan names: 무료, 베이직, 프로 / Free, Basic, Pro.

- [ ] **Step 1:** Cubit tests with `blocTest` for Review Focus 1–5; view tests with `MockCubit`; a page test with `FakeEntitlements`; the narrow-screen largest-text test; see them fail.
- [ ] **Step 2:** Implement, `merry run l10n`, `merry run check`, `merry run coverage`; commit `feat(plans): show the plans and sell them`.

### Task 5: Disclosure and records

**Files:**

- Modify: `web/privacy/index.html`, `web/privacy/en/index.html`, `test/web/privacy.test.mjs` (both languages together, effective date the merge date)
- Modify: `docs/notes/2026-10-02-first-test-distribution.md` (the App Privacy rows, the Data safety rows, the RevenueCat dashboard steps: the four package identifiers, the entitlements `basic` and `pro`, the Firebase extension, and the products in each store; the App Store metadata needs the terms of use link too)
- Modify: `CLAUDE.md` ("Units", "Current state", "Architecture" bullets that name the ports and the screens), `docs/plans/2026-10-05-m3-subscriptions.md` (PR 4 split into 4a and 4b, operator, 2026-10-05, and no release build between their merges)
- Create: this brief as the first commit of the pull request

- [ ] **Step 1:** `merry run web`, cspell, `trunk check`; commit `docs(privacy): disclose RevenueCat as the processor of purchases` and `docs: describe the plans screen`.

The pull request body lists every privacy clause that the code does not show by itself, for the operator's review, and the deploy of Hosting after the merge, with the operator's approval.

## Reconciliation, 2026-10-05

The shipped code is the authority where it differs from the steps above.

- Task 2 names `({String id, String price})` as the package record and four new methods of `RevenueCatStore`. `RevenueCatStore` in `lib/billing/revenuecat_entitlements.dart` adds `productId` to the record and a fifth method, `activeProductIds()`. The reason is Review Focus 6: the record of the brief cannot tell which period of the current plan is in use, so the screen could not mark one period as "이용 중" and still sell the other.
- `offers()` reads the products in use apart from the offering. When that read fails, the offers show without a product marked as active, and the screen counts both periods of the current plan as in use. `test/billing/revenuecat_entitlements_test.dart` covers it ("gives the offers, none of them active, when the read of the products in use throws").
- After a purchase, `PlansCubit` keeps the screen busy until the offers are read again, and when that read gives no offers it marks none of them as active, so the product that was just bought cannot be bought again. A new plan from the store removes the pending message. `test/presentation/plans/cubit/plans_cubit_test.dart` covers both.
- Task 1 names four new methods of `Entitlements`, and Task 2 names four new methods of `RevenueCatStore`. The port adds a fifth, `invalidate()`, and `RevenueCatStore` adds `invalidateCustomerInfoCache()`. `PlansCubit` adds `refresh()`, which `PlansView` calls when the app comes back to the foreground. The reason: a person can switch the period in the store subscription management while the screen is open. That switch keeps the plan, so `planChanges` reports nothing, and `Purchases.getCustomerInfo` "normally" gives the customer information that RevenueCat keeps (`purchases_flutter` 10.14.0). Without these methods, the screen kept the old product marked as in use. `test/presentation/plans/cubit/plans_cubit_test.dart` ("refresh") and `test/presentation/plans/view/plans_page_test.dart` ("shows the period that the person switched to …") cover it.
- Task 4 names a company profile entry that shows the current plan name. The shipped entry shows only the label and opens `PlansPage.route()`, and it reads nothing from `Entitlements`. The reason: in the production flavor each read of the plan configures RevenueCat with the Firebase user ID, so the entry made a RevenueCat customer record for a person who opened the company profile screen only to delete all data. Now nothing reaches RevenueCat until the person opens the plans screen. `test/presentation/company_profile/view/company_profile_page_test.dart` ("reads nothing from the entitlements while the screen opens, saves a name, and deletes all data") covers it.
