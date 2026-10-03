# Durable client page deletion implementation plan

> For implementers: Read the specification and global constraints first. For behavior changes, complete the failing-test, implementation, passing-test, and commit steps in order; use existing checks for documentation changes. Review the complete branch before publishing product changes.

**Goal:** Persist deletion intent and acknowledgement for each client page, prevent reuse of its ID, and show truthful recovery state after failures or restart.

**Architecture:** Extend the existing `ClientPage`, SQLite publishing repository, single publish queue, and client-link Cubit. A per-page transaction records intent before `deletePage`; another records acknowledgement afterward. Keep both transactions inside the timed operation and preserve the existing deletion order and explicit fresh-ID sharing.

**Tech stack:** Dart/Flutter, Bloc, sqflite, sqflite_common_ffi, flutter_test, and the existing mocktail/fake helpers. No new dependencies.

**Specification:** [Durable client page deletion](../specs/2026-10-03-durable-page-deletion-design.md), approved and merged in [PR #30](https://github.com/AndrewDongminYoo/kkomkkomi/pull/30).

**Base:** main at `f1df991ead3addcaea7348fed9834c7473b762ab`, verified on 2026-10-03. Schema is still version 3; the design has no application implementation. Refs #26 and #29. This plan is for review, not authorization to start product changes.

## Global constraints

- Advance the authoritative version 3 schema directly to version 4 with both columns: `server_delete_requested_at INTEGER` and `server_deleted_at INTEGER`, nullable UTC microseconds.
- An eligible open page requires `revoked_at`, `server_delete_requested_at`, and `server_deleted_at` all null.
- Both deletion fields null does not prove server existence. Intent alone proves neither access removal nor page absence.
- Preserve each first timestamp, `revoked_at`, page rows, and completed/failed job history. No job-status backfill or automatic intent clearing.
- Keep all photo deletes first and all report deletes second. Record intent immediately before each page's own delete, never for every page before the photo loop.
- Keep hold, upload settlement, generation/status compare-and-set, and the current account/device order. Startup never resumes whole-app deletion automatically.
- Recovery remains explicit Delete All Data, including any fresh pages. A subsequent explicit share can publish only its requested visit under a fresh eligible ID.
- Add no global phase, intent table, job kind, dependency, server field, rule change, URL migration, automatic historical republish, or deployment.
- Preserve production-only Firebase boundaries and paired Korean/English copy. Keep the 100% `lib` coverage acceptance gate.

## Review focus

Each case below has an explicit test in the owning task.

1. A quarantined job must stop before identity waits or backend writes; otherwise an unavailable identity hides durable retirement (task 3).
2. A repeated intent/confirmation with zero changed jobs must still invalidate page readers without fabricating job updates (task 3).
3. A fresh-ID share after old intent must retain the existing first-share notice and publish no other historical visit (tasks 3 and 4).
4. An older failed read must not hide a newer valid link state, including after close/reissue requests (task 4).
5. Archived clients' page rows must remain in the inclusive deletion snapshot; archive status must not exclude cleanup (task 3).

## File map and ownership

| Task                              | Production files                                                                                                                                                                                                    | Tests and support                                                                                                                                                                                                                                                                       |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1: model and migration            | `lib/application/client_page.dart`, `lib/persistence/schema.dart`, page mappings in `lib/persistence/sqlite_publish_repository.dart`                                                                                | Create `test/application/client_page_test.dart`; modify `test/persistence/open_repositories_test.dart` and `test/persistence/sqlite_publish_repository_test.dart`                                                                                                                       |
| 2: repository transactions        | `lib/application/publish_repository.dart`, `lib/persistence/sqlite_publish_repository.dart`                                                                                                                         | `test/helpers/fakes.dart`, forwarding `_GatedRepository` in `test/application/publish_queue_test.dart`, `test/persistence/sqlite_publish_repository_test.dart`                                                                                                                          |
| 3: queue and deletion lifetime    | `lib/application/publish_queue.dart`, lifecycle comments in `lib/application/delete_all_data.dart`                                                                                                                  | `test/application/publish_queue_test.dart`, `test/application/delete_all_data_test.dart`, `test/persistence/sqlite_local_data_repository_test.dart`, targeted gates in `test/helpers/fakes.dart`                                                                                        |
| 4: link state and feedback        | `lib/presentation/client_detail/cubit/client_link_cubit.dart`, comments in `client_link_state.dart`, `lib/presentation/client_detail/view/client_detail_page.dart`, both `lib/l10n/arb/app_en.arb` and `app_ko.arb` | `test/presentation/client_detail/cubit/client_link_cubit_test.dart`, `test/presentation/client_detail/view/client_detail_page_test.dart`, `test/presentation/visit_report/cubit/report_link_cubit_test.dart`, `test/presentation/company_profile/cubit/company_profile_cubit_test.dart` |
| 5: shipped behavior documentation | `CLAUDE.md`, `web/privacy/index.html`, `web/privacy/en/index.html`                                                                                                                                                  | `test/web/privacy.test.mjs`                                                                                                                                                                                                                                                             |
| 6: complete-branch verification   | No additional product files                                                                                                                                                                                         | Focused suites, repository aggregate gates, independent final review                                                                                                                                                                                                                    |

Do not refactor the large queue or shared fake file beyond the contracts below. `ReportLinkCubit` already catches rejected share requests and buffers early job updates; task 4 verifies those paths instead of redesigning them.

## Task 1: Persist both page fields and migrate historical databases

**Interfaces produced in `ClientPage`:**

```dart
// Add optional constructor fields and final UTC properties.
final DateTime? serverDeleteRequestedAt;
final DateTime? serverDeletedAt;
bool get isQuarantined; // Either deletion time is non-null.
bool get isServerDeletionPending; // Requested, with no confirmation.
bool get isOpen; // Not revoked and not quarantined.
ClientPage requestServerDeletion(DateTime at); // Keep the first intent.
ClientPage confirmServerDeletion(DateTime at); // Keep the first confirmation.
```

Keep `isRevoked` and `revoke(DateTime at)`; revoke copies preserve both deletion fields. Equality, hash, and string representation include both. Confirmation without intent is a valid state.

- [ ] **Write failing model and migration tests.** Create `client_page_test.dart` with named cases `normalizes deletion times and preserves them through revoke`, `keeps the first intent and confirmation`, and `quarantines confirmed pages without intent`. Use an offset input and distinct retry times:

  ```dart
  final at = DateTime.parse('2026-10-03T10:00:00.123456+09:00');
  final later = at.add(const Duration(minutes: 1));
  final page = ClientPage(id: 'page-1', clientId: 'client-1', createdAt: at);
  final requested = page.requestServerDeletion(at);
  final confirmed = requested.confirmServerDeletion(at);
  expect(requested.serverDeleteRequestedAt, DateTime.utc(2026, 10, 3, 1, 0, 0, 123, 456));
  expect(requested.isServerDeletionPending, isTrue);
  expect(confirmed.isServerDeletionPending, isFalse);
  expect(confirmed.requestServerDeletion(later).confirmServerDeletion(later), confirmed);
  expect(confirmed.revoke(later).serverDeletedAt, confirmed.serverDeletedAt);
  expect(page.confirmServerDeletion(at).isQuarantined, isTrue);
  expect(page.isOpen, isTrue);
  ```

  Pin equality/hash differences for each timestamp, the changed string representation, and revoked/open combinations. In `open_repositories_test.dart`, require `schemaVersion == 4`, both nullable INTEGER columns via `PRAGMA table_info(client_pages)`, fresh creation, and v1/v2/v3 upgrades preserving rows with both fields null. Add a v3 file close/reopen case with a revoked page, completed/failed jobs, and an open capture.

- [ ] **Correct historical fixtures before the new mapper runs.** Replace the v2 fixture's `written.publishing.openPageOf(...)` with `old.insert('client_pages', ...)` using exactly the four old columns and UTC integers. Seed any historical jobs/photos with their old column maps as well. Open the old file with `upgradeSchema(..., to: 2)` or `to: 3`; invoke current publishing repositories only after upgrade. Keep unchanged client/visit repositories where their schema is unchanged.
- [ ] **Run the failing focused cases.** Run `flutter test test/application/client_page_test.dart test/persistence/open_repositories_test.dart test/persistence/sqlite_publish_repository_test.dart`. Expected failure: missing model API/current schema is 3, not an unrelated setup or fixture error.
- [ ] **Implement the model, `_version4` migration, and page mappings.** Add the two ALTER statements to the ordered migration list and update timestamp documentation. Serialize both UTC microsecond values and decode nullable columns after migration; do not silently treat an old schema that has not been upgraded as v4. Add repository round-trip assertions for null, intent-only, and confirmed fields.
- [ ] **Run the same focused suites to green and commit.** Expected: all pass, old data intact. Commit `feat: persist client page deletion state` with only task 1 files.

## Task 2: Make quarantine and pending-job stops atomic

**Consumes:** task 1 page properties and copies.

**Produces in `PublishRepository`, SQLite, and the fake:**

```dart
Future<List<PublishJob>> beginPageServerDeletion(String pageId, DateTime at);
Future<List<PublishJob>> markPageServerDeleted(String pageId, DateTime at);
Future<List<PublishJob>> stopPendingJobs(PublishFailure reason);
```

Each new operation requires an existing page, preserves its first field, and stops pending publish AND revoke jobs for that page in one transaction. Return only changed jobs, oldest first with existing tie order. Preserve done/failed history. Keep current signatures of `openPageOf`, `enqueue`, `revoke`, and `saveJob`.

- [ ] **Write failing transaction and guard tests in `sqlite_publish_repository_test.dart`.** Using its existing `page(...)` and `job(...)` fixtures, cover `intent stops both job kinds and preserves history`, `confirmation preserves first time and legacy revoke time`, `repeated markers return no unchanged jobs`, `missing page rejects without side effects`, and `enqueue and revoke reject a stale quarantined page`.

  ```dart
  await repository.openPageOf('client-1', create: () => page('page-1'));
  await repository.enqueue(job('waiting'));
  await repository.enqueue(job('revoke', visitId: null, kind: PublishJobKind.revoke));
  final at = DateTime.utc(2026, 10, 3);
  final stopped = await repository.beginPageServerDeletion('page-1', at);
  expect(stopped.map((job) => job.failure), everyElement(PublishFailure.deletion));
  expect(await repository.openPageOf('client-1'), isNull);
  await expectLater(repository.enqueue(job('late')), throwsStateError);
  expect(await repository.saveJob(job('waiting').succeed()), isFalse);
  expect(await repository.beginPageServerDeletion('page-1', at.add(const Duration(minutes: 1))), isEmpty);
  ```

  Require revoke false with no replacement/history jobs when storage changed after the caller read the page. Pin fresh creation while old intent exists, and global stop returning only changed jobs.

- [ ] **Add real SQLite rollback proof.** Use a `BEFORE UPDATE OF status ON publish_jobs` trigger that raises `ABORT` when `NEW.failure = 'deletion'`. Fail intent/confirmation after the field update but during job stop; assert the field and jobs equal their values at transaction entry. Drop the trigger and retry. Existing completed/failed rows must never change.
- [ ] **Run these tests red.** Run `flutter test test/persistence/sqlite_publish_repository_test.dart --plain-name 'intent stops both job kinds and preserves history'`, then the full file. Expected: the unimplemented contract/guards fail.
- [ ] **Implement all repository changes together.** Use `COALESCE` field updates inside the same transaction as job stops. Require all three fields null in open selection and revoke CAS. Inside enqueue, reject absent/quarantined pages with `StateError` before insert/restart. Never reconstruct a stale page. Keep `saveJob` status/generation CAS unchanged.
- [ ] **Update fake and forwarding implementations, then verify gated races.** In `test/helpers/fakes.dart`, check page state after `beforeEnqueueGate`/`revokeGate`; apply timestamp/job changes only after any failure gate resolves. Add nullable `Completer<void>? beginDeletionGate` and `markDeletedGate`, and `Object? beginDeletionFailure` and `markDeletedFailure` for targeted tests. Update `_GatedRepository` to forward both methods and the list-returning global stop; mocktail repository mocks inherit the interface without manual forwarding. Run `flutter test test/persistence/sqlite_publish_repository_test.dart test/application/publish_queue_test.dart test/application/delete_all_data_test.dart` to green.
- [ ] **Commit the atomic repository contract.** Commit `feat: quarantine pages in publishing transactions` with only task 2 files.

## Task 3: Track durable page deletion through hold, timeout, and restart

**Consumes:** task 2 transactions and returned stopped jobs.

**Produces in `PublishQueue`:**

```dart
Stream<String> get pageChanges; // Broadcast client-ID invalidations.
Future<List<ClientPage>> pagesOf(String clientId); // Inclusive, existing page order.
```

Keep existing `Stream<PublishJob> updates`, `deletePublished({TimedDelete? timed})`, hold/release, and public share/revoke/reissue signatures. Use private `Future<void> _deletePageAndRecord(ClientPage page)` and `void _notifyPageChange(String clientId, List<PublishJob> stopped)` helpers; the latter emits only while not disposed.

- [ ] **Write failing queue lifecycle tests.** In `publish_queue_test.dart`, pin `intent exists before deletePage and confirmation follows acknowledgement`, `both stale job kinds stop before identity and backend writes`, `zero stopped jobs still invalidate page readers`, `archived client pages are deleted`, and `fresh share publishes only the requested visit`. Seed a stale pending job directly into the fake map after intent to exercise dispatch rather than enqueue. Gate identity and assert the quarantined job fails with deletion without reaching that gate. Record job/page stream events and assert only committed changes are emitted.

  ```dart
  await queue.hold();
  final remoteGate = publisher.gates['deletePage'] = Completer<void>();
  final deletion = queue.deletePublished();
  await pumpEventQueue();
  final pending = publishing.pagesById['page-1']!;
  expect(pending.serverDeleteRequestedAt, isNotNull);
  expect(pending.serverDeletedAt, isNull);
  remoteGate.complete();
  await deletion;
  expect(publishing.pagesById['page-1']!.serverDeletedAt, isNotNull);
  ```

  Repeat already-confirmed deletion with no pending jobs: `pageChanges` includes `client-1`, but `updates` has no fabricated stopped job. Verify A confirmed/B remote failure/C not reached independently, preserving the three global loop order.

- [ ] **Write failing coordinator/restart regressions.** In `delete_all_data_test.dart` cover intent failure (no page call or later stage), remote refusal (intent retained), confirmation failure (intent retained/no account or device), completed publish/no revoke followed by account or erase transaction failure, and fresh-ID sharing included on the next attempt. Replace the existing `page-1` recreation expectation with `newPage.id != 'page-1'` and only `<newPage.id>/visit-1` published.

  ```dart
  publishing.markDeletedFailure = Exception('SQLite confirmation failed');
  await expectLater(deleteAllData()(), failsAt(DeletionStep.publishedData));
  expect(identity.deletions, 0);
  expect(localData.erasures, 0);
  expect(publishing.pagesById['page-1']!.isServerDeletionPending, isTrue);
  ```

  Use existing short-timeout/completer patterns for timeout during intent, remote call, and confirmation. Assert `queue.isHeld == true` until the combined future settles; late success commits, late error retains intent, and neither resumes account/device automatically. Include lost acknowledgement, held enqueue before/after intent, delayed revoke/reissue, and disposed queue completion without closed-stream errors.

- [ ] **Run queue tests red.** Run `flutter test test/application/publish_queue_test.dart test/application/delete_all_data_test.dart`. Expected: absent events/intent, old-ID writes, or missing dispatch guard; retain existing upload/cancel/reissue tests as regression checks.
- [ ] **Implement the combined page future and both-kind guard.** Before identity/backend work in `_runJob`, read current page state and throw the existing `_Stop(PublishFailure.deletion)` for quarantine; a missing page is a `StateError` with no backend write. Keep the existing publish revoke check. Emit global stopped-job updates after persistence. In the third deletion loop call `await run(_deletePageAndRecord(page))`; the helper commits intent, notifies, deletes remotely, commits confirmation, and notifies. Do not move intent before the photo/report loops. Add/close the page stream alongside job updates. Keep inclusive snapshots and both existing settlement protections.
- [ ] **Add durable SQLite restart and erase-stage tests.** In `publish_queue_test.dart`, use its existing file-database fixture: close/reopen after intent before the call, and after simulated remote success before confirmation; create a new queue and assert neither old-ID job kind writes. Insert stale pending publish/revoke rows through raw SQL to exercise dispatch even though normal enqueue rejects them. Explicit retry confirms and preserves first times/history. In `sqlite_local_data_repository_test.dart`, retain the trigger-backed erase rollback test and add post-commit VACUUM/checkpoint faults through a test-only mocktail database wrapper that delegates the transaction to real SQLite and throws only at the selected later operation; assert all rows already empty. In `delete_all_data_test.dart`, add photo-file failure after database erase, with `localData.onErase` actually clearing fake page/job maps, and preserve the existing late-account behavior. Change no erase protocol.
- [ ] **Run the three suites to green and commit.** Run `flutter test test/application/publish_queue_test.dart test/application/delete_all_data_test.dart test/persistence/sqlite_local_data_repository_test.dart`. Commit `fix: retain page deletion intent through queue settlement`. Update deletion/timeout comments to match the combined future, explicit retry, and fresh-ID behavior.

## Task 4: Derive truthful link state and preserve report sharing

**Consumes:** `ClientPage.isOpen`, `isServerDeletionPending`, `serverDeletedAt`; queue `pagesOf`, `pageChanges`, and existing job updates/revoke reads.

**Produces:** Existing `ClientLinkState` flags derived per page, two disposed subscriptions, and generation-safe `loadFailed` on current read failure. Preserve public Cubit/view APIs; add no global recovery mode or new screen.

- [ ] **Write failing Cubit tests with explicit page/job ownership.** Add `intent alone is unresolved rather than closed`, `confirmation suppresses only its page warnings`, `old confirmed and new open keeps new controls`, `old unresolved and new open shows both states`, `page invalidation with no jobs refreshes automatically`, and `obsolete read failure does not replace later success`.

  ```dart
  expect(cubit.state.hasOpenLink, isFalse); // Intent-only page, with no completed revoke.
  expect(cubit.state.hasClosedLink, isFalse);
  expect(cubit.state.hasUnfinishedDeletion, isTrue);
  // After that page is confirmed, with no other warning page:
  expect(cubit.state.hasClosedLink, isTrue);
  expect(cubit.state.hasUnfinishedDeletion, isFalse);
  ```

  Adjust old tests that treated a completed page delete as unfinished; preserve a separate unconfirmed-page failure fixture. Gate `pages()` with an error, complete a newer successful read, then release the older failure and assert the newer state survives. A current refresh failure and a current post-request read failure must each produce `ClientLinkStatus.loadFailed`, with no stale action controls. Test retry and both subscription cancellations.

- [ ] **Run Cubit tests red.** Run `flutter test test/presentation/client_detail/cubit/client_link_cubit_test.dart`. Expected: absent page state/notifications or stale-state behavior, not missing fixture setup.
- [ ] **Implement page-aware reads and generation-safe failure handling.** Add `StreamSubscription<String>? _pageChanges`, filtering invalidations to `_clientId`. Read inclusive pages, then associate revoke jobs by page ID. `hasOpenLink` uses `isOpen`; closed uses confirmation or done revoke; unfinished uses pending intent or deletion-stopped revoke on an unconfirmed page; closing/failed-close only inspect unconfirmed pages. Let `_read({ClientLinkStatus? status})` own the read token and its success/failure handling; ignore every superseded result, report each current error once, and emit `loadFailed` on current failure. Remove `_request`'s fallback that guesses link state when the read fails. Retain existing request failure handling before storage accepts a request.
- [ ] **Add failing widget and sharing cases.** In `client_detail_page_test.dart`, assert intent-only warning with no old-ID buttons, confirmed closed copy, mixed fresh-open controls plus old warning, and retry controls after read failure. In `report_link_cubit_test.dart`, gate enqueue before intent, assert existing failed request state/no share sheet, then make a separate explicit share and assert a fresh ID. Preserve early stopped-job buffering and ID/generation filtering. For old intent/no eligible page, `load()` must keep `isFirstShare == true`; PDF and no-backend flows remain unchanged. In `company_profile_cubit_test.dart`, keep account/device stage feedback distinct from page confirmation, including database rows already erased at a device failure.
- [ ] **Update copy and view comments, then run presentation suites.** Reuse existing open-first layout and closed/retry controls. Update `clientLinkDeletionUnfinishedMessage` in both ARB files to identify a previous link and explain that a new link does not close it:

  English: "A previous link may still open because its deletion is unconfirmed. A new link does not close it. To finish deleting all data, use Delete All Data in Company profile again."

  Korean: "이전 링크가 지워졌는지 확인되지 않아 보고서가 아직 열릴 수 있어요. 새 링크를 만들어도 이전 링크는 닫히지 않아요. 회사 정보에서 모든 데이터 지우기를 다시 해 주세요."

  Run `merry run l10n`, then `flutter test test/presentation/client_detail/cubit/client_link_cubit_test.dart test/presentation/client_detail/view/client_detail_page_test.dart test/presentation/visit_report/cubit/report_link_cubit_test.dart test/presentation/company_profile/cubit/company_profile_cubit_test.dart`. Expected: all pass, including existing share/close/reissue behavior. Commit `fix: show unresolved and confirmed page deletion accurately`.

## Task 5: Document shipped retention and recovery behavior

**Consumes:** Tested tasks 1–4 behavior. No new application interface.

- [ ] **Run the existing privacy tests before editing.** Run `node --test test/web/privacy.test.mjs`. Preserve the established section, security, language, and effective-date checks. If factual assertions need adjustment when the approved behavior changes, update only those existing expectations; do not add tests that merely mirror new paragraphs.
- [ ] **Update both privacy pages and current-code guidance.** Update sections 1 and 6 as applicable, describing only the stored local page timestamps and proven behavior. Clarify that a failed device stage may occur after database erasure, and that a new link does not prove the old one closed. Keep existing server retention statements and user rights unchanged. Update `CLAUDE.md` schema/publishing/deletion descriptions from current-code facts; retain production/deployment boundaries. Use the same effective date on both pages if changed, based on the implementation date.
- [ ] **Verify documentation and web checks, then commit.** Run `merry run web`, direct cspell and formatting checks from task 6. Expected: all existing privacy/web tests and documentation checks pass; no server/configuration/dependency changes. Commit `docs: explain durable page deletion and recovery`.

## Task 6: Verify the complete branch and prepare review

**Consumes:** All prior commits. **Produces:** Verified branch and a precise review/PR report; no automatic merge or deployment.

- [ ] **Run the focused regression set once after all interfaces are integrated.** Run the ten suites below; each must pass. Use targeted reruns only for a changed/failing area. Keep intentional red-stage failures distinct from final results.

  ```sh
  flutter test test/application/client_page_test.dart test/persistence/open_repositories_test.dart test/persistence/sqlite_publish_repository_test.dart test/application/publish_queue_test.dart test/application/delete_all_data_test.dart test/persistence/sqlite_local_data_repository_test.dart test/presentation/client_detail/cubit/client_link_cubit_test.dart test/presentation/client_detail/view/client_detail_page_test.dart test/presentation/visit_report/cubit/report_link_cubit_test.dart test/presentation/company_profile/cubit/company_profile_cubit_test.dart
  ```

- [ ] **Run aggregate application acceptance.** Run `merry run check`, then `merry run coverage`. Expected: both succeed, with 100% `lib` coverage. Existing script prerequisites resolve packages and generate localization; do not change dependency pins. Inspect uncovered lines and add behavior tests rather than coverage exclusions.
- [ ] **Run existing emulator security checks.** Run `merry run rules` with Java 21 and project `demo-kkomkkomi`. Expected: success without rule changes or production access. If tooling is unavailable, report the exact local blocker and require the existing hosted rules job to pass; do not substitute a production run.
- [ ] **Run documentation checks using a working checker runtime.** Use a Node version satisfying cspell's `>=22.18.0` requirement. Current Trunk uses Node 22.16 for cspell and can report a false green; do not count that wrapper result as spelling verification or broaden this feature into a tooling change.

  ```sh
  npx --yes cspell@10.2.2 lint '**/*.md' --config cspell.json --no-progress
  trunk check --no-fix --filter=prettier,markdownlint,git-diff-check --cache=false --no-progress
  git diff --check
  ```

  Run the actual planned PR title through `npx --yes cspell@9 stdin --config cspell.json --no-progress --no-summary`, matching the pinned workflow. Expect zero issues and exit 0. If the workflow changes before execution, read its checker version and use that exact invocation. Do not disable checks or add broad dictionary exclusions.

- [ ] **Review the entire diff independently.** Check all five Review Focus cases, every specification acceptance row, both job kinds, persistence/late-success boundaries, and mixed-page copy. Fix verified findings within scope and rerun the affected tests/gates. Never describe a skipped bot review as approval.
- [ ] **Prepare the implementation review only after execution approval.** If authorized to publish the completed implementation, create a Draft PR with a conventional title such as `fix: persist client page deletion intent and confirmation`, `Refs #26` and `Refs #29`, the concrete behavior, exact check evidence, and remaining limitations. Confirm the hosted Flutter/coverage, spell/title, rules, web, Android, iOS, and Windows checks at its final head; attach the created PR to the task. No issue closure, merge, release build, rule/Hosting deployment, or production mutation is part of this plan's execution authorization.

## Plan review and execution choice

Recommended: one implementer executes these dependent tasks sequentially in the current task, then one independent reviewer checks the complete branch.
The repository, queue, and Cubit interfaces depend closely on each other; sequential implementation avoids repeated handoffs while preserving a final independent review.

Alternative: use a separate implementer and reviewer for each task, followed by a complete-branch review. This adds review isolation at each boundary, with more handoffs and time.

Review this plan and select an execution approach before product changes. This local planning branch is not published and opens no new PR.
