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

## Two phases

Phase A is the flow above: briefs 1 to 4, local storage and the PDF, with no backend.
Phase B publishes a report as a web link: briefs 5 to 7, on the Firebase project `kkomkkomi`.

The first version of this document left Phase B out, because no Firebase project existed.
The operator created the project later on 2026-10-01, so the "Phase B" section below replaces that exclusion.

`CLAUDE.md` calls the PDF a secondary output, and it stays secondary: the web link takes the primary place when Phase B ships.

## Units

The code is split into six units under `lib/`.
Each unit depends only on the units listed for it.

| Unit            | Holds                                                                   | May import                                    |
| --------------- | ----------------------------------------------------------------------- | --------------------------------------------- |
| `domain/`       | Entities, value types, validation                                       | Dart core libraries only                      |
| `application/`  | Repository interfaces, port interfaces, use cases                       | `domain/`                                     |
| `persistence/`  | SQLite schema and repository implementations                            | `domain/`, `application/`, `sqflite`, `path`  |
| `export/`       | Report document builder and PDF renderer                                | `domain/`, `pdf`                              |
| `firebase/`     | Firebase adapters of the ports, for the production flavor               | `domain/`, `application/`, FlutterFire        |
| `presentation/` | One folder per screen with `cubit/` and `view/`, plus the port adapters | `domain/`, `application/`, `export/`, Flutter |

`lib/app/` stays the composition root, and `lib/bootstrap.dart` opens the database and builds the repositories.
`firebase/` came with brief 5 of Phase B: no other unit imports a FlutterFire package, and only `lib/main_production.dart` imports `firebase/`.
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

## Phase B: publish a report as a web link

### State of the Firebase project on 2026-10-01

- Firestore exists in `asia-northeast3`, and its rules deny every read and write.
- Anonymous sign-in is enabled.
- Hosting serves `web/` at `https://kkomkkomi.web.app`, and the landing page is live there.
- Storage is set up, and its rules deny every read and write. The operator set it up in the Firebase console later on 2026-10-01, after the first version of this section said it was absent.
- The two items above describe the deployed rules. Pull request 12 changed the tracked `firestore.rules` and `storage.rules` to the rules in "Security rules" below, and nothing deployed them. The operator deploys them after review.
- 2026-10-02: the operator approved the deploy, and the rules and Hosting of `ab6d8d7` were deployed. The deployed rule texts equal the tracked files. The Storage service agent does not hold `roles/firebaserules.firestoreServiceAgent` yet, so the Storage rules deny until the operator grants it. `CLAUDE.md` owns the current state.

### Decisions

- **One-way publish.** SQLite on the phone stays the source of truth. The backend holds only published reports, and nothing syncs back to the phone.
- **Production flavor only.** The development and staging flavors do not initialize Firebase. Their publish port reports that publishing is unavailable, and their screens offer the PDF only.
- **No tracked import of the generated options.** `.gitignore` keeps `lib/firebase_options.dart` and the native config files out of the repository. Tracked code must not import that file. The app calls `Firebase.initializeApp()` without options, which reads the native config on Android and iOS, so CI needs no secret.
- **Identity.** The app signs in anonymously, and the user ID owns what it publishes. An uninstall loses that account, and with it the right to update the published pages. Linking the account to a durable sign-in is a later decision.
- **Fixed client page.** Each client gets one page ID of at least 128 random bits. The page ID is the client's fixed URL, and every published visit is a report under it.

### Data

- `clientPages/{pageId}`: `ownerUid`, `companyName`, `clientName`, `createdAt`, `revokedAt`.
- `clientPages/{pageId}/reports/{visitId}`: `visitDate`, `publishedAt`, and the zone list with each zone's name, note, and photo paths.
- Storage objects under `clientPages/{pageId}/{visitId}/`.

### Security rules

These rules make published reports readable without sign-in, which is what a link opened from KakaoTalk needs.
The operator must review them before they are deployed.

- Anyone can read one client page by its ID, and its reports, while `revokedAt` is unset.
- No one can list the `clientPages` collection.
- Only the owner can write a client page, its reports, and its photos.
- A photo upload must be a JPEG under a size limit.

Access removal sets `revokedAt`.
Reissue creates a new page ID and publishes again.

Brief 6 settled these details:

- Anyone can list the reports of a page that is not revoked, because the history view needs the list. No one can query the reports of every page at once.
- A page can be created revoked, and the owner can revoke a revoked page again, so that a revoke is safe to repeat and does not depend on an earlier write. No one can open a revoked page again.
- `storage.rules` reads the page through `firestore.get` to check the owner and `revokedAt`. Without it, anyone with the link could create objects under the page. This cross-service read needs an IAM role that the Firebase CLI or console asks to grant when the rules are first deployed (https://firebase.google.com/docs/rules/manage-deploy, "Manage permissions for cross-service Cloud Storage Security Rules").
- A revoke also deletes the photos that the app uploaded under the page, because a download URL that a reader got before the revoke works without the rules.
- The size limit is 5 MiB.

Link expiry is not in this build, which leaves one item of the product rule in `CLAUDE.md` open.
The app tells the company, at the first share, that anyone with the link can open the report.

### Upload queue

A table of publish jobs lives in SQLite.
A job uploads the photos, then writes the report document, and each step is safe to repeat.
The queue retries with a growing delay, and it resumes at launch and when the network returns.

### Web report page

A static page under `web/` shows one report, and a second view lists the reports of the client page.
Hosting rewrites the report paths to that page.
The footer prints "꼼꼬미로 만든 보고서".
The link preview in KakaoTalk uses fixed tags in this build, because a preview for each report needs server rendering.
View tracking and the confirm button belong to M2.

Brief 7 settled these details:

- The page is `web/report/index.html`, and `firebase.json` rewrites `/r/**` to it. `/r/<pageId>/<visitId>` shows one report, and `/r/<pageId>` lists the reports of the page, newest visit first.
- The page reads the configuration of the project from `/__/firebase/init.json`. The reserved `/__/firebase/init.js` initializes only the Firebase JavaScript SDK of version 8 and earlier (https://firebase.google.com/docs/hosting/reserved-urls), so the page loads no SDK.
- The page reads the page document and the reports through the Firestore REST API, and loads each photo from the Storage REST API by its object path without a download token. The rules check each read, so a revoke stops each read at once, also of a photo that issue #13 leaves in Storage.
- A revoked page and an unknown page ID fail the same rule, and the page shows one message for both.
- The app shares the link of a report only after the publish job of the visit is done, so the page and the report exist when the link opens.
- The notice that anyone with the link can open the reports shows before the first link of each client, which is the share that creates the client page.

## Delivery

Seven pull requests, in this order, each with its own brief under `docs/plans/`:

1. Domain model and SQLite persistence.
2. Client list, client detail, and company profile screens.
3. Visit capture.
4. Report PDF and share.
5. Firebase startup and anonymous sign-in for the production flavor.
6. Publish queue and security rules.
7. Web report page and link share.
