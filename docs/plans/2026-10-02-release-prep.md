# Brief: prepare the first test distribution

Read `CLAUDE.md` and the `release-cut` skill before you start.
This brief depends on the privacy policy brief, whose page is at `https://kkomkkomi.web.app/privacy/`.

## Goal

Everything in the repository that the first TestFlight and Google Play internal testing upload needs, proven by a release build of each platform, and a written list of the console steps that only the operator can take.

## Decisions taken for the operator

- The bundle and application ID is `kr.donminzzi.kkomkkomi` (operator, 2026-10-02). iOS and Android already use it. Change only the macOS production ID in `macos/Runner/Configs/AppInfo.xcconfig`, which is still `com.example.myApp`. Do not run `flutterfire configure`. The Firebase macOS app is still registered as `com.example.myApp`: report that mismatch as a console item, because macOS is not a target.
- Store metadata follows the operator's two-store Flutter repositories: `fastlane/metadata/ios/{ko,en-US}` and `fastlane/metadata/android/{ko-KR,en-US}`. Create the tree without asking.
- The first version is `1.0.0+1`, which `pubspec.yaml` already holds.

## In scope

1. The macOS bundle ID.
2. `CHANGELOG.md` with the `1.0.0` entry, per `release-cut`.
3. Store metadata in Korean and English: name, subtitle (iOS), short description (Play), full description, keywords (iOS), privacy policy URL, support URL, release notes for `1.0.0` build `1`, and categories. Load the `user-facing-copy` skill first. Describe only what M1 ships. Write no price and no plan.
4. A release build of each platform, one at a time:
   - Android: generate a throwaway keystore in your scratchpad, pass it through the `ANDROID_KEYSTORE_*` variables that `android/app/build.gradle.kts` reads, and build the production release App Bundle. Never commit or keep the key. This checks R8 and `proguard-rules.pro`.
   - iOS: `flutter build ios --release --no-codesign --flavor production --target lib/main_production.dart`, with `ios/Runner/GoogleService-Info.plist` copied in from the main checkout only for the build, as pull request 15 did, and removed afterwards. This checks the Copy Firebase Config phase in a Release configuration.
5. Checks with sources:
   - Whether the app target needs a `PrivacyInfo.xcprivacy`. Read the privacy manifests that the plugins bundle, and add the app manifest if a required-reason API needs it.
   - Whether the `targetSdk` of the Flutter version in use meets the current Google Play minimum for a new app.
6. `docs/notes/2026-10-02-first-test-distribution.md` with the console steps for the operator: the Apple Developer bundle ID, the App Store Connect app record, the TestFlight group, the Play Console app, the internal testing track, the real upload key and where it lives, and draft answers for App Store "App Privacy" and Play "Data safety" derived from the code and from the privacy policy page.

## Do not

- Do not guess `DEVELOPMENT_TEAM`. Read it from the `project.pbxproj` of another of the operator's personal apps that the parent session names, report it, and do not set it unless the operator confirms it.
- Do not create store records, upload a build, or sign anything with a real key.
- Do not add fastlane lanes that upload. Metadata files only.

## Acceptance criteria

- Both release builds succeed, and the pull request body states the commands and the artifact sizes.
- `merry run check` passes, and the Markdown spell check passes.
- The release notes fit the store limits that `release-cut` names, counted with newlines.
