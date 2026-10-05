# M3 subscriptions: pull request split

Date: 2026-10-05.
Refs #36. The design is [`docs/specs/2026-10-04-m3-subscriptions-design.md`](../specs/2026-10-04-m3-subscriptions-design.md), and this document does not restate it.
The operator started M3 on 2026-10-05 with `/pr-loop Issue #36`.

The repository is public, so no plan document names a price, a billing term, or a fee.

## Order

Each pull request gets its own brief under `docs/plans/` when it starts, written against the code of that time.
Every pull request body says `Refs #36`, and none closes it: the acceptance criteria of #36 include purchases in the store test environments, which the operator makes by hand.

| PR  | Brief                                      | Scope                                                                                                                                                                                                                                                                                                                                                                                                                                      | Needs before it starts                                                                                     |
| --- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| 1   | `2026-10-05-m3-01-report-branding.md`      | `firestore.rules` accepts `unbranded` only with a paid claim. The web report hides the footer text of an unbranded report. The Free footer text becomes `꼼꼬미로 작성됨`.                                                                                                                                                                                                                                                                 | Nothing outside the repository. The `rules` and `web` CI jobs verify it.                                   |
| 2   | `2026-10-05-m3-02-entitlements-port.md`    | The `Entitlements` port, `lib/billing/` with `purchases_flutter` and its boundary test, the Free-only adapter of development and staging, and the wiring in `bootstrap()`. No screen.                                                                                                                                                                                                                                                      | The RevenueCat project and its public SDK keys. The checks listed below.                                   |
| 3   | `2026-10-05-m3-03-unbranded-publish.md`    | The paid answer of `Identity` from the token claim, ~~the token refresh when `Entitlements` says paid and the token does not,~~ a newly issued token at each check, and `unbranded` in the report that `PublishQueue` gives the publisher. ~~It is the first pull request that calls `currentPlan()`, so it also adds RevenueCat as a processor to the privacy pages and to the App Privacy and Data safety answers in the console note.~~ | PR 1 merged and its rules deployed with the operator's approval, PR 2 merged.                              |
| 4   | `2026-10-05-m3-04-plans-and-limits.md`     | The paywall and the current-plan screen, restore, the store subscription management link, the active client limit, and the PDF footer from the cached entitlements. It is the first pull request that calls `currentPlan()`, so it also adds RevenueCat as a processor to the privacy pages and to the App Privacy and Data safety answers in the console note.                                                                            | PR 2 merged. Store products in the store test environments, which need the App Store Connect record (#40). |
| 5   | `2026-10-05-m3-05-deletion-and-privacy.md` | The subscription notice of Delete All Data, the rest of the privacy pages and of the App Privacy and Data safety answers, and the terms of use link.                                                                                                                                                                                                                                                                                       | PR 4 merged.                                                                                               |

The client limit lands in PR 4 together with the purchase path.

The privacy pages and the store answers for RevenueCat as a processor moved from PR 5 to PR 3 on 2026-10-05, with the brief of PR 2: a build of PR 3 is the first that sends anything to RevenueCat, so its disclosure ships with it.
They moved again, from PR 3 to PR 4, on 2026-10-05 with the brief of PR 3 (`2026-10-05-m3-03-unbranded-publish.md`): PR 3 decides `unbranded` from the claim of a newly issued ID token and does not call `Entitlements`, so no build of PR 3 sends anything to RevenueCat, and PR 4 is the first pull request that calls `currentPlan()`.
PR 2 adds only the Purchase History that the RevenueCat privacy manifest declares, as the Diagnostics row follows the Firebase manifests.
A build that limits clients without a way to buy would leave a tester at 2 clients with no way out.

## PR 4 split into 4a and 4b (2026-10-05)

The operator split PR 4 on 2026-10-05, after the row of PR 4 above was written, and this section is the authority for PR 4 where the two differ.

- 4a, `2026-10-05-m3-04a-plans-screen.md`: the plans screen that the company profile screen opens, purchase, restore, the store subscription management link, the terms of use and privacy policy links, and the RevenueCat disclosure in the privacy pages and in the App Privacy and Data safety answers. The terms of use link moved here from PR 5, because Apple asks for it on the purchase screen; the operator chose Apple's standard EULA.
- 4b: the active client limit, with a second entry to the plans screen at the limit, and the PDF footer from the cached entitlements.

No release build is made between the merges of 4a and 4b: the plans screen of 4a describes the client limit and the footer of each plan, which only 4b ships, so a build of 4a alone would describe behavior that it does not have (App Store Review Guideline 3.1.2(c), "clearly describe what the user will get").

### Reconciliation with 4b (2026-10-05)

The brief of 4b, `2026-10-05-m3-04b-limits-and-pdf.md`, and its shipped code are the authority where they differ from the two points above.

- The PDF footer does not come from the cached entitlements. `VisitReportCubit` reads `Identity.hasPaidEntitlement()` once when the visit report screen opens, the same token claim that decides the web report footer, so the PDF path never reaches RevenueCat, and a device that cannot get a newly issued token prints the footer. The tests are in `test/presentation/visit_report/cubit/visit_report_cubit_test.dart` and `test/export/report_pdf_test.dart`.
- The constraint that no release build is made between 4a and 4b ends when 4b merges, because the app then has the client limit and the footer that the plans screen describes. A release build is allowed again after that merge, subject to the deploy order in "Operator steps outside the repository": the rules of PR 1 (#42) are deployed before a build that writes `unbranded` reaches a tester.

## PR 5 and the end of the split (2026-10-05)

The brief of PR 5 is `2026-10-05-m3-05-deletion-and-terms.md`, not the file name in the row of PR 5 above, and that brief and its shipped code are the authority where they differ from the row.

- The RevenueCat disclosure in the privacy pages and in the store answers shipped with 4a, and so did the terms of use link of the plans screen.
- PR 5 ships the subscription notice in the confirmation of Delete All Data (`lib/presentation/company_profile/view/company_profile_page.dart`, tested in `test/presentation/company_profile/view/company_profile_page_test.dart`), the terms of use and privacy policy links at the end of the two App Store descriptions, and the publish token request in section 9 of the privacy pages.
- The RevenueCat customer record of a deleted user is removed by hand on request (operator, 2026-10-05), and the console note `docs/notes/2026-10-02-first-test-distribution.md` owns that step.

PR 5 is the last pull request of the split, so its merge completes the split.
#36 stays open after that merge: its acceptance criteria include the purchases in the store test environments in "Operator steps outside the repository", which the operator makes by hand.

## Checks before PR 2

- The RevenueCat public SDK keys stay out of the repository (operator, 2026-10-05): a file that git ignores holds them, and the production build reads them through `--dart-define`, as `google-services.json` stays out of the repository today.

- Whether Play Console requires an uploaded build that holds the billing library before it lets the operator create subscriptions. If it does, PR 2 ships in a build before the operator sets up the Play products.
- The minimum iOS and Android versions of `purchases_flutter` against those of the project.
- The lockfile is regenerated and committed with `pubspec.yaml`.

## Operator steps outside the repository

- Create the RevenueCat project and its apps, and install its Firebase extension on the Blaze project `kkomkkomi`.
- Create the products in App Store Connect and Google Play after the store records exist (#40).
- Deploy the rules of PR 1 when the operator approves it, before any app build that writes `unbranded` reaches a tester.
- Buy, restore, and change plans in the Apple sandbox and in Google Play license testing.
