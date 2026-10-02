# Brief: privacy policy page

Read `CLAUDE.md`, the "Phase B" section of `docs/specs/2026-10-01-m1-local-first-design.md`, `firestore.rules`, and `storage.rules` before you write.

## Goal

A privacy policy page in Korean and English at `https://kkomkkomi.web.app/privacy/`, which the store listings can name.
The page describes what the app and the Firebase project actually collect, keep, show, and delete, and it does not describe what a privacy policy usually says.

## In scope

- New files under `web/privacy/`. Do not edit `web/index.html` or the landing page assets.
- One page with a Korean section and an English section, or two pages with a link between them. Choose, and state why.
- A link from the web report page footer to the policy, if the report page has a footer that can take it without a design change.

## What the page must state, each with its source

Trace every clause to a rule, a line of code, or a command output, and list the trace in the pull request body.

- What the app keeps only on the phone: clients, zones, visits, photos, notes, and the company name in SQLite and app files.
- What a publish sends: the company name, the client name, the visit date, the zone names, the notes, and the photos, under a page ID.
- Who can read it: anyone who has the link, while the page is open. `firestore.rules` and `storage.rules` say this.
- What a revoke does and does not do: it deletes the photos and hides the page, and the page and report documents stay in Firestore, because the rules allow no delete. Say this plainly.
- What an uninstall does: the anonymous account is lost, and a link that was never revoked stays readable, and nobody can revoke it from the app. Say this plainly.
- The anonymous sign-in and the user ID it creates.
- Where the data is stored: Firestore is in `asia-northeast3`. Read the Storage bucket location with `gcloud storage buckets describe gs://kkomkkomi.firebasestorage.app` (read-only), and cite where Firebase Authentication keeps accounts. State whether this is a transfer abroad or a processing outsourcing to Google that the page must disclose, with the source of that requirement.
- What the app does not collect: check for analytics, crash reporting, advertising, and location in `pubspec.lock` and `lib/`, and state only what the check shows.
- Photos can show people, monitors, and documents. The capture guide note of the business plan is not built yet, so do not claim that it exists.

## Do not invent

- The privacy officer and the contact address. Put a marked placeholder, `[운영자 확인 필요: 개인정보 보호책임자와 연락처]` in Korean and `[Operator to confirm: privacy officer and contact]` in English. The repository and the site are public.
- Any legal conclusion. The business plan leaves open whether the company or the app operator is responsible for the people in the photos under the Korean Personal Information Protection Act. Mark that point for the operator's review, and do not decide it.

## Account deletion

Find out, with citations to the Apple App Store Review Guidelines and to the Google Play policy, whether an app that signs in anonymously and keeps no account the person can see must offer account deletion.
Do not build a deletion path in this brief. Report the answer, because it can block the test distribution.

## Out of scope

- Terms of service.
- Any deploy. The page goes live only on a Hosting deploy, which needs the operator's approval.

## Acceptance criteria

- The page renders at a 320 pixel width without horizontal scroll, checked with the same method as the web report page tests.
- `merry run check` passes.
- The pull request body lists each clause with its source, the placeholders, and the account deletion answer.
