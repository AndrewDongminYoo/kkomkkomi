# Report abuse controls

## Status and decision

Approved local direction for issue #86, based on main at `6cb836b78c1570aebdbe0768cd3a632a2575bf97`.
The operator approved controlled publisher admission, the safety budgets and retaining the shared host on 2026-10-08.
The approved baseline keeps report recipients anonymous and requires operator approval of each publishing account.
The operator supplied `donminzzi@gmail.com` as the abuse-report address in this session.

## Problem and evidence

An anonymous Firebase user can currently create pages and publish arbitrary report content directly.
`firestore.rules` checks ownership and the top-level report shape, but does not bound report counts, zones, or text lengths.
`storage.rules` accepts owner uploads with declared JPEG type and at most 5 MiB per object, without a total object or byte budget.
`FirebaseIdentity` creates anonymous accounts, and a replacement account can bypass a UID-only blocklist.
The landing page inquiry form is a preview that sends nothing.
The issue does not establish that abusive content caused the Chrome warning in #53.

## Recommended baseline

### Publisher admission and repeat abuse

Keep anonymous Firebase authentication.
Require an operator-managed publication grant for writes; a new anonymous UID has no grant by default.
Clients cannot create, delete, copy, or modify approval and budget fields; rules permit only resource-bound usage and reservation updates.
The operator approves identifiable legitimate publishers and does not approve a replacement UID merely because the previous UID was blocked.
Existing publishers require explicit enrollment before enforcement.
Account deletion or reinstall can require renewed approval, which is a deliberate cost of this baseline.
Do not silently grandfather every anonymous account.

Grant withdrawal stops new page, report, and photo writes.
An operator-managed page block immediately denies public reads of the page, its reports, and its photos, independently of owner-controlled revoke fields.
Owners retain deletion access for their own data.
The app must explain a denied publication and provide an approval-request path without preventing local capture or PDF sharing.

### Content and volume limits

Enforce grant-bound page, report, photo-object, and reserved-byte budgets at the backend boundary.
Use Firestore transactions and rules that verify the matching resource creation and usage increment together.
Reject standalone resource writes, forged or decreased counters, concurrent quota overruns, and grant self-escalation.
Deleting a resource does not refund its lifetime allowance; retries of an existing resource do not consume another allowance.
Reserve each photo path and maximum byte size before upload; Storage checks the exact reservation, owner, page, and grant.
An upload cannot enlarge the reservation or create unreserved orphan objects.
Keep the existing unique retake paths because delayed uploads must not overwrite newer photos.

Initial approval defaults are 50 pages, 1,000 reports, 2,000 photo objects, and 1 GiB of lifetime reserved photo bytes per grant.
These are safety budgets independent of subscription entitlements.
The operator can issue a larger trusted grant instead of resetting client-writable counters.
Per-report limits are 20 zones, 100 characters for company, client, and zone names, and 2,000 characters each for notes and exception reasons.
Every zone and photo reference must be validated; a list-size check alone is insufficient.
Include a rules-enforced cooldown for successful new publication or photo reservations, with idempotent retry exemptions, and test it using emulator time-compatible fixtures.
Confirm rules expression and document-access limits before accepting this implementation approach.
If those limits prevent correct enforcement, return with the concrete failure rather than adding a server service silently.

### Abuse reporting and operator response

Add an accessible report-abuse email action to report, history, and unavailable views, including unbranded reports.
Compose a mail to `donminzzi@gmail.com` with the affected report or page link and a request for a short reason.
Use only a validated report path; exclude URL query parameters, fragments, report text, photos, company phone, and account identifiers from the generated email.
Show the address as a fallback when no mail app opens.
The user reviews and sends the message; opening the page sends no abuse report automatically.
Mailbox delivery cannot be verified without a separately authorized test message and receipt.

Document and exercise operator actions with fictional emulator data: block one page and its photos, withdraw its publisher grant, inspect the result, and preserve enough evidence to investigate.
Use privileged operator access for grants and page blocks; recipient requests cannot perform takedowns.
Record the minimum retained identifiers and the handling of abuse reports in both privacy pages.

### Shared host decision

Retain the current host for this first controlled-publisher baseline.
Do not create a Hosting site, migrate domains, or change public report URLs in this implementation.
A separate host would reduce coupling between public URLs but does not establish independent browser reputation or prevent malicious publication.
The operator accepted the residual shared-host risk for this implementation.
Approved publishers can still submit abusive content; admission, finite budgets, reporting, and takedown reduce risk without claiming automatic moderation or complete anti-Sybil protection.
App Check may complement these controls, but is not a substitute for admission or quotas.

## Implementation constraints

A single `publishingGrants/{uid}` document holds operator-managed limits and approval alongside validated counters and the immutable-size reservation map.
At most 2,000 active reservation keys of at most 384 characters fit the fixed document budget; cumulative usage is not refunded.
A private report header reserves a lifetime report slot before staging seven fixed chunks of up to three zones in separate transactions.
Each private chunk rechecks approval and ownership, then verifies every zone below the request expression limit.
Header reservation and public publication bind account charges and the server cooldown; bounded private chunk updates do not change usage.
The final public report transaction reads all seven validated chunks and the header, checks their concatenation, and publishes the complete report atomically.
Interrupted drafts consume a report slot and remain private; retries reuse the same slot, and updating an inventoried legacy report does not charge another slot.
Deleting a draft does not refund its slot.
Storage creates read only the page and grant; public reads check the page and a durable operator-only `blockedPages/{pageId}` record.
Operator blocking writes `blockedAt` and the durable block together, then removes photos to invalidate issued download tokens.
Client deletion cannot erase the block.
Existing identical adapter retries perform no mutation and need no renewed approval; changed resources require approval.
A previously admitted account may create a closed page after approval withdrawal, within its existing page budget and cooldown, to reconcile a revoke whose earlier page write never arrived.
A UID without any grant cannot create such a page.
Owner-only reads include closed reports for reconciliation; public reads remain restricted to open, unblocked pages.
Approval and usage records survive app account deletion until operator deletion on request; page block identifiers remain while the service operates.
Emails are deleted after handling; no mail delivery has been exercised.

## Acceptance and verification

1. Admission → verify: a legitimate approved anonymous writer publishes, while unapproved, withdrawn, and replacement UIDs cannot; all client grant mutations fail.
2. Budgets → verify: exact boundaries pass, one-over writes fail, forged counters and concurrent attempts fail, and retries do not charge twice.
3. Content → verify: all zones and fields are checked, including malformed later zones, cross-page photo paths, long Unicode text, and unknown keys.
4. Photos → verify: exact reserved uploads pass; unreserved, oversized, cross-owner, and post-withdrawal uploads fail.
5. Takedown → verify: the real web reader cannot fetch the blocked page, its reports, or Storage photos; a replacement UID cannot restore it.
6. Reporting → verify: fictional report links produce the correct mail action on every relevant view without leaking extra data or sending a message automatically.
7. Compatibility → verify: existing publication retries, retakes, revoke/reissue, deletion, paid footer behavior, and local/PDF use remain correct.
8. Local gates → verify: `merry run check`, `merry run coverage`, and `merry run rules`; relevant scoped Trunk checks and bounded browser checks.

## Rollout and authority

No production deploy, store upload, mailbox message, grant mutation, commit, push, or new PR is authorized by the request to start local implementation.
Prepare and verify a staged rollout: deploy the report and privacy pages before collecting approval requests or issuing records, inventory existing publishers and usage, enroll approved users, deliver a compatible app, then enforce Firestore and Storage rules.
Every live operation requires its own existing or new explicit approval.
Document old-client behavior and rollback limits before enforcing the rules.

## Sources

- [Issue #86](https://github.com/AndrewDongminYoo/kkomkkomi/issues/86).
- Current `firestore.rules`, `storage.rules`, `lib/firebase/firebase_publisher.dart`, `lib/firebase/firebase_identity.dart`, and `lib/application/publish_queue.dart` at the inspected main revision.
- [Firestore atomic-write rule conditions](https://firebase.google.com/docs/firestore/security/rules-conditions) describe `getAfter` and access-call limits.
- [Firebase rule behavior and limits](https://firebase.google.com/docs/rules/rules-behavior) specify the 1,000-expression Firestore limit and two-document Storage limit.
- [Firebase App Check](https://firebase.google.com/docs/app-check) describes complementary protection and its incomplete abuse coverage.
- Oracle retrieval for anonymous publishing and abuse controls returned \[no precedent found\]; no project precedent was applied.
