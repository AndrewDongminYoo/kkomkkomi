# Google Play terms preparation — 2026-11-05

The app previously linked Apple's standard EULA on every platform. The proposed change keeps it on iOS and gives Android the provider's own service terms at:

- Korean: https://kkomkkomi.web.app/terms/
- English: https://kkomkkomi.web.app/terms/en/

The static pages reuse the privacy stylesheet and are linked from the landing footer. They describe the existing subscription and report-sharing behavior without publishing prices, declaring trader status or adding address/phone information.

## Release order

1. Review the provider, subscription and consumer-rights wording. The proposed effective date is 2026-11-05; align it with the actual publication date if publication is delayed.
2. Review the complete Hosting delta against the deployed revision recorded in `CLAUDE.md`. The working tree includes unrelated, previously undeployed report/privacy changes; do not deploy all of `web/` as an incidental terms-only release. Obtain approval for the exact Hosting scope, then verify both terms URLs, their language switch and privacy links on the live host.
3. Run the changed plans widget tests and the normal Flutter gates before releasing a binary that uses the Android URL. This editing environment has no Flutter SDK, so no Flutter pass is claimed.
4. Separately read Play Console account declaration and per-app requirements. Confirm distribution countries, real payment activity, account type and public-contact preview before choosing a status. If trader applies, supply this app's service terms URL where requested.

No Hosting deploy, store upload, declaration, country selection or public-contact change is part of this patch. Repository content alone does not establish current app distribution, sales or declaration completion.

Policy reference: https://support.google.com/googleplay/android-developer/answer/17594752
