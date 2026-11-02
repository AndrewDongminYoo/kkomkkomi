# Firebase deploy log

## Current state

Moved unchanged from `CLAUDE.md` § Current state on 2026-11-02.
`CLAUDE.md` keeps the commits that the deployed rules and Hosting equal, and the approval rule.

The operator approved each deploy. The rules and Hosting were first deployed from `ab6d8d7` on 2026-10-02, and again from `34d5d23` on 2026-10-02, after the account deletion merged, which added the owner delete to `firestore.rules` and published the privacy pages under `web/privacy/`.
Hosting alone was deployed a third time from `bc4d57c` on 2026-10-03, after the client link pull request merged, which changed section 5 and the effective date of the privacy pages.
Hosting alone was deployed a fourth time from `d438781` on 2026-10-04, after the durable page deletion pull request (#32) merged, which changed the privacy pages; the same deploy carried a formatting-only change of `web/index.html` and `web/report/index.html`.
The Firestore rules and Hosting were deployed from `135c67f` on 2026-10-05, after the M3 pull requests #42 to #45 and #47 to #49 merged: `firestore.rules` accepts `unbranded` from a paid writer (#42), the web report hides the footer text of an unbranded report (#42), and the privacy pages changed in #43, #44, #45, #48, and #49. `storage.rules` had not changed since `34d5d23`, so it was not deployed.
Hosting alone was deployed from `0da9ccf` on 2026-10-06, after #55 merged, which added the Google Search Console verification file under `web/` (issue #53). No other file under `web/` had changed since `135c67f`.
Hosting alone was deployed again from `6bae5df` on 2026-10-06, after #57 merged, which added `web/sitemap.xml` and `web/robots.txt`.
Hosting alone was deployed from `300add7` on 2026-10-07, after #69 merged, which changed the web report and both privacy pages for the zone status. No other file under `web/` had changed since `6bae5df`.
Hosting alone was deployed again from `59b1c84` on 2026-10-07, after #74, #76, #77, #78, and #80 merged, which changed the web report (the gallery mark of #77) and both privacy pages (#76, #77, #78). No other file under `web/` had changed since `300add7`.

## RevenueCat extension

Issue #51 tracks the update to 0.2.0 before Cloud Functions decommissions `nodejs20` on 2026-10-30, and the replacement of the extension before Firebase Extensions shuts down on 2027-03-31.
