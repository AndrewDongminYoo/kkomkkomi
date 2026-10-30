# Production build and upload plan (#40)

## Workspace and authority

Use the existing main workspace on `codex/production-build-40`, based on `5042a76c35987020b00732caa8a74c5f97ae35d1`.
The operator approved the [spec](../specs/2026-10-31-production-build-provenance.md), including TestFlight and Play internal-draft upload, through the explicit PR Loop request.
Gated merge is delegated; cleanup, memory publication, public rollout and other excluded actions are not included.
No worktree or dependency upgrade is needed.

## Owned paths

- `CHANGELOG.md`, `pubspec.yaml` and its regenerated lockfile.
- The existing iOS release notes and new Android build 6 changelogs for English and Korean.
- `CLAUDE.md`, the first-distribution note and the matching dated preparation note, spec and plan.

## Execution and checks

1. Re-read store maxima, establish `1.1.2+6`, check existing credential lanes without a store call and restore only locked release-tool dependencies.
   Keep account references in private task control state and inject them only into the existing Fastfile lane process.
2. Prepare the scoped version/notes/docs change, run `flutter pub get` without dependency upgrades and inspect its lockfile result.
   Validate note limits, local formatting/analysis and the complete concern-based candidate before committing the build source.
3. Check capacity, then build/sign the IPA and AAB sequentially with the declared project commands.
   Verify actual versions, identity/signing, build records and SHA-256; preserve immutable copies and private logs in the surviving artifact directory.
4. Add measured build evidence to the dated note in a separate documentation commit, preserving the build-source commit.
   Revalidate the final candidate, full source test gate, affected docs and scope-calibrated review.
5. Publish a non-closing PR, finish current-head CI/reviews, final body/assignment and delegated merge.
   Verify the merge preserves the source commit and binary inputs before external upload.
6. Run the native upload lanes on the preserved exact files: iOS TestFlight first, then Android internal with explicit `draft` status.
   Read back exact version/build and processing/track status; an unknown result is not a retry authorization.
7. Audit the dated docs against actual outcomes, preserve a visible completion/upload receipt and retire only settled owned control state.
   Keep the previous distribution snapshot historical and report remaining #40 criteria separately.

## Precedent and limits

The retained project export-renumbering precedent requires reading exported IPA versions rather than trusting pubspec or a stale local file.
The retained store-state regeneration precedent keeps screenshot/listing approvals separate from binary upload and records why track names/statuses must be explicit.
Fresh Oracle retrieval failed before an agent started; it was not an empty precedent result.
The pinned old listing profile is expected to refuse a newer target until separately rebound; do not count that refusal as a binary-upload check failure or a listing pass.
