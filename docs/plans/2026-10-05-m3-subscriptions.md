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
