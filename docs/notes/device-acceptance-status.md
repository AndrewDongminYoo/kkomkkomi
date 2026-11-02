# Device acceptance status

## Current state

Moved unchanged from `CLAUDE.md` § Current state on 2026-11-02.

On 2026-10-30 the operator confirmed JPEG, PNG and HEIC gallery selection, gallery-source labels, no capture time, cancellation preservation and visit reopen persistence on the physical iPhone 16 Pro with a new development/release build.
`docs/notes/2026-10-30-gallery-device-acceptance.md` owns the build identity, operator-reported evidence and limits; Android and physical rejection acceptance remain open in #82.
The operator also confirmed the five iPhone camera/time scenarios on that DEV build: correct preview/PDF time and different-day date captions, persistence, retake cancellation, gallery replacement and preview resume, with no microphone prompt observed.
`docs/notes/2026-10-30-capture-time-device-acceptance.md` owns this bounded report; Android and unobserved camera failure/interruption acceptance remain open in #61.
The operator also reported a TestFlight `1.1.1(5)` billing baseline: no-purchase restoration, one approved Basic monthly purchase, successful in-place restoration with retained displayed state/data, and management-link navigation to an App Store list that did not show the test subscription.
`docs/notes/2026-10-30-ios-restore-management-acceptance.md` owns those observations; the binary's source/SDK versions, actual management transitions, Firebase claim propagation, identity-transfer cases and Android remain unverified, so #36 stays open.
