# Gallery photos: deferred to M2

On 2026-10-03 the operator ran the production release build of `339cd34` (brand theme, client name on the capture screen, Korean keep-all line breaks) on an iPhone and approved the new design.
The operator also noted that a zone photo can only be taken with the camera, and that a photo from the gallery cannot be used.
The operator chose to keep this for M2.

## Where the app stands

- The M1 design takes each photo from the camera through `image_picker` (`docs/specs/2026-10-01-m1-local-first-design.md`, "Photos").
- `ios/Runner/Info.plist` and the `InfoPlist.strings` files already hold a photo library usage description, which the app never uses (`CLAUDE.md`, "Photos").
- M2 replaces the picker adapter with a camera preview inside the app, because the ghost overlay of the previous photo needs a live preview (the same design section).

## Questions to settle before a brief

1. Trust of the report. Today every photo of a visit was taken during that visit. A gallery photo can be older, and the 발주처 uses the report as a record of the cleaning, so the report may need to mark a photo that came from the gallery or show when it was taken. This is a product decision.
2. File format and location. `withoutLocation` accepts only a well-formed JPEG, and any other file fails the save with a `FormatException` (`CLAUDE.md`, "Photos"). A gallery photo can be in another format, such as HEIC. Check on a device which format `image_picker` returns for a gallery pick with the app's size and quality options, and decide whether to convert it or to refuse it, before the location stripping can apply.
3. Fit with the in-app camera of M2. A gallery pick is a separate source from the camera, so it can come before, with, or after the in-app camera; the brief should say which.
