# Brief: build iOS in CI from a clean checkout

Read `CLAUDE.md` before you write code.

## Problem

FlutterFire added `ios/Runner/GoogleService-Info.plist` to the Resources build phase of the Runner target in `ios/Runner.xcodeproj/project.pbxproj`, and the same for macOS in `macos/Runner.xcodeproj/project.pbxproj`.
`.gitignore` keeps that file out of the repository.
A clean checkout therefore has a required resource that does not exist, and Xcode is expected to stop every iOS build with a missing input file, for every flavor.
No CI job builds iOS, so nothing has checked this.
`CLAUDE.md` says that a fresh clone needs `flutterfire configure` only before a production build, which is then wrong for iOS.

## Goal

A clean checkout builds the iOS development flavor without any Firebase config file, and CI proves it on every pull request.

## In scope

1. Reproduce the failure first: a CI job, or a local `flutter build ios --no-codesign --debug --flavor development --target lib/main_development.dart` in a clean worktree when the machine load allows one platform build.
2. Make the plist optional in the iOS and macOS Runner targets, in the same spirit as Android, which skips the google-services task for the development and staging variants. One way: remove the plist from the Resources phase and copy it with a Run Script build phase only when the file exists. Choose the way, and state it in the pull request body.
3. A production build with the plist present must still bundle it. Check the built app bundle for the file in the operator's main checkout only if the parent session allows it; otherwise state that the production bundle was not checked.
4. Add an `ios` job to `.github/workflows/main.yaml` on `macos-latest` that runs `flutter pub get` and the development build above. Pin actions by SHA, as the other jobs do.
5. Correct the `CLAUDE.md` sentence about `flutterfire configure`.

## Out of scope

- Signing, archives, and any production iOS build in CI.
- The `InfoPlist.strings` of issue #8, which is the next brief.

## Requirements

- Do not commit any Firebase config file.
- Do not edit the Xcode project by hand in ways that Xcode rewrites. Prefer the smallest edit, and keep the project file valid: the `ios` job is the proof.
- Do not touch `web/` or the icon assets.

## Acceptance criteria

- The `ios` job passes on the pull request.
- `merry run check` passes.
- The pull request body states what was verified about the production bundle and what was not.
