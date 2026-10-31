# Closed Alpha distribution plan (#40)

## Workspace and authority

Use the existing checkout on `codex/play-alpha-distribution-40`, based on `b6b726934205e02231c87b0d7271a23abd832c43`.
The explicit PR Loop invocation and Alpha clarification approve the [spec](../specs/2026-10-31-play-alpha-distribution.md), scoped test distribution and gated PR lifecycle.
No new binary, dependency update or worktree is required.

## Steps and checks

1. Read exact live app/track identities, existing tester eligibility and pending publishing changes.
   Verify: native Console and pure-read track summaries.
2. Select existing code 6 in a native Alpha release and inspect the final target/content before publishing.
   Verify: retained operation identity and release-summary evidence, with no duplicate bundle upload.
3. Submit only the authorized Alpha release and read its resulting review/publication state.
   Verify: Console result and exact remote track read-back; reconcile before any retry.
4. Read the existing tester opt-in and store access route with the signed-in personal account.
   Verify: visible membership/access state, with no enrollment or device action.
5. Record measured outcomes in the [dated note](../notes/2026-10-31-play-alpha-distribution.md) and update affected release pointers in the same PR.
   Verify: links, Markdown checks, source formatting/analysis and a scope-calibrated local review.
6. Commit/push, complete current-head CI/reviews, read back the final body and assign the operator at merge readiness, then perform the delegated gated merge.
   Preserve a visible receipt and retire only settled owned control state.

## Evidence boundaries

Keep public documentation free of tester identities, email addresses and account credentials.
Fresh Oracle retrieval was blocked by the parent configuration provenance guard before an agent started.
The retained store-state precedent requires explicit track/status evidence and warns that metadata actions may change draft state; no metadata lane is used here.
The lack of an Android device remains an explicit verification limit.
