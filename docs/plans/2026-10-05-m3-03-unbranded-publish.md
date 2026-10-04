# M3-03: publish a report without the footer from the token claim

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A paying company's published report carries `unbranded: true`, decided from the `revenueCatEntitlements` claim of a freshly issued ID token, and a refused write of that key falls back to the report with the footer in the same job.

**Architecture:** The `Identity` port gets a second answer, whether the current token holds a paid entitlement, and `FirebaseIdentity` reads it from a token that it asks Firebase Auth to issue anew. `PublishQueue` asks for it right before it writes a report and puts it into `PublishedReport.unbranded`. `FirebasePublisher` writes the key only when it is true. The rules of PR 1 already accept it only from a paid writer.

**Tech Stack:** Flutter, `firebase_auth` (`User.getIdTokenResult`), the existing publish queue and its in-memory test repositories, `mocktail`.

**Spec:** [`docs/specs/2026-10-04-m3-subscriptions-design.md`](../specs/2026-10-04-m3-subscriptions-design.md), section "Trust boundary". The split is [`2026-10-05-m3-subscriptions.md`](2026-10-05-m3-subscriptions.md). PR 1 (#42) added the rules and the web view. Refs #36.

## Global Constraints

- The claim name is `revenueCatEntitlements`, a list. Paid means that the list holds `basic` or `pro`, as `paid()` in `firestore.rules` reads it.
- The queue decides `unbranded` from the token claim only. It does not call `Entitlements` (the RevenueCat adapter), so no build of this pull request contacts RevenueCat, and the privacy pages and the store answers do not change.
- Each check of the claim asks Firebase Auth for a newly issued token, so a claim that the extension removed after an expiry or a transfer does not survive in a cached token. This replaces the spec's "refresh when `Entitlements` says paid and the token does not": a fresh token on every check needs no second source, and it leaves RevenueCat out of the publish path.
- A refused report write that carried `unbranded: true` is written again in the same job without the key, so the report appears with the footer instead of stopping with `PublishFailure.refused`. Any other refusal keeps today's behavior.
- `Identity.hasPaidEntitlement()` never throws: any failure, no account, and no network give false, so the report keeps the footer.
- The rules of PR 1 must be deployed (operator approval) before an app build of this pull request reaches a tester. The pull request body says so.
- Coverage of `lib` stays at 100%, and `merry run check` passes.
- Name no price, billing term, or fee: the repository is public.

## Review Focus

1. A token without the claim, with an empty list, with `["team"]`, or with a claim that is not a list: false, and the report has the footer.
2. The token refresh fails (offline, revoked account): false, no exception reaches the queue, and the job then fails or retries for its own network reason as today.
3. The write with `unbranded: true` is refused once: the same run writes the report without the key and the job succeeds; a second refusal of the report without the key stops the job with `refused` as today.
4. A job that runs again after the plan ended writes the report again with the footer, because the fresh token has no claim.
5. A revoke job and the page and photo writes never ask for the claim: only the report write does.

---

### Task 1: `Identity.hasPaidEntitlement()`

**Files:**

- Modify: `lib/application/identity.dart`, `lib/presentation/adapters/unavailable_identity.dart`, `lib/firebase/firebase_identity.dart`, `test/helpers/fakes.dart` (`FakeIdentity` gets a settable answer and a call count)
- Test: `test/firebase/firebase_identity_test.dart`, the test of `UnavailableIdentity`

**Interfaces:**

- Produces, on `Identity`:

```dart
  /// Whether a newly issued ID token of the current user holds a paid entitlement (`basic` or `pro`) in its
  /// `revenueCatEntitlements` claim, which the RevenueCat Firebase extension writes and `firestore.rules` reads.
  ///
  /// Gives false without an account, without a network, and for any failure, so a caller falls back to the report
  /// with the footer. The call does not throw.
  Future<bool> hasPaidEntitlement();
```

- `FirebaseIdentity` waits for an attempt on its way (as `deleteAccount` does), starts Firebase, takes `auth.currentUser`, and reads `(await user.getIdTokenResult(true)).claims?['revenueCatEntitlements']`. It never signs in.
- `UnavailableIdentity` gives false.

- [ ] **Step 1:** Write the tests for the cases of Review Focus 1 and 2 against the fake `FirebaseAuth` that the existing tests use, and a test that the call passes `true` to `getIdTokenResult`. See them fail.
- [ ] **Step 2:** Implement, run `merry run check`, and commit `feat(identity): tell whether a fresh token holds a paid entitlement`.

### Task 2: The report carries `unbranded`

**Files:**

- Modify: `lib/application/publisher.dart` (`PublishedReport` gets `final bool unbranded`, default false, in `==` and `hashCode`)
- Modify: `lib/firebase/firebase_publisher.dart` (`writeReport` adds `'unbranded': true` only when it is true, so a report with the footer keeps the three keys of today)
- Test: `test/firebase/firebase_publisher_test.dart`, `test/application/publisher_test.dart` if it exists

- [ ] **Step 1:** Tests: the written map of a branded report has exactly the three keys, and the map of an unbranded one has `unbranded: true` as well. See them fail, implement, pass.
- [ ] **Step 2:** Commit `feat(publish): write unbranded into a report without the footer`.

### Task 3: The queue decides the key and falls back on a refusal

**Files:**

- Modify: `lib/application/publish_queue.dart` (`_publish`)
- Test: `test/application/publish_queue_test.dart`

**Interfaces:**

- Consumes: `Identity.hasPaidEntitlement()` (Task 1), `PublishedReport.unbranded` (Task 2).
- In `_publish`, right before the report write: `final unbranded = await _step(_identity.hasPaidEntitlement());` and the report gets `unbranded: unbranded`. When that write throws a `PublishException` of kind `refused` and `unbranded` was true, log it and write the same report with `unbranded: false` once; any other exception propagates as today.

- [ ] **Step 1:** Tests for Review Focus 3, 4, and 5 with `FakeIdentity` and `FakePublisher`: a paid identity gives a written report with `unbranded: true`; a refusal of that write gives a second write without it and a succeeded job; a refusal of the second write stops the job with `refused`; a revoke job never calls `hasPaidEntitlement`. See them fail.
- [ ] **Step 2:** Implement, run `merry run check` and `merry run coverage`, and commit `feat(publish): publish without the footer for a paid writer`.

### Task 4: Records

**Files:**

- Create: this brief, `docs/plans/2026-10-05-m3-03-unbranded-publish.md`, as the first commit.
- Modify: `docs/plans/2026-10-05-m3-subscriptions.md`: PR 3 reads the claim of a fresh token and does not call `Entitlements`, so the privacy pages and the store answers for RevenueCat as a processor move to PR 4, the first pull request that calls `currentPlan()`. Keep the line that records the earlier move, and add the date and the reason of this one.
- Modify: `CLAUDE.md`: "Identity" (the second answer and its fresh token), "Publishing" (the queue sets `unbranded` from it and falls back to the footer on a refusal of that key), and "Current state".

- [ ] **Step 1:** cspell and `trunk check` on the changed Markdown.
- [ ] **Step 2:** Commit `docs: describe the unbranded report write`.

The pull request body lists, under "After the merge": the rules of #42 deploy before any build of this pull request reaches a tester, with the operator's approval.

## Reconciliation, 2026-10-05

This brief is the record of what was approved. The shipped code of this pull request is the authority where the two differ.

- Task 3, "`final unbranded = await _step(_identity.hasPaidEntitlement());`": the queue calls `_identity.hasPaidEntitlement().timeout(_stepTimeout, onTimeout: () => false)`. Under `_step`, a check that did not answer in time made the whole job retry after the page and the photos were written, which contradicts "any failure, no account, and no network give false" in Global Constraints and Review Focus 2. The test "a check of the paid entitlement that does not answer in time gives the report with the footer in the same run" in `test/application/publish_queue_test.dart` holds it.
- Global Constraints, "the privacy pages and the store answers do not change": that sentence is about RevenueCat as a processor, which still moves to PR 4. Section 3 of both privacy pages now lists the `unbranded` mark that a report upload can hold, because the app sends it and anyone with the link can read it. The test "lists the mark of a report without the footer text among what a link share sends" in `test/web/privacy.test.mjs` holds it.
