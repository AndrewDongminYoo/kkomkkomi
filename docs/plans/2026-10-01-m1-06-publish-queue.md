# M1 brief 6: publish queue and security rules

Design: `docs/specs/2026-10-01-m1-local-first-design.md`, section "Phase B".
Read the design and `CLAUDE.md` before you write code.
This brief depends on briefs 1 to 5.

## Starting state

Firestore and Storage both exist, and the deployed rules of both deny every read and write.
`firestore.rules` and `storage.rules` in the repository match the deployed rules.

## Goal

A worker publishes a visit, and the photos and the report document reach the backend even when the network drops in the middle.

## In scope

- Add `cloud_firestore` and `firebase_storage`.
- A publish port in `lib/application/` and its Firebase adapter.
- The client page ID: created once for each client, stored in SQLite, and at least 128 random bits.
- The publish job table in SQLite and the queue that runs the jobs.
- `firestore.rules` and `storage.rules` as the design's "Security rules" section states, with rules tests.
- Access removal and reissue of a client page.

## Out of scope

- The web report page and the share of the link, which belong to brief 7.
- Link expiry.
- View tracking and the confirm button, which belong to M2.

## Requirements

- Each job step is safe to repeat: a photo upload uses a path that depends only on the page, the visit, the zone, and the slot.
- The queue retries with a growing delay, resumes at launch, and resumes when the network returns.
- A job that fails for a reason a retry cannot fix stops and shows its reason.
- The security rules change opens published reports to readers without sign-in. State this in the pull request body under its own heading, and do not deploy the rules. The operator deploys them after review.
- Do not write to the live project from a test. Use fakes for unit tests and the Firebase emulator for rules tests.

## Acceptance criteria

- Queue tests cover success, a failure in each step, a retry that completes, and a restart with jobs left over.
- Rules tests cover: a reader gets one page by ID, a reader cannot list pages, a reader cannot read a revoked page, a non-owner cannot write, and a non-JPEG or oversize upload is refused.
- `merry run check` passes.
- `merry run coverage` passes at 100 percent.

## Reconciliation, 2026-10-02

This brief is the record of what was approved. The shipped code of pull request 12 (`5e1f3eb`) is the authority where the two differ, and the pull request body lists every decision.

- "A photo upload uses a path that depends only on the page, the visit, the zone, and the slot": the path also carries the local file name of the photo, `clientPages/<page>/<visit>/<zone>-<slot>-<file>.jpg`. An upload that timed out kept running and could overwrite a retake at a fixed path (`6a206ec`). Each step is still safe to repeat, which is what the requirement was for.
- The queue saves a job only while its row is still pending and has the same generation, so a revoke or a restart during a run is not overwritten (`b5fe70a`, `4d95b44`). The schema is version 2.
- `publishedAt` and `revokedAt` come from the device clock, fixed before the first attempt, so a retry writes the same time (`1681d7a`).
- Every upload path is recorded before the upload starts, so cleanup and revoke delete every object that may exist (`4d95b44`). Issue #13 holds the case that remains: an upload that finishes after a revoke.
- The Storage rules read the client page through a cross-service `firestore.get`, which needs an IAM grant at the first deploy.
- The rules in this pull request are not deployed. `CLAUDE.md` records that gap.
