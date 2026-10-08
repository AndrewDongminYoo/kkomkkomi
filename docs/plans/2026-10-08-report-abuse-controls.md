# Report abuse implementation plan

## Status and workspace

The operator approved admission, budgets and shared-host retention in the matching spec on 2026-10-08.
Reuse the main workspace and preserve the existing build artifacts.
Do not create a worktree or begin live rollout.
The root owns staging, final verification, and any later explicitly authorized publication.

## Expected scope

Inspect and modify `firestore.rules`, `storage.rules`, `lib/firebase/firebase_publisher.dart`, and their existing tests first.
Add narrowly scoped quota and reservation support only when required to preserve the Publisher API and queue retry behavior.
The grant explanation and request path may require the visit report or company profile UI, associated localization inputs, and their tests.
Add the report-abuse action to the existing web view and tests, with minimal styling.
Update both privacy pages, their tests, relevant `CLAUDE.md` architecture descriptions, the first-test console note, and one operator runbook under `docs/notes/`.
Do not rewrite the queue, introduce another identity system, add Cloud Functions, migrate Hosting, or upgrade dependencies.
Summarize the exact owned paths after admission approval and before source edits.

## Execution order

1. Resolve publisher admission, quota defaults, and residual shared-host acceptance with the operator.
2. Create failing emulator tests for unapproved and replacement accounts, grant escalation, and page/photo takedown.
3. Implement the grant and block rule boundaries while preserving recipient anonymous reads and owner deletion.
4. Add failing transaction and emulator tests for resource-bound quotas, reserved photo bytes, repeated jobs, concurrent writes, and cooldown periods.
5. Implement quota/reservation writes in the Firebase adapter, preserving the Publisher interface and unique photo paths.
6. Add field and zone validation with exact-boundary and malformed-later-zone fixtures; prove the rules remain within evaluation limits.
7. Add approval-required app feedback and a request path with narrow-screen and local/PDF compatibility tests.
8. Add the report-abuse action with the provided address, privacy minimization, unavailable-view coverage, and browser verification.
9. Write and exercise the fictional-data operator runbook; update both privacy pages and the console note together.
10. Run the project gates, with at most one heavy mobile job at a time and a load check before each.
11. Perform structured adversarial review at the final diff's depth and repair verified in-scope findings.
12. Report local implementation and evidence; commits, push, PR, deployment, and store uploads remain separate authorization boundaries.

## Failure and retry checks

- Counter and grant tests must fail against the present permissive rules before relying on their later pass.
- A mutation removing the admission check must allow the deliberately rejected replacement UID, so the negative fixture demonstrates the intended boundary.
- Concurrent writes and interrupted retries must exercise real emulator transactions rather than mock only the expected counter shape.
- A blocked-page fixture must contain accessible photos before takedown and become inaccessible through the same web reader afterward.
- A generated mail action must exclude a fixture query string and fragment, and remain available for paid/unbranded reports.
- Do not claim receipt of email, live takedown, or deployed protection from local tests.

## Success criteria

1. Backend controls → verify: positive legitimate anonymous publishing and all direct-API bypass denials in `merry run rules`.
2. App compatibility → verify: adapter, queue, deletion, and approval-feedback tests through `merry run check`, plus `merry run coverage`.
3. Recipient reporting → verify: Node tests and an isolated browser read of fictional report, history, unavailable, and unbranded views.
4. Operator rollout → verify: runbook actions reproduced in emulators and explicit deployment prerequisites recorded without production mutation.
