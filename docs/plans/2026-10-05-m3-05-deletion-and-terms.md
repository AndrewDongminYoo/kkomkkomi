# M3-05: the subscription notice of Delete All Data, the store terms link, and the last privacy gap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Before Delete All Data, the company learns that a store subscription keeps billing and how to cancel it; the App Store descriptions carry the terms of use and privacy policy links; and section 9 of the privacy pages names every moment the app asks Google for a sign-in token.

**Architecture:** The confirmation of Delete All Data on the company profile screen gets one more paragraph and, on Android, a link to the Play subscriptions center through `ExternalLinks`. No call to `Entitlements` is added: the notice is shown to every company in the production flavor, so the screen still never contacts RevenueCat. The App Store descriptions and the privacy pages change as text.

**Tech Stack:** Flutter, the existing `ExternalLinks` port, fastlane metadata, the static privacy pages.

**Spec:** [`docs/specs/2026-10-04-m3-subscriptions-design.md`](../specs/2026-10-04-m3-subscriptions-design.md), section "Deletion and legal requirements". The split is [`2026-10-05-m3-subscriptions.md`](2026-10-05-m3-subscriptions.md). Refs #36.

## Global Constraints

- The operator decided on 2026-10-05 that the RevenueCat customer record of a deleted user is removed by hand on request: the app shows no deletion of that record and calls no backend for it. The privacy pages already say so; keep them consistent.
- The notice says, in the confirmation of Delete All Data and only in the production flavor (where `Entitlements` is not `FreeEntitlements`, decided without calling it, for example by a flag the page gets from the flavor, or by the identity being available): deleting the data does not cancel a subscription bought in the store, and how to cancel it.
  - Android: a link to `https://play.google.com/store/account/subscriptions` ("Use the following URL to direct users to the page that shows all of their subscriptions", https://developer.android.com/google/play/billing/subscriptions, read on 2026-10-05).
  - iOS: no link, the steps "In Settings, tap your name. Tap Subscriptions." (https://support.apple.com/en-us/118428, read on 2026-10-05), in the user's language. No Apple URL is used, because no Apple source for a subscriptions URL was found.
- The App Store descriptions (`fastlane/metadata/ios/ko/description.txt`, `fastlane/metadata/ios/en-US/description.txt`) end with the terms of use link `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/` and the privacy policy link (`https://kkomkkomi.web.app/privacy/` for Korean, `https://kkomkkomi.web.app/privacy/en/` for English), as Apple's subscriptions page requires ("your app and App Store metadata must include links to your Terms of Use and Privacy Policy", https://developer.apple.com/app-store/subscriptions/, read on 2026-10-05). `merry run release check` must still pass (store limits). Name no price.
- Section 9 of both privacy pages, Google part, "When and how": add that the app asks Google for a new sign-in token when it publishes a report as a link (#44, `PublishQueue` before the report write), next to the visit report screen that #48 added.
- User-facing text follows the `user-facing-copy` skill, every string is an ARB key in both languages, `KeepAllText`, no overflow at `tester.useNarrowScreenWithLargestText()`.
- `CLAUDE.md` ("Deletion", "Current state"), the console note (the operator's manual RevenueCat deletion on request, and the App Store description links), and the split plan (PR 5 done; #36 stays open for the operator's purchases in the store test environments) are updated.
- Coverage of `lib` stays at 100%, and `merry run check` passes.

## Review Focus

1. The development and staging flavors show no subscription notice in the confirmation.
2. Android production shows the link and opens the Play subscriptions center through `ExternalLinks`; a failed open shows the existing link failure notice, not a crash.
3. iOS production shows the steps and no link.
4. Opening the confirmation never calls any `Entitlements` member (the counting fake of `FakeEntitlements`).
5. Both App Store descriptions stay within the limits of `tool/release_check.dart` with the two links.

---

### Task 1: The notice in the confirmation of Delete All Data

- Modify: `lib/presentation/company_profile/view/` (the confirmation), how the page learns that it runs in the production flavor without asking `Entitlements`, ARB files
- Test: `test/presentation/company_profile/view/company_profile_page_test.dart`
- [ ] Tests for Review Focus 1–4 and the narrow-screen check; implement; `merry run check`; commit `feat(profile): tell that Delete All Data does not cancel a store subscription`.

### Task 2: Store links, privacy gap, and records

- Modify: the two iOS descriptions, `web/privacy/index.html`, `web/privacy/en/index.html`, `test/web/privacy.test.mjs`, `docs/notes/2026-10-02-first-test-distribution.md`, `docs/plans/2026-10-05-m3-subscriptions.md`, `CLAUDE.md`
- Create: this brief as the first commit of the pull request
- [ ] `merry run release check` is not runnable on a dirty tree, so run `dart run tool/release_check.dart` only for its limit output, or the release check test; `merry run web`; cspell with `--gitignore-root`; `trunk check`; commits `chore(store): link the terms of use and the privacy policy from the App Store descriptions`, `docs(privacy): name the publish token request`, and `docs: record the end of the M3 split`.

The pull request body lists the Hosting deploy after the merge, with the operator's approval.
