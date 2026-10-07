# Privacy disclosures before the next Hosting deploy

## Problem and scope

Issue #81 identifies incomplete deletion disclosures, unshipped in-app camera descriptions, and missing gallery-source regression coverage.
Both privacy pages are already live from the Hosting deployment of `59b1c84`.
The retained build 3 records also name that commit, while the in-app camera merged later in #79 at `43e1cce`.
Mark the camera disclosures as planned until a build that includes that feature ships.

## Constraints

Keep the Korean and English pages consistent with `SqliteLocalDataRepository.eraseAll`, `FirebasePublisher`, and the existing Firestore rules.
Preserve camera cleanup and optional device-only observation details as future disclosures, without presenting them as available in the distributed build.
Change neither security rules nor page layout.
Do not upload a build or deploy Hosting through this PR loop.
The later Hosting deployment requires separate operator approval and verification of the live pages.

## Acceptance

- Section 6 names the optional business phone in the local database deletion list in both languages.
- The camera cleanup and shutter-observation paragraphs, and the capture-time item in the data list, explicitly identify the planned feature.
- A focused privacy regression fails if either language loses the gallery-source disclosure in section 3.
- Emulator tests exercise owner writes with both source fields, anonymous reads, and non-owner or revoked-page write denials without relaxing rules.
- The existing local check, coverage, rules, lint, and current-head hosted review gates pass.

## Sources and verification limits

Issue https://github.com/AndrewDongminYoo/kkomkkomi/issues/81 owns the contract.
`lib/persistence/sqlite_local_data_repository.dart` deletes `company_profile`; `lib/firebase/firebase_publisher.dart` serializes gallery sources.
Retained source records and store verification results under `~/Desktop/kkomkkomi-1.1.0+3/` establish build 3 provenance and the observed upload state, rather than current main establishing shipped functionality.
Privacy source tests check disclosure presence and section placement; a browser check reads the rendered text and narrow-screen overflow.
Oracle retrieval for privacy pages and shipped features returned \[no precedent found\]; current issue and repository evidence determine the scope.
