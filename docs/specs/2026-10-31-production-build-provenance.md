# Production build provenance and upload (#40)

## Approved outcome

The operator explicitly requested new production builds with preserved source commits and file hashes, followed by upload, on 2026-10-31.
Target the existing production bundle `kr.donminzzi.kkomkkomi`: TestFlight on iOS and the Google Play internal track with `draft` status on Android.
Fresh read-only store lists showed maximum build/version code 5 on both platforms.
Use `1.1.2+6`: the next integer build and a patch version for a binary that differs from an already distributed build.
This does not infer the source or embedded SDKs of the previous `1.1.1(5)` binaries.

## Evidence and invariants

- Build through the existing `merry run build ipa` and `merry run build aab` commands, one heavy job at a time after a capacity check.
- A clean source commit and `tool/build_record.sh` must bind each artifact to its actual SHA-256.
  If a build changes tracked inputs, retain the failure, review/commit the required inputs and rebuild; never relabel an earlier dirty build as a clean commit.
- Read actual exported versions, production identity and signing before upload.
  Preserve both binaries, source/hash records and toolchain/configuration fingerprints outside disposable build output and Git-local control state.
- If documentation is added after building, prove the recorded source remains an ancestor and every tracked binary input is unchanged before uploading the preserved bytes.
- Complete the PR's local/hosted review and gated merge before executing the authorized uploads through the existing `ios beta` and `android internal` lanes.
- Retain the exact upload target and artifact hash before dispatch.
  Verify that target remotely after interruption or an unknown result before any retry.
- Upload success, store processing, internal-group assignment, draft creation and actual tester availability are separate results.
  Keep #40 open for acceptance that was not observed or authorized.

## Boundaries

No public rollout, store app-review submission, tester/account change, device write, additional purchase, backend deployment or listing/screenshot transfer is included.
Keep credentials and account/tester identities out of tracked files and public PR text.
Use the operator-provided credential locations only in the task's process environment, preserving project/account boundaries.
The earlier `1.1.1(5)` listing snapshots and screenshot approvals remain unchanged; a listing/image target mismatch must fail closed rather than silently rebind them.
No product UI or rendered asset changes are proposed, so no new visual implementation approval is required.

## Acceptance checks

Release metadata, localized note limits, lockfile regeneration, Dart formatting/analysis, source tests and documentation checks pass for the reviewed candidate.
Each preserved IPA/AAB has a verified source/hash, identity/version and signing result.
After merge, each exact file has an observed TestFlight upload/processing result or Play internal-draft result, with any remaining processing/access failure explicit.
The [dated preparation record](../notes/2026-10-31-production-build-provenance.md) and surviving local receipt distinguish build evidence from actual store results without claiming an unobserved device pass.
