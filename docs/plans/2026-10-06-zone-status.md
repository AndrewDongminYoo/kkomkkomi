# Zone status and report summary: pull request split

Date: 2026-10-06.
Refs #60. The design is [`docs/specs/2026-10-06-zone-status-design.md`](../specs/2026-10-06-zone-status-design.md), and this document does not restate it.

## Order

Each pull request gets its own brief under `docs/plans/` when it starts, written against the code of that time.
Every pull request body says `Refs #60`, and only the last one closes it.

The capture screen comes last.
Until it ships, no person can set an exception, so every report shows done zones only and `main` stays releasable after each merge, while #36 and #40 still need test builds.

| PR  | Brief                                  | Scope                                                                                                                                                                                                                                    | Needs before it starts |
| --- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| 1   | `2026-10-06-zone-status-01-domain.md`  | `ZoneStatus`, the status and the reason of `ZoneRecord`, `hasContent`, schema version 5 with its upgrade from version 4, and `SqliteVisitRepository`. No screen and no report change.                                                    | Nothing.               |
| 2   | `2026-10-06-zone-status-02-report.md`  | `ReportZone`, the summary of `ReportDocument`, the PDF, the preview, the empty slot texts, the missing photo warning, and sample renders. Tests build the records with a status, because no screen sets one yet.                         | PR 1 merged.           |
| 3   | `2026-10-06-zone-status-03-publish.md` | `PublishedZone`, `FirebasePublisher`, the rules test, `web/report/`, and the three lists of both privacy pages.                                                                                                                          | PR 2 merged.           |
| 4   | `2026-10-06-zone-status-04-capture.md` | The status control and the reason field of the visit capture screen, the two `VisitCaptureCubit` actions on the save path of the notes, the localization keys of the screen, and the store screenshot of the capture screen. Closes #60. | PR 3 merged.           |

## Release builds

A release build is allowed after each merge, with one condition: the Hosting deploy of the privacy pages of PR 3 comes before the first build that holds PR 4, because PR 4 is the first change that lets a person set an exception and publish its reason.
The deploy needs the approval of the operator, and the deploy record in `CLAUDE.md` follows it.

## Verification of each pull request

- `merry run check` and `merry run coverage` (100% of `lib`).
- PR 1 adds a test of the upgrade from version 4 with stored records.
- PR 2 sends sample PDFs to the operator before the merge, as #63 did.
- PR 3 runs `merry run web` and `merry run rules`.
- PR 4 runs the capture screen tests at the narrow screen with the largest text.
