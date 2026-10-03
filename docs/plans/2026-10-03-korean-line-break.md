# Brief: break Korean text between words, not inside them

Read `CLAUDE.md` ("Localization", "Tests") and `lib/presentation/shared/` before you write code.
Start after the brand theme pull request (`docs/plans/2026-10-03-brand-theme.md`) merges, because both touch the shared widgets.

## Why

A capture of the development build on an iOS simulator (iPhone 18 Pro, Korean, 2026-10-03) showed Flutter breaking Korean lines inside words: "추가 / 하면" at the default text size, and "거래처 / 가 없어요", "있어 / 요." at the largest accessibility size.
Flutter has no keep-all line breaking for Korean; the upstream issues are https://github.com/flutter/flutter/issues/59284 and https://github.com/flutter/flutter/issues/19584, both open.
Korean is the primary locale, so this touches the text of every screen, and more so at large text sizes.

## Approach (operator, 2026-10-03)

Insert a zero-width joiner (U+200D) between the characters of each whitespace-separated word that contains Hangul, so that the line breaker can break only at spaces and newlines.
The operator has used this technique before. Implement it in this repository as a small function; do not add a package (`text_ko` does the same and is version 0.1.2).

The operator also found that a line break placed by hand reads best where a layout is fixed.
It does not replace the joiners here: the app must not overflow at 320 px with the largest text size, and the capture shows that at that size even "아직 거래처가" does not fit one line, so a hand-placed break after it would still break "거래처 / 가".
Do not add `\n` to the ARB strings in this pull request.

Requirements of the function:

- Match by code point: a `RegExp` with `unicode: true`, so that a joiner never lands between the two halves of a surrogate pair (a client name can hold any character).
- Leave a word that holds an emoji unchanged, because a joiner between emoji changes how they render.
- Keep every space and newline of the input in place.
- Return the input unchanged when it holds no Hangul.

## In scope

1. The function under `lib/presentation/shared/`, with unit tests for: Hangul words, mixed Hangul and Latin, a non-BMP character (for example U+20000), an emoji word, multiple spaces, newlines, the empty string, and text without Hangul.
2. Apply it at display only: the `Text` widgets that show Korean copy from the ARB files and the names and notes that the person entered. Choose one place that most screens pass through (a shared text widget or a helper that the screens call) and say in the pull request body which widgets use it and which do not.
3. Never apply it to a value that leaves the screen: `TextField` content, stored values, the PDF (`lib/export/` does its own layout), the published report data, the share text, and the clipboard.
4. Semantics: the accessible label stays the original string, without joiners. Show it with a semantics test.
5. A widget test that proves the line break: render a Korean sentence at a narrow width and assert, from the text layout (`TextPainter` line metrics or line boundaries), that each line ends at a space. Make it fail once without the function before you trust it.

## Out of scope

- Line breaking in the PDF and in the web report page.
- Any change to the ARB strings themselves.

## Acceptance criteria

- `merry run check` and `merry run coverage` pass, and `tester.useNarrowScreenWithLargestText()` and `tester.expectWholeText()` still pass on every screen.
- The pull request body lists the widgets that apply the function and the values that never pass through it.
- The parent session captures the client list and the visit capture screen at the largest text size on an iOS simulator after the merge.
