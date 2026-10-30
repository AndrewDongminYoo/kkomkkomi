# Capture-time device acceptance plan (#61)

## Authority and workspace

The operator explicitly invoked `$pr-loop #61` for the previously selected bounded iPhone acceptance.
Use the main workspace on `codex/iphone-capture-time-61`, based on `e7ede462f40730501d7998c78e256a552ef9fea7`.
The [acceptance spec](../specs/2026-10-30-capture-time-device-acceptance.md) retains the approved camera, observation-time and local-output contracts.
No Android phone is available, and daily-phone writes remain separately authorized.
Gated merge is delegated by the invocation; branch cleanup and store or backend actions are not included.

## Owned paths

- This plan and the matching acceptance spec.
- A dated device-result note after actual operator observations.
- Applicable current evidence claims in `CLAUDE.md`, `docs/notes/2026-10-02-first-test-distribution.md` and directly affected metadata or camera specifications.

No Dart or native implementation edit is planned.
A reproduced defect requires a focused failing regression and the smallest contract-preserving repair before delivery.
Preserve prior dated evidence and keep local build/check logs and approval media in the visible sibling review directory recorded in Git-local state.

## Steps and success criteria

1. Identify the reusable DEV build and compare it with current main.
   Verify executable-input equivalence, both iOS pin hashes, the retained manifest's file hashes and `codesign --verify --deep --strict`; preserve the earlier installation record.
2. Read current camera/visit/report controls and prepare the operator checklist.
   Verify that every step maps to implemented UI and that no device write runs automatically.
3. Run focused camera, capture, persistence and rendered-output regressions.
   Verify with `flutter test --no-pub --concurrency=2` on the explicit affected test paths, plus `flutter analyze --no-pub` and `dart format --output=none --set-exit-if-changed lib test`.
   These checks inspect controlled observations and generated output, not physical sensor or native permission behavior.
4. Receive operator-run iPhone results for camera capture, captions in preview/actual PDF, persistence, cancellation, different visit dates, gallery replacement and preview resume.
   Retain unobserved scenarios and Android as explicit gaps; wait rather than inventing a completed result.
5. Record the bounded observations and check applicable documentation against the same result.
   Run explicit-path Markdown checks, spelling and relative-link checks, then one scope-calibrated adversarial review.
6. Commit, push and create a non-closing evidence PR only after useful physical results exist.
   Observe current-head CI and required hosted reviews, complete the final body and operator assignment, and satisfy any required visual approval before the delegated merge.
7. Verify the exact merge, review scoped memory consistency under the retained operator request, preserve a visible completion receipt and retire only this loop's owned completed state.

## Verification boundaries

No new unit test is needed for procedure-only documents; use the existing meaningful regressions.
Run full project checks and coverage if a behavior repair changes executable inputs, and follow any required repository publication gate.
Do not rerun a heavy native build simply to regenerate equivalent acceptance evidence.
Do not close #61 while required Android or other material device/output acceptance remains incomplete.
