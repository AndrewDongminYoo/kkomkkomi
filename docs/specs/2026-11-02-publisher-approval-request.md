# Publisher approval request

## Status and decision

Decision record for issue #146, under the parent issue #145. Issue #147 implements it.
Option 2 below was chosen in a `/pr-loop` plan gate on 2026-11-02:

1. A user whose ID token holds a paid entitlement is approved automatically with the default safety budgets. Paid means `paid()` in `firestore.rules`: the `revenueCatEntitlements` claim is a list that holds `basic` or `pro`.
2. A free user requests approval inside the app. The app writes a request record, and no email is sent.
3. Pending requests are found in the Firestore console. There is no new processor and no notification mail.
4. A grant that the app created automatically stays after the subscription ends, within its existing budgets.

This spec changes only publisher admission in `docs/specs/2026-10-08-report-abuse-controls.md`.
The rest of that spec stays in force (see "What stays from the 2026-10-08 spec").
The #86 rules are not deployed: the deployed Firestore rules equal `firestore.rules` at `135c67f` (`CLAUDE.md`, "Current state"), which has no `match` for `publishingGrants`.
The #86 client is already in `1.1.2+6`: `78ceded` (the #86 client commit) is an ancestor of `bcac1e4`, the clean source of that build (`docs/notes/2026-10-31-production-build-provenance.md`).
That client reads `publishingGrants/{uid}` in each share transaction, the deployed rules deny the read with `permission-denied`, the job ends as `refused`, and the visit report screen offers the email dialog.
So no new link share of `1.1.2+6` succeeds against the deployed rules, for a paid user or a free one; a grant created by hand would not help, because the deployed rules deny the read itself.
Version code `6` showed `completed` on the Play internal, Alpha and production tracks on 2026-11-02 (`docs/notes/2026-10-31-play-internal-distribution.md`), which does not establish delivery to a user. No record establishes a TestFlight upload of `1.1.2(6)`.
So a user who runs `1.1.2+6` can see the email flow now, and approval emails may already exist. No record shows whether any was sent; rollout step 2 of the operations note covers any that arrived (see "Ordering constraints").
The sentence "No email has been sent or delivery verified." in `docs/notes/report-abuse-operations.md`, "State and authority", has not changed since `888af8a` (2026-10-08), before any distribution of `1.1.2+6`. So it does not cover the `mailto` messages that users write in that build, and it does not conflict with the line above.

## Problem and evidence

- After the backend refuses a link share, the visit report screen offers **Request link sharing approval**. Its dialog asks the publisher to email the anonymous registration code (the user ID) for approval (`lib/presentation/visit_report/view/visit_report_page.dart`, `_requestApproval`, ARB key `reportApprovalMessage`).
- Clients cannot create a grant. `match /publishingGrants/{uid}` in `firestore.rules` allows only `get` of one's own grant and the bounded usage updates of `validUsage`.
- `publishingGrants/{uid}` is created by hand in the Firestore console (`docs/notes/report-abuse-operations.md`, "Enrollment").
- A cleaning company that wants to share its first report link must leave the app, send an email, and wait for a manual step.

## Options

Issue #146 lists three options.
The table compares them on the three points that the issue asks for.

| Option                                                                                             | Abuse exposure                                                                                                                                                                                                                               | Manual work per new publisher                                              | Privacy-page change                                                                |
| -------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| 1. Every publisher writes a request record, and each one is approved in the console                | Lowest. Each publisher is reviewed before the first write. Request records can be created by any anonymous account (see "Residual risks").                                                                                                   | One console review and one grant for each publisher, paid or free          | A new stored document (the request record). The approval email goes away.          |
| 2. A paid user gets the default grant automatically, and a free user uses option 1 (chosen)        | A paid user publishes without review, limited by the budgets of its grant. A purchase that moves to a new UID can create a further grant (see "Residual risks"). A free user has the exposure of option 1.                                   | None for a paid user. One console review and one grant for each free user. | The request record of option 1, and a new automatic decision based on the purchase |
| 3. Every user gets the default grant automatically, and abuse handling relies on the blocks of #86 | Highest. Each new anonymous UID gets its own full budgets, so the total is not bounded. Abuse is handled only after a report, by a block and a takedown. This reverses the 2026-10-08 rule that a new anonymous UID has no grant by default. | None up front. Work happens only in reaction to abuse reports.             | A new automatic decision for every account. No request record.                     |

### Why option 2

- A paying company does not wait for a manual approval before its first link share.
- A purchase goes through a store account and a payment, so a paid UID costs more to replace than a new anonymous UID. The free accounts, which cost nothing to replace, still need review.
- The per-publisher work happens only for free users, and it needs no mail and no new processor.
- Option 3 removes the admission control that was approved on 2026-10-08.
  Option 1 keeps the manual step for paying customers, and that step is the problem of #145.

## Mechanism outline for #147

This outline sets the constraints. Issue #147 owns the rules, the code, and their tests.

### Automatic grant for a paid user

- A signed-in user may create `publishingGrants/{uid}` only for its own UID, and only while `paid()` holds for the token of the request.
- The created document must equal the initial document of `docs/notes/report-abuse-operations.md`, "Enrollment", plus `updatedAt` at the fixed time that the next line of that note gives, with no other key:
  - `enabled: true`;
  - the default limits (`pageLimit`, `reportLimit`, `photoLimit`, `byteLimit`) of the 2026-10-08 spec;
  - zero usage (`pages`, `reports`, `photos`, `bytes`) and `reservations: {}`;
  - `type: 'page'`, `pageId: 'initial'`, `visitId: ''`, and `fileName: ''`;
  - `updatedAt` equal to 2000-01-01 UTC.
- `updatedAt` controls the one-second cooldown of `validUsage`, so the client must not choose its value, and the rule requires the fixed past time.
  It must not be `request.time`: `validUsage` requires `request.time >= before.updatedAt + 1s`, so a page charge less than one second after the create would fail as `refused` and show the approval dialog to a paid user.
- The app commits the grant create as its own write, before the page transaction, and never in the same batch or transaction as a page write.
  `approved()` reads the grant with `get()`, which does not see a write of the same request, and `charged()` requires `getAfter(...).updatedAt == request.time`, which a create at the fixed time cannot satisfy.
- A `create` fails when the document exists. So while the grant document exists, a grant that was withdrawn (`enabled: false`) cannot be created again by a paid user, and no client can raise its own limits or reset its counters.
  After a grant is deleted, a paid UID that can still sign in could create a new one; "Operations note" below closes that path.
- Clients still cannot update approval or limit fields, or delete a grant. The `update` rule of `validUsage` stays unchanged.
- `approved()` reads only `grant(uid).enabled == true` and does not call `paid()`. So decision 4 needs no rule change. Issue #147 must not add a paid check to `approved()` or to `validUsage`.
- Issue #147 decides where the app creates the grant: before the first page write, or after a refused share and then a retry. Either way, a paid user must share its first link with no dialog and no manual step.

### Request record for a free user

- A signed-in user may create `publishingRequests/{uid}` only for its own UID.
  The collection name is a proposal, and #147 can change it if it updates this spec and the privacy pages to match.
- The record holds only these fields:
  - `requestedAt`, which must equal `request.time`;
  - `companyName`, optional, the company name saved in the app, at most 100 characters (the same `text()` bound as the page `companyName`).
- The record holds no business phone, no email address, no client name, no report content, and no photo.
- The owner may `get` its own record, so that the app can show that a request is pending. Nobody else may read it, and no client may `list` the collection.
- The owner may `delete` its own record. No client may `update` it. To send the request again, the app deletes the record and creates a new one.
- A request is approved by creating the grant with privileged console access, as in the operations note, and then deleting the request.
  A request is declined by deleting it. The app learns the result only on its next share or its next read of the record.
- The email step and the registration-code dialog go away: the `mailto` action, the shown user ID, and the email fallback text. The abuse-report mail action of the web report stays.

### Legitimacy check

The operations note requires each publisher to be confirmed against an existing relationship. It says that an email address or replacement UID alone is not sufficient.
With no email, the request record is the only input.
A free publisher is confirmed by its company name against an existing relationship.
A request whose company cannot be identified stays pending or is declined.
The UID alone is never a reason to approve, and a replacement UID is not approved because an earlier UID was blocked or deleted.

### Deletion

- Delete All Data deletes the request record of the user before `Identity.deleteAccount`, because the rule needs the signed-in owner.
- A grant that the app created automatically is an approval and usage record, like a grant created by hand. It stays after Delete All Data until it is deleted on request, as both privacy pages say now.

### Operations note

Issue #147 changes `docs/notes/report-abuse-operations.md` to match this spec:

- Admission now depends on the entitlement for a paid user.
  So the sentence "store purchase entitlements do not grant publication approval" is no longer true, and #147 changes it.
- "Retention and deletion requests": before the grant of a UID is removed on a verified deletion request, it is confirmed that the Auth account of that UID no longer exists.
  Otherwise a paid UID that can still sign in creates a fresh grant with zero usage, which that section forbids ("Do not create a fresh grant automatically as a side effect of deletion").

## What stays from the 2026-10-08 spec

- The per-grant budgets and the per-report limits of the 2026-10-08 spec, "Content and volume limits".
  These budgets stay independent of subscription entitlements: a paid grant gets the same defaults, and a plan does not raise them.
- Blocks: `blockedPages/{pageId}`, `blockedAt`, and grant withdrawal by `enabled: false`.
- The abuse-report mail action on the report, history, and unavailable views, to the address of the 2026-10-08 spec.
- Deleting a resource does not refund its budget.
- A replacement anonymous UID without a paid entitlement gets no grant. A new anonymous UID has no grant by default.
- The approval-request path when the backend refuses a publication, and capture and PDF sharing without approval.

## Residual risks

- The claim follows the purchase, not the UID. If a purchase moves to a new anonymous UID, for example at a restore after Delete All Data or a reinstall, that UID can create its own grant, and the grant of the old UID stays.
  So one purchase can produce more than one grant over time, each with its full budgets.
  RevenueCat identity-transfer behavior is not verified for this app (`CLAUDE.md`, "Current state", issue #36), so this spec does not say when a transfer happens.
- `paid()` reads the ID token that the client sends. A token issued before a subscription ended can still carry the claim until it expires, so a user can create a grant during that time.
- Any anonymous account can hold one stored request record at a time. It can delete that record and create a new one, so the rules limit stored records and not the number of requests over time. The number of stored records is limited only by the number of anonymous accounts. This spec adds no cooldown and no other limit on repeated requests. Records can be deleted in bulk, and no request gets a grant without review.
- A paid UID whose grant was deleted can create a fresh grant with zero usage while it can still sign in. The check of the Auth account in "Operations note" closes that path. This spec does not establish whether the rules accept an ID token that was issued before the account was deleted.
- A blocked paid publisher can come back through a new UID that holds the purchase. The block of its pages and the withdrawal of its old grant stay. This spec adds no store-account blocklist. A later decision can add one.

## Privacy-page consequences for #147

Issue #147 changes both `web/privacy/index.html` and `web/privacy/en/index.html` together:

- Section 2: replace the paragraph that says the operator receives the registration code (user ID) and the email address of an approval request. Say that a paid account gets link sharing automatically, and that a free account sends an approval request inside the app.
- The automatic decision: say that the app reads the purchase entitlement from the ID token (the `revenueCatEntitlements` claim) to create the grant, and that the grant stays after the subscription ends.
- The request record: name its fields (the user ID as the document ID, the request time, and the optional company name), that it is stored in Cloud Firestore in the Seoul region, that only the app of the user and the operator read it, and that it is deleted when the operator approves or declines the request or the user deletes all data. It has no automatic deletion.
- Section 6: add the request record to the list of what Delete All Data deletes.
- Section 8: add the request record to the retention list. Split the paragraph "Approval requests and abuse reports contain the sender's email address …": approval requests no longer use email, and abuse reports still do.

## Acceptance criteria for #147

1. Paid self-grant → verify with `merry run rules`: a paid token creates its own grant only with the exact initial document; a wrong key, a changed limit, non-zero usage, an `updatedAt` other than 2000-01-01 UTC (`request.time` included), another UID's grant, and a free token fail; a create over an existing or withdrawn grant fails; a page charge right after the paid create, in a separate write, succeeds.
2. Grant after expiry → verify: a grant that a paid token created still publishes with a free token, within its budgets; `approved()` and `validUsage` do not call `paid()`.
3. Request record → verify: the owner creates, gets, and deletes only its own record with only the allowed fields; update, list, another UID's record, an over-long company name, and a `requestedAt` that is not the request time fail.
4. App flow → verify with widget and Cubit tests: a paid user shares its first link with no approval dialog; a free user sends a request with no email action and sees that the request is pending; the dialog shows no registration code.
5. Deletion → verify: Delete All Data deletes the request record before the account, and a failure of that step stops before the account deletion, as the other published-data steps do.
6. Documents → verify: both privacy pages and `docs/notes/report-abuse-operations.md`, "Enrollment", match this spec, and `test/web/privacy.test.mjs` passes.
7. Gates → verify: `merry run check`, `merry run coverage`, `merry run rules`, and the CI jobs pass.

## Ordering constraints

- #147 merges before the #86 rules are deployed. The privacy pages of #147 are deployed to Hosting before the app collects request records or creates grants, as rollout step 1 of the operations note requires.
- Rollout step 2 of the operations note (inventory and enrollment of existing publishers) finishes before the rules are enforced.
  This includes existing paid publishers. A grant that a paid user creates starts at zero usage with no reservations, so an existing paid publisher that is not inventoried would count fewer pages and reports than it has and leave its existing photos unreserved.
  An enrolled publisher already has a grant, so the `create` rule refuses a second one.
- Rollout step 3 of the operations note ("Deliver the compatible app before enforcement") now means a build that holds #147.
  `1.1.2+6` holds the #86 client but not #147, so it cannot create a grant, and after enforcement it still shows the email dialog to a paid user without a grant until that user updates.
  How an approval email is handled from such a build is left to the operations-note change of #147.
- Each deploy, grant, and enrollment still needs the user's approval for that run.

## Sources

- [Issue #146](https://github.com/AndrewDongminYoo/kkomkkomi/issues/146), [issue #145](https://github.com/AndrewDongminYoo/kkomkkomi/issues/145), and [issue #147](https://github.com/AndrewDongminYoo/kkomkkomi/issues/147).
- `docs/specs/2026-10-08-report-abuse-controls.md` and `docs/notes/report-abuse-operations.md` on main at `58bdff2`.
- `firestore.rules` (`grant`, `approved`, `paid`, `validUsage`, and `match /publishingGrants/{uid}`) and `lib/presentation/visit_report/view/visit_report_page.dart` (`_requestApproval`) at the same revision.
- `web/privacy/en/index.html`, sections 2, 6, and 8, at the same revision.
- `docs/notes/revenuecat-claims-cutover.md` for the writer of the `revenueCatEntitlements` claim.
- For the shipped #86 client: `git merge-base --is-ancestor 78ceded bcac1e4` (exit 0), `lib/firebase/firebase_publisher.dart` at `bcac1e4` (`_approved`, `_refusedCodes`), `firestore.rules` at `135c67f`, `docs/notes/2026-10-31-production-build-provenance.md`, and `docs/notes/2026-10-31-play-internal-distribution.md`.
