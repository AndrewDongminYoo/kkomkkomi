# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product

Kkomkkomi (꼼꼬미) is a mobile app for small cleaning companies in Korea: teams of one to five people that clean offices and shops on a recurring schedule.
A worker selects a client and a visit date, takes paired before/after photos for each saved zone, adds notes, and shares a completion report that carries the company logo.
The next visit loads the same zone list and the previous photos.
The source of this section is the business plan dated 2026-10-01, which is not checked in.

### Public repository

The repository is public while implementation is in progress, and the operator makes it private when the business starts (operator decision, 2026-10-01).
Until then, keep pricing, validation criteria, sales channels, and unit economics out of every tracked file, `docs/` included.

### Current state

The operator directed implementation to start on 2026-10-01, and M1 is the milestone in progress.
The data layer of the M1 build exists: the domain model, the repository interfaces and use cases, and the SQLite repositories.
The client list, the client detail, the visit capture, and the company profile screens use it, and the client list is the home screen.
The client detail screen starts a visit and opens a past one, and the visit capture screen takes the before photo, the after photo, and the note of each zone.
The visit capture screen opens the visit report screen, which previews the completion report and shares it as a PDF through the OS share sheet.
No web report exists yet.
The production flavor starts Firebase and signs in anonymously.
The publish queue publishes a visit as a report under the fixed page of its client and reads the user ID before each job, and no screen starts a publish yet.
The stack is Flutter with Firebase (Auth, Firestore, Storage, Hosting), and the Firebase project is `kkomkkomi`.
The "Phase B" section of `docs/specs/2026-10-01-m1-local-first-design.md` owns the state of that project and the backend decisions.

Firebase is for the production flavor only.
Android skips the google-services task for the development and staging variants, and only the production entry point may start Firebase.
`lib/main_production.dart` gives `bootstrap()` the `FirebaseIdentity` and `FirebasePublisher` adapters, and the development and staging entry points give it `UnavailableIdentity` and `UnavailablePublisher`.
`lib/firebase/` is the one directory under `lib/` that may import a FlutterFire package, which is a `firebase_*` or a `cloud_*` package, and `lib/main_production.dart` is the one file outside that directory that may import it.
`test/firebase/boundary_test.dart` fails for an import that breaks one of the two rules, and for a tracked file under `lib/` that names the generated options file.
`.gitignore` keeps the generated FlutterFire files out of the repository, so tracked code must not import `lib/firebase_options.dart`.
A fresh clone needs `flutterfire configure` before a production build for Android, iOS, or macOS.
After `flutterfire configure`, run `dart format lib/firebase_options.dart`, because the local format check reads that file and CI never sees it.

### Milestones

Keep the work inside the milestone in progress.

| Milestone | Scope                                                                                                                                        |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| M1        | Client and zone model, paired before/after capture, offline upload queue, image compression, web report on Firebase Hosting, OS share sheet  |
| M2        | Ghost overlay of the previous photo on the camera preview, logo branding, view tracking with an explicit confirm button, monthly bundled PDF |
| M3        | Subscription billing, free-tier limits and watermark, staff accounts                                                                         |

Scheduling, quotes and payments, and staff attendance are out of scope for v1.

### Product rules that constrain code

- The web link is the primary report output, opened from KakaoTalk. PDF and image are secondary outputs, and the PDF is generated on the device and sent through the OS share sheet.
- Each client has a fixed report URL with a cumulative history page. The plan treats this history as the reason a company stays, so do not design reports as one-off files.
- A link open is not a confirmation. Show a link open as "열람됨" only, and show "담당자 확인" only after the recipient presses the confirm button inside the report.
- A report URL is hard to guess but not private. The plan requires link expiry, reissue, and per-client access removal, and it requires the app to tell the company that anyone with the link can open the report.
- Photos can show faces, monitors, and documents. The plan lists a caution in the capture guide and a masking tool before upload as items to evaluate, and the legal scope under the Korean privacy law is an open question to settle before release.
- Field networks are unreliable. Upload retry and compression of large photos are the two technical risks the plan names.
- User-facing copy presents only the features of shipped milestones as available and marks later features as "예정".

### Vocabulary

| Term in the plan | Meaning                                                                              |
| ---------------- | ------------------------------------------------------------------------------------ |
| 거래처           | A customer of the cleaning company. Zones, reports, and report history belong to it. |
| 구역             | An area inside a client site that gets one before/after photo pair per visit.        |
| 방문             | One cleaning visit to a client on a date.                                            |
| 발주처           | The party that orders the cleaning and receives the report, and that can require it. |

## Commands

`merry.yaml` owns the local scripts and their definitions, and `merry ls` lists them.

```sh
# Local gate: format check, analyze, bloc lint, test
merry run check

# Coverage under the CI threshold
merry run coverage

# Security rules tests in the Firebase emulators (needs Java 21 and the Firebase CLI)
merry run rules

# Run a flavor (development, staging, production)
merry run dev

# Regenerate localizations after an ARB edit
merry run l10n

# One test file, then one test by name
flutter test test/domain/client_test.dart
flutter test test/domain/client_test.dart --plain-name "trims the name"
```

The project has no `lib/main.dart`, so a bare `flutter run` fails.
`lib/l10n/gen/` is ignored by git and generated from the ARB files.
`flutter pub get` generates it because `pubspec.yaml` sets `generate: true`.
When that directory is missing, `flutter analyze` reports `AppLocalizations` as undefined and does not regenerate it.

## CI

`.github/workflows/main.yaml` calls the Very Good reusable workflows for the title check, the Flutter gate, and the spell check, and it adds an Android build job and a Windows build job.

- Coverage must be 100% for `lib`, and CI counts only the files that a test imports. `merry run check` does not measure coverage, so run `merry run coverage` before a push.
- The pull request title must be a conventional commit.
- cspell checks every Markdown file and the pull request title against `cspell.json`. Project words go in `words` there, and general vocabulary goes in `.cspell/custom-dictionary.txt`.
- The `android` job builds the development debug APK. It cannot build a production variant, because those read `google-services.json`, which the repository does not hold, so no CI job checks the Firebase wiring or the release signing.
- The `windows` job is the only verification of the Windows build. Do not add a local Windows build script.
- The `rules` job runs `test/rules/` against the Firestore and Storage emulators with the project ID `demo-kkomkkomi`, as `merry run rules` does. `merry run check` leaves it out, because the emulators need Java 21. Firebase documents that a project ID with the `demo-` prefix reaches emulators only (https://firebase.google.com/docs/emulator-suite/connect_firestore, "Choose a Firebase project"), so never run the rules tests under another project ID.

Trunk installs a format hook on commit and a check hook on push (`.trunk/trunk.yaml`).

Codex reviews every pull request, and CodeRabbit was attached on 2026-10-01 after pull request 1.
`/pr-loop` keeps its usual terminal conditions, so a CodeRabbit verdict or skip notice counts when one arrives.
If CodeRabbit posts nothing on a pull request, the operator's ruling of 2026-10-01 applies: the merge needs a clean Codex verdict on the head commit, every check passing, and no unresolved review thread, and the report states that one reviewer ran.

## Architecture

The M1 design splits the code under `lib/` into units and owns the table of what each unit may import.
Each screen is a folder under `lib/presentation/` in the Very Good CLI layout: `cubit/` and `view/` subdirectories and a barrel file named after the screen.
Other code imports a unit or a screen through its barrel, for example `package:kkomkkomi/presentation/client_list/client_list.dart`.

- **Units.** `lib/domain/`, `lib/application/`, `lib/persistence/`, `lib/export/`, `lib/firebase/`, and `lib/presentation/` exist, each with a barrel file named after the unit. `domain/` holds the entities and their rules, `application/` holds the repository interfaces, the `Identity`, `IdGenerator`, `Clock`, `PhotoCapture`, `PhotoStore`, `ReportFont`, `ReportShare`, `Publisher`, and `NetworkMonitor` ports, the use cases, and the `PublishQueue`, and `persistence/` holds the version 2 SQLite schema, its upgrade from version 1, and the `sqflite` repositories. `export/` holds the report document builder, the report file name, and the A4 PDF renderer. `firebase/` holds `FirebaseIdentity` and `FirebasePublisher`, the Firebase adapters of the `Identity` and `Publisher` ports. `presentation/` holds one folder per screen, the adapters of the other seven ports, `UnavailableIdentity`, and `UnavailablePublisher` under `adapters/`, and what more than one screen uses under `shared/`. `test/domain/boundary_test.dart` fails when a file under `lib/domain/` imports a library that the design does not allow. That rule excludes `package:meta`, so a domain file that overrides `==` carries an `ignore_for_file` comment for the lint that asks for `@immutable`.
- **Entry points.** `lib/main_development.dart`, `lib/main_staging.dart`, and `lib/main_production.dart` each call `bootstrap()` from `lib/bootstrap.dart`. `bootstrap()` installs the `FlutterError.onError` handler and `AppBlocObserver`, asks the `Identity` of the flavor for the user ID once, opens the database, and passes the repositories and that identity to the builder that makes the app. It does not wait for the answer of the identity, and a failure of the identity does not stop it. When the database is open, it starts a `PublishQueue` with the publisher of the flavor, and a failure of the queue does not stop it either. While the database does not open, it shows `StartupFailureApp`, and the retry control opens the database again. `App` provides each repository, the identity, and the adapter of each other port to the widgets below it through `RepositoryProvider`. `App` has no default identity, because the flavor decides it. Configuration that all flavors share goes in `bootstrap()`, and configuration for one flavor goes in its `main_*.dart`.
- **Flavors.** Android defines them in `android/app/build.gradle.kts` with the application ID suffixes `.dev` and `.stg`. iOS and macOS define them as Xcode schemes. `windows/` has no flavor configuration, so a Windows build selects its entry point with `--target` alone. The `.vscode/launch.json` configurations pass the matching `--flavor` and `--target`.
- **State.** Each page widget creates its Cubit in a `BlocProvider` and renders a separate view widget that reads it, as `ClientListPage` and `ClientListView` do. This split lets a widget test inject a mock Cubit into the view. A state is one final class with a status enum, `copyWith`, and hand-written equality, in a `part` file of its Cubit. A Cubit turns a `DomainException` into a `NameEntry` value in its state, and `NameField` shows the message of that value under the field. A screen or a dialog that saves wraps itself in `SaveGuard`, which takes no touch and no back press while the change is on its way to storage, so that the answer finds the screen as the change left it.
- **Identity.** `Identity.currentUserId()` gives the ID of the current user, or null while identity is unavailable, and it does not throw. `FirebaseIdentity` calls `Firebase.initializeApp()` without options, which reads the native config file of the platform, and then gives the ID of the account that the device holds or signs in anonymously. A start or a sign-in that fails gives null, and the next call starts Firebase and signs in again. `bootstrap()` asks once, and the publish queue asks again before each job, so a job waits with its retry delay while identity is unavailable. Calls at one time share one attempt. The Windows runner has no native config file, so there the start fails and identity stays unavailable. No build and no test checks the start of Firebase on a device: the tests replace `Firebase.initializeApp` and `FirebaseAuth` with fakes.
- **Photos.** `ImagePickerPhotoCapture` opens the camera app through `image_picker` and owns the size limit and the JPEG quality of a photo. `DocumentsPhotoStore` copies the picked file into `photos/<visitId>/` under the application documents directory, under a new name for each capture, and a `PhotoRef` holds the path relative to that directory. `VisitCaptureCubit` sends the whole visit to the repository at each photo and each note edit. A note edit does not wait for the save before it, so `VisitRepository.save` must apply saves in the order of the calls, and a capture waits for the answer to the newest save before it opens the camera. It deletes the file of a replaced photo only after storage took the new one. While storage does not hold a note, the screen keeps a notice with a control that saves again. The screen takes no back press while a note is on its way to storage, and it asks before a person leaves with a note that storage did not take. `ios/Runner/Info.plist` holds the camera usage description in Korean only, because the project has no `InfoPlist.strings`. It also holds a photo library usage description, although the app never opens the photo library, because the `image_picker` README says that App Store policy requires the entry. Android needs no manifest entry, because the picker opens the camera app through an intent, and a `CAMERA` permission in the manifest would add a permission request that the flow does not need. Known limit: when Android destroys the app while the camera app is open, the photo of that capture is lost, because nothing calls `retrieveLostData` of `image_picker`. The design replaces the picker adapter with a camera preview inside the app in M2, which removes the camera app from the flow.
- **Report.** `ReportDocument.fromVisit` in `lib/export/` builds what a report prints from a visit, its client, and the company profile, and it leaves out a zone record without a photo and without a note. A zone record without a photo and with a note stays, with two empty slots. The preview of the visit report screen and `renderReportPdf` both show that document, so they hold the same zones, and both show the whole of each photo in a slot of the ratio `reportSlotAspectRatio`. `lib/export/` imports only the domain and `package:pdf`, and no Flutter library, and `test/export/boundary_test.dart` fails when a file there imports another library. So the caller gives the renderer what needs Flutter or a file: the texts as a `ReportLabels` value from the ARB files, the font bytes from the `ReportFont` port, and the photo bytes from `PhotoStore.read`. `PrintingReportShare` is the one file under `lib/` that imports `printing`, and `test/presentation/printing_import_test.dart` fails when a second file imports it. On Android and iOS the plugin answers when the share sheet opens, so the app does not know whether the person sent the file. The plugin writes the file under the name that it is given, and a name that the file system refuses makes the share do nothing without an error, so `reportFileName` removes the characters that a file name cannot hold and limits each part in UTF-8 bytes. `VisitReportCubit.share` catches every object, because the image decoder of `pdf` throws an `Error` for a file that is no image, and the screen takes no touch while a share is on its way. The PDF is rendered on the UI isolate. `assets/fonts/NotoSansKR-Regular.ttf` is the font of the PDF, with its license in `assets/fonts/OFL.txt`. It is the regular weight of the variable Noto Sans KR font, made with `fonttools varLib.instancer NotoSansKR.ttf wght=400 --update-name-table`, because `pdf` reads no weight axis and prints a variable font at its lightest weight. A character that the font does not have, such as an emoji, prints as a crossed box. Known limits, which the adapter cannot see: when the plugin cannot write the file, no share sheet opens and the call still answers that it did, and on Android the plugin leaves each shared file in the cache directory of the app, where only the end of the app process or the system removes it.
- **Publishing.** `PublishQueue` in `lib/application/` owns the order of the steps, the retries, and the job state, and `FirebasePublisher` only writes what the queue gives it. A client gets its page at its first publish: the page ID is 128 random bits from `newPageId`, stored in `client_pages`. A publish job writes the page, uploads each photo to `clientPages/<pageId>/<visitId>/<zoneId>-<slot>-<photo file name>.jpg`, then writes the report with the paths of its photos, never download URLs, and with the creation time of its job as `publishedAt`, and then deletes the objects of the visit that the report no longer names. The name of the photo file is in the path because a retake is a new file, so an upload of the old photo that outlived its step timeout cannot replace the retake. `published_photos` records which photo file reached which object, so a retry does not upload a photo again. A job that fails for a reason that a retry can fix, a step that takes longer than `PublishQueue.defaultStepTimeout` included, runs again after a delay that doubles from 5 seconds up to 15 minutes. A job that fails for another reason stops with a `PublishFailure`, and `PublishQueue.updates` gives each change of a job for a screen to show. The queue runs every pending job at once at its start and when `NetworkMonitor.restored` reports a return of the network. `bootstrap()` makes the one queue of the app: a second queue on the same database would run the same job at the same time, so the screens of brief 7 must use that instance. A run saves the result of a job only while the stored job is pending, so a revoke that stops a job during its run holds. A revoke marks the page as revoked on the backend and deletes the photos that the app uploaded under it, and a reissue revokes the old page and publishes each of its visits again under a new page. The revoke writes the revoke time stored with the local page, so a revoke job that runs again writes the same page. `firestore.rules` and `storage.rules` are the rules of the design, and `test/rules/` tests them in the emulators. `storage.rules` reads the page through `firestore.get`, which needs the IAM role that the Firebase CLI asks to grant at the first deploy of those rules.
- **Navigation.** No router package exists. A page has a static `route()` that makes a `MaterialPageRoute`, and a widget opens it with `Navigator.push`.
- **Web.** No Flutter web app is planned. `web/` is the deploy root of the static landing page, which lives in this repository and not in a separate one, and `web/index.html` is that page (operator decision, 2026-10-01). It is one hand-written HTML file, so no Flutter build produces or checks it. `web/og.png` and the two icons under `web/icons/` are renders of the cards under `tool/web_assets/`, and `tool/web_assets/render.sh` owns how to make them again. Firebase Hosting serves `web/` at `https://kkomkkomi.web.app`, and `firebase deploy --only hosting` publishes it. A deploy, and a change to the deployed security rules, needs the operator's approval each time.
- **App icon.** `tool/app_icon/symbol.svg` is the master of the mark, and `tool/app_icon/render.sh` owns the list of the files that hold a copy of it and makes the legacy Android images, the launch images, and the Windows icon. Android uses an adaptive icon in each source set, and iOS and macOS use the Icon Composer bundles under `ios/Runner/AppIcons/` and `macos/AppIcons/`. The development and staging icons carry a label. The launch screen of Android and iOS shows the icon on a white ground, because the first screen of the app is light.
- **Localization.** All user-facing strings come from `lib/l10n/arb/` through `context.l10n`, which `lib/l10n/l10n.dart` defines. `app_en.arb` is the template and `app_ko.arb` is the Korean locale, so each new key goes in both files. A new locale also needs an entry in `CFBundleLocalizations` in `ios/Runner/Info.plist`. Every `MaterialApp` takes `appLocalizationsDelegates` from `lib/l10n/l10n.dart`, because the generated `AppLocalizations.localizationsDelegates` does not serve the widgets of `material_ui`.
- **Tests.** `test/` mirrors `lib/`. Widget tests use `tester.pumpApp()` from `test/helpers/`, which wraps the widget in a `MaterialApp` with the localization delegates. Cubit tests use `blocTest`, and view tests mock the Cubit with `MockCubit` from `bloc_test` and stub it with `mocktail`. Repository tests run the `sqflite` repositories against `sqflite_common_ffi`, and `test/persistence/support.dart` opens the in-memory database that they use. `mockRepositories()` from `test/helpers/` gives a widget test repositories that never reach a database. A page test passes the in-memory repositories of `test/helpers/fakes.dart` to `pumpApp`, which then provides what `App` provides. `FakePhotoCapture` and `FakePhotoStore` from the same file replace the camera and the photo files, and `FakeReportShare` replaces the share sheet, so no screen test touches a platform channel. `FakeIdentity` replaces the identity, `FakePublisher` and `FakeNetworkMonitor` replace the backend and the network state, and no test starts Firebase. The queue tests run `PublishQueue` against the in-memory SQLite repositories. `FileReportFont` reads the font file from the source tree, so a screen test renders the PDF, and `PdfSummary` from `test/helpers/` reads the size, the text, and the images of each page of the result. `PdfSummary` is not a PDF library: it follows the cross-reference stream to the catalog, the page tree, and each page, decodes the compressed streams on that path, and reads only the forms that the `pdf` package writes. A photo on the screen is a `PhotoThumbnail`, and `tester.photoPathsIn()` reads the file paths that the thumbnails show, because the fake photo store holds no file to show. `tester.useNarrowScreenWithLargestText()` sets the 320 pixel width and the largest text size at which no screen may overflow, and `tester.expectWholeText()` fails for text that the framework cuts without an overflow error.

## Documents

Specs go in `docs/specs/`, implementation plans in `docs/plans/`, and working notes in `docs/notes/`.
`docs/specs/2026-10-01-m1-local-first-design.md` is the design of the M1 build: its units, domain model, screens, and what it leaves out until a Firebase project exists.
Read it before feature work and cite it instead of restating it.
The briefs under `docs/plans/` split that design into pull requests.

## Conventions

- Material widgets come from `package:material_ui/material_ui.dart`. No file imports `package:flutter/material.dart`.
- Constructors are declared with `new` in place of the class name, for example `const new({super.key});`, and a class with an empty body ends with `;`. Keep this Dart 3.13 syntax and do not rewrite it to the older form.
- Lint rules are `very_good_analysis` plus `bloc_lint/recommended`, with the exceptions that `analysis_options.yaml` lists. The formatter page width is 120.
