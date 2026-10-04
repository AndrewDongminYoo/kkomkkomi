# Brief: store screenshots and the Play feature graphic

Read `CLAUDE.md`, `tool/web_assets/` (the cards and `render.sh`), the token block of `web/index.html`, `test/helpers/` (the fakes and `pumpApp`), and `fastlane/metadata/` before you write code.
Load the `user-facing-copy` skill before you write any headline.

## Why

The first TestFlight and Google Play listings need screenshots and a feature graphic, and the repository has none.
Simulator captures are ruled out: on 2026-10-03 three boots of the iOS simulator saturated this machine (load average above 80) before one screen was captured.
The operator chose on 2026-10-04 to render the screens with Flutter at store resolution, from fixture data, without a device.
The operator also chose an iPhone-only app (the release flow brief changes the device family), so no iPad set is needed.

## Store requirements (read on 2026-10-04)

- App Store: an iPhone 6.9-inch set is required; 1320 × 2868 portrait is one accepted size; 1 to 10 screenshots per size; PNG or JPEG without an alpha channel (https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
- Google Play: at least 2 phone screenshots, and at least 4 at 1080 × 1920 or larger in 9:16 portrait for the recommended formats; a 1024 × 500 feature graphic is required; JPEG or 24-bit PNG without alpha (https://support.google.com/googleplay/android-developer/answer/9866151).

## Goal

A command regenerates every store image from the repository: framed screenshots in Korean and English for iPhone (1320 × 2868) and Android (1080 × 1920), and the Play feature graphic (1024 × 500), all without an alpha channel.

## In scope

1. A screen renderer under `tool/store_screenshots/`, outside `test/`, so that `merry run check`, `merry run coverage`, and CI never run it. It pumps the real screens with fictional fixture data through the fakes of `test/helpers/` or equivalents, and writes one raw PNG per screen, locale, and platform size. Four or five screens that show only M1 features: the client list, the client detail with zones, the visit capture with before and after photos, the report preview, and the shared web report link if it reads well. Photos come from fixture images that the repository may hold (generate neutral placeholder room photos, no people, no screens, no documents).
2. Real glyphs: load `assets/fonts/NotoSansKR-Regular.ttf` and the Material Icons font of the Flutter SDK into the render, because the test font draws boxes. Only the Regular weight is bundled, so bold styles render at the Regular weight; say so in the pull request body and do not add a font asset.
3. Frames: an HTML card per screenshot in the style of `tool/web_assets/`, with a short headline per screen in Korean and English from one copy file, the brand tokens of `web/index.html`, and the raw screen inside; rendered by a script in the manner of `tool/web_assets/render.sh` at the exact store size. The feature graphic is a card of the same family at 1024 × 500 with the app icon and the product line.
4. Output paths that the release flow reads: iPhone screenshots in `fastlane/screenshots/ios/{ko,en-US}/`, Android screenshots in `fastlane/metadata/android/{ko-KR,en-US}/images/phoneScreenshots/`, and the feature graphic in `fastlane/metadata/android/{ko-KR,en-US}/images/featureGraphic.png`. Commit the generated images.
5. One merry script that runs the renderer and the frames in order, documented in `CLAUDE.md` with what it needs (a headless Chromium, a network connection if a card loads a web font).
6. A check in the script, or a separate one, that fails for an image with an alpha channel or a wrong size.

## Copy rules

- Fixture companies, clients, zones, and notes are fictional and plain; the repository is public.
- Headlines describe M1 features only, and name no price, plan, or later milestone.
- Korean copy follows the `user-facing-copy` skill.

## Out of scope

- Any upload, and any change to the store metadata text.
- An iPad set.
- Changing the app theme, the fonts that the app uses, or the screens themselves.

## Requirements

- No new package dependency in `pubspec.yaml`; tools that the machine already has (ImageMagick 7, a headless Chromium) may be named in the script.
- Read every generated image before the pull request: a structural check passed while a headline was missing in an earlier project.

## Acceptance criteria

- `merry run check` and `merry run coverage` pass unchanged.
- The script regenerates every image, and the check reports each image's size and that none has alpha.
- The pull request body lists every image path with its size, the headlines in both languages, and the font limitation.
