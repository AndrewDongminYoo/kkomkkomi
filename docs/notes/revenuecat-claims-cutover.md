# RevenueCat claims cutover

This runbook moves the writer of the `revenueCatEntitlements` custom claim from the RevenueCat Firebase extension `firestore-revenuecat-purchases` to the repository function `revenueCatWebhook` under `functions/` (issue #51).
`functions/NOTICE` owns the list of differences from the extension handler.

## State and authority

The function is not deployed, its secret has no value, and the extension still writes the claim.
The operator approved this plan on 2026-11-02 and approves each step below separately: setting the secret, the deploy, the RevenueCat integration change, and the extension uninstall.
Each step is an external action on the production project `kkomkkomi`, which the paying users of Google Play production `1.1.2` (version code `6`) depend on.
Record each completed step, with its date and commit, in `docs/notes/firebase-deploy-log.md`.

## What does not change

- The claim name `revenueCatEntitlements` and its value (the list of active entitlement identifiers), which `firestore.rules` `paid()` and `FirebaseIdentity.hasPaidEntitlement()` read.
- The watermark claim `revenueCatEventTimestampMs`, which the extension has written since version 0.1.19.
- Nothing in Firestore: the function writes custom claims only, as the extension does with both collection parameters empty, so the privacy pages do not change.
- No Dart code, rules, or Hosting file changes, and no app release is needed.

## 1. Set the secret

The shared secret is the one that the RevenueCat Firebase Extension settings page generated for the extension.
Keep that value, so that RevenueCat signs requests for the extension and for the function with the same key during the switch.
Read it from RevenueCat or from the Secret Manager secret of the extension; do not paste it in a chat, an issue, or a tracked file.

```sh
firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET --project kkomkkomi
```

The function refuses every request with status 500 while the secret is empty.

## 2. Deploy the function

Deploy from a clean checkout of `main` after `npm ci --prefix functions`:

```sh
firebase deploy --only functions:revenueCatWebhook --project kkomkkomi
```

- The `predeploy` step of `firebase.json` builds `functions/lib/` first.
- The first functions deploy can ask to enable the Cloud Functions, Cloud Build, Artifact Registry, Cloud Run, and Secret Manager APIs; read the prompt before accepting it.
- Now that `firebase.json` holds a `functions` block, a bare `firebase deploy` includes the function.
  Keep naming the target with `--only`, as the rules and Hosting deploys already do.
- The function runs in `asia-northeast3` on `nodejs24`, with at most one instance.
  Its URL is in the deploy output and in Firebase console > Functions.
- Firebase Auth has no compare-and-set, so the function orders the events of one user by reading the watermark and writing the claims inside a per-user queue of its one instance.
  Two requests that two instances or two revisions serve at the same time, for example while a deploy replaces the revision, are not ordered, and an older event can then write last until the next event of that customer.
  The same holds at the URL change of step 3, when an event that the extension still handles can overlap one that the function handles.
  Closing that window needs a transactional watermark in Firestore, which needs a change of the privacy pages and the operator's approval first.
  Do not raise `maxInstances` without that.

Check the function before RevenueCat calls it:

```sh
curl -sS -X POST -H 'Content-Type: application/json' -d '{}' <function URL>
```

The expected answer is status 401 with `{"message":"The webhook token could not be verified with the shared secret."}`.
A 500 with `The webhook shared secret is not configured.` means step 1 is missing.
An HTML 403 page from Google means the function does not allow unauthenticated calls, which RevenueCat needs.

## 3. Change the RevenueCat integration URL

In the RevenueCat Firebase Extension settings page, replace the Trigger URL of the extension with the URL of `revenueCatWebhook`.
Leave the shared secret as it is.
Write down the old Trigger URL first, because the rollback needs it.

## 4. Verify with a sandbox purchase

1. Make a sandbox purchase of Basic or Pro on a test device of the production flavor.
2. In RevenueCat Customer History, confirm that the Firebase integration event was delivered successfully.
3. In the Cloud Functions logs of `revenueCatWebhook`, confirm the request and that no error was logged.
4. Read the user with the Firebase Admin SDK or `firebase auth:export`, and confirm that its custom claims hold `revenueCatEntitlements` with the purchased entitlement and a `revenueCatEventTimestampMs`, and keep any other claim that the user had.
5. Confirm on the device that a new visit report has no footer text.
6. Cancel or let the sandbox subscription expire, and confirm that the next event empties the list.

If the write fails with a permission error, the runtime service account of the function lacks Firebase Authentication admin rights.
Grant it `roles/firebaseauth.admin` with the operator's approval, then repeat the sandbox event.

A failed claim write is logged as an error and answered with status 200, as the extension did, so Customer History shows the event as delivered even then.
The function log of step 3 is the place where such a failure shows.

## 5. Uninstall the extension

After step 4 passes, uninstall the extension instance `firestore-revenuecat-purchases` from Firebase console > Extensions.
If its Secret Manager secret remains after the uninstall, it can be deleted with the operator's approval; `REVENUECAT_WEBHOOK_SECRET` does not reference it.
Update the extension paragraph of `CLAUDE.md` and the RevenueCat extension section of `docs/notes/firebase-deploy-log.md` in the same change.

## Roll back

- Before step 5: put the old Trigger URL back in the RevenueCat Firebase Extension settings page.
  The extension writes the same claims, so no user data changes.
- After step 5, do not plan on reinstalling the extension: issue #51 records that its 0.2.0 update could not be deployed, and Firebase Extensions shuts down on 2027-03-31.
  Fix the function and deploy it again instead: `git revert` the faulty change, then repeat step 2.
- A claim that a faulty deploy wrote is corrected by the next event of that customer that the fixed function applies.
- `firebase functions:delete revenueCatWebhook --region asia-northeast3 --project kkomkkomi` removes the function, and leaves every claim as it is.
