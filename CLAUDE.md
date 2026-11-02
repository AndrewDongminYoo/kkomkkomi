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

The operator directed implementation to start on 2026-10-01, and M1 and M3 are both milestones in progress (operator, 2026-10-05).
The operator started M2 work on 2026-10-06 with the report layout of #54 and the zone status of #60, which follows `docs/plans/2026-10-06-zone-status.md`.
M1 waits for the first test distribution (#40), and M3 follows `docs/plans/2026-10-05-m3-subscriptions.md`.
See `docs/notes/2026-10-31-store-distribution-status.md` § Current state (moved 2026-11-02).
A read-only track check on 2026-11-02 found Google Play `1.1.2`, version code `6`, with status `completed` on the internal, closed Alpha and production tracks, and the operator confirmed that the production release was intended.
`docs/notes/2026-10-31-play-internal-distribution.md` owns that read-back and its limits; tester eligibility on the internal track and an Android physical-device pass keep #40 open.
No check has read the App Store production state.
The data layer of the M1 build exists: the domain model, the repository interfaces and use cases, and the SQLite repositories.
The client list, the client detail, the visit capture, the company profile, and the plans screens use it, and the client list is the home screen.
The client detail screen starts a visit and opens a past one, and the visit capture screen takes the before photo, the after photo, the status, and the note of each zone, and the reason of a zone that is partly done or not done.
The visit capture screen opens the visit report screen, which previews the completion report and shares it as a PDF through the OS share sheet.
In the production flavor, the visit report screen also publishes the visit and then shares the link of its web report, and the web report page under `web/report/` shows that report and the list of the reports of the client.
The production flavor starts Firebase and signs in anonymously.
The publish queue publishes a visit as a report under the fixed page of its client and reads the user ID before each job, and in the production flavor the client detail screen closes the link of its client or replaces it with a new link.
A report goes without the footer when a newly issued ID token of the user holds a paid entitlement in its `revenueCatEntitlements` claim, which the repository function `revenueCatWebhook` has written since 2026-11-02 in place of the RevenueCat Firebase extension; the queue reads that claim and never asks `Entitlements`.
The company profile stores the name and optional business phone.
The phone appears in the preview and PDF only, and the web publisher sends no phone (`docs/specs/2026-10-07-report-photo-and-company-metadata.md`).
The company profile screen deletes all data: what the app published, the anonymous account, and the data on the phone.
In the production flavor on Android and iOS, its confirmation also says that the deletion does not cancel a subscription bought in the store and how to cancel it; the "Deletion" part of "Architecture" owns how.
The App Store descriptions under `fastlane/metadata/ios/` end with the terms of use link and the privacy policy link of their language, as Apple asks of an app with subscriptions.
The app knows the plan of the company (Free, Basic, or Pro) through the `Entitlements` port, from RevenueCat in the production flavor. The company profile screen opens the plans screen and reads nothing from `Entitlements`. The plans screen shows the plan and what each plan holds, sells Basic and Pro monthly or annually, restores purchases, opens the store subscription management, and links the terms of use (Apple's standard EULA, operator, 2026-10-05) and the privacy policy. Opening the plans screen in a production build with keys configures RevenueCat with the Firebase user ID, so the privacy pages name RevenueCat as a processor. The plans screen and the add control of the client list are the only readers of `Entitlements`, and the client list reads it only when the company has at least as many active clients as the Free limit, so that a person who never opens the plans screen and stays under that limit, or who opens the company profile screen to delete all data, sends nothing to RevenueCat; `test/presentation/company_profile/view/company_profile_page_test.dart` fails when the company profile screen uses a member of `FakeEntitlements`, and the client list tests fail when a company under the Free limit does. A company cannot add a client while its active clients reach the limit of its plan (`Plan.clientLimit`: Free 2, Basic 5, Pro none), and archived clients do not count. The add control then shows a notice that names the plan and its limit, with the way to the plans screen, in place of the name dialog, and `ClientListCubit.addClient` checks the limit again before the save, and nothing is deleted or archived after a downgrade. `currentPlan()` gives the last plan that it knew, so the limit holds as for Free only when RevenueCat never answered on the device: the press of the add control waits for the answer, and the check before the save fails the save without naming a plan when the plan does not answer within `ClientListCubit.defaultPlanTimeout`, because the dialog takes no touch while it runs. A plan that answers after the person left the client list opens no dialog. The visit report screen reads `Identity.hasPaidEntitlement()` once when it opens, and the preview and the PDF leave out the footer text when it answers true and keep the page number of the PDF. The report does not wait for that check, which asks Firebase for a newly issued token: it shows with the footer text until the check answers true, and a PDF that is shared before then prints the footer text. Release builds are allowed since M3 PR 4b merged, subject to the deploy order in `docs/plans/2026-10-05-m3-subscriptions.md`.
See `docs/notes/device-acceptance-status.md` § Current state (moved 2026-11-02).
The stack is Flutter with Firebase (Auth, Firestore, Storage, Hosting), and the Firebase project is `kkomkkomi`.
The "Phase B" section of `docs/specs/2026-10-01-m1-local-first-design.md` owns the backend decisions, and this file owns the deploy state below.

Firebase is for the production flavor only.
Android skips the google-services task for the development and staging variants, and only the production entry point may start Firebase.
iOS and macOS do not list `GoogleService-Info.plist` as a resource of the Runner target. Its "Copy Firebase Config" build phase copies the file into the bundle for a production configuration, stops that build when the file is missing, and leaves the file out for the development and staging configurations.
`lib/main_production.dart` gives `bootstrap()` the `FirebaseIdentity` and `FirebasePublisher` adapters, and the development and staging entry points give it `UnavailableIdentity` and `UnavailablePublisher`.
`lib/firebase/` is the one directory under `lib/` that may import a FlutterFire package, which is a `firebase_*` or a `cloud_*` package, and `lib/main_production.dart` is the one file outside that directory that may import it.
`test/firebase/boundary_test.dart` fails for an import that breaks one of the two rules, and for a tracked file under `lib/` that names the generated options file.
`lib/billing/` is the one directory under `lib/` that may import `purchases_flutter`, and `lib/main_production.dart` is the one file outside it that may import it or `lib/billing/`. `test/billing/boundary_test.dart` fails for an import that breaks one of the two rules.
`.gitignore` keeps the generated FlutterFire files out of the repository, so tracked code must not import `lib/firebase_options.dart`.
A fresh clone needs `flutterfire configure` before a production build for Android, iOS, or macOS, and before no other build.
After `flutterfire configure`, run `dart format lib/firebase_options.dart`, because the local format check reads that file and CI never sees it.

The local controls of issue #86 require publisher approval and resource-bound safety budgets: the operator issues a grant after an in-app request, and a paid user creates its own default grant (`docs/specs/2026-11-02-publisher-approval-request.md`); `docs/specs/2026-10-08-report-abuse-controls.md` owns the limits and `docs/notes/report-abuse-operations.md` owns enrollment and takedown.
They have not been deployed.
`firestore.rules` and `storage.rules` let anyone read a client page, its reports, and their photos by page ID while the page is open, and let the owner delete them.
See `docs/notes/firebase-deploy-log.md` § Current state (moved 2026-11-02).
The deployed Firestore rules equal the tracked ones at `135c67f`, the deployed Hosting files equal the tracked ones at `59b1c84`, and the deployed Storage rules equal the tracked ones at `34d5d23`.
A deploy is the operator's decision each time: do not deploy rules or Hosting without that approval.

The operator installed the RevenueCat Firebase extension from the Firebase console on 2026-10-05, as the instance `firestore-revenuecat-purchases`.
It is version 0.1.19 in `asia-northeast3`, with `SET_CUSTOM_CLAIMS` enabled and both collection parameters empty, so it writes the `revenueCatEntitlements` claim and nothing in Firestore.
Its shared secret is in Secret Manager, and `firebase.json` holds no `extensions` block.
Keep both collection parameters empty unless the privacy pages change first.
Install, update, or reconfigure the extension only with the operator's approval.
See `docs/notes/firebase-deploy-log.md` § RevenueCat extension (moved 2026-11-02).
`functions/` holds `revenueCatWebhook`, the repository function that replaces the extension handler and writes the same claims, and `docs/notes/revenuecat-claims-cutover.md` owns its secret, deploy, URL change, verification, uninstall, and rollback steps.
It was deployed from `1343768` on 2026-11-02 and has received the RevenueCat events since the operator changed the integration's Trigger URL that day; the extension stays installed without events until a subscription expiry is verified, and `docs/notes/firebase-deploy-log.md` § RevenueCat claims function owns the record.
Each further step, including the extension uninstall, needs the operator's approval.

`storage.rules` reads the client page through `firestore.get`, which needs the Firebase Storage service agent (`service-146496738802@gcp-sa-firebasestorage.iam.gserviceaccount.com`) to hold `roles/firebaserules.firestoreServiceAgent`.
The operator granted it on 2026-10-02, after the deploy. A `firebase deploy --only storage` with `--non-interactive` does not offer that grant, so a new project needs the grant by hand, and without it every Storage rule that reads the page denies.

### Milestones

Keep the work inside the milestones in progress, M1, M2, and M3.

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
# Local gate: format check, analyze, bloc lint, test, web report page test
merry run check

# Coverage under the CI threshold
merry run coverage

# Security rules tests in the Firebase emulators (needs Java 21 and the Firebase CLI)
merry run rules

# Run a flavor (development, staging, production)
merry run dev

# Regenerate localizations after an ARB edit
merry run l10n

# Regenerate lib/gen/assets.gen.dart after a change of the assets in pubspec.yaml
dart run build_runner build

# The web report page with fixture data, in Node (part of check)
merry run web

# Type-check and test the RevenueCat claims function under functions/ (needs Node 24)
merry run functions

# The store screenshots and the Play feature graphic, then their check
CHROME=/path/to/chrome-headless-shell merry run store

# One test file, then one test by name
flutter test test/domain/client_test.dart
flutter test test/domain/client_test.dart --plain-name "trims the name"
```

The project has no `lib/main.dart`, so a bare `flutter run` fails.
`lib/gen/assets.gen.dart` is the FlutterGen output of the asset list in `pubspec.yaml`, and git tracks it. Code takes an asset path from `Assets` and never writes the path itself.
`build_runner` skips the generator while its cache is current, so when the file does not change after an asset change, run `dart run build_runner clean` first.
`lib/l10n/gen/` is ignored by git and generated from the ARB files.
`flutter pub get` generates it because `pubspec.yaml` sets `generate: true`.
When that directory is missing, `flutter analyze` reports `AppLocalizations` as undefined and does not regenerate it.

`merry run store` runs `tool/store_screenshots/render.sh`, which owns the steps and the output paths, and `tool/store_screenshots/check.sh` (`merry run store check`) owns the store sizes and the alpha check.
`CHROME` names the headless Chromium binary, the render needs ImageMagick 7, and the frames load Noto Sans KR from Google Fonts, so it also needs a network connection.
`render_screens.dart` pumps the real screens with fictional fixture data through the fakes of `test/helpers/`, in `flutter test` outside `test/`, so the suite, the coverage gate, and CI never run it.
The app bundles the regular and the bold weight of Noto Sans KR for the PDF, and `render_screens.dart` registers the regular file under every font family that the theme asks for, so the rendered screens draw every weight from it. The frames and the feature graphic load Noto Sans KR from Google Fonts at the weights that they use.

## CI

`.github/workflows/main.yaml` calls the Very Good reusable workflows for the title check, the Flutter gate, and the spell check, and it adds an Android build job, an iOS build job, and a Windows build job.

- Coverage must be 100% for `lib`, and CI counts only the files that a test imports. `merry run check` does not measure coverage, so run `merry run coverage` before a push.
- The pull request title must be a conventional commit.
- cspell checks every Markdown file and the pull request title against `cspell.json`. Project words go in `words` there, and general vocabulary goes in `.cspell/custom-dictionary.txt`.
- The `android` job builds the development debug APK. It cannot build a production variant, because those read `google-services.json`, which the repository does not hold, so no CI job checks the Firebase wiring or the release signing.
- The `ios` job builds the development debug app without signing on `macos-latest`, from a checkout without `GoogleService-Info.plist`. No CI job builds the production flavor of iOS, and no CI job builds macOS.
- The `windows` job is the only verification of the Windows build. Do not add a local Windows build script.
- The `web` job runs `test/web/` in Node, as `merry run web` does.
- The `functions` job type-checks and tests `functions/` in Node 24, as `merry run functions` does.
- The `rules` job runs `test/rules/` against the Firestore and Storage emulators with the project ID `demo-kkomkkomi`, as `merry run rules` does. `merry run check` leaves it out, because the emulators need Java 21. Firebase documents that a project ID with the `demo-` prefix reaches emulators only (https://firebase.google.com/docs/emulator-suite/connect_firestore, "Choose a Firebase project"), so never run the rules tests under another project ID.

Trunk installs a format hook on commit and a check hook on push (`.trunk/trunk.yaml`).

Codex reviews every pull request, and CodeRabbit was attached on 2026-10-01 after pull request 1.
`/pr-loop` keeps its usual terminal conditions, so a CodeRabbit verdict or skip notice counts when one arrives.
If CodeRabbit posts nothing on a pull request, the operator's ruling of 2026-10-01 applies: the merge needs a clean Codex verdict on the head commit, every check passing, and no unresolved review thread, and the report states that one reviewer ran.

## Release

A release runs on the operator's machine with fastlane, and no CI job releases.
The root `Gemfile` pins fastlane (run `bundle install` once), `fastlane/Fastfile` holds the lanes, `fastlane/Appfile` holds the bundle ID, and `merry.yaml` owns the scripts that run them.

- `merry run release check` is offline. It fails for a working tree with uncommitted changes, for a version of `pubspec.yaml` without its entry in `CHANGELOG.md`, for a build number without `fastlane/metadata/android/<locale>/changelogs/<build>.txt` in each locale, for a store text that the metadata lanes upload when it is over its store limit in `tool/release_check.dart`, and when `config/revenuecat.json` is missing or does not hold each of its two keys as a string. The metadata lanes run it with `--metadata`, which leaves out the keys file, because they build nothing.
- `merry run build apk`, `merry run build aab`, and `merry run build ipa` read the RevenueCat public SDK keys from `config/revenuecat.json` with `--dart-define-from-file`, as `REVENUECAT_IOS_API_KEY` and `REVENUECAT_ANDROID_API_KEY`. Git ignores the file, so the keys are never tracked (operator, 2026-10-05), and `config/revenuecat.example.json` shows its two keys with empty values. A file with empty keys builds an app without subscriptions on purpose, and the release check of `release ios` and `release android` stops for a missing file, a file that is not a JSON object, and a missing or misspelled key, so that no build lacks the keys by accident.
- `merry run build aab` and `merry run build ipa` delete the file of the last build first, and after the build write `build-record.txt` beside the new file with `tool/build_record.sh`: the commit of HEAD and the SHA-256 of the file. A tree with uncommitted changes gets no record. No tool reads the record since the `./store-upload` launcher was removed.
- `merry run release ios` runs the check, checks the credentials, deletes `build/ios/ipa`, builds the production IPA, and uploads it to TestFlight. The upload lane stops for an IPA whose version and build number are not those of `pubspec.yaml`, because `flutter build ipa` exits 0 when the export of the IPA fails after the archive.
- `merry run release android` runs the check, checks the credentials, builds the production App Bundle, and uploads it with its changelogs to the internal testing track. To upload to the closed testing track instead, run the same steps by hand and end with `bundle exec fastlane android internal track:alpha`.
- `merry run release metadata ios` and `merry run release metadata android` run the check, so that a text over its store limit stops before the upload.
  The iOS screenshot lane loads `AppStoreAssets.prepare` from `APP_STORE_ASSETS_ROOT` or the sibling checkout, so its behavior depends on that checkout and is not protected by the runtime pin below.
  Use the guarded entrypoint for an approved screenshot transfer; `bundle exec fastlane ios metadata skip_screenshots:true` uploads the texts only.
  The Android lane uploads its metadata and images without a binary or review submission; it needs a release on the internal testing track that holds the build number of `pubspec.yaml`, because `supply` stops before it uploads when it finds no release on the track that it is given. The store listing belongs to the app and not to a release, so when the internal track holds none, `bundle exec fastlane android metadata track:alpha version_code:<code>` names a release of the closed testing track instead (on 2026-10-19 that track held version codes 3 and 1, and the internal track none).

The build number is an integer that grows by one for each upload, so bump `pubspec.yaml`, add the changelogs, and commit before a release.
iOS signs automatically with the `DEVELOPMENT_TEAM` of the Xcode project, without `match`.

| Variable                                                                                                                | Read by              | Value                                                                                        |
| ----------------------------------------------------------------------------------------------------------------------- | -------------------- | -------------------------------------------------------------------------------------------- |
| `APP_STORE_CONNECT_API_KEY_KEY_ID`                                                                                      | the iOS lanes        | The key ID of the App Store Connect API key                                                  |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID`                                                                                   | the iOS lanes        | The issuer ID of that key                                                                    |
| `APP_STORE_CONNECT_API_KEY_KEY_FILEPATH`                                                                                | the iOS lanes        | The path of its `.p8` file, outside the repository                                           |
| `SUPPLY_JSON_KEY`                                                                                                       | the Android lanes    | The path of the JSON key of the Google Play service account, outside the repository          |
| `SUPPLY_RELEASE_STATUS`                                                                                                 | `release android`    | `draft` (the default, which a draft app in Play Console needs) or `completed`                |
| `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_ALIAS`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEYSTORE_PRIVATE_KEY_PASSWORD` | the App Bundle build | The upload key, which `android/app/build.gradle.kts` reads, or else `android/key.properties` |

A lane without its variables, or with a path that names no file, stops before any network call and names the variable.
Every script but `release check` publishes to a store, which is an external action: the operator runs it or approves each run.
See `AGENTS.md` § Store Uploads (moved 2026-11-02).
`fastlane/creative/ios/<locale>/header.png` and `search.png` are the App Store product page header and search result image that `merry run store` renders; no lane and no pinned runtime uploads them, so the operator adds them in App Store Connect (the Header and Search Results tab of the version page, or Asset Library) after checking them with its preview tool, because Apple publishes no safe area outside its design templates.
`docs/notes/2026-10-02-first-test-distribution.md` lists the console steps that stay with the operator.

## Architecture

The M1 design splits the code under `lib/` into units and owns the table of what each unit may import.
Each screen is a folder under `lib/presentation/` in the Very Good CLI layout: `cubit/` and `view/` subdirectories and a barrel file named after the screen.
Other code imports a unit or a screen through its barrel, for example `package:kkomkkomi/presentation/client_list/client_list.dart`.

- **Units.** `lib/domain/`, `lib/application/`, `lib/persistence/`, `lib/export/`, `lib/firebase/`, `lib/billing/`, and `lib/presentation/` exist, each with a barrel file named after the unit. `domain/` holds the entities and their rules, `Plan` among them, `application/` holds the repository interfaces, the `LocalDataRepository` that erases the whole database among them, the `Identity`, `Entitlements`, `ExternalLinks`, `IdGenerator`, `Clock`, `PhotoCapture`, `PhotoStore`, `ReportFont`, `ReportShare`, `LinkShare`, `Publisher`, and `NetworkMonitor` ports, the use cases, `DeleteAllData` among them, the `PublishQueue`, `reportLinkOf`, which makes the link of a report, and `withoutLocation`, which removes the location from a photo, and `persistence/` holds the version 8 SQLite schema, its upgrades from versions 1 through 7, and the `sqflite` repositories. `export/` holds the report document builder, the report file name, and the A4 PDF renderer. `firebase/` holds `FirebaseIdentity` and `FirebasePublisher`, the Firebase adapters of the `Identity` and `Publisher` ports. `billing/` holds `RevenueCatEntitlements`, the RevenueCat adapter of the `Entitlements` port, `PurchasesStore`, the one class that calls `purchases_flutter`, and `revenueCatEntitlementsFor`, which gives that adapter for iOS and Android when the key of the platform is not empty. The adapter configures RevenueCat with the Firebase user ID as the app user ID at its first call of any method that has a user ID, moves RevenueCat to a new user ID with `logIn`, shares one configuration between calls at one time, and gives the last plan that it knew for the current user ID, and Free before any answer for that ID, when RevenueCat or the identity fails. It sells the packages `basic_monthly`, `basic_annual`, `pro_monthly`, and `pro_annual` of the current offering, in that order, with the `priceString` of the store, and ignores any other package. On Google Play, `PurchasesStore` passes the subscription identifier of the Google Play subscription in use, without its base plan, as the product that a purchase replaces, because `basic` and `pro` are two Google Play subscriptions and a purchase without it would start a second one, with the replacement mode `withTimeProration` for a change to the other subscription and `chargeFullPrice` for a change of the base plan inside one subscription, which Google Play fails in any mode but `CHARGE_FULL_PRICE` and `WITHOUT_PRORATION`; a purchase does not start when that read fails. A purchase or a restore updates the known plan from the answer of the store and reports a change on `planChanges`; the error codes `purchaseCancelledError` and `paymentPendingError` give `cancelled` and `pending`, and every other failure gives `failed`. A `PlanOffer` is active when its store product grants an active entitlement; for Google Play the store also answers the subscription and base plan identifiers joined by a colon. `presentation/` holds one folder per screen, the adapters of the other nine ports, `UnavailableIdentity`, `UnavailablePublisher`, and `FreeEntitlements` (which sells nothing) under `adapters/`, and what more than one screen uses under `shared/`. `test/domain/boundary_test.dart` fails when a file under `lib/domain/` imports a library that the design does not allow. That rule excludes `package:meta`, so a domain file that overrides `==` carries an `ignore_for_file` comment for the lint that asks for `@immutable`.
- **Entry points.** `lib/main_development.dart`, `lib/main_staging.dart`, and `lib/main_production.dart` each call `bootstrap()` from `lib/bootstrap.dart`. `bootstrap()` installs the `FlutterError.onError` handler and `AppBlocObserver`, asks the `Identity` of the flavor for the user ID once, opens the database, and passes the repositories, that identity, the `Entitlements` of the flavor, and the publish queue to the builder that makes the app. It does not ask the entitlements for the plan. It does not wait for the answer of the identity, and a failure of the identity does not stop it. When the database is open, it starts a `PublishQueue` with the publisher of the flavor, and a failure of the queue does not stop it either. Before the queue starts, it runs `RecoverLostCapture`, and the builder gets what that step did, so that `App` opens the visit of a lost capture over the client list; a failure of the step is logged and the app opens on the client list. While the database does not open, it shows `StartupFailureApp`, and the retry control opens the database again. `App` provides the client, visit, company profile, and open capture repositories, the identity, the entitlements, the publish queue, the adapter of each other port that a screen uses, and one `DeleteAllData` for its whole life to the widgets below it through `RepositoryProvider`. The publish repository, the `Publisher`, and the `NetworkMonitor` go only to the queue, and the `LocalDataRepository` goes only to `DeleteAllData`. `App` has no default identity and no default entitlements, because the flavor decides them. The production entry point makes one `FirebaseIdentity` for `bootstrap()` and the RevenueCat adapter, and gives `FreeEntitlements` when `revenueCatEntitlementsFor` gives none; development and staging give `FreeEntitlements`. Configuration that all flavors share goes in `bootstrap()`, and configuration for one flavor goes in its `main_*.dart`.
- **Flavors.** Android defines them in `android/app/build.gradle.kts` with the application ID suffixes `.dev` and `.stg`. iOS and macOS define them as Xcode schemes. `windows/` has no flavor configuration, so a Windows build selects its entry point with `--target` alone. The `.vscode/launch.json` configurations pass the matching `--flavor` and `--target`.
- **Theme.** `appTheme()` in `lib/app/view/app_theme.dart` is the one theme, light only, and `App` and `StartupFailureApp` use it. Its color scheme takes the tokens of `web/index.html` for the roles that match one and generates the others from the teal, and a dialog sits on white because the teal of a text button is under 4.5:1 on the generated dialog color. `test/app/view/app_theme_test.dart` fails when a pair of colors that carries text is under 4.5:1. `showConfirmDialog` takes `isDestructive` for an action that deletes data, closes a link, or loses a note, and a `Notice` from `lib/presentation/shared/` shows a message in the info tone or a failure in the error tone.
- **State.** Each page widget creates its Cubit in a `BlocProvider` and renders a separate view widget that reads it, as `ClientListPage` and `ClientListView` do. This split lets a widget test inject a mock Cubit into the view. A state is one final class with a status enum and hand-written equality, in a `part` file of its Cubit, and every state but `ReportLinkState` has `copyWith`. A Cubit turns a `DomainException` into a `NameEntry` value in its state, and `NameField` shows the message of that value under the field. A screen or a dialog that saves wraps itself in `SaveGuard`, which takes no touch and no back press while the change is on its way to storage, so that the answer finds the screen as the change left it.
- **Identity.** See `docs/domain/IDENTITY.md` § Identity (moved 2026-11-02).
- **Photos.** See `docs/domain/PHOTO.md` § Photos (moved 2026-11-02).
- **Report.** See `docs/domain/REPORT.md` § Report (moved 2026-11-02).
- **Publishing.** See `docs/domain/PUBLISHING.md` § Publishing (moved 2026-11-02).
- **Deletion.** See `docs/domain/DELETION.md` § Deletion (moved 2026-11-02).

- **Plans.** See `docs/domain/PLANS.md` § Plans (moved 2026-11-02).
- **Navigation.** No router package exists. A page has a static `route()` that makes a `MaterialPageRoute`, and a widget opens it with `Navigator.push`.
- **Web.** See `docs/domain/WEB.md` § Web (moved 2026-11-02).
- **App icon.** `tool/app_icon/symbol.svg` is the master of the mark, and `tool/app_icon/render.sh` owns the list of the files that hold a copy of it and makes the legacy Android images, the 512-pixel Play Store icon of each source set (`android/app/src/<source set>/ic_launcher-playstore.png`, a full square in a 32-bit PNG), the launch images, and the Windows icon. The icons are the same in every language. Android uses an adaptive icon in each source set, and iOS and macOS use the Icon Composer bundles under `ios/Runner/AppIcons/` and `macos/AppIcons/`. The development and staging icons carry a label. The launch screen of Android and iOS shows the icon on a white ground, because the first screen of the app is light.
- **Localization.** All user-facing strings come from `lib/l10n/arb/` through `context.l10n`, which `lib/l10n/l10n.dart` defines. `app_en.arb` is the template and `app_ko.arb` is the Korean locale, so each new key goes in both files. A new locale also needs an entry in `CFBundleLocalizations` in `ios/Runner/Info.plist`, and an `InfoPlist.strings` under `ios/Runner/<locale>.lproj/` in the `InfoPlist.strings` variant group of the Runner target. Every `MaterialApp` takes `appLocalizationsDelegates` from `lib/l10n/l10n.dart`, because the generated `AppLocalizations.localizationsDelegates` does not serve the widgets of `material_ui`. Flutter breaks Korean lines between any two syllables, so a screen shows its text through `KeepAllText` in `lib/presentation/shared/keep_all_text.dart` in place of `Text`: `keepAll` puts a word joiner (U+2060) between the grapheme clusters of each word that holds Hangul, so that a line breaks only at a space or a newline, and the accessible label stays the original string. `KeepAllText` is a `Text` of the original string, so `find.text` and `expectWholeText` take the string without the joiners. For a string that holds Hangul, it builds a second `Text` of the joined string below it, so the tree holds two: `find.byType(Text)` matches only the inner one, because it matches the exact type, and `find.textContaining` with a part that the joiners do not split, such as a Latin word, matches both, so a test finds the text with `find.text` of the whole string or with `find.byType(KeepAllText)`. `NameField` gives its helper and its error to the decoration as `KeepAllText` widgets and not as strings, and a test reads the error with the `errorMessage` getter of `InputDecoration` in `test/helpers/field_messages.dart`. A value that leaves the screen never passes through `keepAll`: the content of a text field, a stored value, the PDF, the published report, and the share text. The tooltips are strings that Flutter shows, so they keep the line breaks of Flutter.
- **Tests.** `test/` mirrors `lib/`. Widget tests use `tester.pumpApp()` from `test/helpers/`, which wraps the widget in a `MaterialApp` with `appTheme()` and the localization delegates. Cubit tests use `blocTest`, and view tests mock the Cubit with `MockCubit` from `bloc_test` and stub it with `mocktail`. Repository tests run the `sqflite` repositories against `sqflite_common_ffi`, and `test/persistence/support.dart` opens the in-memory database that they use. `mockRepositories()` from `test/helpers/` gives a widget test repositories that never reach a database. A page test passes the in-memory repositories of `test/helpers/fakes.dart` to `pumpApp`, which then provides what `App` provides. `FakePhotoCapture` and `FakePhotoStore` from the same file replace the camera and the photo files, `FakeOpenCaptureRepository` replaces the stored open capture, and `FakeReportShare` and `FakeLinkShare` replace the share sheet, so no screen test touches a platform channel. `FakeIdentity` replaces the identity, `FakeEntitlements` replaces the entitlements and the store sheet, `FakeExternalLinks` replaces the opener of web pages, `FakePublisher` and `FakeNetworkMonitor` replace the backend and the network state, `FakeLocalDataRepository` replaces the erase of the database, and no test starts Firebase or RevenueCat: `test/billing/purchases_store_test.dart` answers the channel of `purchases_flutter` itself. The queue tests run `PublishQueue` against the in-memory SQLite repositories. A widget test runs in fake time, where the database does not answer, so a screen test that runs the queue uses `FakePublishRepository`, and `publishQueueOf()` makes a queue over the repositories of a test, without a backend unless the test gives one. `FileReportFont` reads the font files from the source tree, so a screen test renders the PDF, and `PdfSummary` from `test/helpers/` reads the size, the text, and the images of each page of the result. `PdfSummary` is not a PDF library: it follows the cross-reference stream to the catalog, the page tree, and each page, decodes the compressed streams on that path, and reads only the forms that the `pdf` package writes. A photo on the screen is a `PhotoThumbnail`, and `tester.photoPathsIn()` reads the file paths that the thumbnails show, because the fake photo store holds no file to show. `tester.useNarrowScreenWithLargestText()` sets the 320 pixel width and the largest text size at which no screen may overflow, and `tester.expectWholeText()` fails for text that the framework cuts without an overflow error.

## Documents

Specs go in `docs/specs/`, implementation plans in `docs/plans/`, and working notes in `docs/notes/`.
`docs/specs/2026-10-01-m1-local-first-design.md` is the design of the M1 build: its units, domain model, screens, and what it leaves out until a Firebase project exists.
Read it before feature work and cite it instead of restating it.
The briefs under `docs/plans/` split that design into pull requests.

## Conventions

- Material widgets come from `package:material_ui/material_ui.dart`. No file imports `package:flutter/material.dart`.
- Constructors are declared with `new` in place of the class name, for example `const new({super.key});`, and a class with an empty body ends with `;`. Keep this Dart 3.13 syntax and do not rewrite it to the older form.
- Lint rules are `very_good_analysis` plus `bloc_lint/recommended`, with the exceptions that `analysis_options.yaml` lists. The formatter page width is 120.
