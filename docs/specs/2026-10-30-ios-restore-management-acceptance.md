# iOS restore and subscription-management acceptance (#36)

## Approved scope

The operator invoked the PR loop for [issue #36](https://github.com/AndrewDongminYoo/kkomkkomi/issues/36), starting with iOS Sandbox build/account identification and purchase restoration and management.
Retain the [subscription design](2026-10-04-m3-subscriptions-design.md#accounts-and-restore) and [M3 plan](../plans/2026-10-05-m3-subscriptions.md).
The issue's recorded iOS purchases and branding checks from 2026-10-06 are historical evidence; restoration and management were left untested.
Android, complete lifecycle coverage, account migration and backend replacement are separate remaining work.
No dependency, restore-policy or product-design change is proposed without a reproduced defect.

## Build and account prerequisites

The operator identified the installed production-bundle app as TestFlight `1.1.1(5)`.
Native app inventory confirms bundle `kr.donminzzi.kkomkkomi` with that version/build, but does not establish its source commit or embedded RevenueCat/Flutter versions.
No corresponding local production IPA/archive or build record was present during discovery.
Do not claim a current-source or upgraded-SDK device pass unless an immutable build/source mapping is obtained.
Results on the existing TestFlight app may instead be recorded as an explicitly limited store-build baseline.
The known DEV camera/gallery build uses `FreeEntitlements` and cannot establish real subscription behavior.

[Apple documents](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight) that TestFlight apps automatically use the Sandbox purchase environment.
This does not identify which account owns historical test purchases, prove an active entitlement, or isolate the production flavor's Firebase and RevenueCat services.
The operator initially did not know whether the prior test account remained available.
Record account availability and purchase state without collecting email addresses, passwords, tokens or receipt bytes in public artifacts.
Do not sign out of the daily phone's Media and Purchases account, create an account, reset purchase history or reinstall merely to manufacture a test state.
Existing authenticated store access was not established during discovery; do not infer App Store Connect or RevenueCat dashboard settings from local configuration.

## Evidence sequence

1. Record the exact installation channel/version and available source provenance, then inspect the current plan, offers, restore control and management control without purchasing or restoring.
   Record only product presence and state; keep actual business prices out of tracked documents.
2. Confirm the intended test-account context and whether an active Sandbox entitlement exists.
   An old or expired subscription does not establish the positive-restoration precondition.
   A separate Sandbox account is needed for some Apple test controls; do not change the device's account configuration implicitly.
3. After the exact context and operator action are agreed, restore and record the visible result and resulting plan/product state.
   Distinguish an active purchase restored, no active purchase found, cancellation/authentication interruption and a failure.
   A no-purchase result without a known active entitlement is not a restoration defect.
4. When a management link is available, inspect where it opens and return to the app.
   Record whether the plan/product refreshes; a return without a store-side change does not prove a subscription transition.
   If the provider gives no management link, record that condition rather than inventing a visible control or a successful management pass.
5. Compare pre/post client, photo and report presence without deleting app data.
   Any purchase, cancellation, tier/period change, restore ownership transfer or other provider write needs its exact approved target and evidence.

[RevenueCat's restore policy](https://www.revenuecat.com/docs/projects/restore-behavior) can transfer or alias purchases across App User IDs and can have a Sandbox-specific override.
The project's approved policy is not proof of the live dashboard configuration.
Do not infer that restoring an entitlement restores local clients/photos, that Firebase claims of another identity were revoked, or that the extension is healthy.
Issue #51 remains separate; no extension update, webhook replay, Hosting/rules deployment or paid report publication is included.

## Delivery and limits

Run controlled adapter, store-channel, Cubit and view regressions, keeping them distinct from device/account/provider evidence.
Prepare an exact build and individual installation proposal only if the existing TestFlight baseline is insufficient; do not run an upload/release lane as a verification shortcut.
Record actual observations in a dated note and update directly affected current instructions, distribution notes and subscription documentation in the same PR.
Do not publish preparation as completed acceptance, add an automatic issue-closing reference or claim complete billing acceptance from an iOS-only pass.
Any rendered implementation change requires its own final visual approval.
Fresh precedent retrieval was unavailable during authoring; the existing tracked subscription contracts govern this bounded pass.

The [dated TestFlight record](../notes/2026-10-30-ios-restore-management-acceptance.md) separates completed operator observations from pending or unverified checks.
