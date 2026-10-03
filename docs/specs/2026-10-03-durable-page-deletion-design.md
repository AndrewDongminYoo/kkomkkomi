# Durable client page deletion

Date: 2026-10-03.
Status: written specification for review. The operator approved the combined design; this document implements no change.
Refs #26 and #29: [deletion confirmation](https://github.com/AndrewDongminYoo/kkomkkomi/issues/26) and [durable intent and recovery](https://github.com/AndrewDongminYoo/kkomkkomi/issues/29).

The code observations use main at `8a689971e9a9c550f1febe0b6ce775abd0fc5483`, verified on 2026-10-03.
[PR #28](https://github.com/AndrewDongminYoo/kkomkkomi/pull/28) merged the [acknowledgement-only brief](../plans/2026-10-03-issue-26-server-deletion-state.md), without application changes.
The current schema remains version 3; neither deletion confirmation nor deletion intent exists in the code.
This specification includes the unimplemented Issue #26 foundation and extends it with the approved Issue #29 intent, recovery, and fresh-ID policy.
For this combined work, it replaces the brief's one-column migration and its decision to defer durable intent. The brief remains the record of the earlier minimum scope.

Read `CLAUDE.md` ("Publishing", "Deletion", "Documents") and the "Phase B" section of [the M1 design](2026-10-01-m1-local-first-design.md) for the existing boundaries and backend contract.

## Purpose and approved scope

Delete All Data can remove a server page and then fail at the account or device step.
Today its local page row remains open, and a later share can recreate the old page ID.
Recording only the server acknowledgement fixes the screen after that record commits, but leaves a window when the remote delete succeeds and SQLite fails or the process ends before recording it.

Persist a per-page intent before sending that page's delete, and prohibit writes under the ID from that commit onward.
Persist confirmation after the backend acknowledges the delete, so the screen can distinguish an unresolved deletion from a confirmed one.
Both states survive restart while their database rows remain.

The operator approved these choices:

- Include the Issue #26 model, migration, repository, queue, and screen foundation in the same design as Issue #29.
- Preserve the three global deletion loops: all photos, then all reports, then pages. Record each page's intent immediately before its own page delete.
- Keep intent after failures and ambiguous outcomes. Recovery requires another explicit Delete All Data request; startup does not delete an account or device data automatically.
- Allow a later explicit report share to create a fresh page ID while an older page is unresolved. Share only the requested report; retain the old-link warning.

Use the existing units and ports. Add no global deletion phase, intent table, job kind, dependency, server field, rule change, or deployment.
Do not migrate old URLs, automatically republish historical jobs, or change the early photo/report failure policy.
Application code, tests, localized copy, privacy pages, and production settings are unchanged by this specification-only PR.

## Current code and failure boundary

[The schema](../../lib/persistence/schema.dart) gives `client_pages` `id`, `client_id`, `created_at`, and `revoked_at`.
[The repository](../../lib/persistence/sqlite_publish_repository.dart) selects an open page using only `revoked_at IS NULL`.
It records a revoke request before its backend job succeeds; that time cannot mean server deletion.

[`PublishQueue.deletePublished`](../../lib/application/publish_queue.dart) requires a hold, checks unsettled uploads and identity, stops all pending jobs, then deletes photos, reports, and pages.
It retains local page and job rows for retry.
[`DeleteAllData`](../../lib/application/delete_all_data.dart) then deletes the account, erases database rows, and deletes photo files.
Its timeout retains the remote future and holds the queue until that future settles. The hold does not survive process death.

[`ClientLinkCubit`](../../lib/presentation/client_detail/cubit/client_link_cubit.dart) currently reads an open-page boolean and revoke jobs.
Completed publish jobs without revoke jobs provide no deletion evidence, and a refresh read failure keeps stale controls.
[`FirebasePublisher`](../../lib/firebase/firebase_publisher.dart) uses Firestore `set` for both page publication and revocation; either can recreate an absent page.
Protect both job kinds.

Remote deletion and a local SQLite transaction cannot commit atomically.
The intent does not establish remote success; it prevents the app from recreating the target while the outcome is unknown.
Disk loss, database corruption, multiple independent queue instances, and deletion outside this application are outside this guarantee.
Keep the existing single queue from `bootstrap`, hold, and settlement checks: a local dispatch check alone cannot cancel a remote write that already started.

## Persisted page state

Advance the authoritative version 3 schema directly to version 4 with both columns:

```sql
ALTER TABLE client_pages ADD COLUMN server_delete_requested_at INTEGER;
ALTER TABLE client_pages ADD COLUMN server_deleted_at INTEGER;
```

Add nullable `DateTime? serverDeleteRequestedAt` and `DateTime? serverDeletedAt` to `ClientPage`.
Normalize both to UTC and map them to integer microseconds since the epoch, as the existing timestamps are.
Preserve both in constructors, copies including `revoke`, equality, hash, string representation, and SQLite mappings.
Keep `revoked_at` independent.

| Deletion fields                       | Meaning                                                                                       | Write policy for this page ID         |
| ------------------------------------- | --------------------------------------------------------------------------------------------- | ------------------------------------- |
| Both null                             | No persisted deletion intent or confirmation. This does not prove server existence.           | Eligible under existing revoke rules. |
| Requested set, confirmed null         | The app committed to deleting this page; the remote outcome is unresolved. It may still open. | Quarantined.                          |
| Confirmed set, either requested value | The app persisted a backend acknowledgement. The ID is retired.                               | Quarantined.                          |

An eligible open page requires `revoked_at`, `server_delete_requested_at`, and `server_deleted_at` all null.
Quarantine requires either deletion timestamp, regardless of revoke state.
An unresolved deletion requires intent and no confirmation.
Confirmation takes precedence over that page's unresolved state and old job warnings.
A completed revoke independently confirms access removal; an intent alone confirms neither access removal nor page absence.

The intent is the first locally persisted request time from the queue clock before that page delete.
The confirmation is the first locally persisted acknowledgement time from the clock after successful remote completion.
Retries preserve each first value. Neither field clears automatically or after a refused remote call.
A refusal on one attempt does not prove that an earlier ambiguous attempt failed.
Permit confirmed rows without intent for the confirmation contract; normal combined deletion records intent first.
Do not infer either field from old publish/revoke job status or backfill legacy rows.
Retain page rows, completed and failed jobs, and `revoked_at` until the existing erase of all local data.

## Repository transactions and race protection

Extend [`PublishRepository`](../../lib/application/publish_repository.dart) and its SQLite and fake implementations with two operations:

| Operation                             | One transaction                                                                                                                          | Result after commit                   |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| `beginPageServerDeletion(pageId, at)` | Require the page; set the first intent if absent; stop that page's pending publish and revoke jobs with `PublishFailure.deletion`.       | The actual jobs changed by this call. |
| `markPageServerDeleted(pageId, at)`   | Require the page; set the first confirmation if absent; stop that page's pending publish and revoke jobs with `PublishFailure.deletion`. | The actual jobs changed by this call. |

Use conditional updates such as `COALESCE(column, ?)` to preserve first timestamps.
Repeat the pending-job stop even if a timestamp already exists.
Preserve done/failed jobs and their generations and failure reasons. Do not manufacture a change notification for unchanged jobs.
A missing page is a storage/state failure. Any transaction failure rolls back its field and job changes together and propagates; it does not count as recorded intent or confirmation.
Change the existing global `stopPendingJobs` to return its actual changed jobs as well.

Inside the existing `openPageOf` transaction, select only pages whose three timestamps are null.
When none is eligible, an explicit create callback stores a new page with a fresh ID and both deletion fields null, even if old intent rows exist for the client.
Keep `pages()` inclusive and ordered as today; deletion and history reads must include unresolved and confirmed rows.

Inside the enqueue transaction, read the current page and reject either job kind when either deletion field is set.
A publish request that read an eligible page before intent, but reaches enqueue after intent, must fail through the share request failure path.
Do not retry that request automatically on a new ID. A subsequent explicit share can obtain the fresh page.
Missing pages also fail the request; do not reconstruct them from the stale `ClientPage` object.

The revoke compare-and-set must require all three timestamps null in the transaction.
If intent or confirmation won first, return false without adding a revoke job, replacement page, or historical republish jobs.
Keep existing reissue behavior for an eligible open page; an unresolved old page is never a source of automatic republishing.

Keep `saveJob`'s pending-status and generation compare-and-set.
It prevents a stale run from overwriting a transaction's stopped job or a newer request generation.
Mirror every state and race check in `FakePublishRepository`, after any test gate that delays the operation.

## Queue and deletion coordinator

### Order, scope of quarantine, and per-page operation

Retain hold, the wait for the current job, unsettled upload protection, `forgetArrivedUploads`, and identity checks.
Keep the global pending-job stop before the first backend delete; emit its actual job updates after commit.
Hold continues to accept requests while preventing execution.

Keep all photo deletes first and all report deletes second.
In the third loop, perform this combined operation for each page before moving to the next:

```text
await timed(deletePageAndRecord(page))

deletePageAndRecord(page):
  stopped = await repository.beginPageServerDeletion(page.id, clock.now())
  notifyCommittedPageChange(page.clientId, stopped)
  await publisher.deletePage(page.id)
  stopped = await repository.markPageServerDeleted(page.id, clock.now())
  notifyCommittedPageChange(page.clientId, stopped)
```

This is a contract sketch, not implemented code.
The future passed to `TimedDelete` must include intent persistence, the remote delete, confirmation persistence, and their notifications.
Putting persistence after `await timed(deletePage(...))` loses it when the timed await fails but the remote delete succeeds later.

Intent commit failure sends no page delete for that ID and fails `publishedData` before account/device stages.
Photos and reports may already have been deleted; this is not a promise that no network deletion occurred.
Do not mark every page before the photo loop. An early photo/report failure leaves newly unattempted pages without intent and keeps their existing eligibility; any intent from an earlier attempt remains.
The stronger guarantee starts only when an individual page's intent commits.

For A acknowledged, B failed or ambiguous, and C not reached: A is confirmed, B keeps intent if its intent committed, and C acquires no new intent.
Persist A's confirmation immediately, rather than after the page loop or account deletion.

### Failure, timeout, restart, and explicit recovery

| Event                                                                 | Durable result and next action                                                                                        |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Intent transaction fails                                              | No new intent and no page delete for that attempt. Stop at published data; retry explicitly.                          |
| Process ends after intent, before remote call                         | Intent remains; dispatch cannot write under the ID. Explicit retry sends the idempotent delete.                       |
| Remote failure, refusal, timeout, or lost acknowledgement             | Keep committed intent; no confirmation. Do not clear quarantine automatically.                                        |
| Remote succeeds, confirmation transaction fails or process ends first | Intent remains; stop before account/device stages. Explicit retry records confirmation after another acknowledgement. |
| Remote and confirmation commit succeed                                | Retire that ID, retain first timestamps, then continue the existing deletion order.                                   |
| Account or device step fails after confirmation                       | Keep confirmed state wherever rows remain. The profile reports the actual failed step.                                |

`DeleteAllData._timed` tracks the combined future until it settles, including delayed SQLite work.
If it times out during intent persistence, the operation may later commit intent and send the remote delete; hold remains until the entire operation settles.
Late remote success must record confirmation. Late failure or late confirmation failure leaves intent.
Timeout has already failed the caller's attempt; a late success does not resume account or device deletion automatically.
Retain the existing late-account-success behavior and release only after the coordinator's settlement rules permit it.

At startup, ordinary queue work can resume for eligible pages, but both job kinds must obey durable quarantine.
Do not start Delete All Data or automatically delete the account/device on startup.
Recovery remains the explicit company-profile Delete All Data flow, with its existing confirmation and failing-step feedback.
It deletes all data, including any fresh page; it is not a page-only recovery action.

Each retry takes a fresh inclusive page snapshot, repeats idempotent deletes even for confirmed rows, and preserves first timestamps and job history.
Fresh pages created after the previous snapshot are included on the next attempt.
Do not skip marked rows initially, change cleanup order, or silently migrate their reports.

### Backend dispatch and notifications

Before either publish or revoke performs backend writes, read the stored page and stop a job targeting either deletion field with `PublishFailure.deletion`.
Test that no page set, report write, or upload occurs for a quarantined ID.
The hold prevents an active job racing a new intent through the normal deletion entry point; the common dispatch guard protects stale pending work after release and restart.
Neither the publish-only revoke check nor a saved job status replaces these controls.

Keep `Stream<PublishJob> updates` and its ID/generation behavior for `ReportLinkCubit`.
Emit the actual stopped jobs from global stop, intent, and confirmation commits.
Add `Stream<String> pageChanges` carrying client IDs as invalidations after successful intent or confirmation persistence, even when no pending job changed.
An invalidation tells consumers to reread storage; it is not an authoritative state snapshot.

On queue disposal, finish required durable writes and remote-operation settlement, but do not add to closed streams.
Both stream subscriptions and controllers need the existing lifecycle protections.
Failure before a transaction commits emits no successful page invalidation.

## Screen state and fresh sharing

Expose `pagesOf(clientId)` through the queue, backed by the inclusive repository page list.
`ClientLinkCubit` subscribes to both job updates and page invalidations, disposing both subscriptions and retaining read-generation guards.
Read page state and associate revoke jobs with their page IDs.

- `hasOpenLink`: an eligible page exists with all three timestamps null.
- `hasClosedLink`: a page has persisted deletion confirmation or a completed revoke.
- `hasUnfinishedDeletion`: an unresolved intent exists, or an unconfirmed page has a revoke job stopped by deletion.
- Closing and failed-close warnings: only jobs belonging to pages without deletion confirmation; keep warnings about other pages.

Confirmed deletion suppresses that page's old closing, failed-close, and unfinished-deletion warnings.
It does not suppress another page's warnings, imply that whole-app deletion is unfinished, or assert that account/device erasure completed.
An unresolved intent alone must never produce the closed-link message.
Reuse existing closed copy and controls where accurate.
For unresolved intent, show that deletion is unconfirmed, the old link may still open, and recovery is through Delete All Data in the company profile.
Keep account/device failure feedback in `CompanyProfileCubit` separate from page-level state.

With only an unresolved page, hide close/reissue controls for that old ID and show the recovery warning.
With an old confirmed page and a fresh eligible page, show the fresh open state and its controls.
With an old unresolved page and a fresh eligible page, show the fresh open state and controls plus the unresolved old-link warning.
The new link does not close the old link or complete whole-app deletion.

A subsequent explicit report share uses `openPageOf` to obtain or create a fresh eligible page and publishes only the visit requested.
Never republish historical reports automatically from the quarantined page, reuse its URL for the new share, or clear its intent to reuse its ID.
During hold, the fresh job can be stored but cannot execute. Existing full-success device erasure may remove queued work; no sharing bypasses the hold.
Keep `ReportLinkCubit`'s subscription and early job buffering; rejected stale enqueue requests use its existing request-failure path.

An automatic refresh read failure must show `loadFailed` and retry rather than retain stale open controls.
Use read generations for failures as well as successes, so an older failed read does not replace a newer valid state.
Do not infer closed state from a failed read after a close/reissue request; show a retryable load failure when storage cannot provide current state.

## Local erase and migration correctness

[`SqliteLocalDataRepository.eraseAll`](../../lib/persistence/sqlite_local_data_repository.dart) deletes rows in one transaction, then executes `VACUUM` and `wal_checkpoint(TRUNCATE)`.
An erase transaction failure rolls back and retains page state.
A later VACUUM/checkpoint failure can report `deviceData` failure after every row is already gone.
A photo-file erase failure can likewise happen after database erasure.
The screen must report the failing stage without reconstructing deleted rows or claiming that every device failure preserves confirmation.
Keep these order and retry semantics; changing the erasure protocol is outside this work.

Test fresh creation at schema version 4 and upgrades from versions 1, 2, and 3, preserving existing rows and null defaults.
The version 2 fixture in [`open_repositories_test.dart`](../../test/persistence/open_repositories_test.dart) currently seeds a historical database with today's publish repository.
Replace historical publishing inserts with raw SQL for that historical schema before the updated mapper names new columns.
Do not make historical fixtures depend on the current mapper or merely adjust the expected version number.
Test UTC microseconds, SQLite close/reopen, first-value retention, and both repository implementations.

## Acceptance criteria and regression evidence

These are requirements for future implementation, not tests executed for this document.

| Area                      | Required cases and expected evidence                                                                                                                                                    |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Issue #26 foundation      | Completed publish with no revoke, server success, then account failure or erase transaction failure: closed page state survives reads/restart wherever rows remain.                     |
| Persistence boundary      | Commit intent, close/reopen before the remote call; remote success before confirmation, then close/reopen: old ID remains quarantined in both cases.                                    |
| Intent failure            | Transaction rollback preserves page/jobs as they were at transaction entry, sends no `deletePage` for that ID, emits no success invalidation, and prevents later account/device stages. |
| Confirmation failure      | Remote success plus marker rollback leaves intent, prevents later stages, and explicit retry confirms without changing the first intent time.                                           |
| Atomic race guards        | Read-before-intent/enqueue-after-intent; delayed revoke/reissue; fake gates; stale dispatch of publish and revoke: no writes or resurrection under the old ID.                          |
| Held requests             | Jobs accepted after global stop and before intent stop atomically; jobs reaching storage after intent reject. Fresh-ID jobs remain held and cannot resurrect the old ID.                |
| Timed operation           | Timeout during intent, remote call, and confirmation; late success/failure/lost acknowledgement: durable result is truthful and hold lasts through the combined future.                 |
| Settlement                | Unsettled upload and identity checks; late account success: retain existing no-conflicting-write and release behavior.                                                                  |
| Multiple pages            | A confirmed, B unresolved, C not reached; old failure plus fresh open page: independent state, accurate warnings, and current controls.                                                 |
| Early failure             | Photo/report failure before any new page intent keeps the current eligibility policy; a prior intent never clears.                                                                      |
| Idempotence and history   | Repeated delete/recovery preserves first timestamps, revoke time, completed/failed jobs, and generation/status guards; no status backfill.                                              |
| Explicit sharing          | Account failure followed by sharing gets a fresh ID and only the requested report; another Delete All Data includes that page. No URL migration or historical republish.                |
| Cubit invalidation        | Intent/confirmation with zero changed jobs refreshes automatically; subscribe/dispose both streams; out-of-order successes and failures cannot restore stale controls.                  |
| User feedback             | Pending intent never falsely says closed; confirmed page suppresses only its warnings; new open state coexists with old unresolved warning; profile retains account/device failure.     |
| Erase failure stages      | Separate transaction rollback from post-commit VACUUM/checkpoint and photo-file failures; do not assume rows survive all device failures.                                               |
| Persistence and migration | Fresh v4, v1/v2/v3 upgrades with historical SQL fixtures, close/reopen, UTC mapping, null defaults, copy/equality preservation, fake parity.                                            |
| Disposal                  | Required writes and late settlement finish after disposal, with no job/page notification added to closed streams.                                                                       |

Update the existing same-ID recreation expectation in [`delete_all_data_test.dart`](../../test/application/delete_all_data_test.dart) to require a fresh ID after committed deletion state.
Update the existing deletion-stopped revoke expectations in [`client_link_cubit_test.dart`](../../test/presentation/client_detail/cubit/client_link_cubit_test.dart): suppress warnings for confirmed pages and preserve unconfirmed-page warnings.
Add focused cases to [`sqlite_publish_repository_test.dart`](../../test/persistence/sqlite_publish_repository_test.dart), [`publish_queue_test.dart`](../../test/application/publish_queue_test.dart), [`report_link_cubit_test.dart`](../../test/presentation/visit_report/cubit/report_link_cubit_test.dart), and [`client_detail_page_test.dart`](../../test/presentation/client_detail/view/client_detail_page_test.dart).

Implementation acceptance requires the focused tests, `merry run check`, and `merry run coverage` with the repository's 100% `lib` coverage gate.
Keep the existing emulator rule checks and hosted build gates passing without changing rules or production configuration.
Update relevant application comments and `CLAUDE.md` publishing/deletion descriptions when the behavior ships.
Review and update both [Korean](../../web/privacy/index.html) and [English](../../web/privacy/en/index.html) privacy pages together for clauses affected by retained deletion state and fresh sharing, with the repository's web checks.
Document exact validation results in the implementation PR; this specification does not claim runtime verification.

## Review and next step

The combined design and fresh-ID policy are approved; this written specification still requires operator review.
After that review, prepare the implementation plan and agree on its execution before product changes.
This document is a specification, not an implementation plan or a claim that either issue is fixed.

## Reconciliation, 2026-10-04

Pull request #32 implemented this specification and merged as `1b1b93a`; the shipped code under `lib/` and its tests are now the authority, and the status lines above record the state before that merge.
The intent and confirmation timestamps are schema version 4 (`lib/persistence/schema.dart`), the queue records them around each page delete (`PublishQueue.deletePublished`), and `ClientPage.isOpen` is false while a page is quarantined, so the client detail screen offers no old-link controls for it.
A read-only check on 2026-10-04 mapped the acceptance rows of issue #29 to tests in `test/application/delete_all_data_test.dart`, `test/application/publish_queue_test.dart`, `test/persistence/sqlite_publish_repository_test.dart`, `test/persistence/open_repositories_test.dart`, and the client link Cubit and view tests, and ran the 17 "durable page deletion" tests of `delete_all_data_test.dart`, which passed.
Four rows are covered in part and accepted as limits: a restart is a closed and reopened database file, not a killed process; the first confirmation time is kept at the model and repository level without an end-to-end repeated recovery; the two-page case covers a refused page B, not a timed-out one; and the parity of the fake repository has no dedicated test.
Issues #26 and #29 were closed on 2026-10-04 with comments that cite this evidence.
