# M3 subscriptions and entitlements

Date: 2026-10-04.
Status: written specification for review. The operator approved the design in conversation on 2026-10-04. This document implements no change.
Refs #36: [Basic and Pro subscription billing and entitlements](https://github.com/AndrewDongminYoo/kkomkkomi/issues/36).

The code observations use main at `a02a2884523304363046d32fb02069d90212dac9`, verified on 2026-10-04.
M1 is the milestone in progress, and M2 comes before M3 in the milestone table of `CLAUDE.md`.
So this specification stays at the level of decisions: the product matrix, the trust boundary, the device rules, and the restore policy.
The implementation plan is written when M3 starts, against the code of that time.

The repository is public.
This document names no price, no billing term, and no fee of a vendor or of Firebase, as `CLAUDE.md` ("Public repository") requires.

## Purpose and approved scope

The app stays free to download.
Two paid plans, Basic and Pro, are auto-renewable subscriptions, each with a monthly and an annual period.
A plan changes two things in M3: the number of clients that a company can keep active, and the footer of its reports.

| Plan  | Active client limit | Report footer                                      |
| ----- | ------------------- | -------------------------------------------------- |
| Free  | 2                   | `꼼꼬미로 작성됨` on the web report and on the PDF |
| Basic | 5                   | None                                               |
| Pro   | No limit            | None                                               |

Pro also gets the M2 features that issue 36 names (the monthly bundled PDF and view tracking) when M2 has shipped them.
Gating those features is work for the time when both M2 and M3 exist, and this document does not design it.

The operator made these choices on 2026-10-04:

- RevenueCat verifies the purchases, and its Firebase extension gives the active entitlements to Firebase Auth as a custom claim.
- The Firebase project `kkomkkomi` is on the Blaze plan already, which the extension needs.
- The Free limit is 2 active clients.
- The first release keeps the anonymous Firebase identity and shares no entitlement between platforms.
- An active client is a client that is not archived.

## Current code

- `Client.isArchived` exists, and a client is archived and never deleted (`lib/domain/client.dart`). No unarchive operation exists.
- `ClientRepository.save` stores a new client. No rule limits the number of clients.
- `firestore.rules` accepts a report with exactly the keys `visitDate`, `publishedAt`, and `zones` (`isReport`).
- The web report prints the constant `texts.footer` (`"꼼꼬미로 만든 보고서"`) on every report (`web/report/view.js`).
- The PDF prints `ReportLabels.footer`, which comes from the ARB key `reportFooter` (`lib/export/report_pdf.dart`).
- `FirebaseIdentity` signs in anonymously. A reinstall can give a new user ID.

## Products

RevenueCat holds two entitlements, `basic` and `pro`.
A Pro product grants both entitlements, so that a check for "paid" reads one of two identifiers and a check for Pro reads one.

There are four products: Basic monthly, Basic annual, Pro monthly, and Pro annual.

- App Store Connect: one subscription group holds the four products. Pro is ranked above Basic. The monthly and annual products of one plan share a level, as issue 36 cites from Apple's subscription guidance.
- Google Play: two subscriptions, `basic` and `pro`, each with a monthly and an annual base plan.
- RevenueCat: one default offering holds the four packages.

The product identifiers go into the repository, because the app needs them.
The prices stay in the store consoles, and the paywall shows the localized price that the store gives.

## Trust boundary

The web report is the primary output, and anyone with the link can open it.
The footer of the web report is the one entitlement effect that the backend enforces.

- The app configures RevenueCat with the Firebase user ID as the RevenueCat app user ID. The Firebase extension needs that equality.
- The extension writes the active entitlements into the custom claim `revenuecatEntitlements` of that user.
- A report gets one optional key, `unbranded`, whose only allowed value is `true`.
- `firestore.rules` accepts `unbranded` only when the claim of the writer holds `basic` or `pro`.
- The web report prints the footer when the key is absent. A report that exists today has no such key, so it keeps its footer.

The app writes `unbranded` from the claim in its current ID token, not from the RevenueCat SDK.
So the app and the rules read the same value.
After a purchase, the app refreshes the ID token.

Each disagreement falls back to the footer:

- When the claim is not yet updated after a purchase, the app writes no `unbranded` key, and the report keeps its footer.
- When the app reads the claim from one token and writes with a newer token that no longer holds it, the rules refuse the write. The publish job fails, and the next run writes the report again with the footer.

The publish queue must count that refusal as a failure that a retry can fix.
The implementation plan checks how the queue classifies a permission error today.

Known limit: a claim is part of an ID token.
After a subscription ends, a token that was issued before still holds the entitlement until the app gets a new token, so a report written in that window can have no footer.
The implementation plan states how long a token lives, from the Firebase documentation.

The footer is decided when a report is written.
A report written while paid keeps no footer after a downgrade.
A report written again after a downgrade gets the footer, for example at a reissue of the client link.

## Device rules

The client limit and the PDF footer work offline, so the device decides them.
They read the `CustomerInfo` that the RevenueCat SDK caches.

- The app refuses a new client while the count of active clients equals or exceeds the limit of the plan.
- The app keeps every stored client, visit, photo, and report after a cancellation, an expiry, or a downgrade. A company above its new limit keeps its clients and cannot add one until it archives clients or upgrades.
- An unarchive operation, if one is added, follows the same check.
- The PDF prints the footer unless the cached entitlements hold `basic` or `pro`.

A changed app can skip a device rule.
The operator accepts that risk for the client limit and the PDF.

## Units

The design follows the boundary pattern of `lib/firebase/`.

- `lib/application/` gets an `Entitlements` port that gives the current plan and its changes, starts a purchase, restores purchases, and opens the store subscription management.
- A new unit `lib/billing/` holds the RevenueCat adapter. It is the one directory under `lib/` that may import `purchases_flutter`, and `lib/main_production.dart` is the one file outside it that may import it. A boundary test like `test/firebase/boundary_test.dart` enforces both rules.
- The development and staging entry points give `bootstrap()` an adapter that always reports Free and refuses a purchase, as `UnavailableIdentity` does for identity.
- The paywall and the current-plan screen are screens under `lib/presentation/` in the Very Good CLI layout, with their texts in the ARB files. They are app screens, not the RevenueCat paywall UI, so that they follow `KeepAllText` and the theme.

## Accounts and restore

- RevenueCat keeps its default restore behavior, "Transfer to new App User ID". A restore moves the purchase to the current user ID and removes it from the earlier one, so one purchase never serves two owners at the same time.
- After a reinstall or on a new device, the person presses Restore Purchases. The local data does not come back, because the app is local-first. Only the entitlement comes back.
- A subscription bought on iOS does not unlock Android, and the reverse is also true.
- Open item for the implementation: check on a device whether the anonymous user ID survives an iOS reinstall, and write the result into the restore copy.

## Deletion and legal requirements

- Delete All Data shows, before it starts, that a subscription keeps billing through the store, and it links to the store subscription management.
- Open decision: how the RevenueCat customer record of a deleted user is removed. The RevenueCat REST API needs a secret key, so the app cannot call it. The plan names the options and the operator chooses.
- The privacy pages (`web/privacy/` in Korean and English) add RevenueCat as a processor and the purchase history as data, in one change, as `CLAUDE.md` requires.
- The App Privacy and Data safety answers in `docs/notes/2026-10-02-first-test-distribution.md` add the purchase history.
- The paywall and the store metadata link to the terms of use and the privacy policy, as App Store Review Guideline 3.1.2 requires for auto-renewable subscriptions. The implementation plan quotes the guideline at that time.
- The Free footer text becomes `꼼꼬미로 작성됨` (operator, 2026-10-04) in the ARB file and in `web/report/view.js`.

## Testing

- Unit tests: the mapping from entitlements to the client limit and to the footer, including the boundary at each limit and a downgrade above the limit.
- Rules tests in the emulators: `unbranded` with a `basic` claim, a `pro` claim, no claim, and an unknown entitlement. The emulators accept custom claims in the token of a test.
- Web tests: a report with `unbranded` and a report without it.
- Store test environments, by hand: each of the four products bought, restored, and changed between plans in the Apple sandbox and in Google Play license testing.

## Out of scope

- Staff accounts (M3) and every M2 feature.
- Store production activation and app review, which are release steps.
- A durable account, and entitlement sharing between platforms.
