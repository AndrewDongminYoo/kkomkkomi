# Zone status PR 3: publish

Date: 2026-10-07.
Refs #60. The design is [`docs/specs/2026-10-06-zone-status-design.md`](../specs/2026-10-06-zone-status-design.md) ("Web report and publishing" and "Privacy"), and the split is [`2026-10-06-zone-status.md`](2026-10-06-zone-status.md).
Written against main at `ade2fe4`, after PR 2 (#68).

No screen sets a status yet, so a release build of this pull request publishes done zones only, and a published report holds no new key.

## Published zone

- `PublishedZone` gets `status` (default `ZoneStatus.done`) and `reason` (default empty). Equality, the hash code, and `toString` include both.
- `PublishQueue` copies the status of each record that it publishes. It copies the reason only for an exception, without the space around it, as it does with the note. A done record publishes an empty reason, also when the device keeps a reason from a status that was set back to done.

## Publisher

- `FirebasePublisher` writes `status` (the name of the value: `partlyDone` or `notDone`) and `reason` into a zone only for an exception. A done zone has the four keys of today, so a report that an earlier version published and a report of a done zone have the same shape.

## Rules

- `firestore.rules` does not change: `isReport` checks that `zones` is a list and does not check its items.
- `test/rules/rules.test.js` writes a report whose zones carry both keys, so that a later check of the items cannot refuse them unnoticed.
- `test/rules/web_report.test.js` publishes one exception zone through the emulator, so that the REST encoding of the keys reaches `decodeReport`.

## Web report

- `decodeReport` reads `status`: a missing key reads as `done`; `done`, `partlyDone`, and `notDone` read as themselves; every other value, a value that is no text included, reads as `notDone`. It reads `reason` only for an exception, and an empty text otherwise.
- `texts` loses `noPhoto` and gets `partlyDone` (`일부 완료`), `notDone` (`못 함`), and `notPhotographed` (`촬영하지 않음`), with the Korean texts of the app.
- `renderReport` shows a summary between the head and the zones when the report has a zone: the line `{total}곳 중 {done}곳 완료`, then one line for each exception, `{name} · {status}` and `: {reason}` when the reason is not empty. The lines of a reason break as the note does.
- A zone with an exception shows its status after its name as a text inside a border, so that a print without color keeps it.
- An empty slot says `못 함` for a zone that is not done, and `촬영하지 않음` otherwise. `photoFailed` stays for a photo that does not load.
- The list of the reports of a client page does not change.

## Privacy

Each page lists the notes as data in four places, and each gets the status and the reason, in both languages:

1. Section 1, the phone database: the status of each zone and its reason.
2. Section 3, a link share: the status and the reason of a zone that is partly done or not done.
3. Section 5, the documents that stay on the server after a revoke: the same as section 3.
4. Section 6, the phone database that the deletion erases.

The pages describe data only and name no control of the capture screen, because they go live before PR 4.
The effective date of both pages becomes the date of this pull request, as earlier changes of their content did, and moves to the deploy date if the deploy comes later.

`docs/notes/2026-10-02-first-test-distribution.md` adds the status and the reason of an exception to the description of the App Privacy row "User Content: Other User Content". The Data safety row "App activity: Other user-generated content" has no description, so its answer stays.

## Deploy

The pages go live only with a Hosting deploy, which needs the approval of the operator after the merge. The Firestore and Storage rules do not change, so the deploy is Hosting only. It comes before the first build that holds PR 4.

## Tests

- `publish_values_test.dart`: equality, the hash code, and `toString` of `PublishedZone` with a status and a reason.
- `publish_queue_test.dart`: an exception record publishes its status and its reason without the space around it; a done record with a kept reason publishes no reason; a not done record without a photo and without a note is published with two empty slots.
- `firebase_publisher_test.dart`: the map of a zone for each status, with the exact keys of a done zone.
- `test/web/report.test.mjs`: the decoding of each status value and of a reason, the summary and its absence without a zone, the badge, and the empty slot texts.
- `test/web/privacy.test.mjs`: sections 1, 3, and 5 of each page name the reason and the two status labels.

## Verification

- `merry run check`, `merry run coverage` (100% of `lib`), `merry run web`, and `merry run rules`.
