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
The code is still the Very Good CLI scaffold, and its only feature is the template `counter`.
No Firebase package or domain model exists yet.
The planned stack is Flutter with Firebase (Auth, Firestore, Storage, Hosting).

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
flutter test test/counter/cubit/counter_cubit_test.dart
flutter test test/counter/cubit/counter_cubit_test.dart --plain-name "initial state is 0"
```

The project has no `lib/main.dart`, so a bare `flutter run` fails.
`lib/l10n/gen/` is ignored by git and generated from the ARB files.
`flutter pub get` generates it because `pubspec.yaml` sets `generate: true`.
When that directory is missing, `flutter analyze` reports `AppLocalizations` as undefined and does not regenerate it.

## CI

`.github/workflows/main.yaml` calls the Very Good reusable workflows for the title check, the Flutter gate, and the spell check, and it adds one Windows build job.

- Coverage must be 100% for `lib`, and CI counts only the files that a test imports. `merry run check` does not measure coverage, so run `merry run coverage` before a push.
- The pull request title must be a conventional commit.
- cspell checks every Markdown file and the pull request title against `cspell.json`. Project words go in `words` there, and general vocabulary goes in `.cspell/custom-dictionary.txt`.
- The `windows` job is the only verification of the Windows build. Do not add a local Windows build script.

Trunk installs a format hook on commit and a check hook on push (`.trunk/trunk.yaml`).

## Architecture

The code follows the Very Good CLI layout: one folder per feature under `lib/`, with `cubit/` and `view/` subdirectories and a barrel file named after the feature.
Other code imports a feature through its barrel, for example `package:kkomkkomi/counter/counter.dart`.

- **Entry points.** `lib/main_development.dart`, `lib/main_staging.dart`, and `lib/main_production.dart` each call `bootstrap()` from `lib/bootstrap.dart`. `bootstrap()` installs the `FlutterError.onError` handler and `AppBlocObserver`, then runs the app. Configuration that all flavors share goes in `bootstrap()`, and configuration for one flavor goes in its `main_*.dart`.
- **Flavors.** Android defines them in `android/app/build.gradle.kts` with the application ID suffixes `.dev` and `.stg`. iOS and macOS define them as Xcode schemes. `windows/` has no flavor configuration, so a Windows build selects its entry point with `--target` alone. The `.vscode/launch.json` configurations pass the matching `--flavor` and `--target`.
- **State.** Each page widget creates its Cubit in a `BlocProvider` and renders a separate view widget that reads it, as `CounterPage` and `CounterView` do. This split lets a widget test inject a mock Cubit into the view.
- **Web.** No Flutter web app is planned. `web/` is the deploy root of the static landing page, which lives in this repository and not in a separate one, and the landing page replaces the scaffold's `web/index.html` (operator decision, 2026-10-01).
- **Localization.** All user-facing strings come from `lib/l10n/arb/` through `context.l10n`, which `lib/l10n/l10n.dart` defines. `app_en.arb` is the template and `app_ko.arb` is the Korean locale, so each new key goes in both files. A new locale also needs an entry in `CFBundleLocalizations` in `ios/Runner/Info.plist`.
- **Tests.** `test/` mirrors `lib/`. Widget tests use `tester.pumpApp()` from `test/helpers/`, which wraps the widget in a `MaterialApp` with the localization delegates. Cubit tests use `blocTest`, and view tests mock the Cubit with `MockCubit` from `bloc_test` and stub it with `mocktail`.

## Documents

Specs go in `docs/specs/`, implementation plans in `docs/plans/`, and working notes in `docs/notes/`.

## Conventions

- Material widgets come from `package:material_ui/material_ui.dart`. No file imports `package:flutter/material.dart`.
- Constructors are declared with `new` in place of the class name, for example `const new({super.key});`, and a class with an empty body ends with `;`. Keep this Dart 3.13 syntax and do not rewrite it to the older form.
- Lint rules are `very_good_analysis` plus `bloc_lint/recommended`, with the exceptions that `analysis_options.yaml` lists. The formatter page width is 120.
