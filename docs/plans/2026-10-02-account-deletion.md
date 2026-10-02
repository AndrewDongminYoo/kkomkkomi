# Brief: delete the account and all data from the app

Read `CLAUDE.md`, `firestore.rules`, `storage.rules`, the privacy policy pages under `web/privacy/`, and `docs/notes/2026-10-02-first-test-distribution.md` before you write code.
This brief depends on the brief for issue #20, which also edits the privacy policy pages, and must start after that pull request merges.

## Why

App Store Review Guideline 5.1.1(v) asks that an app that creates an account lets the person delete it, and Apple's guidance names accounts that the app creates on its own.
The app signs in anonymously, and an external TestFlight build goes through review.
The operator decided on 2026-10-02 to build this before the trial.

## Goal

From the company profile screen, a person deletes everything the app holds for them: the published client pages, their reports, their photos, the anonymous account, and the data on the phone.

## In scope

1. A "delete all data" action on the company profile screen, with a confirm step that names what is deleted and that open links stop working.
2. The order of the deletion, in `lib/application/` where tests reach it:
   - delete the Storage objects of every client page that the account owns, using the recorded upload paths and intents, because the rules allow no list;
   - delete the report documents, then the page documents;
   - delete the anonymous account;
   - only then delete the local database and the photo files, and return the app to its first-launch state.
     A step that fails stops the deletion before the local data is touched, so the person can try again, and the screen says what failed.
     In the development and staging flavors, where publishing is unavailable, the action deletes the local data only.
3. `firestore.rules`: allow the owner to delete a client page and its reports, and nobody else. Add rules tests for the owner, a non-owner, and a reader without sign-in.
4. The privacy policy pages, Korean and English:
   - the privacy officer and contact: 유동민 (Dongmin Yu), ydm2790@gmail.com (operator, 2026-10-02);
   - remove the statement that Firebase deletes anonymous accounts after 30 days: the operator turned that setting off on 2026-10-02 (issue #21);
   - describe the new deletion, and what remains after it, if anything;
   - name the diagnostic data that the Firebase SDKs declare in their privacy manifests (operator decision, 2026-10-02: declare it as the SDKs do);
   - fill the remaining placeholders with defaults, each with its source: the effective date is the date the pull request merges; a request by email is answered within the period the Personal Information Protection Act sets, cited from the law or its decree. For the legal basis and for who is responsible for the people in a photo, write a plain default and list both in the pull request body as items the operator should have reviewed by someone qualified. Do not claim that a default is legal advice.
5. `docs/notes/2026-10-02-first-test-distribution.md`: the App Privacy row for Other Diagnostic Data is declared, the Data safety answer about deletion is "yes, in the app", and the account deletion item is closed.

## Out of scope

- Any deploy. The parent session deploys the rules and Hosting after the merge.
- Account linking.

## Requirements

- Every user-facing string goes in both ARB files, in the `warm` voice. Load the `user-facing-copy` skill first, and treat this as a destructive action.
- Tests through fake ports for every step and every failure. No test touches Firebase.

## Acceptance criteria

- `merry run check`, `merry run coverage`, and `merry run rules` pass.
- The pull request body lists the deletion order, what remains after a deletion, and the defaults that need the operator's review.
