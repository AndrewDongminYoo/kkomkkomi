# Report photo slot orientation implementation

Date: 2026-10-08.
Approved direction: issue #62 and the operator's instruction to proceed.
The [slot orientation spec](../specs/2026-10-08-report-photo-orientation.md) owns the behavior.

## Steps

1. Add output regressions in the PDF and report-page tests, extending the existing PDF test reader to observe image drawing rectangles.
   Verify that the current square layout fails the expected portrait and landscape dimensions.
2. Add the shared ratio rule and orientation reader in `lib/export/report_pdf.dart`.
   Select a ratio for each PDF zone and pass it to both slots.
3. Load portrait photo references in `VisitReportCubit`, preserve them in `VisitReportState`, and pass the same shared rule to both preview slots.
   Keep failed photo reads local to that photo and verify cancellation of UI updates after close.
4. Update the report contract in `CLAUDE.md` and affected pagination expectations.
   Test state preservation, rotated photos, unreadable images, source captions and long-note pagination.
5. Run scoped tests, `dart format` on changed Dart paths, `merry run check` and `merry run coverage`.
   Perform one structured local review of the final diff and render fictional-photo previews and PDFs for operator review.

## Ownership and authority

The root agent owns changes in the four report production files, the three corresponding report test files, the PDF test reader and the documentation named above.
Use the main workspace and preserve unrelated edits.
The initial approval covered local implementation and verification.
The operator subsequently invoked `pr-loop`, authorizing scoped commits, push, a PR and hosted review.
Merge, device writes and deployment retain their separate approval boundaries.
