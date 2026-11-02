// Derived from functions/src/index.ts of RevenueCat/firestore-revenuecat-purchases
// at commit 8089f19e948b3326040425de158fa1233891d675 (Apache-2.0).
// Modified for kkomkkomi: a Cloud Functions v2 HTTPS function in
// asia-northeast3 that reads its shared secret from Secret Manager. See NOTICE.
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { onRequest } from "firebase-functions/v2/https";

import { createHandler } from "./handler";

initializeApp();

/** The shared secret of the RevenueCat Firebase integration. */
const webhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");

/**
 * The URL that the RevenueCat Firebase integration calls for each event. It
 * writes the `revenueCatEntitlements` custom claim and nothing in Firestore.
 */
export const revenueCatWebhook = onRequest(
  // One instance, so that the per-user queue of the handler sees every event
  // of a user. Overlapping requests share that instance.
  { region: "asia-northeast3", maxInstances: 1, secrets: [webhookSecret] },
  createHandler({
    auth: getAuth(),
    getSecret: () => webhookSecret.value(),
    now: () => Date.now(),
    logger,
  }),
);
