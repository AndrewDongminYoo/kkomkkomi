# Brief: issue #8, localize the iOS usage descriptions

Read `CLAUDE.md` and issue #8 before you write code.
This brief depends on the brief `docs/plans/2026-10-02-ios-ci-build.md`: the `ios` CI job must exist, because it is the only check of the Xcode project file.

## Decisions taken for the operator

The operator asked to continue without stopping, so these defaults apply. The pull request body repeats them.

- `NSPhotoLibraryUsageDescription` stays. The `image_picker` README gives the App Store policy reason for it. Check that the README still says so, and quote it in the pull request body.
- The Korean texts stay as they are in `ios/Runner/Info.plist`.
- The English texts are new. Load the `user-facing-copy` skill and write them in the Apple style it describes.

## In scope

- `ios/Runner/en.lproj/InfoPlist.strings` and `ios/Runner/ko.lproj/InfoPlist.strings` with both keys, added to the Runner target.
- The `Info.plist` values stay as the fallback.

## Out of scope

- macOS, which is not a target.
- Any check on a device or a simulator. State in the pull request body that the prompt was not seen in either language.

## Acceptance criteria

- The `ios` CI job passes.
- `merry run check` passes.
- The pull request closes issue #8.
