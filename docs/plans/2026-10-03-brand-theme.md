# Brief: give the app the product's own theme

Read `CLAUDE.md`, `lib/app/view/app.dart`, `lib/app/view/startup_failure_app.dart`, `lib/presentation/shared/`, the token block of `web/index.html` (`:root`), and `web/report/report.css` before you write code.

## Why

A UI/UX review on 2026-10-03 (static source review, `flutter-ui-ux-review` in full mode) found that the app still runs the theme of the project template, and the operator wants the app to stop looking like an example app.

- `lib/app/view/app.dart` passes `ThemeData(appBarTheme: …, useMaterial3: true)` without a color scheme, so every screen uses the default Material 3 purple scheme. `StartupFailureApp` has no theme.
- The AppBar color reads `Theme.of(context).colorScheme.inversePrimary` above `MaterialApp`, where it gets the fallback theme, so the AppBar stays lavender whatever theme the app passes.
- The launcher icon (`tool/app_icon/`), the landing page (`web/index.html`), and the web report (`web/report/report.css`) all use the same tokens: teal `#0f7f7a`, ink `#16243b`, a warm ground `#faf7f1`, error `#b4342c`, a 10 px radius. The report that a client opens is teal and navy, and the app that makes it is purple.
- Every confirmation looks the same: `showConfirmDialog` always shows a `FilledButton`, for a notice ("공유하기") and for an action that cannot be undone ("지우기", "링크 막기", "나가기" with an unsaved note, "삭제하기").
- Failures and warnings have four unrelated looks, and two failures render as plain body text: the client link section (`clientLinkCloseFailedMessage`, `clientLinkDeletionUnfinishedMessage`) and the link status of the visit report screen (`reportLinkFailedMessage` and its siblings).
- The share buttons of the visit report screen replace their label with a `CircularProgressIndicator` that has no semantics label while they work.

## Goal

Every screen uses one theme built from the product tokens, a destructive confirmation looks destructive, and a failure looks different from a neutral status.

## In scope

1. One theme function under `lib/app/view/` that both `App` and `StartupFailureApp` use, light only:
   - a `ColorScheme` with the literal tokens of `web/index.html` where a role matches (primary, onPrimary, surface, onSurface, onSurfaceVariant, outline or outlineVariant, error), and generated roles for the rest; state which roles you set and from which token;
   - an AppBar on the surface color with ink text, without the `inversePrimary` read;
   - the 10 px radius of `--radius` for buttons, dialogs, and the notice boxes;
   - a `TextTheme` that sets the size and weight of the styles the screens use, on the platform font. Do not bundle a new font: `assets/fonts/NotoSansKR-Regular.ttf` is the PDF font.
2. `showConfirmDialog` takes a flag for a destructive action, which styles the confirm button with the error colors. Pass it from every caller whose action deletes data, closes a link, or loses an unsaved note. Keep the dismiss label `닫기`.
3. One shared notice widget under `lib/presentation/shared/` with an info tone and an error tone. Use it for the existing notices and failure texts of the client detail, visit capture, visit report, and company profile screens, so that each failure uses the error tone.
4. The share buttons keep an accessible name while they work.
5. `pumpApp` in `test/helpers/` uses the app theme, so that screen tests run under the real theme. Add a test that fails when the app shell does not use the theme function, and a test of the destructive flag.

## Out of scope

- A dark theme. `CLAUDE.md` records that the launch screen is white because the first screen is light; a dark theme changes that decision and needs the operator.
- The client name on the visit capture screen: a separate brief.
- Moving primary actions between the top and the bottom of a screen.
- Any change to `web/`.

## Requirements

- Material widgets come from `package:material_ui/material_ui.dart`. No new package.
- Keep `tester.useNarrowScreenWithLargestText()` and `tester.expectWholeText()` passing on every screen; a new radius or text style must not cut text.
- Contrast: the pairs that carry text (onPrimary on primary, onSurface and onSurfaceVariant on surface, onError on error, the notice text on its fill) meet WCAG 2.2 AA for normal text, 4.5:1. Compute each ratio and list it in the pull request body.

## Acceptance criteria

- `merry run check` and `merry run coverage` pass.
- The pull request body lists each color role and its token, each contrast ratio, and each caller that now passes the destructive flag.
- The parent session captures the screens on an iOS simulator before and after the change; the implementer does not boot a simulator.
