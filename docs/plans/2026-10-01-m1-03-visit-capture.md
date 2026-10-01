# M1 brief 3: visit capture

Design: `docs/specs/2026-10-01-m1-local-first-design.md`.
Read the design and `CLAUDE.md` before you write code.
This brief depends on briefs 1 and 2, which must be merged first.

## Goal

A worker starts a visit for a client and a date, then takes a before photo and an after photo for each zone and writes a note.

## In scope

- Start a visit from the client detail screen with a date that defaults to today.
- Visit capture screen: one row for each zone record with a before slot, an after slot, a note field, and the previous photos of that zone when they exist.
- A photo capture port in `lib/application/` and its `image_picker` adapter under `lib/presentation/`.
- A photo store port that copies the picked file into `photos/<visitId>/` under the application documents directory and returns the relative path.
- Retake of a photo, which replaces the stored file.
- Reopen of a past visit from the client detail screen.
- The camera usage descriptions that iOS and Android need.

## Out of scope

- The report and the share.
- The ghost overlay, which belongs to M2.
- Upload and Firebase.

## Requirements

- Add `image_picker` and `path_provider`. Compress at capture with the picker's maximum width and quality options, and state the chosen values in the pull request body.
- Every change to a zone record is saved at once, so that closing the app loses no photo and no note.
- A cancelled capture changes nothing.
- A capture failure shows a message and keeps the screen usable.
- Tests replace both ports with fakes. No test touches a platform channel.
- Every user-facing string goes in both ARB files, with Korean in polite informal style (해요체).

## Acceptance criteria

- Cubit tests cover capture, retake, cancel, failure, note edit, and reopen.
- Widget tests cover a zone with no photo, with one photo, with both photos, and with previous photos.
- A test pins that the stored path is relative.
- `merry run check` passes.
- `merry run coverage` passes at 100 percent.
