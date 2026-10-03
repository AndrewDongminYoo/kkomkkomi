# Brief: issue #26, remember when the server deleted a client page

Status: proposed design and regression plan. This document implements no change.
Refs #26: [the issue](https://github.com/AndrewDongminYoo/kkomkkomi/issues/26) follows [pull request #25](https://github.com/AndrewDongminYoo/kkomkkomi/pull/25), which is merged.
The code observations below use main at `50f522e4526ef5f148d90c73b00c79da0fc43b8f`, verified on 2026-10-03.

Read `CLAUDE.md` ("Publishing", "Deletion", "Documents") and the "Phase B" section of [the M1 design](../specs/2026-10-01-m1-local-first-design.md) before implementation.
This brief keeps their units, backend contract, and deletion order.

## Problem in current main

[The version 3 schema](../../lib/persistence/schema.dart) gives `client_pages` four columns: `id`, `client_id`, `created_at`, and `revoked_at`.
[The publish repository](../../lib/persistence/sqlite_publish_repository.dart) treats `revoked_at IS NULL` as an open page.
It records `revoked_at` when it accepts a revoke request, before the backend has completed that job.
That time cannot also mean that the server deleted the page.

[`PublishQueue.deletePublished`](../../lib/application/publish_queue.dart) stops pending publish and revoke jobs with `PublishFailure.deletion`, then deletes all recorded photos, all known reports, and finally the pages.
It keeps the local page and job rows for a retry.
[`DeleteAllData`](../../lib/application/delete_all_data.dart) deletes the account next, then erases the database and the photo files.
An account failure or a database erase failure leaves the local page rows after the server pages are gone.

[`ClientLinkCubit`](../../lib/presentation/client_detail/cubit/client_link_cubit.dart) reads an open-page boolean and revoke jobs.
A completed publish with no revoke job has no deletion state for it to read.
The screen therefore says that the link is open and offers both actions after its server page was deleted.
A revoke job stopped by deletion instead shows an unfinished deletion warning even when the page delete succeeded.
Neither a stopped job nor a completed publish proves what the delete did on the server.

## Goal and scope

After the backend acknowledges a page delete and local storage records that acknowledgement, the client detail screen treats that page as closed, even if a later deletion step fails.
The confirmation survives a restart while the local database remains.
A later explicit report share obtains a new page ID.

The minimum change adds one local page field, repository transactions and guards, queue notifications, and a page-aware Cubit read.
It adds no global deletion phase, server field, security rule, job kind, or dependency.
It does not automatically publish historical jobs again or move old URLs to the new page.
This PR contains only this brief. Application code, tests, privacy pages, and production settings are unchanged.

## Page state

Add schema version 4 with this migration:

```sql
ALTER TABLE client_pages ADD COLUMN server_deleted_at INTEGER;
```

Add `DateTime? serverDeletedAt` to `ClientPage`, stored as UTC microseconds since the epoch in `server_deleted_at`, as the existing time columns are.
Update its constructor, equality, hash, string representation, row mapping, and methods that copy the page, including `revoke`, to preserve the field.
Update the comments that currently equate a null revoke time with an open page.

| Local fields                                 | Meaning for this page                                                                                                             |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Both times null                              | No local revoke request and no locally recorded server deletion confirmation. Eligible as the open page under the existing model. |
| `revoked_at` set, deletion time null         | A revoke was requested. Its job says whether it completed, is pending, or failed.                                                 |
| `server_deleted_at` set, either revoke value | The backend acknowledged deletion and the app persisted that confirmation. This page ID is retired.                               |

`NULL` means that the app has no persisted deletion confirmation. It does not prove that the server still has the page.
The marker records the first locally persisted confirmation time, using the queue clock after the acknowledgement.
Once set, it never clears or changes, even if a retry acknowledges the same delete at a later time.
Keep `revoked_at`, page rows, and completed or failed job history.
Only the existing erase of all local data removes these rows.
Do not backfill the marker from legacy job status: no job status confirms the page delete.

## Repository contract and races

Add `markPageServerDeleted(pageId, at)` to `PublishRepository` and implement it in SQLite and `FakePublishRepository`.
In one transaction:

1. Require the page row to exist and set `server_deleted_at` only if it is null. Use `COALESCE(server_deleted_at, ?)` or an equivalent conditional update.
2. Stop every pending job of that page, both publish and revoke, with `PublishFailure.deletion`.
3. Return the actual changed jobs after the transaction commits, so the queue can notify their subscribers. Keep every completed or failed job as it was.

Repeat the job stop even when the marker was already set.
An SQL failure rolls back the marker and job changes together and propagates to the caller.
It must not look like a successful confirmation.

Change `openPageOf` to require both `revoked_at IS NULL` and `server_deleted_at IS NULL`, including its transaction that creates a page.
Keep `pages()` inclusive of all pages for deletion and history reads.
The revoke compare-and-set must require both columns to be null in the transaction, rather than trust the `ClientPage` that the caller read.
If deletion won first, return false with no revoke job, replacement, or automatic republish.

Inside the enqueue transaction, read the current page before inserting or restarting a job.
Reject a page whose deletion marker is set, for either job kind.
A publish request can read an open page, wait while deletion records the marker, then reach enqueue: the transaction must reject that old ID.
Fail that request through the existing share failure path. A subsequent explicit share reads the open page again and creates a fresh ID.
Never clear the marker to accept a request.
Mirror these checks in the fake after any test gate, so a delayed operation sees current storage.

Keep the existing `saveJob` status and generation compare-and-set.
A run that read a pending job before the marker transaction cannot overwrite its stopped state with success or a retry.
That compare-and-set protects stored job state; the queue hold and dispatch guard below protect backend writes.

## Queue lifecycle

### Keep the deletion order and hold

Keep `hold`, the wait for the current job, unsettled upload protection, and `forgetArrivedUploads` before any delete.
Keep the existing global `stopPendingJobs(PublishFailure.deletion)` before the first backend delete.
Change it to return changed jobs if needed, and emit those actual stopped job updates after persistence.
The first stop protects work already pending when deletion starts.

`hold` prevents execution and still accepts requests.
The per-page marker transaction stops jobs accepted after the global stop and before that page's confirmation.
The enqueue and revoke guards reject requests that reach storage after confirmation.
Together with dispatch and `saveJob` guards, these cover a retired page without changing the meaning of hold.

Keep the three loops: all photos first, then all reports, then pages.
In the page loop, persist each page's marker immediately after its own delete succeeds, before starting the next page delete.
If page A succeeds and page B fails, A remains confirmed and B remains unconfirmed.
Do not wait until the whole loop or Delete All Data completes to record A.

### Track the whole page operation through a timeout

The future passed to `TimedDelete` must include the backend delete, the marker transaction, and notifications after that transaction.
The intended shape is:

```text
await timed(deletePageAndRecord(page))

deletePageAndRecord(page):
  await publisher.deletePage(page.id)
  stopped = await repository.markPageServerDeleted(page.id, clock.now())
  if queue is not disposed:
    emit stopped jobs on updates
    emit page.clientId on pageChanges
```

This is pseudocode, not an implemented API.
Writing `await timed(publisher.deletePage(...))` and persisting after that await loses the marker when the timed await throws but the delete later succeeds.
`DeleteAllData._timed` must retain the combined future until it settles.
The queue therefore stays held through a late marker write and its notifications, as it stays held for other late deletes today.
A late remote failure writes no marker.
A late remote success followed by a marker failure remains a failed confirmation and is reconciled by a retry.

A marker failure during the normal call fails `DeletionStep.publishedData` before account or device deletion.
Retain the existing account late-success behavior and settlement rules.
After a timeout the caller already has a failure; settling the combined future does not silently resume account or device deletion.

On retry, repeat idempotent backend deletes and keep the first marker time.
Initially continue to iterate marked page rows as well as unmarked ones, preserving existing cleanup behavior and job history as the source of known reports.
Read the current page list on each attempt, so a fresh page made between attempts is included next time.

### Block both job kinds and retain both notification contracts

Add a common dispatch check of the stored page's deletion marker before either publish or revoke performs backend writes.
Stop a stale job with `PublishFailure.deletion` when it targets a marked page.
The existing publish-only `isRevoked` check is insufficient: [`FirebasePublisher.revokePage`](../../lib/firebase/firebase_publisher.dart) uses Firestore `set`, which can recreate an absent page as revoked.
Test that neither `writePage` nor `revokePage`, report writes, or uploads run for the retired page.

Keep `Stream<PublishJob> updates` and its ID/generation semantics for `ReportLinkCubit`.
Emit the job objects actually stopped by repository transactions, so a report share waiting for its job does not wait forever.
Add a broadcast `pageChanges` stream of client ID invalidations, and expose `pagesOf(clientId)` through the queue.
Emit a page invalidation after a successful marker write even when no pending job changed.
A completed publish with no revoke job is the key case that job updates alone cannot notify.
Use the same page invalidation contract after successful page creation, revoke, and reissue persistence.
Subscribers read storage again; the event itself is not a state snapshot.

Dispose both streams and cancel the Cubit's subscriptions.
If disposal occurs while an acknowledged page delete is being recorded, finish the durable marker transaction.
Check disposal before adding notifications to closed controllers.
A notification failure must not undo a committed marker.

## Client detail state

Read `pagesOf(clientId)` and revoke jobs, associating each job with its page ID.
Derive the open boolean from that page read rather than from a separate open-page read.
Retain the existing read generations so a later invalidation cannot be overwritten by an older read.
Subscribe to `pageChanges` before the initial read, filter it by client ID, and refresh on both page invalidations and existing job updates.

| State field             | Derivation                                                                            |
| ----------------------- | ------------------------------------------------------------------------------------- |
| `hasOpenLink`           | Any page has both times null.                                                         |
| `hasClosedLink`         | Any page has a persisted deletion marker, or any revoke job completed.                |
| `isClosing`             | Any pending revoke job belongs to an unmarked page.                                   |
| `hasFailedClose`        | Any failed revoke job with a failure other than deletion belongs to an unmarked page. |
| `hasUnfinishedDeletion` | Any revoke job stopped with `PublishFailure.deletion` belongs to an unmarked page.    |

A confirmed marker overrides only that page's old closing or failure warning.
It does not suppress a warning from another unconfirmed page of the same client.
A marker alone must not set `hasUnfinishedDeletion`: it confirms the page's deletion, not the outcome of the whole application deletion.
The company profile screen already names an account or device failure separately.

The existing closed message and button conditions can be reused.
With a confirmed old page and a fresh open page, show the new open state and its controls.
Warnings for other unconfirmed pages still apply, as they do after a reissue today.
With only confirmed pages and no remaining warning, show the closed message and no close/reissue controls.
The next report share creates the new link; this does not automatically republish history.

When an automatic refresh fails, show `loadFailed` with the existing retry control instead of retaining stale open controls.
Do not let an older failing read replace a newer successful read.
Review the request follow-up read path under the same rule, so a close/reissue fallback cannot advertise a page that storage has since retired.
The flavors without publishing retain their unavailable state.

## Distributed transaction boundary

The backend delete and SQLite marker write are separate transactions.
Remote success followed by SQLite failure, or process death before the marker commit, cannot be made atomic by adding a timestamp.
That page can still have both local times null, and a queued request may still target it after the hold is released or the app restarts.
The design guarantees retirement after persisted confirmation, not after every remote success whose answer or local write was lost.
A retry of Delete All Data repeats the idempotent delete and records its acknowledgement, which reconciles this case.

A durable pending deletion intent written before the network request could provide a stronger quarantine guarantee across that gap.
It would also change the current behavior after an early remote failure by barring a page without confirmed deletion.
Leave that extra state and behavior outside this minimum scope.
Do not infer success or invent legacy confirmations to hide the gap.

## Implementation diff units

1. **Model and migration:** `lib/application/client_page.dart`, `lib/persistence/schema.dart`, value tests, and database upgrade/reopen tests. Add version 4 and preserve the nullable time in every mapper and copy.
2. **Repository transactions and fakes:** `lib/application/publish_repository.dart`, `lib/persistence/sqlite_publish_repository.dart`, `test/helpers/fakes.dart`, and repository contract tests. Include first-time persistence, job stops, enqueue/revoke races, and status/generation protection.
3. **Queue lifecycle:** `lib/application/publish_queue.dart`, the `DeleteAllData` timeout contract, and their tests. Include combined future settlement, dispatch guards, `pagesOf`, both streams, and disposal.
4. **Cubit and view:** client detail Cubit/state documentation and tests, client detail view tests, and report share regression tests. Preserve job notifications and verify the closed/open/warning combinations.
5. **Docs:** update the current-state descriptions in `CLAUDE.md` and this brief when implemented. Reconcile any changed behavior descriptions in both privacy pages together; this design PR changes no shipped copy.

Two existing fixtures need deliberate changes in the implementation PR:

- [`delete_all_data_test.dart`, around lines 222–239](../../test/application/delete_all_data_test.dart): "a retry deletes what a share published again after a failed deletion" currently expects `page-1` to be recreated. Expect a fresh ID, retain the old page's marker and job history, and verify that the next deletion includes both page IDs.
- [`client_link_cubit_test.dart`, around lines 210–250](../../test/presentation/client_detail/cubit/client_link_cubit_test.dart): successful page deletion currently leaves unfinished-deletion and failed-close warnings. Suppress them for confirmed pages and add remote-failure/unconfirmed cases that still show the warnings.

The version 2 fixture in [`open_repositories_test.dart`, around lines 104–107](../../test/persistence/open_repositories_test.dart) currently uses today's publish repository to seed an old database.
Before a new page mapper reads or writes `server_deleted_at`, seed historical page rows with raw SQL for the old schema instead.
Use old-schema SQL for new version 3 fixtures too.
Upgrade assertions must target version 4, preserve existing data, and leave legacy markers null.

## Regression plan and implementation acceptance

These are required future tests, not tests executed by this documentation PR.
Use fake backend ports and real SQLite where persistence matters; no test should reach production Firebase.

| Scenario                                                              | Required result                                                                                                                                            |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Completed publish, no revoke; server deletion succeeds, account fails | Marker persists; automatic Cubit invalidation shows closed without open controls; local data remains.                                                      |
| Same setup, database erase fails at device step                       | Marker remains in the database; link stays closed; company profile names device failure.                                                                   |
| Queue/app restarts with surviving local data                          | Marker survives; no stale job recreates that page. Include SQLite file close/reopen, not only an in-memory fake.                                           |
| Page A delete succeeds, page B delete fails                           | A marked immediately; B unmarked; account and device untouched; B's existing warnings remain.                                                              |
| Remote page delete fails or times out and later fails                 | No confirmed marker; do not claim that this page was deleted. Preserve pending-stop safety and unconfirmed revoke warnings.                                |
| Marker transaction fails after remote success                         | Normal call fails at published data; later stages untouched; retry records confirmation; document the non-atomic gap above.                                |
| Page delete times out, then succeeds late                             | Marker and invalidation occur on late success; hold lasts until combined delete/write/notification future settles.                                         |
| Marker write itself outlives the timeout                              | Hold remains through persistence; no premature account/device continuation; record success or failure when it settles.                                     |
| Requests accepted during hold                                         | Jobs queued before the marker are stopped; enqueue after the marker rejects the old page; stale publish and revoke dispatch make no backend write.         |
| Page read before deletion, enqueue/revoke after marker                | Transaction guards reject the stale page; no replacement or historical republish through a rejected revoke.                                                |
| Next explicit share after confirmation                                | Fresh ID and freshly uploaded photos; old IDs stay retired; no automatic historical job or URL migration.                                                  |
| Repeated marker and repeated deletion                                 | First timestamp unchanged; pending jobs stopped; completed/failed history and revoke time retained; current page list includes new pages between attempts. |
| Confirmed old page with unconfirmed warning page or new open page     | Suppress only the confirmed page's warnings; preserve other warnings; show a fresh open page's state and controls.                                         |
| Marker commit with no pending job                                     | `pageChanges` refreshes the Cubit without `load()` by hand; report job subscribers still receive actual job stops.                                         |
| Refresh read fails, or reads finish out of order                      | Load failure and retry replace stale controls; older reads cannot replace newer state.                                                                     |
| New database and upgrades from versions 1, 2, and 3                   | Version 4 column exists; legacy markers null; all prior data and job history remain; old fixtures use old-schema SQL.                                      |
| Queue/Cubit disposed during a late confirmation                       | Durable writes finish; subscriptions end; no add to a closed stream or emit from a closed Cubit.                                                           |

Focused tests should cover `test/application/publish_values_test.dart`, `test/persistence/sqlite_publish_repository_test.dart`, `test/persistence/open_repositories_test.dart`, `test/application/publish_queue_test.dart`, `test/application/delete_all_data_test.dart`, both link Cubit test files, and the client detail view tests.
After implementation, run `merry run check` and `merry run coverage` and meet the repository's 100% `lib` coverage gate.
The unchanged rules contract remains under `merry run rules`; report any environment limitation explicitly.
Run the repository's Markdown format, lint, and spelling checks for changed docs and the conventional PR title.
None of these future implementation gates is evidence that this design is already implemented.
