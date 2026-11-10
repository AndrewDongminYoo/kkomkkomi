# eMudhra Firestore SDK patch and the #86 rollout

## Trigger

On 2026-11-10 a Firebase notice for the `kkomkkomi` project asked for an upgrade of the Firestore client SDKs of Apple, Flutter, C++ and Unity, because the private keys of several eMudhra intermediate CA certificates were compromised and revoked.
The Firebase guide [Updates required to remediate the eMudhra certificate compromise](https://firebase.google.com/support/guides/compromised-emudhra-intermediate-ca) (read 2026-11-10) lists `cloud_firestore` 7.0.0 and earlier as affected, except 6.10.1 and 6.10.2, and `cloud_firestore` 7.1.0 as the recommended fix.
For Apple it lists `FirebaseFirestore` 13.1.0 and earlier as affected, except 12.19.3, and 13.1.1 or later as fixed.
The Android and web SDKs are not affected, so the Google Play builds need no action for this notice.

## Source state

`6e042dd` (2026-10-26) moved `cloud_firestore` from 7.0.0 to 7.1.0, and `firebase_core` 5.1.0 pins `firebase-ios-sdk` 13.1.1 in its `Package.swift`.
The four `Package.resolved` files of iOS and macOS resolve `firebase-ios-sdk` 13.1.1.
`bcac1e4` (`1.1.2+6`) and `c59e08b` (`1.1.3+7`) both descend from `6e042dd`.
`c2611c5`, the candidate source of `1.1.1+5`, resolves `cloud_firestore` 6.10.0 and `firebase-ios-sdk` 12.19.0, which are affected.
No code change was needed.

## App Store state

A read-only App Store Connect API read on 2026-11-10 found iOS `1.1.1` (build 5, uploaded 2026-10-15 PDT) as `READY_FOR_SALE`.
Build 5 was uploaded before `6e042dd`, so it holds an affected SDK whatever its exact source commit.
Builds 6 (`1.1.2`) and 7 (`1.1.3`) were `VALID`, and build 7 was uploaded 17 minutes after `c59e08b`.
On 2026-11-10 version `1.1.3` with build 7 was submitted for review; a second read found it `WAITING_FOR_REVIEW` with the release type `AFTER_APPROVAL`, so it releases when Apple approves it.

## Why the rules went out first

`1.1.2` and later read `publishingGrants/{uid}` in each share transaction, and the Firestore rules deployed at `135c67f` denied that read, so no new link share of those builds could succeed (`docs/specs/2026-11-02-publisher-approval-request.md`).
Releasing `1.1.3` on iOS against those rules would have stopped iOS link sharing as well.
The rollout of `docs/notes/report-abuse-operations.md` § Compatibility and rollout was therefore run on 2026-11-10, each step with approval:

1. Hosting was deployed from `101fd6d`. The live `/`, `/privacy/`, `/privacy/en/`, `/terms/`, `/terms/en/`, `/report/index.html`, `/report/app.js`, `/report/view.js` and `/sitemap.xml` were byte-identical to the tracked files. The web report change adds only the report mail link to the footer and no new read.
2. The inventory found one publisher UID, which owns two client pages (one revoked), two reports and two Storage objects of 458,337 bytes. Its grant had been created on 2026-11-02 with exactly those counters and the two photo reservations, so no grant was created or changed. No `publishingRequests` collection existed. The Auth account of that UID exists and its claim holds `basic` and `pro`.
3. `1.1.3` was submitted for review, as above.
4. `merry run rules` passed 108 tests, and the Firestore and Storage rules were deployed together from `101fd6d`. The Firebase Rules API showed both releases at 2026-11-10T06:10Z, and their sources were byte-identical to `firestore.rules` and `storage.rules`. The Storage service agent still holds `roles/firebaserules.firestoreServiceAgent`.

After the deploy, unauthenticated reads returned 200 for the open page, its report and its photo URL without a token, and 403 for the revoked page.

## Consequences until 1.1.3 is released

iOS `1.1.1` does not charge usage or reserve photos, so it cannot create or change a page, a report or a photo under the deployed rules; open links, local capture and PDF sharing still work.
Android `1.1.2` reads the grant and can share again for an enrolled UID, but it holds the #86 client without #147, so a paid UID without a grant still sees the email dialog until it updates.
Rollout step 5 (tests with an approved publisher, an unapproved UID, an exact allowance, a blocked fictional page, approval fallback and anonymous reads) has not been run, except the anonymous reads above.
