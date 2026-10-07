# Zone status PR 2: report

Date: 2026-10-07.
Refs #60. The design is [`docs/specs/2026-10-06-zone-status-design.md`](../specs/2026-10-06-zone-status-design.md) ("Report document, PDF, and preview"), and the split is [`2026-10-06-zone-status.md`](2026-10-06-zone-status.md).
Written against main at `6245e43`, after PR 1 (#67).

No screen sets a status yet, so a release build of this pull request shows done zones only: a summary line of the count and no badge.

## Report document

- `ReportZone` gets `status` and `reason`. `ReportZone.fromRecord` copies the status, and copies the reason only for an exception, with the conversion of the note: `\r\n` and `\r` become `\n`, and the space around the text goes. A done zone gets an empty reason.
- `ReportDocument` gets `doneCount` (the zones whose status is done) and `exceptions` (the zones that are not done, in order). The total is `zones.length`.

## Labels

`ReportLabels` changes, and `reportLabelsOf` and both ARB files follow:

- Remove `zoneCountHeading` and `noPhoto`, and the ARB keys `reportZoneCountHeading` and `reportNoPhotoLabel`, which nothing else reads after this change.
- Add `partlyDone` (`일부 완료`, `Partly done`), `notDone` (`못 함`, `Not done`), and `notPhotographed` (`촬영하지 않음`, `Not photographed`).
- Add `summaryOf`, a `String Function(int done, int total)` from the ARB key `reportSummary` with two placeholders (`{total}곳 중 {done}곳 완료`, `{done} of {total} zones done`).
- Add `statusOf(ZoneStatus)` as a method of `ReportLabels` that gives `partlyDone` or `notDone`, and an empty text for done.
- Add `emptySlotOf(ZoneStatus)`: `notDone` for a zone that is not done, else `notPhotographed`.

## PDF

- The header table keeps the client and the visit date in one row.
- When the document has a zone, the header ends with the summary line from `summaryOf`, in Bold.
- Each exception line follows the header as a direct child of the page, with `pw.TextOverflow.span`: `{name} · {status}` and `: {reason}` when the reason is not empty.
- A zone with an exception shows its status after its name, as a text inside an edge.
- An empty slot says `emptySlotOf(zone.status)`. The dashed edge of an empty slot stays.

## Preview

- Under the visit date: the summary line and the exception lines, with the same texts as the PDF.
- After the name of a zone with an exception: the status, as a text inside an edge.
- An empty slot keeps its icon, and its semantic label becomes `emptySlotOf(zone.status)`.

## Missing photo warning

- `VisitReportCubit.load` leaves a not done record out of `zonesLackingPhoto`, because its photos are missing on purpose. A partly done record stays.

## Tests

- `report_document_test.dart`: `fromRecord` for each status, a reason with `\r\n` and `\r`, a done zone that drops its reason, `doneCount`, and `exceptions`.
- `report_pdf_test.dart`: the summary line and its absence without a zone, the exception lines in order, the badge text, the empty slot texts, and more exceptions with a longer reason than one page holds, with every line in the PDF.
- `visit_report_page_test.dart`: the summary and the exception lines, the badge, the semantic label of an empty slot, `reportLabelsOf` in both languages, and the narrow screen with the largest text.
- `visit_report_cubit_test.dart`: a not done record without photos stays out of `zonesLackingPhoto`.
- Sample PDFs for the operator before the merge.
- The store screenshot `02_report.png` shows the summary line after this change, so render it again and commit only the images whose content changes.

## Verification

- `merry run check` and `merry run coverage` (100% of `lib`).
