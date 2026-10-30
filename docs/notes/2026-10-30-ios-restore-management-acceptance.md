# TestFlight restore and management baseline (#36)

## Build, account and evidence

On 2026-10-30 the operator identified the regular Kkomkkomi app as TestFlight `1.1.1(5)`.
Native app inventory confirmed `kr.donminzzi.kkomkkomi`, version `1.1.1`, build `5`.
The installed binary's source commit, Flutter version and embedded RevenueCat SDK versions were not established.
No matching local production IPA/archive or build record was present.
This is an existing store-build baseline, not proof of a build from current main or physical acceptance of the latest dependency upgrade.
The separate DEV camera/gallery app has free-only entitlements and was not the billing test target.

The operator reported that both Developer Sandbox Apple Account and Media and Purchases were signed in.
No account identity, password, raw receipt or provider customer record was collected, and the account actually selected for each StoreKit request was not independently established.
[Apple documents](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight) that TestFlight apps operate in the Sandbox purchase environment; a separate Sandbox account selection involves additional account settings.
No account switch, reinstall or purchase-history reset was requested or reported in this pass.
The purchase environment does not isolate the production flavor's Firebase and RevenueCat project services.

These observations are operator-reported device results, not agent screen captures or direct Apple/RevenueCat/Firebase transaction reads.
Exact execution times were not supplied.
The [acceptance spec](../specs/2026-10-30-ios-restore-management-acceptance.md) and [plan](../plans/2026-10-30-ios-restore-management-acceptance.md) bound the pass.

## Observations

| Observation                                      | Operator-reported result                                                                                              |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| Initial plan and controls                        | Plan section and purchase-restoration control displayed; management control absent; operator reported no subscription |
| Initial restore                                  | Displayed the no-purchase notice, retained the free plan and showed no management control                             |
| One approved Basic monthly purchase              | Purchase completed successfully; Basic and its five-client limit were displayed                                       |
| Management navigation after purchase             | Control appeared and opened the actual App Store subscription list; the test subscription was not listed there        |
| Restore after the purchase and return to the app | The operator reported the successful-restoration notice; Basic/monthly state and the management control remained      |
| Existing local data after restoration            | The operator reported that existing clients, photos and reports remained                                              |

The initial restore establishes the visible no-active-purchase path, not the absence of every historical transaction.
The current source maps no active paid entitlement to its no-purchase notice, but no receipt contents or provider-side state were inspected here.
Management-link navigation does not establish that the Sandbox subscription can be changed or cancelled in that list.
No actual subscription-management transition was performed.
The approved single purchase was consumed by the successful operator transaction; it grants no authority for additional purchases or account changes.
The operator reported both restore outcomes: the initial no-purchase notice and the successful-restoration notice after the approved purchase.
These are in-place observations on the same installed app, not recovery after reinstall or a controlled transfer between identities.
Local-data preservation is operator-reported; no pre/post database or file inventory was captured.
Returning from management without a store-side change establishes the retained displayed state, not a subscription-transition refresh.

## Controlled checks and limits

Current-source store-channel, entitlement adapter and plans Cubit/view regressions passed, covering controlled restore outcomes, management-link behavior and foreground refresh.
`flutter analyze --no-pub`, `dart format --output=none --set-exit-if-changed lib test` and preparation-document checks passed.
These checks use controlled store responses; they do not prove the installed TestFlight binary's implementation or live account/provider state.
No application, dependency, schema, native setting or rendered-output implementation changed for this pass.

Android, coverage of the full product/period matrix, reinstall or changed-identity restoration, expired/revoked/pending transitions, failure injection, actual subscription-management changes and Firebase claim propagation remain unverified by these observations.
Issue #51 remains separate; no extension deployment, webhook replay, paid report publication or store upload was performed.
Issue #36 remains open for the remaining acceptance.
