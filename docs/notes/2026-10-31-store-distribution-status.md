# Store distribution observed on 2026-10-30 (#40)

This record was written on 2026-10-31 from the read-only store inspection on 2026-10-30.
It is a dated snapshot, not a new store check on the writing date.
The operator approved a documentation-only PR after the inspection; no upload or distribution change is included.

## Live store observations

The existing authenticated personal-account browser sessions showed the production bundle `kr.donminzzi.kkomkkomi` in both stores.
No account credential, tester identity or receipt is reproduced here.

| Surface                           | Observed state                                                                            |
| --------------------------------- | ----------------------------------------------------------------------------------------- |
| TestFlight internal group         | `1.1.1(5)` testing in the group named “내부”, with one tester                             |
| Other builds linked to that group | `1.0.0(1)`, `1.0.0(2)` and `1.1.0(3)`, all shown as testing                               |
| Apple build metadata              | `1.1.1(5)`, verified binary; upload displayed as 2026-10-16 09:39                         |
| Play internal testing             | Inactive, no release                                                                      |
| Play closed Alpha                 | Active release `1.1.1`, version code `5`, shown as 100% released to selected testers      |
| Play Alpha release details        | Release displayed as October 19 at 14:01; retained App Bundles: none                      |
| Play artifact details             | `5.aab(1.1.1)`, upload displayed as October 19 at 11:46; minimum SDK 24 and target SDK 36 |

Times preserve the displayed fields; their views did not label a timezone.
The Apple upload-status list separately showed creation at 09:34, which is not the metadata upload field above.
Closed Alpha distribution does not satisfy the Play internal-testing criterion of #40.
This console inspection establishes neither an Android device pass nor a production rollout.

## Binary-to-source provenance

No matching production IPA, archive, AAB or APK was present in the prescribed local output directories, and no corresponding `build-record.txt` was established.
`tool/build_record.sh` writes clean HEAD and an artifact SHA-256 after a build; it was read, not run.
The tracked `fastlane/store-state/ios-remote-1.1.1-build5-after-u5.json` snapshot identifies production iOS `1.1.1(5)` as valid but has no source-commit binding.

Commit `c2611c59b4800969dde560d8d74744b61496c45b` prepares `1.1.1+5` on October 16.
That version/date correlation is a candidate only; it does not prove which checkout produced either uploaded binary.
The Git commit, embedded Flutter version and RevenueCat SDK versions of both store binaries remain unverified.
Do not assign current main or its later dependency upgrades to those binaries from the shared version number.
Missing local artifacts also do not mean an upload failed: the live store observations above establish distribution independently.

## Remaining work and authority

TestFlight build `1.0.0(1)` is linked to the internal group, but Play internal testing has no release.
The [first-distribution checklist](2026-10-02-first-test-distribution.md) retains its remaining review, privacy, rollout and device-verification work.
Issue #40 remains open; neither the original checklist nor source/SDK provenance is complete.
The [TestFlight billing baseline](2026-10-30-ios-restore-management-acceptance.md) remains an existing-store-build observation.
No new physical-device or provider acceptance follows from this snapshot.
Future uploads, rollout changes, tester changes and device writes need their own concrete target and approval.
The [spec](../specs/2026-10-31-store-distribution-status.md) and [plan](../plans/2026-10-31-store-distribution-status.md) bound this documentation pass.

## Current state

Moved unchanged from `CLAUDE.md` § Current state on 2026-11-02.

The store reads on 2026-10-30 found TestFlight `1.1.1(5)` in the internal group and Google Play `1.1.1` (version code `5`) active in closed Alpha testing; the Play internal track was inactive with no release.
`docs/notes/2026-10-31-store-distribution-status.md` owns that dated snapshot and the unverified binary-to-source mapping.
The Play internal-track criterion and the remaining distribution checklist keep #40 open; closed Alpha is not internal testing.
The operator authorized preparing production `1.1.2+6` and uploading the verified files to TestFlight and the Play internal track as a draft on 2026-10-31.
`docs/notes/2026-10-31-production-build-provenance.md` owns the preparation evidence and separates an artifact's clean source/hash from upload, processing and tester availability.
This direction authorizes no public rollout, app review submission, tester/account change, backend deployment or device installation.
On 2026-10-31 the operator separately selected closed Alpha distribution of existing `1.1.2`, version code `6`.
`docs/notes/2026-10-31-play-alpha-distribution.md` owns that operation and its review/publication and web-access evidence.
The separate request includes the Alpha review step required for test distribution, while retaining the Android physical-device validation limit and the separate internal-track criterion of #40.
