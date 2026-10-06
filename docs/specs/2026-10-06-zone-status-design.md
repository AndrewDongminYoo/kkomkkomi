# Zone status and report summary

Date: 2026-10-06.
Status: written specification for review. The operator approved the design in conversation on 2026-10-06. This document implements no change.
Refs #60: [Show the status of each zone and a summary on the completion report](https://github.com/AndrewDongminYoo/kkomkkomi/issues/60).

The code observations use main at `be6f396`, verified on 2026-10-06.
The operator chose #60 as the next implementation on 2026-10-06, which starts M2 work beside M1 and M3.

## Purpose

A reader of the completion report, usually the party that ordered the cleaning, reads the first page and must see two answers there:

- Was the agreed work done?
- Is anything left for the next visit?

Today the report cannot answer either question:

- An empty photo slot reads the same whether the zone was not cleaned or the photo was not taken.
- A follow-up in a note ("the inside of the microwave on the next visit") sits on a later page.
- The header table shows only the number of zones.

Success criteria:

- The first page of the PDF, the preview, and the web report show how many reported zones are done, and list each zone that is not done with its reason.
- Each zone that is not done carries its status as text next to its name, so that a black-and-white print keeps it.
- A person in the field sets nothing for a zone that was done.

## Decisions

The operator made these choices on 2026-10-06:

1. **Done by default.** Every zone record is done. The person sets a status only for an exception: partly done, or not done.
2. **The reason is the follow-up.** An exception has one free-text reason, for example "전자레인지 안쪽은 다음 방문에". The summary on the first page lists each exception with its reason. No separate follow-up field exists.
3. **An empty done zone stays out.** A zone record that is done and has no photo and no note stays out of the report, as today, because it means that the zone was not part of this visit. A zone record with an exception is in the report also without a photo or a note, so that a zone that was not cleaned is never left out.

Rejected options, for the record:

- A status that the person must set for every zone: the most exact, but it adds a step to every zone of every visit.
- A status that the app derives from the photos: no input, but a zone without its after photo would read as not done.
- A separate follow-up field: it overlaps the note.
- Every zone always in the report: with done by default, a zone that nobody touched would count as done.

## Domain

- A new enum `ZoneStatus` in `lib/domain/` has the values `done`, `partlyDone`, and `notDone`.
- `ZoneRecord` gets `status` (default `ZoneStatus.done`) and `reason` (default empty), and `withStatus` and `withReason`, beside `withNote`. Equality and the hash code include both.
- `ZoneRecord.hasContent` becomes true also when the status is not `done`.
- The domain does not require a reason for an exception. A save that the domain refuses would leave the person in the field with no way to continue. The capture screen asks for the reason instead.
- A record keeps its reason when its status goes back to `done`, so that a status that was set by mistake and then set back loses no text. Every reader of a record with the status `done` ignores its reason.

## Persistence

- Schema version 5 adds two columns to `zone_records`: `status TEXT NOT NULL DEFAULT 'done'` and `reason TEXT NOT NULL DEFAULT ''`. The upgrade from version 4 is `ALTER TABLE` statements in `_migrations` of `lib/persistence/schema.dart`, as version 4 did, so every record that a device holds reads as done with no reason.
- The column stores the name of the enum value. A stored value that the app does not know reads as `notDone`, so that a database that a later version wrote opens and the report never claims a completion that the app cannot read.
- `SqliteVisitRepository` writes and reads both columns.

## Capture screen

- Each zone of the visit capture screen gets a control with the three statuses, under its photos, with `완료` selected.
- An exception shows a reason field under the control. The field saves as the note does: each edit goes to `VisitCaptureCubit`, which saves the whole visit through the path of `editNote` (`_saveNotes`), keeps the text when storage does not take it, and shows the notice with the control that saves again.
- `VisitCaptureCubit` gets `setStatus(zoneId, status)` and `editReason(zoneId, reason)`. A status change saves at once.
- An exception with an empty reason shows a hint under the field that the report shows the reason to the client. It does not block anything.
- The screen must pass `tester.useNarrowScreenWithLargestText()` and `tester.expectWholeText()`, as every screen does. Three Korean labels side by side may not fit at 320 pixels with the largest text, so the implementation plan chooses a control that wraps.

## Report document, PDF, and preview

- `ReportZone` gets `status` and `reason`. `ReportZone.fromRecord` copies the status, and copies the reason without the space around it only for an exception.
- `ReportDocument` gets a summary: the number of zones, the number of done zones, and the exceptions in the order of the zones. The PDF, the preview, and the web report read it, so they count the same zones.
- The header table keeps the client and the visit date. The row of the number of zones gives way to a summary block under the table:
  - one line, for example `5곳 중 4곳 완료`;
  - one line for each exception, for example `탕비실 · 일부 완료: 전자레인지 안쪽은 다음 방문에`, or the zone and the status alone when the reason is empty.
- A zone with an exception shows its status as a text badge after its name. A done zone shows no badge, so that the usual report stays clean.
- An empty slot of a done zone says `촬영하지 않음` in place of `사진 없음`. An empty slot of a zone that is not done says `못 함`. An empty slot of a partly done zone says `촬영하지 않음`.
- The warning of the visit report screen about zones without photos (`reportMissingPhotosTitle`) leaves out a zone that is not done, because its photos are missing on purpose. It keeps a partly done zone.
- The text of a status never depends on color alone. A badge has a text and an edge, so that a black-and-white print keeps it.
- The summary block makes the first page taller. With an exception, the first page can hold one zone and not two. The implementation checks it with sample renders, as #63 did.

## Web report and publishing

- `PublishedZone` gets `status` and `reason`. `FirebasePublisher` writes the key `status` (`partlyDone` or `notDone`) and the key `reason` only for an exception, and leaves both keys out for a done zone. A report that an earlier version published then reads as done in every zone.
- `firestore.rules` needs no change: `isReport` checks that `zones` is a list and does not check its items. A rules test adds a report with the two keys, so that a later check of the items cannot refuse them unnoticed.
- `web/report/` shows the same summary under the header, the same badge after the name of a zone with an exception, and the same empty slot texts as the PDF. It puts every text from the backend into `textContent`, as it does today. A missing `status` key reads as done, and a `status` value that the page does not know reads as not done, as on the device.
- The list of the reports of a client page stays as it is.

## Privacy

- The status and the reason are new data that the app keeps, and the status and the reason of an exception are new published data. Both privacy pages (`web/privacy/index.html` and `web/privacy/en/index.html`) add them to the list of what the phone database keeps, to the list of what a shared report holds, and to the list of what stays on the server, in one change.
- The new pages go live only with a Hosting deploy, which needs the approval of the operator. That deploy comes before the first build that holds the capture screen change, because only that change lets a person set an exception.
- The data stays on the device until the person shares a link, as the notes do. The draft App Privacy answers in `docs/notes/2026-10-02-first-test-distribution.md` declare "User Content: Other User Content" for the names, the notes, and the visit date that a link share uploads, so the status and the reason join that row. The implementation checks the Data safety answers of the same note for the same row.

## Out of scope

- A status on the client detail screen or on the history of a client.
- A reason that is required before a share.
- The monthly bundled PDF of M2, view tracking, and the capture time of #61.
- Any change to how a zone enters a visit.

## Testing

- Domain: the default, `withStatus`, `withReason`, `hasContent` for each status, and equality.
- Persistence: the round trip of both columns, the upgrade from version 4 with records that read as done, and an unknown stored status that reads as not done.
- Capture: the Cubit actions, the save path and its failure, the control, the reason field, and the narrow screen with the largest text.
- Report: `ReportZone.fromRecord`, the summary of `ReportDocument`, the PDF text (summary lines, badge text, empty slot texts), the preview, and sample renders.
- Publishing: the publisher map for each status, the web report tests in Node, the rules test, and `test/web/privacy.test.mjs` for both pages.

## Open items for the implementation

- The control of the capture screen that fits at 320 pixels with the largest text: segmented buttons that wrap, or choice chips.
- The English labels. A draft: `Done`, `Partly done`, `Not done`, `Not photographed`.
