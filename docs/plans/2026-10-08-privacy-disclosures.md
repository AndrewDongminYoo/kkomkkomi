# Privacy disclosure delivery plan

## Owned paths

The root owns `web/privacy/index.html`, `web/privacy/en/index.html`, `test/web/privacy.test.mjs`, `test/rules/rules.test.js`, and this plan with its matching spec.
Use the existing main workspace and the scoped task branch.

## Execution and checks

1. Add focused deletion and planned-camera disclosure assertions; run `node --test test/web/privacy.test.mjs` and observe the intended missing-disclosure failures before changing HTML.
2. Add the gallery clause regression; remove each clause in turn in a reversible fixture to demonstrate its expected failure, then restore exact bytes.
3. Add source-marked report write and anonymous read tests alongside owner-boundary denials; verify a controlled emulator-only rule fixture rejects the marked payload, then restore the production rule bytes.
4. Update both privacy pages together, preserve current layout, and advance their effective date to the date of this change.
5. Run `merry run check`, `merry run coverage`, and `merry run rules`, with at most one heavy mobile job at a time.
6. Check the rendered local pages at a narrow viewport, review the bounded diff, and run scoped Trunk checks.
7. Commit by concern, push normally, open the PR, and use `ci-babysit` with the hosted review round handler until current-head terminal gates pass.
8. Request operator merge; retain Hosting deployment as a separate approved action.

## Success criteria

1. Disclosure correction → verify: intended privacy test failures become passes, and a browser reads both updated sections.
2. Compatibility regression → verify: emulator write/read tests and denied-write fixtures exercise the source-marked payload.
3. Delivery → verify: clean current-head checks, no unresolved review threads, and a PR with the approved issue scope.
