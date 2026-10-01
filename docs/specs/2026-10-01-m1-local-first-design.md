# M1 local-first design

Date: 2026-10-01.
Status: written by the agent under the operator's mandate to work without review for this session, so every decision here is open to revision by the operator.

This document is the source of truth for the M1 build until the operator replaces it.
`CLAUDE.md` owns the product rules and the milestone table, and this document does not restate them.

## Goal

A worker can do the whole M1 flow on one phone without a network:

1. Save a client and its zones.
2. Start a visit for a client and a date.
3. Take a before photo and an after photo for each zone, and write a note.
4. Share a completion report as a PDF through the OS share sheet.
5. Start the next visit with the same zones and see the previous photos.

## What this build leaves out

M1 in `CLAUDE.md` also names the web report and the upload queue.
Both need a Firebase project, and no Firebase project exists.
Creating one, and choosing its billing plan, is the operator's decision.

This build therefore leaves out:

- Firebase Auth, Firestore, Storage, and Hosting.
- The upload queue and the web report link.
- Link expiry, reissue, and access removal.

The PDF is the only report output of this build.
`CLAUDE.md` calls the PDF a secondary output, and it stays secondary: the web link takes the primary place when the backend exists.

## Units

The code is split into five units under `lib/`.
Each unit depends only on the units listed for it.

| Unit            | Holds                                                                   | May import                                    |
| --------------- | ----------------------------------------------------------------------- | --------------------------------------------- |
| `domain/`       | Entities, value types, validation                                       | Dart core libraries only                      |
| `application/`  | Repository interfaces, port interfaces, use cases                       | `domain/`                                     |
| `persistence/`  | SQLite schema and repository implementations                            | `domain/`, `application/`, `sqflite`, `path`  |
| `export/`       | Report document builder and PDF renderer                                | `domain/`, `pdf`                              |
| `presentation/` | One folder per screen with `cubit/` and `view/`, plus the port adapters | `domain/`, `application/`, `export/`, Flutter |

`lib/app/` stays the composition root, and `lib/bootstrap.dart` opens the database and builds the repositories.
A test in `test/domain/` fails when a file under `lib/domain/` imports anything outside the Dart core libraries and `lib/domain/`.

## Domain model

- **Client**: `id`, `name`, `isArchived`, `createdAt`. A client is archived, never deleted, because its visits must stay readable.
- **Zone**: `id`, `clientId`, `name`, `position`, `isActive`. Removing a zone sets `isActive` to false, so that past visits keep their records.
- **Visit**: `id`, `clientId`, `visitDate` (a calendar date without a time), `createdAt`, and an ordered list of zone records.
- **ZoneRecord**: `zoneId`, `zoneName`, `beforePhoto`, `afterPhoto`, `note`. `zoneName` is copied when the visit starts, so a later rename does not change a past report.
- **PhotoRef**: a path relative to the application documents directory. The absolute directory changes between iOS launches, so an absolute path must not be stored.
- **CompanyProfile**: `name`. The report header prints it. The logo belongs to M2.

Rules:

- A name is trimmed, and an empty name is refused.
- Two zones of one client must not share a name.
- A client can have more than one visit on one date.
- Starting a visit copies the client's active zones, in `position` order, into zone records.
- The previous photos of a zone are the photos of the newest earlier visit that holds a record for that zone.
- Identifiers are opaque strings from an injected generator, and the time comes from an injected clock, so tests control both.

## Persistence

SQLite through `sqflite`, schema version 1, with one table for each of: company profile, clients, zones, visits, zone records.
A write that touches more than one table runs in one transaction.
Tests run the same repositories against `sqflite_common_ffi`.

Open decision: when the Firebase project exists, Firestore can replace these repositories or become their sync target.
The repository interfaces in `application/` are the seam for both paths, and this build does not choose between them.

## Photos

`image_picker` takes the photo from the camera.
Compression happens at capture through the picker's maximum width and quality options, which keeps one dependency doing both jobs.
The use case copies the picked file into `photos/<visitId>/` under the application documents directory and stores the relative path.
The picker sits behind a port in `application/`, so tests never touch a platform channel.

The ghost overlay belongs to M2 and needs a live camera preview, so M2 replaces the picker adapter.

## Screens

| Screen          | Purpose                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------- |
| Client list     | Home screen. Lists active clients, adds a client, and opens the company profile.            |
| Client detail   | Renames or archives the client, edits the zone list, lists past visits, and starts a visit. |
| Visit capture   | Shows each zone with a before slot, an after slot, a note field, and the previous photos.   |
| Visit report    | Lists zones that lack a photo, previews the report, and shares the PDF.                     |
| Company profile | Edits the company name that the report prints.                                              |

All user-facing text is Korean in the `ko` ARB file with an English template entry.
A report can be shared while zones lack photos, and the report screen says which zones lack them before the share.

## Report

`export/` builds a report document from a visit, its client, and the company profile, then renders an A4 PDF.
The document holds the company name, the client name, the visit date, and for each zone the before photo, the after photo, and the note.
The footer prints "꼼꼬미로 만든 보고서".
The PDF embeds a Korean font that ships with the app under its own license file.
`printing` shares the PDF, and exactly one file under `lib/presentation/` imports it.

## Platforms

iOS and Android are the targets of this build.
The Windows build must keep passing in CI, and Windows runtime behavior is not a goal of this build.

## Delivery

Four pull requests, in this order, each with its own brief under `docs/plans/`:

1. Domain model and SQLite persistence.
2. Client list, client detail, and company profile screens.
3. Visit capture.
4. Report PDF and share.
