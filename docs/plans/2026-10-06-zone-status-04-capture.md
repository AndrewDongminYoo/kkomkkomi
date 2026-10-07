# Zone status PR 4: capture screen

Date: 2026-10-07.
Closes #60. The design is [`docs/specs/2026-10-06-zone-status-design.md`](../specs/2026-10-06-zone-status-design.md) ("Capture screen"), and the split is [`2026-10-06-zone-status.md`](2026-10-06-zone-status.md).
Written against main at `300add7`, after PR 3 (#69).

This is the first change that lets a person set an exception and publish its reason.
The release rule of the split holds: Hosting was deployed from `300add7` on 2026-10-07, so the privacy pages that name the status and the reason are live before any build that holds this change.

## Cubit

- `VisitCaptureCubit.setStatus(zoneId, status)` and `editReason(zoneId, reason)` change the record, show the change at once, and save the whole visit through `_saveNotes`, as `editNote` does. A call does nothing when the value does not change, and while the visit takes no change.
- A failed save keeps the change in the state, so `isStored`, `isSavingNote`, the unsaved notice, the save-again control, the back press, and the leave question apply to a status and a reason as they apply to a note. The fields keep their names, and their documentation names the status and the reason.

## Screen

Under the photos and the previous photos of each zone, before the note:

- A label (`청소 상태`, `Cleaning status`) and three choice chips in a `Wrap`: `완료`, `일부 완료`, `못 함`. A `Wrap` moves a chip to the next line when the three do not fit, so the control fits at 320 pixels with the largest text. The chip of the record's status is selected, and a press of another chip calls `setStatus`. The chips take no press while a capture runs.
- For an exception, a reason field under the chips, built as the note field is: the label is a text of its own above the field, and each edit calls `editReason`. The label says what to write: `남은 부분` (`What's left`) for partly done, and `못 한 이유` (`Why it wasn't done`) for not done. While the field is empty, a helper under it says that the client reads it in the report. It blocks nothing.
- A record keeps its reason when its status goes back to done, so the field shows that text again when the person sets an exception again.

The note field and the reason field share one private widget.

## Texts

- The chips of the exceptions reuse `reportPartlyDoneLabel` and `reportNotDoneLabel`, so the screen and the report use the same words. New keys: `zoneStatusLabel`, `zoneStatusDoneLabel`, `zoneReasonPartlyDoneLabel`, `zoneReasonNotDoneLabel`, and `zoneReasonHelper`.
- The unsaved notice and the leave question name changes, not notes, because a status or a reason can also be the change that storage did not take: `visitUnsavedMessage` becomes `바꾼 내용을 저장하지 못했어요.` (`Can't save your changes right now.`), and `visitLeaveUnsavedDialogMessage` becomes `저장하지 못한 내용이 사라져요.` (`Your unsaved changes will be lost.`).

## Tests

- `visit_capture_cubit_test.dart`: each action saves the whole visit; a failed save keeps the change and shows the visit as not stored; a later save holds it; no call while capturing or for the same value.
- `visit_capture_page_test.dart`: the chips with `완료` selected; a press calls `setStatus`; the reason field and its label for each exception; the helper only while the reason is empty; an edit calls `editReason`; no chip press during a capture; the narrow screen with the largest text, with an exception and a long reason, and `expectWholeText` for every new text. A page test with the in-memory repositories stores a status and a reason.
- The store screenshot `01_capture.png` shows the chips after this change, so render it again and commit only the images whose content changes.

## Documents

- `CLAUDE.md` names the status and the reason where it describes the capture screen and `VisitCaptureCubit`.

## Verification

- `merry run check` and `merry run coverage` (100% of `lib`).
