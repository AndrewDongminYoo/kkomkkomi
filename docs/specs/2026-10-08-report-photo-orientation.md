# Report photo slot orientation

Date: 2026-10-08.
The operator approved the proposed behavior of issue #62 and proceeding now instead of waiting for field comparison.

## Contract

The PDF and report preview use one slot ratio for both photos of each zone.
Use 3:4 only when both photos exist and both are portrait after their Exif orientation is applied.
Use 4:3 for every other case, including mixed directions, square photos, empty slots and unreadable preview photos.
Show the whole photo without cropping.
Keep source and capture-time captions, status, empty-slot notices and notes.
Keep a zone name and its photo row together in the PDF; long notes may span pages.
Portrait rows may reduce the number of zones on a page.

## Implementation constraints

Reuse the installed PDF image reader, whose image dimensions account for JPEG rotation.
Read preview orientation through the existing photo store when the report loads and retain only the portrait photo references.
An unreadable photo keeps the report accessible with its existing broken-image placeholder and a landscape slot; PDF sharing still reports a file failure.
No new dependency, persistence field, photo rewrite, web layout change or device operation is needed.
The M1 local-first design owns the existing units and report model.

## Acceptance

- Exercise portrait pairs, landscape pairs, both mixed orders, square photos, missing photos and rotated JPEGs.
- Read actual preview slot dimensions and actual image drawing rectangles from generated PDF bytes.
- Check that portrait pagination keeps names and pairs together, retains every zone and stays within page margins.
- Check Korean and English previews at 320 pixels with the largest supported text scale.
- Run the project check and 100% line-coverage gates, then review rendered preview and PDF artifacts.
- Operator visual approval remains required before merge.
