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
The client list, the client detail, and the company profile screens use it, and the client list is the home screen.
The control that starts a visit on the client detail screen is disabled until the visit capture screen exists.
No Firebase package exists yet.
The stack is Flutter with Firebase (Auth, Firestore, Storage, Hosting), and the Firebase project is `kkomkkomi`.
The "Phase B" section of `docs/specs/2026-10-01-m1-local-first-design.md` owns the state of that project and the backend decisions.

Firebase is for the production flavor only.
Android skips the google-services task for the development and staging variants, and only the production entry point may start Firebase.
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

Trunk installs a format hook on commit and a check hook on push (`.trunk/trunk.yaml`).

Codex reviews every pull request, and CodeRabbit was attached on 2026-10-01 after pull request 1.
`/pr-loop` keeps its usual terminal conditions, so a CodeRabbit verdict or skip notice counts when one arrives.
If CodeRabbit posts nothing on a pull request, the operator's ruling of 2026-10-01 applies: the merge needs a clean Codex verdict on the head commit, every check passing, and no unresolved review thread, and the report states that one reviewer ran.

## Architecture

The M1 design splits the code under `lib/` into units and owns the table of what each unit may import.
Each screen is a folder under `lib/presentation/` in the Very Good CLI layout: `cubit/` and `view/` subdirectories and a barrel file named after the screen.
Other code imports a unit or a screen through its barrel, for example `package:kkomkkomi/presentation/client_list/client_list.dart`.

- **Units.** `lib/domain/`, `lib/application/`, `lib/persistence/`, and `lib/presentation/` exist, each with a barrel file named after the unit. `domain/` holds the entities and their rules, `application/` holds the repository interfaces, the `IdGenerator` and `Clock` ports, and the use cases, and `persistence/` holds the version 1 SQLite schema and the `sqflite` repositories. `presentation/` holds one folder per screen, the adapters of the two ports under `adapters/`, and what more than one screen uses under `shared/`. `test/domain/boundary_test.dart` fails when a file under `lib/domain/` imports a library that the design does not allow. That rule excludes `package:meta`, so a domain file that overrides `==` carries an `ignore_for_file` comment for the lint that asks for `@immutable`.
- **Entry points.** `lib/main_development.dart`, `lib/main_staging.dart`, and `lib/main_production.dart` each call `bootstrap()` from `lib/bootstrap.dart`. `bootstrap()` installs the `FlutterError.onError` handler and `AppBlocObserver`, opens the database, and passes the repositories to the builder that makes the app. While the database does not open, it shows `StartupFailureApp`, and the retry control opens the database again. `App` provides each repository, the `IdGenerator`, and the `Clock` to the widgets below it through `RepositoryProvider`. Configuration that all flavors share goes in `bootstrap()`, and configuration for one flavor goes in its `main_*.dart`.
- **Flavors.** Android defines them in `android/app/build.gradle.kts` with the application ID suffixes `.dev` and `.stg`. iOS and macOS define them as Xcode schemes. `windows/` has no flavor configuration, so a Windows build selects its entry point with `--target` alone. The `.vscode/launch.json` configurations pass the matching `--flavor` and `--target`.
- **State.** Each page widget creates its Cubit in a `BlocProvider` and renders a separate view widget that reads it, as `ClientListPage` and `ClientListView` do. This split lets a widget test inject a mock Cubit into the view. A state is one final class with a status enum, `copyWith`, and hand-written equality, in a `part` file of its Cubit. A Cubit turns a `DomainException` into a `NameEntry` value in its state, and `NameField` shows the message of that value under the field. A screen or a dialog that saves wraps itself in `SaveGuard`, which takes no touch and no back press while the change is on its way to storage, so that the answer finds the screen as the change left it.
- **Navigation.** No router package exists. A page has a static `route()` that makes a `MaterialPageRoute`, and a widget opens it with `Navigator.push`.
- **Web.** No Flutter web app is planned. `web/` is the deploy root of the static landing page, which lives in this repository and not in a separate one, and `web/index.html` is that page (operator decision, 2026-10-01). It is one hand-written HTML file, so no Flutter build produces or checks it. `web/og.png` and the two icons under `web/icons/` are renders of the cards under `tool/web_assets/`, and `tool/web_assets/render.sh` owns how to make them again. Firebase Hosting serves `web/` at `https://kkomkkomi.web.app`, and `firebase deploy --only hosting` publishes it. A deploy, and a change to the deployed security rules, needs the operator's approval each time.
- **App icon.** `tool/app_icon/symbol.svg` is the master of the mark, and `tool/app_icon/render.sh` owns the list of the files that hold a copy of it and makes the legacy Android images, the launch images, and the Windows icon. Android uses an adaptive icon in each source set, and iOS and macOS use the Icon Composer bundles under `ios/Runner/AppIcons/` and `macos/AppIcons/`. The development and staging icons carry a label. The launch screen of Android and iOS shows the icon on a white ground, because the first screen of the app is light.
- **Localization.** All user-facing strings come from `lib/l10n/arb/` through `context.l10n`, which `lib/l10n/l10n.dart` defines. `app_en.arb` is the template and `app_ko.arb` is the Korean locale, so each new key goes in both files. A new locale also needs an entry in `CFBundleLocalizations` in `ios/Runner/Info.plist`. Every `MaterialApp` takes `appLocalizationsDelegates` from `lib/l10n/l10n.dart`, because the generated `AppLocalizations.localizationsDelegates` does not serve the widgets of `material_ui`.
- **Tests.** `test/` mirrors `lib/`. Widget tests use `tester.pumpApp()` from `test/helpers/`, which wraps the widget in a `MaterialApp` with the localization delegates. Cubit tests use `blocTest`, and view tests mock the Cubit with `MockCubit` from `bloc_test` and stub it with `mocktail`. Repository tests run the `sqflite` repositories against `sqflite_common_ffi`, and `test/persistence/support.dart` opens the in-memory database that they use. `mockRepositories()` from `test/helpers/` gives a widget test repositories that never reach a database. A page test passes the in-memory repositories of `test/helpers/fakes.dart` to `pumpApp`, which then provides what `App` provides. `tester.useNarrowScreenWithLargestText()` sets the 320 pixel width and the largest text size at which no screen may overflow, and `tester.expectWholeText()` fails for text that the framework cuts without an overflow error.

## Documents

Specs go in `docs/specs/`, implementation plans in `docs/plans/`, and working notes in `docs/notes/`.
`docs/specs/2026-10-01-m1-local-first-design.md` is the design of the M1 build: its units, domain model, screens, and what it leaves out until a Firebase project exists.
Read it before feature work and cite it instead of restating it.
The briefs under `docs/plans/` split that design into pull requests.

## Conventions

- Material widgets come from `package:material_ui/material_ui.dart`. No file imports `package:flutter/material.dart`.
- Constructors are declared with `new` in place of the class name, for example `const new({super.key});`, and a class with an empty body ends with `;`. Keep this Dart 3.13 syntax and do not rewrite it to the older form.
- Lint rules are `very_good_analysis` plus `bloc_lint/recommended`, with the exceptions that `analysis_options.yaml` lists. The formatter page width is 120.
