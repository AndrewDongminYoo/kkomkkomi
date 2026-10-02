# Brief: issue #13, a photo whose upload finishes after a revoke

Read `CLAUDE.md`, issue #13, and the "Phase B" section of `docs/specs/2026-10-01-m1-local-first-design.md` before you write code.

## Problem

Issue #13 states it: an upload that timed out can still create its object after a revoke deleted the recorded path, and no later cleanup knows the object.
Access is not the problem, because `storage.rules` allows a `get` only while the page is open, and the web report page reads photos through the rules.
Retention is: a customer photo can stay in Storage.

## Step 1: try to refute the issue

`storage.rules` allows `create` only while the page is open.
Find out whether Storage evaluates that rule when a resumable upload finishes, or only when it starts.

- Cite the Firebase documentation for the answer.
- An emulator test can support the answer, but the emulator may differ from production on this point, so it cannot decide alone.

If the rule is evaluated when the upload finishes, a late upload after a revoke is refused.
Then close issue #13 with the evidence, change no code, and add a rules test that pins the refusal if the emulator shows it.

## Step 2: repair, only if step 1 does not refute the issue

Choose one of the options in issue #13, or a combination:

1. Keep the intent record of an upload until the upload settles, and delete the object again after it settles.
2. Cancel the `UploadTask` on timeout, and wait for its end before the step counts as failed.

Keep the logic in `lib/application/` where tests reach it, and keep `lib/firebase/` thin.
Write the failing test first.

## Out of scope

- Any change to the access rules.
- Any deploy.

## Acceptance criteria

- `merry run check`, `merry run coverage`, and `merry run rules` pass.
- The pull request closes issue #13, or step 1 closes it without a pull request.
