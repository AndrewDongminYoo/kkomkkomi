# Scoped import sorting

## Problem and scope

The existing workspace groups imports in 202 Dart files but its unscoped sorter can rewrite generated code and does not enforce deterministic output.
Review and deliver these import-only changes with the existing spelling configuration changes.
Keep Flutter, third-party package, and project groups with emoji headers.

## Constraints

Preserve import targets, aliases, combinators, executable tokens, and import-scoped lint exceptions.
Exclude generated files and the comment-sensitive `keep_all_text.dart` from automatic sorting.
Replace the incompatible `directives_ordering` lint with a scoped sorter check in the local gate and CI.
The checker compares import order and group comments while `dart format` owns blank lines, because the upstream sorter removes the formatter's separator between package and relative imports.
The same checker applies fixes with `--fix`, so both lanes use identical path normalization and exclusions on every platform.
The existing locked `yaml` package becomes a direct development dependency so the checker can read the same sorter configuration as the write command.
The existing locked `analyzer` package parses complete import directives, including multiline conditional imports, before sorting.
Unsupported annotations or comments outside a directive stop the operation before any source is written, except group headers and a comment-only preamble ending in an initial file-level lint directive.
The checker also retains export URI group and alphabetical ordering from [Dart directives_ordering](https://github.com/dart-lang/sdk/blob/main/pkg/linter/lib/src/rules/directives_ordering.dart).
Unsorted exports or documentation imports stop both lanes before writes; their comments and conditional directives are not rewritten.
Explicit library declarations, including documentation and metadata, stay before ordinary imports.
Library preambles and file bodies are opaque to the upstream line sorter, so import-like comment text or string delimiters cannot affect sorting.
Do not change app behavior, store artifacts, security rules, or release metadata.

## Acceptance

- Every changed Dart file has the same import directive tokens and non-import tokens as the base.
- Sorting changes only eligible `lib` and `test` sources, leaves excluded paths intact, and is idempotent.
- The check fails for unsorted imports without writing files.
- `merry run check`, `merry run coverage`, hosted checks, and the current-head review gates pass.

## Precedent

Oracle sources `wiki/concepts/dart-actions-import-sorter.md` and `wiki/concepts/trunk-stack-baselines.md` support an explicit apply command and a check that does not write files.
`wiki/sources/claude--skills--setup-trunk--skill.md` supports narrow spelling exclusions and identifiable mechanical changes.
There is no direct indexed precedent for this project's replacement of `directives_ordering`.
