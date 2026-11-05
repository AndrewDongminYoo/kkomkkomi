# Report abuse operations

## State and authority

These are the local controls of issue #86, not a record of live enrollment or deployment.
Controlled publisher admission, the safety budgets and retaining `kkomkkomi.web.app` were approved on 2026-10-08.
Every production grant, block, deletion, rule deploy, Hosting deploy and app upload still needs approval for that run.
No email has been sent or delivery verified.
The landing inquiry form does not send messages.

## Enrollment

`docs/specs/2026-11-02-publisher-approval-request.md` owns the admission decision of issue #146; this section is the operational procedure.
A publisher without a grant presses **Share link** once first, because the app does not read its grant before a share.

- A paid publisher: after that refusal, the app asks for a newly issued ID token, and when its `revenueCatEntitlements` claim holds `basic` or `pro`, the app creates `publishingGrants/{uid}` itself with the initial document below and shares again. No manual step is needed.
- A free publisher: the visit report screen offers **Request link sharing approval**, and its dialog writes `publishingRequests/{uid}` with `requestedAt` and, when the company profile is saved, `companyName`. No email is sent, and the screen shows the request as pending.

Find pending requests in the Firestore console under `publishingRequests`; the document ID is the UID.
Confirm the company name against an existing relationship; the UID alone, an email address, or a replacement UID is not sufficient.
Do not approve a replacement UID because an earlier UID was blocked or deleted, and do not grant every existing anonymous UID.
To approve, use privileged Firestore console access to create `publishingGrants/{uid}`, then delete the request.
To decline, delete the request.
When the company cannot be identified, decline the request or leave it pending; a declined request is never kept.
The app learns the result only at its next share or its next read of the request.
Clients can read only their own grant, can create one only with a paid token and only as the initial document below, and cannot update approval or limits or delete a grant.

The initial document has these fields:

```json
{
  "enabled": true,
  "pageLimit": 50,
  "reportLimit": 1000,
  "photoLimit": 2000,
  "byteLimit": 1073741824,
  "pages": 0,
  "reports": 0,
  "photos": 0,
  "bytes": 0,
  "reservations": {},
  "type": "page",
  "pageId": "initial",
  "visitId": "",
  "fileName": ""
}
```

Also set `updatedAt` to a Firestore timestamp in the past, such as 2000-01-01 UTC.
The JSON above is a field reference; it is not a command to issue a live grant.
For an existing publisher, inventory page/report counts and photo objects/bytes first and seed those totals, rather than resetting them to zero.
Seed each existing photo reservation as `pageId/visitId/fileName: byteLength`.
If legitimate existing usage exceeds a default, increase the managed limit after approval; preserve the counters.
Reserve at most 2,000 active photo paths per document and keep keys at most 384 characters; do not raise that structural limit by changing only a grant.
Read back the exact UID, approval, limits and inventory counters before testing with that user.
A new or deleted UID needs a new approval.
A paid entitlement admits a UID only through the self-created initial grant; it never raises limits, resets counters, or re-enables a withdrawn grant, and the grant stays after the subscription ends.

Builds without issue #147, such as `1.1.2+6`, still show the email dialog with the registration code (the UID).
Handle such an email as a request record: confirm the sender against an existing relationship before creating a grant, and delete the email after handling.
A paid publisher on such a build gets its grant automatically after it updates to a build that holds #147, so ask it to update rather than granting by hand.

## Reports and takedown

Recipients use **이 보고서 신고하기** on a report, history or unavailable view, including unbranded reports.
It opens a mail draft to `donminzzi@gmail.com` with a validated report path and a blank reason.
The recipient reviews and sends it; no message is sent by a page read.
The visible address remains a fallback when no mail application is configured.
Do not ask for photos, full report contents, business phone numbers or other unnecessary personal data in email.
Keep the supplied link and the minimum reason needed to investigate; do not copy the report into GitHub.
Delete request emails after handling.

After approval for the exact page and publisher:

1. In a single privileged Firestore batch, set `clientPages/{pageId}.blockedAt` to a timestamp and create `blockedPages/{pageId}` with only `blockedAt`.
2. Set the publisher's grant `enabled` to false to stop new publication throughout that account.
3. Delete all Storage objects below `clientPages/{pageId}/` to invalidate existing download tokens, then delete the page's report and private validation documents if required by the response.
4. Keep the durable `blockedPages/{pageId}` record, even if the parent page is deleted.
5. Read the page, history, report and token-free photo endpoint through the anonymous web reader; each must be unavailable. Also check any known issued download URL after object deletion.
6. Confirm that another UID has no grant and the original owner cannot recreate the blocked page or remove its block.

Page blocking denies current rules-based reads immediately.
An already issued Storage download token bypasses subsequent rule reads, so blocking alone is insufficient: photo deletion is part of takedown.
Cached or downloaded copies cannot be recalled.
Grant withdrawal alone stops new writes but does not close previously published pages; use the page block and photo deletion too.
Clients retain owner deletion and revoke access; they cannot erase durable blocks.
An admitted account may reconcile an absent page as closed after withdrawal within its existing budget and cooldown.

## Retention and deletion requests

App deletion removes photos and their active reservations, reports, private report reservation headers and their seven validation chunks, pages, the anonymous Auth account and device data.
The account's approval and lifetime usage document remains until deletion on request; the app cannot reset its allowance.
On a verified deletion request, remove that UID's grant document after checking the relevant pages have been removed, and remove its `publishingRequests/{uid}` document if one remains.
Before removing the grant, confirm in the Authentication console that the Auth account of that UID no longer exists; otherwise a paid UID that can still sign in creates a fresh grant with zero usage.
Do not create a fresh grant automatically as a side effect of deletion.
Durable blocks retain only blocked page IDs and times while the report-sharing service operates, to prevent the same address being reopened.
Both privacy pages disclose these records and email handling.

## Compatibility and rollout

1. Deploy the web reporting action and both privacy pages with Hosting approval, and read back the files before collecting approval requests or issuing grant records.
2. Obtain approval to inventory existing publishers and their usage, paid ones included, and enroll only legitimate users with accurate counters and reservations. A self-created grant starts at zero usage, and the create rule refuses a second grant, so an enrolled paid publisher keeps its seeded counters. Review remaining existing pages and apply the approved takedown procedure where legitimacy cannot be established; requiring a grant for new writes does not hide old content by itself.
3. Deliver the compatible app before enforcement: a build that holds issue #147, so that a paid publisher gets its grant and a free publisher sends an in-app request. Its page transaction charges one bound resource; each changed report reserves a private slot, validates seven chunks in separate transactions, then atomically publishes the whole report; its photo upload reserves bytes and compares uncertain prior bytes instead of overwriting an object.
4. Deploy Firestore and Storage rules as one approved rollout and read back the deployed sources. Storage must retain the existing Firestore service-agent role described in `CLAUDE.md`.
5. Test one approved publisher, an unapproved UID, an exact allowance, a blocked fictional page, approval fallback and anonymous recipient reads before widening distribution.

Build 3 and other old clients cannot create or change resources after enforcement because they do not charge usage or reserve photos.
Existing open links remain readable; local capture and PDF sharing continue.
Existing identical new-adapter retries consume no new allowance; changed resources require approval and one second between charges using server time.
Deletion does not refund page, report, object or reserved-byte allowance, including abandoned report drafts.
A report retry reuses its reserved slot; deleting the header and starting again consumes another slot.
Removing a photo reservation and recreating its object consumes another object and byte allowance.
Do not roll back to permissive anonymous writes as a routine recovery: withdraw grants or pause sharing while repairing a compatible client.
Changes to budgets and retention are separate decisions; subscription plans do not override these safety controls.
The shared host still exposes the landing/privacy host to approved-publisher content and browser-reputation risk; there is no automated content moderation or complete defense against repeated fraudulent approval requests.

## Local verification

Use fictional data and only the `demo-kkomkkomi` project in emulators.
The rules suite exercises direct API bypass, quotas, payload validation, retry, deletion, blocks, the paid self-grant, the approval request record and the real token-free web reader.
The mailbox is not exercised by this command.

```sh
merry run rules
merry run check
merry run coverage
```

[Firebase rules limits](https://firebase.google.com/docs/rules/rules-behavior) restrict Storage to two Firestore document reads per request and Firestore to 1,000 expressions per request.
The account document combines approval, usage and reservations so Storage creates read only the account and page; public gets read the page and durable block.
Report validation reserves a quota-bound private header, commits seven fixed private chunks of three zones separately, and then publishes a report matching their concatenation.
Partial drafts stay private and count toward the lifetime report budget; the final transaction pins all seven versions, so a concurrent draft cannot publish mixed content.
The app removes the header and chunks during report deletion, including interrupted queue jobs.
[Firestore atomic-write conditions](https://firebase.google.com/docs/firestore/security/rules-conditions) describe the `getAfter` binding.
[Firebase Storage downloads](https://firebase.google.com/docs/storage/web/download-files) describe directly usable download URLs; their deletion check remains part of local takedown verification.
