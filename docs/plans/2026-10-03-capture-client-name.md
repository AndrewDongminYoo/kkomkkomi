# Brief: name the client on the visit capture screen

Read `CLAUDE.md` ("Photos", "State"), `lib/presentation/visit_capture/`, and the header of the report preview in `lib/presentation/visit_report/view/visit_report_page.dart` before you write code.
Start after the brand theme pull request (`docs/plans/2026-10-03-brand-theme.md`) merges, and use its text styles.

## Why

A UI/UX review on 2026-10-03 found that the AppBar of the visit capture screen shows only the visit date (`visitDateLabel`), and `VisitCaptureState` holds no client name.
Zone names such as 로비 or 화장실 repeat across clients, so a worker who visits several clients a day cannot see on this screen which client the photos go to.
It matters most after a lost-capture recovery, where `App` opens the visit over the client list without the client detail screen in between.

## Goal

The visit capture screen names the client and the visit date.

## In scope

1. `VisitCaptureCubit` reads the client of the visit through the existing repositories and keeps its name in the state.
2. The AppBar shows the client name, and the visit date as secondary text, in the order that the report preview uses.
3. A client that the cubit cannot read leaves the date alone in the title, as now; the screen does not fail for it.

## Out of scope

- Any change to the report, the PDF, or the web report.
- A client switch from this screen.

## Requirements

- Every new user-facing string goes in both ARB files.
- Tests for the loaded name, the missing client, and the recovery route; the title passes `tester.useNarrowScreenWithLargestText()` and `tester.expectWholeText()` with a long client name.

## Acceptance criteria

- `merry run check` and `merry run coverage` pass.
