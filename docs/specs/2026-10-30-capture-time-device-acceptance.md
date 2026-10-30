# iPhone capture-time acceptance (#61)

## Approved scope

The operator selected the remaining iPhone camera, preview and PDF acceptance of [issue #61](https://github.com/AndrewDongminYoo/kkomkkomi/issues/61) and invoked the PR loop on 2026-10-30.
Reuse the implemented [camera contract](2026-10-07-in-app-still-camera.md), [metadata contract](2026-10-07-report-photo-and-company-metadata.md) and [capture-date rule](2026-10-08-report-capture-date.md).
The issue's original discussion predates those decisions: capture time belongs to the local preview and PDF, with no web timestamp or Firebase payload change.
No new camera feature, dependency, schema, report layout or release operation joins this pass.
Change application behavior only for a reproduced defect within these contracts.

## Tested-build prerequisite

Reuse the identified development/release app installed for the [gallery pass](../notes/2026-10-30-gallery-device-acceptance.md), rather than treating the shared version number as source identity.
Its retained manifest identifies source `a2cf0b334480774a3c28f821f4a81457bddcd505` plus regenerated iOS pins, Flutter 3.47.9, Dart 3.13.7 and bundle `kr.donminzzi.kkomkkomi.dev` version `1.1.1+5`.
Before reuse, compare the executable inputs and iOS pin hashes with current main and verify the preserved artifact's signature and manifest file hashes.
The earlier installation record and operator continuity identify the installed app; this pass does not independently read its executable bytes from the phone.
The operator runs the manual scenarios on non-private test data.
Agent-driven installation, launch, termination, photo import and other daily-phone writes require their own approval.

## Acceptance checks

1. For a visit dated today, take before and after photos through the in-app camera.
   Record whether the preview becomes ready, each photo saves, its orientation is correct, and the report preview and actual generated PDF show the observed local `HH:mm` caption for each camera photo.
2. Reopen the visit and report to verify the committed photos and captions persist.
   Cancel a retake and verify the previous photo and caption remain.
3. For a visit dated another day, capture a new photo without changing the phone's clock.
   Verify the preview and actual PDF show the capture date, including year, and time rather than presenting today's capture under only the visit date.
4. Replace a camera photo through the gallery and verify its gallery label replaces the camera caption, without an inferred capture time.
   Record this replacement separately from the prior gallery-only pass.
5. While an uncaptured camera preview is open, leave the app and return.
   Record preview recovery and whether a later deliberate shutter press saves normally; no automatic capture should occur.
   Record any microphone prompt, camera permission prompt or failure actually observed.

The time represents the device clock sampled at accepted shutter-request dispatch, not sensor exposure, trusted server time or independent proof of work.
Successful cancellation is not permission-denial or save-failure evidence.
Do not change daily-phone privacy settings merely to manufacture a denial case.
Mark first-grant, denial, capture interruption, forced restart, rapid presses, clock-zone changes or raw persisted UTC checks unverified unless actually exercised.
Android physical acceptance remains unavailable; an iPhone-only result does not close the complete device contract or issue #61.

## Evidence and delivery

Keep operator-reported device observations distinct from controlled camera tests, fixture decoding and PDF text assertions.
Record the exact tested build, device/OS, individual scenario result and any evidence gap in a dated result note only after observations arrive.
Update applicable current claims in `CLAUDE.md`, the first-distribution note and directly affected specifications in the same PR.
Do not publish a preparation-only PR as completed acceptance, use an issue-closing reference, or infer visual approval from the instruction to run the loop.
Rendered-output changes require explicit operator approval of their final artifacts before merge.
This pass authorizes no store upload, backend publication, deployment or production billing action.

The [dated result record](../notes/2026-10-30-capture-time-device-acceptance.md) contains the operator's completed five-item iPhone report and the remaining gaps.
No rendering implementation changed; the operator's confirmation concerns the existing build's preview and actual PDF.

## Precedent and retrieval limit

Fresh precedent retrieval was unavailable during authoring.
The [earlier gallery specification](2026-10-30-gallery-device-acceptance.md#precedent) records retained precedent for current-screen procedures and related documentation updates.
This pass keeps controlled checks separate from operator-run physical observations without claiming fresh retrieval or source verification.
