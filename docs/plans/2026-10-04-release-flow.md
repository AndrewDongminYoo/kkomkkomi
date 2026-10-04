# Brief: a local release flow for TestFlight and Google Play internal testing

Read `CLAUDE.md`, `merry.yaml`, `android/app/build.gradle.kts` (the `ANDROID_KEYSTORE_*` variables), `fastlane/metadata/`, `CHANGELOG.md`, `docs/notes/2026-10-02-first-test-distribution.md`, and the `release-cut` skill before you write code.

## Why

The repository holds store metadata but no way to build and upload a release.
The operator's other personal Flutter apps release locally with fastlane, keep CI out of releases, sign iOS automatically without `match`, read the Play key from `SUPPLY_JSON_KEY`, and split a release script into a check and a publish step; follow that shape.
Decisions of the operator on 2026-10-04:

- The app becomes iPhone-only.
- iOS uploads authenticate with an App Store Connect API key, whose file stays outside the repository.
- `ITSAppUsesNonExemptEncryption` is declared `NO`: the app code encrypts nothing, and the Firebase SDKs use HTTPS.
- The build number is an integer that grows by one per upload, continuing `1.0.0+1`.

## In scope

1. `TARGETED_DEVICE_FAMILY = 1` in every build configuration of the Runner target, and `ITSAppUsesNonExemptEncryption` set to `false` in `ios/Runner/Info.plist`. Keep the `ios` CI job passing.
2. A root `Gemfile` that pins fastlane, with its `Gemfile.lock` in the same commit, and `fastlane/Fastfile` (plus `Appfile` if useful) with:
   - an iOS lane that uploads `build/ios/ipa/*.ipa` to TestFlight with `app_store_connect_api_key` from environment variables (key ID, issuer ID, and the path of the `.p8` file);
   - an iOS lane that uploads the metadata of `fastlane/metadata/ios` and the screenshots of `fastlane/screenshots/ios` without a binary and without submitting for review;
   - an Android lane that uploads `build/app/outputs/bundle/productionRelease/app-production-release.aab` to the internal track with the key of `SUPPLY_JSON_KEY`, as a draft if the app is still a draft in Play Console;
   - an Android lane that uploads the metadata and images of `fastlane/metadata/android` without a bundle.
     A lane that misses a credential stops before any network call and names the missing variable.
3. Merry scripts in `merry.yaml`:
   - `release check`: offline checks that fail with a clear message when the working tree is dirty, when `CHANGELOG.md` has no entry for the version of `pubspec.yaml`, when `fastlane/metadata/android/<locale>/changelogs/<build>.txt` is missing for the build number of `pubspec.yaml`, or when a store text is longer than its store limit (the limits of the `release-cut` skill);
   - `release ios` and `release android`: run the check, build the production release (`flutter build ipa` with the production flavor, and `merry run build aab` for Android), and run the upload lane;
   - separate scripts for the metadata lanes.
4. `.gitignore` entries for fastlane output and for credential files (`*.p8`, service account JSON, `fastlane/report.xml`), if missing.
5. `CLAUDE.md`: a short release section that names the scripts, the environment variables, and that a publish is an external action that the operator runs or approves each time. Update `docs/notes/2026-10-02-first-test-distribution.md` so that its build and upload steps use the scripts, and record there that Google Play needs the first bundle uploaded by hand in Play Console before `supply` works (https://docs.fastlane.tools/actions/supply/, "set up your app manually first by uploading at least one build").

## Out of scope

- Any upload, store record, or real signing key. Verify the publish scripts only as far as they stop for a missing credential.
- A CI release job.
- Store images (the store assets brief makes them) and store text changes.
- A script that bumps the version.

## Requirements

- `bundle exec fastlane lanes` lists the lanes, and `merry run release check` passes on a clean tree at the current version and fails once for each check when its input is broken; show each failure in the pull request body.
- No credential, key path of the operator, or account email in any tracked file.

## Acceptance criteria

- `merry run check` and `merry run coverage` pass; CI passes, the `ios` job included.
- The pull request body lists the lanes, the scripts, the environment variables, and the console steps that stay with the operator.
