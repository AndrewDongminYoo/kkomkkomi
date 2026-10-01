# M1 brief 2: client list, client detail, and company profile

Design: `docs/specs/2026-10-01-m1-local-first-design.md`.
Read the design and `CLAUDE.md` before you write code.
This brief depends on brief 1, which must be merged first.

## Goal

Replace the template counter with the screens that manage clients, zones, and the company profile.

## In scope

- Client list as the home screen: list active clients, add a client, open a client, open the company profile.
- Client detail: rename the client, archive the client, and edit the zone list (add, rename, reorder, remove).
- Client detail also lists the client's past visits, newest first, and shows a control that starts a visit. The control can be disabled until brief 3 adds its destination.
- Company profile: edit the company name.
- Remove `lib/counter/`, its tests, and its ARB keys.

## Out of scope

- Visit capture and the report.
- Deleting a client or restoring an archived one.
- Firebase.

## Requirements

- Put each screen under `lib/presentation/<screen>/` with `cubit/` and `view/`, a page widget that provides the Cubit, and a view widget that reads it.
- Every user-facing string goes in both ARB files. Write the Korean text in polite informal style (해요체), short and concrete.
- An empty client list explains what a client is and offers the add control.
- A validation failure from the domain shows next to the field that caused it.
- The layout must not overflow at a 320 logical pixel width or at the largest system text size.

## Acceptance criteria

- Cubit tests cover load, add, rename, archive, each zone edit, and each failure path.
- Widget tests cover the empty state, a populated list, the zone reorder, and a validation message.
- `test/app/view/app_test.dart` checks that the client list is the home screen.
- `merry run check` passes.
- `merry run coverage` passes at 100 percent.
- `CLAUDE.md` no longer names the `counter` feature as the example.
