# Report abuse operations

## State and authority

These are the local controls of issue #86, not a record of live enrollment or deployment.
The operator approved controlled publisher admission, the safety budgets and retaining `kkomkkomi.web.app` on 2026-10-08.
Every production grant, block, deletion, rule deploy, Hosting deploy and app upload still needs approval for that run.
No email has been sent or delivery verified.
The landing inquiry form does not send messages.

## Enrollment

Use the app's **Request link sharing approval** action to obtain the publisher's anonymous registration code.
Confirm that the request belongs to a legitimate intended publisher using the operator's existing relationship; an email address or replacement UID alone is not sufficient.
Do not grant every existing anonymous UID or restore approval merely because an account was replaced.
Use privileged Firestore console access to create `publishingGrants/{uid}`.
Clients can read only their own document and cannot issue or delete grants or modify operator approval and limits.

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
If legitimate existing usage exceeds a default, increase the operator-managed limit after approval; preserve the counters.
Reserve at most 2,000 active photo paths per document and keep keys at most 384 characters; do not raise that structural limit by changing only a grant.
Read back the exact UID, approval, limits and inventory counters before testing with that user.
A new or deleted UID needs a new approval; store purchase entitlements do not grant publication approval.

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
Clients retain owner deletion and revoke access; they cannot erase durable operator blocks.
An admitted account may reconcile an absent page as closed after withdrawal within its existing budget and cooldown.

## Retention and deletion requests

App deletion removes photos and their active reservations, reports, private report reservation headers and their seven validation chunks, pages, the anonymous Auth account and device data.
The account's approval and lifetime usage document remains until operator deletion on request; the app cannot reset its allowance.
On a verified deletion request, remove that UID's grant document after checking the relevant pages have been removed.
Do not create a fresh grant automatically as a side effect of deletion.
Durable blocks retain only blocked page IDs and times while the report-sharing service operates, to prevent the same address being reopened.
Both privacy pages disclose these records and email handling.

## Compatibility and rollout

1. Deploy the web reporting action and both privacy pages with Hosting approval, and read back the files before collecting approval requests or issuing grant records.
2. Obtain approval to inventory existing publishers and their usage, and enroll only legitimate users with accurate counters and reservations. Review remaining existing pages and apply the approved takedown procedure where legitimacy cannot be established; requiring a grant for new writes does not hide old content by itself.
3. Deliver the compatible app before enforcement. Its page transaction charges one bound resource; each changed report reserves a private slot, validates seven chunks in separate transactions, then atomically publishes the whole report; its photo upload reserves bytes and compares uncertain prior bytes instead of overwriting an object.
4. Deploy Firestore and Storage rules as one approved rollout and read back the deployed sources. Storage must retain the existing Firestore service-agent role described in `CLAUDE.md`.
5. Test one approved publisher, an unapproved UID, an exact allowance, a blocked fictional page, approval fallback and anonymous recipient reads before widening distribution.

Build 3 and other old clients cannot create or change resources after enforcement because they do not charge usage or reserve photos.
Existing open links remain readable; local capture and PDF sharing continue.
Existing identical new-adapter retries consume no new allowance; changed resources require approval and one second between charges using server time.
Deletion does not refund page, report, object or reserved-byte allowance, including abandoned report drafts.
A report retry reuses its reserved slot; deleting the header and starting again consumes another slot.
Removing a photo reservation and recreating its object consumes another object and byte allowance.
Do not roll back to permissive anonymous writes as a routine recovery: withdraw grants or pause sharing while repairing a compatible client.
Changes to budgets and retention are separate operator decisions; subscription plans do not override these safety controls.
The shared host still exposes the landing/privacy host to approved-publisher content and browser-reputation risk; there is no automated content moderation or complete defense against repeated fraudulent approval requests.

## Local verification

Use fictional data and only the `demo-kkomkkomi` project in emulators.
The rules suite exercises direct API bypass, quotas, payload validation, retry, deletion, operator blocks and the real token-free web reader.
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
