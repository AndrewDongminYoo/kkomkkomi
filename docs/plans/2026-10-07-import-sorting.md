# Import sorting delivery plan

## Owned scope

The root owns the existing 202 Dart import changes, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `merry.yaml`, `tool/check_imports.dart`, its tests, the Android CI sorting step, and the existing spelling changes in `cspell.json`, `.cspell/custom-dictionary.txt`, and `tool/photo_fixtures/make.py`.
Read-only reviewers inspect source equivalence and tooling independently.

## Execution

1. Compare all changed import directive tokens and executable tokens against the base; prove that changed import and body fixtures fail.
2. Reproduce unsafe sorter scope and missing idempotency enforcement in an isolated fixture, then add shared source discovery, generated-file exclusions, and write, local check, and CI lanes that leave blank lines to Dart formatting.
3. Restore the single-import lint suppression in `keep_all_text.dart` and exclude it from the sorter because the sorter moves per-import comments.
4. Repair the configuration's own spelling check and rerun sorting only within the approved scope.
5. Run `merry run check`, `merry run coverage`, spelling checks, token equivalence, and diff checks.
6. Commit the import policy and mechanical changes together, then commit scoped spelling fixes; push and open a PR.
7. Complete hosted CI and current-head review, verify unresolved threads, and request an operator merge.

## Verification evidence

Keep commands, failing fixtures, review dispositions, and hosted state in the Git-local PR-loop record.
No visual approval is required because executable tokens and rendered behavior do not change.
