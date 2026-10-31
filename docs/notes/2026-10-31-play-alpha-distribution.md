# Closed Alpha distribution verification for 1.1.2(6)

## Direction and preflight

On 2026-10-31 the operator explicitly selected closed Alpha distribution of existing version code 6, rather than release of the internal-test draft.
The [spec](../specs/2026-10-31-play-alpha-distribution.md) and [plan](../plans/2026-10-31-play-alpha-distribution.md) own this bounded operation.
Fresh pure-read API results showed internal `1.1.2`, code `6`, `DRAFT`, and Alpha `1.1.1`, code `5`, `PUBLISHED`.
The native Console showed no pending publishing changes before this operation and an existing selected tester list with participation links.
The existing [production provenance](2026-10-31-production-build-provenance.md) remains the binary source/hash record.

## Evidence boundary

The native Console created Alpha release 3 from the existing bundle library, including only `6 (1.1.2)` and the already prepared Korean/English release notes.
No bundle was uploaded again.
Its final preview was ready, with the full closed-test audience selected and no tester or country setting changed.
Saving produced exactly one publishing change: Alpha `1.1.2`, start full rollout.
The first confirmation to submit that single change was clicked while preliminary checks were running, but the observed result remained `NOT_SENT_FOR_REVIEW`.
After the Console explicitly reported that checks had completed and changes could be sent, a second confirmation still left the same status.
The submission-activity page showed no new submission record, and browser warning/error logs were empty.
The cause is unconfirmed; automated submission stopped after those two attempts, with the exact single Alpha change preserved for operator diagnosis.
Those automated attempts did not establish successful submission or publication.
The prior Alpha code 5 remained `PUBLISHED`, and internal code 6 remained `DRAFT` in the same read-back.

## Operator submission and latest read-back

The operator subsequently reported completing the native submission manually.
A pure-read API check at 2026-10-31 11:17 Asia/Seoul confirmed Alpha `1.1.2`, code `6`, as `IN_REVIEW`.
The prior Alpha code 5 was still `PUBLISHED`, and internal code 6 was still `DRAFT`.
This resolves the submission blocker, but Google approval, publication and delivery of code 6 are not yet established.
Managed publishing was already disabled when the single Alpha change was prepared, so approval may publish that authorized closed-test release without another manual publishing step.

## Tester access and remaining limits

The existing signed-in account's web participation page displayed `App not available`.
A bounded read of the selected tester-list dialog found that account was not included; the dialog was closed without editing, and the tester-settings save action remained disabled.
This establishes a blocked access check for that account, not availability of code 6 to an eligible tester.
The operator reported that checking an already invited account was currently difficult, so eligible-account access remains unverified rather than passed or waived.
No tester identities or addresses are recorded here.

No Android device is available, so installation, device compatibility, the binary actually delivered and runtime behavior remain unverified.
No tester/account change, new binary upload, production rollout, listing/image transfer or backend deployment is included.
Alpha and internal testing are separate tracks; Alpha publication alone does not satisfy #40's internal-track criterion.
