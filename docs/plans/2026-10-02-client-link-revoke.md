# Brief: close and reissue the link of a client from the app

Read `CLAUDE.md` ("Publishing", "Deletion", "Product rules that constrain code"), `lib/application/publish_queue.dart`, `lib/presentation/visit_report/cubit/report_link_cubit.dart`, the client detail screen under `lib/presentation/client_detail/`, and section 5 (`#revoke`) of the privacy policy pages under `web/privacy/` before you write code.

## Why

The product rules in `CLAUDE.md` require per-client access removal and reissue of a report link.
`PublishQueue.revokeClientPage` and `PublishQueue.reissueClientPage` implement both, and no screen calls them: `CLAUDE.md` says "no screen revokes or reissues a page yet", and section 5 of the privacy policy says the app has no way to close the link of one client ("예정").
The operator approved this work on 2026-10-02.

## Goal

From the client detail screen, a person closes the link of that client, or replaces it with a new link, and the screen says what happens to the links that were already sent.

## In scope

1. A link section on the client detail screen, shown only while `PublishQueue.isAvailable` is true, as `ReportLinkCubit` decides for the link share. In the development and staging flavors the screen does not change.
   - It says whether the client has an open link.
   - "Close the link" calls `revokeClientPage`. The confirm step says that every link of this client that was already sent stops opening, that the photos are deleted from the server, and that the next link share of this client makes a new link.
   - "Make a new link" calls `reissueClientPage`. The confirm step says that the old links stop opening and that the reports are published again under a new link, which the person then shares from a visit report.
   - Both actions show only while the client has an open link.
2. The screen must not say that a link is closed before the revoke job of the page is done on the backend. Until then it says that the link is closing. A revoke job that fails for a reason that a retry can fix keeps that state; a job that stops with a `PublishFailure` shows an error. Read the job state from `PublishQueue.updates` and the stored jobs, the way `ReportLinkCubit` follows a publish job.
3. While an action is on its way, the screen takes no touch and no back press, as `SaveGuard` does for a save.
4. The privacy policy pages, Korean and English together: section 5 describes the close and the new link as features of the app, and drops "예정" and the sentence that the app has no such feature. Keep what the section says about the documents that stay and the 7 days of soft delete. Update `test/web/privacy.test.mjs` if it checks the old text.
5. `CLAUDE.md`: replace "no screen revokes or reissues a page yet" with what the screen now does, in "Current state" and in "Publishing".

## Out of scope

- Link expiry. It stays open, as the M1 design says.
- A button that shares the history link of a client. The web report page links to the history, so a report link reaches it.
- Archiving a client does not revoke its page. Do not change that here; name it in the pull request body as a follow-up if you find that it matters.
- Any change to `firestore.rules` or `storage.rules`: the rules already allow the owner to revoke.
- Any deploy. The parent session asks the operator to deploy Hosting after the merge, because the privacy pages change.

## Requirements

- Every user-facing string goes in both ARB files. Load the `user-facing-copy` skill first, and treat both actions as destructive.
- Tests through fake ports for each action, each confirm step, the closing state, a failed revoke job, and the flavor without publishing. No test touches Firebase.
- The screen does not overflow at `tester.useNarrowScreenWithLargestText()`, and `tester.expectWholeText()` passes for the new texts.

## Acceptance criteria

- `merry run check` and `merry run coverage` pass. `merry run rules` passes unchanged.
- The pull request body lists each new string in Korean and English, and says what a person sees from the press of each action to the end of its job.
