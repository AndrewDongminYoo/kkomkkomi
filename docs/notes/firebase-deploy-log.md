# Firebase deploy log

## Current state

Moved unchanged from `CLAUDE.md` § Current state on 2026-11-02.
`CLAUDE.md` keeps the commits that the deployed rules and Hosting equal, and the approval rule.

Each deploy was approved. The rules and Hosting were first deployed from `ab6d8d7` on 2026-10-02, and again from `34d5d23` on 2026-10-02, after the account deletion merged, which added the owner delete to `firestore.rules` and published the privacy pages under `web/privacy/`.
Hosting alone was deployed a third time from `bc4d57c` on 2026-10-03, after the client link pull request merged, which changed section 5 and the effective date of the privacy pages.
Hosting alone was deployed a fourth time from `d438781` on 2026-10-04, after the durable page deletion pull request (#32) merged, which changed the privacy pages; the same deploy carried a formatting-only change of `web/index.html` and `web/report/index.html`.
The Firestore rules and Hosting were deployed from `135c67f` on 2026-10-05, after the M3 pull requests #42 to #45 and #47 to #49 merged: `firestore.rules` accepts `unbranded` from a paid writer (#42), the web report hides the footer text of an unbranded report (#42), and the privacy pages changed in #43, #44, #45, #48, and #49. `storage.rules` had not changed since `34d5d23`, so it was not deployed.
Hosting alone was deployed from `0da9ccf` on 2026-10-06, after #55 merged, which added the Google Search Console verification file under `web/` (issue #53). No other file under `web/` had changed since `135c67f`.
Hosting alone was deployed again from `6bae5df` on 2026-10-06, after #57 merged, which added `web/sitemap.xml` and `web/robots.txt`.
Hosting alone was deployed from `300add7` on 2026-10-07, after #69 merged, which changed the web report and both privacy pages for the zone status. No other file under `web/` had changed since `6bae5df`.
Hosting alone was deployed again from `59b1c84` on 2026-10-07, after #74, #76, #77, #78, and #80 merged, which changed the web report (the gallery mark of #77) and both privacy pages (#76, #77, #78). No other file under `web/` had changed since `300add7`.
Hosting was deployed from `101fd6d` on 2026-11-10 as rollout step 1 of the #86 controls, and the Firestore and Storage rules were deployed together from `101fd6d` the same day as rollout step 4; `docs/notes/2026-11-10-emudhra-firestore-patch.md` owns the read-back of both.

## RevenueCat extension

Issue #51 tracks the update to 0.2.0 before Cloud Functions decommissions `nodejs20` on 2026-10-30, and the replacement of the extension before Firebase Extensions shuts down on 2027-03-31.

## RevenueCat claims function

Each step of `docs/notes/revenuecat-claims-cutover.md` was approved on 2026-11-02 (issue #51).

- Step 1: secret `REVENUECAT_WEBHOOK_SECRET` version 1 was created from version 2 of the extension secret; the two values were compared by hash, and neither was printed.
- Step 2: `revenueCatWebhook` was deployed from `1343768` (#143) to `asia-northeast3` on `nodejs24`. The first deploy enabled the Cloud Run and Eventarc APIs and failed while it created the Cloud Run service; the second succeeded as an update without the public invoker, and `allUsers` `roles/run.invoker` was added by hand. The deploy also granted the default compute service account `roles/secretmanager.secretAccessor` on the new secret. An empty POST then answered 401, and a token signed with the secret for a user that does not exist answered 200 with the "does not exist" warning.
- Step 3: the RevenueCat Firebase integration's Trigger URL was replaced with `https://asia-northeast3-kkomkkomi.cloudfunctions.net/revenueCatWebhook` at about 02:35 UTC; the field rejected the `run.app` URL. The previous URL, for the rollback, is `https://asia-northeast3-kkomkkomi.cloudfunctions.net/ext-firestore-revenuecat-purchases-handler`.
- Step 4: a TestFlight Pro monthly purchase reached the function as two requests at 02:44:07 UTC, both answered 200 with no warning or error. The buyer's claims then read `revenueCatEntitlements: ["basic","pro"]` with `revenueCatEventTimestampMs` 02:44:06 UTC, the extension handler logged nothing after 02:30 UTC, and no footer text showed on a new visit report. RevenueCat answered an entitlement expiry of 2026-11-03 02:44:04 UTC, one TestFlight renewal day, so the expiry check (4.6) waits for the end of the TestFlight renewals, around 2026-11-09.
- Step 5 has not run; the extension instance `firestore-revenuecat-purchases` 0.1.19 is still installed on `nodejs20` and receives no events.
- No Artifact Registry cleanup policy is set in `asia-northeast3`.
