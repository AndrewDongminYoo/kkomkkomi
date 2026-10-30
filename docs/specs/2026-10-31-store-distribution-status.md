# Store-distribution status record (#40)

## Problem and approved direction

Issue #40 still describes the initial build as undistributed and both store app records as absent.
Read-only inspection on 2026-10-30 found later TestFlight internal and Play closed-Alpha distribution.
The operator approved recording this status in a documentation-only PR on 2026-10-31, keeping #40 open.

## Scope and evidence

Add one [dated record](../notes/2026-10-31-store-distribution-status.md), update the first-distribution note and link the snapshot from `CLAUDE.md`.
Preserve historical build 1 instructions while separating the later observations.
Record TestFlight internal-group membership, Play internal-track absence, the active Alpha version and the binary-to-source limits.
Use the completed read-only browser observations and inspected repository history; do not present them as a new store check on the writing date.
Keep account credentials, tester identities, receipts and business prices out of the public diff.

## Acceptance criteria

- TestFlight build `1.0.0(1)` and the later `1.1.1(5)` internal-group membership are attributed to the dated inspection.
- Play closed Alpha `1.1.1` (version code `5`) remains distinct from the inactive internal track with no release.
- Commit/version correlation, local output absence and store metadata do not become a claimed source/SDK mapping.
- The existing instruction and distribution-note summaries agree with the dated record.
- #40 stays open, with no automatic closing reference or claim that every checklist item is complete.
- Document formatting, spelling and relative links pass; the candidate receives a scope-calibrated local review and current-head hosted checks/reviews.

## Constraints

No application behavior, dependency, manifest, build script or store configuration change is proposed.
No upload, rollout, review submission, account change, purchase, device write or backend deployment is authorized by this documentation pass.
There is no rendered implementation change requiring visual approval.
Fresh Oracle retrieval failed before an agent started; retained project export-renumbering evidence supports keeping version identity separate from source provenance.
