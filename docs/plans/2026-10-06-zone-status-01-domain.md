# Zone status PR 1: domain and persistence

Date: 2026-10-07.
Refs #60. The design is [`docs/specs/2026-10-06-zone-status-design.md`](../specs/2026-10-06-zone-status-design.md) ("Domain" and "Persistence"), and the split is [`2026-10-06-zone-status.md`](2026-10-06-zone-status.md).
Written against main at `964fb06`.

No screen and no report reads the new fields in this pull request, so a build of it behaves as `main` does.

## Domain

- Add `lib/domain/zone_status.dart` with `enum ZoneStatus { done, partlyDone, notDone }`, and export it from `lib/domain/domain.dart`.
- `ZoneRecord` gets `status` (default `ZoneStatus.done`) and `reason` (default empty), as named constructor parameters, so that every caller that builds a record today keeps compiling and builds a done record.
- `withPhoto` and `withNote` carry `status` and `reason` into the record that they make. Without that, a photo or a note edit would set a record back to done.
- Add `withStatus(ZoneStatus status)` and `withReason(String reason)`. `withReason` keeps the text as written, as `withNote` does. `withStatus(ZoneStatus.done)` keeps the reason.
- `hasContent` is also true when `status` is not `ZoneStatus.done`.
- `==`, `hashCode`, and `toString` (if the class has one) include both fields.

## Persistence

- `schemaVersion` becomes 5, and `_migrations` gets `_version5`:
  - `ALTER TABLE zone_records ADD COLUMN status TEXT NOT NULL DEFAULT 'done'`
  - `ALTER TABLE zone_records ADD COLUMN reason TEXT NOT NULL DEFAULT ''`
- `SqliteVisitRepository.save` writes `status` as `record.status.name` and `reason`.
- `_recordFromRow` reads `status` with `ZoneStatus.values.asNameMap()`, and a name that it does not know reads as `ZoneStatus.notDone`.

## Tests

- `test/domain/zone_record_test.dart`: the defaults, `withStatus`, `withReason`, `withPhoto` and `withNote` keeping both fields, `hasContent` for each status of a record without a photo and without a note, and equality.
- `test/persistence/sqlite_visit_repository_test.dart`: the round trip of a record with each status and a reason, and a stored status that the app does not know (written with a raw update), which reads as not done.
- `test/persistence/open_repositories_test.dart`:
  - The creation test expects version 5 and the two columns with their types and defaults.
  - The version 2 and version 3 tests write their visits with raw `INSERT` statements, because `SqliteVisitRepository.save` now writes columns that those versions do not have, and they expect the current `schemaVersion`.
  - A new test opens a version 4 file that holds a visit with a record, and reads the record back as done with no reason.

## Verification

- `merry run check` and `merry run coverage` (100% of `lib`).
