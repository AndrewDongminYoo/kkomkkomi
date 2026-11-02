// Derived from functions/src/validate-and-get-payload.ts and
// functions/src/exceptions.ts of RevenueCat/firestore-revenuecat-purchases at
// commit 8089f19e948b3326040425de158fa1233891d675 (Apache-2.0).
// Modified for kkomkkomi: the algorithm is fixed to HS256, an empty secret is
// refused, the payload shape is checked before any write, and the errors carry
// an HTTP status only. See NOTICE.
import * as nJwt from "njwt";

import { BodyPayload } from "./types";

/** A request failure with the HTTP status that the webhook answers. */
export class WebhookError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "WebhookError";
  }
}

export const invalidToken = (): WebhookError =>
  new WebhookError(
    401,
    "The webhook token could not be verified with the shared secret.",
  );

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const hasEntitlements = (value: unknown): boolean =>
  isObject(value) && isObject(value.entitlements);

/** Whether `value` names a user: a string that is not empty. */
export const isUserId = (value: unknown): value is string =>
  typeof value === "string" && value.length > 0;

/**
 * Verifies `body.token` as an HS256 JWT signed with `secret` and returns the
 * JSON payload that its `payload` claim holds.
 *
 * Throws a 500 `WebhookError` when the secret is empty, because an empty HMAC
 * key would accept a token that anyone can sign, a 401 one when the token is
 * missing, expired, or not signed with the secret, and a 500 one, the status
 * with which the upstream handler failed on such a payload, when the verified
 * payload lacks an event or a customer that the claim writer needs.
 */
export const verifyPayload = (
  body: unknown,
  secret: string | undefined,
): BodyPayload => {
  if (!secret) {
    throw new WebhookError(500, "The webhook shared secret is not configured.");
  }

  const token = isObject(body) ? body.token : undefined;
  if (typeof token !== "string" || token.length === 0) {
    throw invalidToken();
  }

  let payload: unknown;
  try {
    const verified = nJwt.verify(token, secret, "HS256");
    const claim = (verified?.body as { payload?: unknown } | undefined)
      ?.payload;
    if (typeof claim !== "string") {
      throw invalidToken();
    }
    payload = JSON.parse(claim);
  } catch {
    throw invalidToken();
  }

  if (!isObject(payload) || !isObject(payload.event)) {
    throw new WebhookError(500, "The webhook payload has no event.");
  }
  const event = payload.event;
  if (isUserId(event.app_user_id) && !hasEntitlements(payload.customer_info)) {
    throw new WebhookError(
      500,
      "The webhook payload has no customer entitlements.",
    );
  }
  if (
    event.type === "TRANSFER" &&
    isUserId(event.origin_app_user_id) &&
    !hasEntitlements(payload.origin_customer_info)
  ) {
    throw new WebhookError(
      500,
      "The transfer payload has no origin customer entitlements.",
    );
  }

  return payload as unknown as BodyPayload;
};
