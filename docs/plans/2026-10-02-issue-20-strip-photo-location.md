# Brief: issue #20, strip the location from photos

Read `CLAUDE.md` and issue #20 before you write code.

## Problem

`image_picker_android` copies the GPS tags of the camera file into the smaller file that the app keeps, and a publish uploads that file where anyone with the report link can read it.
Whether iOS keeps a location was not checked.
The privacy policy page states that a photo keeps its location, which is true today.

## Goal

No photo that the app keeps or uploads carries a GPS tag, on any platform, including the photos that were taken before this change.

## In scope

- One function in `lib/application/` or `lib/domain/` that takes JPEG bytes and returns JPEG bytes without GPS data.
- Apply it where a new photo is stored, so the kept file, the PDF, and the upload are all clean.
- Apply it to the bytes that a publish reads before the upload, so a photo that was stored before this change is clean when it is published.
- Update the sentence about the location on both privacy policy pages under `web/privacy/`.

## Requirements

- The photo must still show the right way up. `image_picker` may leave the rotation in the EXIF orientation tag instead of rotating the pixels: find out from the plugin source of the locked versions, and keep the orientation, or apply it to the pixels, so that the result displays the same.
- Removing the whole EXIF segment is acceptable only if the orientation is kept by another way.
- Prefer no new dependency. A small JPEG segment parser in Dart is enough if it is tested. If you add a package, state why the parser is not enough.
- A JPEG that is not well formed must not crash the capture or the publish: keep the original bytes and log it, or fail the step with a reason that the person can act on. State which, and why.

## Tests

- Fixtures: a JPEG with GPS tags and orientation 6, a JPEG with no EXIF, and a truncated JPEG.
- The GPS tags are gone after the function, the orientation still displays the same, and the image still decodes.
- The store path and the publish path both call the function: a test fails if either stops calling it.

## Acceptance criteria

- `merry run check` and `merry run coverage` pass.
- The pull request closes issue #20.
- The pull request body states what was not checked on a device.
