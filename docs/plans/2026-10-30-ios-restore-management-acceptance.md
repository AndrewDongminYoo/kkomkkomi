# iOS restore and management acceptance plan (#36)

## Authority and workspace

The operator explicitly invoked `$pr-loop #36` for iOS Sandbox build/account identification followed by restoration and management verification.
Use the main workspace on `codex/ios-restore-management-36`, based on `73ffe50bd2d6e5b2bdd2e7b66de6065bd2524a49`.
The [acceptance spec](../specs/2026-10-30-ios-restore-management-acceptance.md) limits the work.
Gated merge is delegated; branch cleanup, store uploads, deployments and unidentified device/account writes are not included.

## Owned paths

- This plan and the matching acceptance spec.
- A dated result note after useful operator observations exist.
- Directly affected current claims in `CLAUDE.md`, the first-distribution note and subscription design, only when this pass changes their evidence.

No application behavior edit is planned.
For a reproduced defect, first write a focused failing regression and make the smallest contract-preserving repair.
Keep private build/account checks, logs and review artifacts in the visible sibling directory recorded in Git-local state.
Never copy credentials, test-account identities, receipt bytes or business prices into public files.

## Steps and success criteria

1. Identify the existing installed app and distinguish its version/channel from source provenance and purchase environment.
   Verify native app inventory, operator TestFlight confirmation, available local build records and configured SDK-key presence without exposing values.
2. Identify the current plan, restore/management controls, account availability and active-purchase preconditions through operator read-only observations.
   Do not change account settings or restore until the intended context is concrete.
3. Run existing billing/store-channel and plans Cubit/view tests with `flutter test --no-pub --concurrency=2` on explicit affected paths.
   Run `flutter analyze --no-pub` and `dart format --output=none --set-exit-if-changed lib test`.
   These checks read controlled store responses and rendered state, not real Apple transactions or Firebase entitlement propagation.
4. If a current-source device build is needed, check machine capacity and prepare a production-flavor build with the existing configuration, without installation or upload.
   Verify its source identity, signing, target bundle, SDK configuration and exact proposed installation before obtaining device-write approval.
5. Receive the approved operator-run restore/management results and record successful, failed and unobserved scenarios separately.
   Preserve Android, identity-transfer and server-claim gaps, and keep #36 open.
6. Update affected documentation, run scoped document/spelling/link checks and one scope-calibrated local review.
   If behavior changes, run its regression and full project gates; otherwise reuse unchanged executable evidence appropriately and satisfy publication gates.
7. Commit and push the scoped result, create a non-closing evidence PR, complete current-head CI/reviews and final body/assignment, then perform the delegated merge after any required visual gate.
8. Verify the merge, review scoped memory consistency under the retained request, preserve a visible completion receipt and retire only this loop's owned settled control state.

## Stop boundaries

Unknown account ownership or purchase state is a missing prerequisite, not permission to create a test purchase or transfer ownership.
A store/backend failure is evidence to diagnose, not authority to change live configuration or replay billing events.
Leave the loop waiting with its exact next action when an individual device/provider approval or a required observation is missing.
