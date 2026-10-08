# Capture date implementation plan

## Scope and authority

Use the main workspace on `report-capture-date-83`, based on merged main at `f541d6b3e73a3e4b2fd098878e5f1d48390bd515`.
The approved direction is the matching capture-date spec and issue #83.
The PR loop authorizes implementation, scoped commits, push, PR creation and review responses; merge remains with the operator.
Deployment, branch cleanup and memory recording are outside this invocation.

Owned paths are this plan, `docs/specs/2026-10-08-report-capture-date.md`, `lib/presentation/visit_report/view/visit_report_page.dart`, both files under `lib/l10n/arb/`, and `test/presentation/visit_report/view/visit_report_page_test.dart`.
Generated localizations remain ignored and must be regenerated from the ARB inputs.

## Steps and checks

1. Add a real preview/shared-PDF regression with different-day and different-year timestamps in both languages; observe failure before changing production code.
2. Correct the existing time-only fixture to use matching local dates and include a local-midnight timestamp.
3. Add one localized full-date caption and select it in the shared labels callback using the local calendar date.
4. Regenerate localizations; run the focused file under UTC and Asia/Seoul to exercise the date boundary.
5. Run explicit-path Dart formatting, `merry run check` and `merry run coverage` after checking machine capacity.
6. Render fictional preview and actual PDF artifacts, inspect them, and complete the scoped local review.
7. Commit the coherent fix and contract, push, open the PR, and observe current-head CI and hosted reviews.
8. Request operator visual approval after technical gates complete, then request operator merge.

## Boundaries

Do not change PDF layout, the `ReportLabels` public API, persistence, web output, security rules, existing release artifacts or unrelated documentation.
Do not start a heavy mobile job while the machine is saturated or interfere with another task's simulator.
The focused regression reads real rendered text and generated PDF bytes through `PdfSummary`; it does not prove a physical device or store build.
