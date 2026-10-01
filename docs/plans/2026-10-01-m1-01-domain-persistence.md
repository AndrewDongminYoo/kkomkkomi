# M1 brief 1: domain model and SQLite persistence

Design: `docs/specs/2026-10-01-m1-local-first-design.md`.
Read the design and `CLAUDE.md` before you write code.

## Goal

Add the data layer of the M1 build with no screen change.

## In scope

- `lib/domain/`: `Client`, `Zone`, `Visit`, `ZoneRecord`, `PhotoRef`, `CompanyProfile`, and the rules in the design's "Domain model" section.
- `lib/application/`: the repository interfaces for clients with their zones, visits, and the company profile, plus the identifier generator and clock ports.
- `lib/application/`: the use case that starts a visit from a client's active zones, and the query that returns the previous photos of each zone.
- `lib/persistence/`: the version 1 schema and the `sqflite` repositories.
- `lib/bootstrap.dart`: open the database before the app mounts and pass the repositories to the builder.
- A boundary test for `lib/domain/` as the design's "Units" section states.

## Out of scope

- Any screen, any ARB string, and the removal of the `counter` feature.
- Photo capture, file copying, and the report.
- Firebase.

## Requirements

- Add `sqflite` and `path` as dependencies and `sqflite_common_ffi` as a dev dependency. Add no other package unless the design needs it, and state the reason in the pull request body.
- Regenerate `pubspec.lock` in the same commit as the `pubspec.yaml` change.
- A database open failure must not leave a blank screen: the app shows a message and a retry control. This is the one widget this brief adds, and its text goes through the ARB files in English and Korean.
- Keep the Dart 3.13 constructor syntax and the `material_ui` import that `CLAUDE.md` describes.

## Acceptance criteria

- Tests pin each domain rule in the design: trimmed and non-empty names, unique zone names within one client, zone order, zone removal that keeps past records, the zone name copied into a visit, and the previous-photo lookup.
- Repository tests run against `sqflite_common_ffi` and cover a round trip for each entity, the multi-table transaction, and a reopen of the database file.
- `merry run check` passes.
- `merry run coverage` passes at 100 percent.
- `CLAUDE.md` describes the new units where this change makes its "Current state" and "Architecture" sections stale.
