# iPhone capture-time acceptance (#61)

## Scope and tested build

On 2026-10-30 the operator reported that all five scenarios in the [acceptance spec](../specs/2026-10-30-capture-time-device-acceptance.md) worked normally.
The operator explicitly confirmed correct capture dates and times in the report preview and actual PDF, and no microphone permission request.
These are operator-reported physical observations, not agent screenshots, a read of the phone database or sensor-exposure measurements.
The exact test time and displayed timestamp values were not supplied.

The pass reused the development/release app installed for the [earlier gallery pass](2026-10-30-gallery-device-acceptance.md): physical iPhone 16 Pro, bundle `kr.donminzzi.kkomkkomi.dev`, version `1.1.1+5`, Flutter 3.47.9 and Dart 3.13.7.
iOS 27.0.1 was read before that installation; it was not queried again for this pass.
The preserved artifact identifies source `a2cf0b334480774a3c28f821f4a81457bddcd505` plus the iOS resolver's native pin updates.
Before reuse, the agent compared the executable sources, tests and Dart manifests with main at `e7ede462f40730501d7998c78e256a552ef9fea7`, matched both iOS pin hashes, verified every retained manifest file hash and passed `codesign --verify --deep --strict` on the preserved artifact.
The earlier successful installation record and operator continuity identify the installed app; version equality alone does not prove its source or installed bytes.
No rebuild, new installation, automated app launch, termination or phone-data extraction was performed for this pass.
CI uses Flutter 3.47.8, separately from the physical build.

## Operator observations

The operator answered the complete five-scenario checklist with all scenarios working normally.
The results below inherit that response; they are not separate instrumented measurements.

| Scenario or additional observation               | Reported result                                                                                             |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| Today-dated visit, in-app before/after capture   | Both photos worked normally, with correct orientation and local time captions in the preview and actual PDF |
| Reopen visit/report and cancel a retake          | Saved photos and captions remained; closing the retake preserved the prior photo and caption                |
| Previous-day visit, newly captured photo         | Preview and actual PDF showed the correct capture date, including year, and time                            |
| Replace camera photo from gallery                | Gallery label replaced the camera caption, without a capture time                                           |
| Leave and return to an uncaptured camera preview | Preview recovered without automatic capture; a deliberate capture worked normally                           |
| Additional observation: microphone permission    | No request was observed in these scenarios                                                                  |

The time remains the app's device-clock observation immediately before dispatching an accepted shutter request.
Correct display does not establish native sensor exposure time, trusted server time, or independent proof of when work happened.
Successful cancellation and preview resume do not establish failure-path or in-flight capture-interruption behavior.

## Controlled checks

Focused camera-driver, composite adapter, camera session/view, capture Cubit/view, domain record and report-preview tests passed.
The report tests inspect localized rendered captions and text extracted from generated PDF bytes, including a capture date different from the visit date.
App-to-camera route tests with a fake driver and SQLite repository tests also passed, covering observed UTC persistence and clearing the time on gallery replacement.
These controlled checks do not read the phone's persisted UTC values or exercise physical camera permissions.
`flutter analyze --no-pub` and `dart format --output=none --set-exit-if-changed lib test` passed before the documentation-only result update.
No application, dependency, schema, native build setting or rendered-output implementation changed in this pass.

## Remaining acceptance and authority

- Android physical camera and output acceptance remain not run: the operator has no Android phone.
- Fresh camera-permission grant, denial/restriction, initialization or save failures, interrupted in-flight capture, rapid shutter presses, forced restart and clock/time-zone changes were not established by the five-item report.
- Raw persisted UTC, native image metadata and an independently timed shutter event were not inspected on the phone.
- The report does not establish every orientation, HEIC variant, OS version or device model, and does not replace the separate remaining gallery checks in #82.
- No web timestamp is added or claimed; the approved capture-time scope remains local preview and PDF only.
- Issue #61 remains open for its remaining device acceptance.
- This pass authorizes no production/backend publication, store upload, release or deployment.
