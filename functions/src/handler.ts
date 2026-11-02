// Derived from functions/src/index.ts and functions/src/error-handler.ts of
// RevenueCat/firestore-revenuecat-purchases at commit
// 8089f19e948b3326040425de158fa1233891d675 (Apache-2.0).
// Modified for kkomkkomi: the handler writes custom claims only, with no
// Firestore collection, no Eventarc channel, no moment, and no extension
// version header or API version check; and it reads and writes through one
// injected Auth. See NOTICE.
import { isUserId, verifyPayload, WebhookError } from "./payload";
import { CustomerInfo, isTransfer } from "./types";

/** The custom claim that `firestore.rules` `paid()` and the app read. */
export const ENTITLEMENTS_CLAIM = "revenueCatEntitlements";

/** The custom claim that holds the timestamp of the last event applied to the user. */
export const EVENT_TIMESTAMP_CLAIM = "revenueCatEventTimestampMs";

/** The part of the Firebase Admin `Auth` that the handler uses. */
export interface ClaimsAuth {
  getUser(uid: string): Promise<{ customClaims?: Record<string, unknown> }>;
  setCustomUserClaims(
    uid: string,
    claims: Record<string, unknown> | null,
  ): Promise<void>;
}

/** The part of the Cloud Functions logger that the handler uses. */
export interface WebhookLogger {
  info(message: string): void;
  warn(message: string): void;
  error(message: string): void;
}

/** The part of the Express request that the handler reads. */
export interface WebhookRequest {
  body?: unknown;
}

/** The part of the Express response that the handler writes. */
export interface WebhookResponse {
  status(code: number): WebhookResponse;
  json(body: unknown): unknown;
}

export interface HandlerDependencies {
  auth: ClaimsAuth;
  /** Reads the shared secret at request time, never at module load. */
  getSecret: () => string | undefined;
  /** The current time in milliseconds since the epoch. */
  now: () => number;
  logger: WebhookLogger;
}

interface ClaimUpdate {
  userId: string;
  customer: CustomerInfo;
}

// An event is stale only when it carries a timestamp that is strictly older than
// the one already applied. A missing timestamp or a stored value that is not a
// number (nothing applied yet) both mean the event is treated as fresh. Equal
// timestamps also apply, since a retry reuses the original event_timestamp_ms
// and must still be able to finish.
const isStale = (
  eventTimestampMs: number | undefined,
  appliedMs: unknown,
): boolean =>
  eventTimestampMs !== undefined &&
  typeof appliedMs === "number" &&
  eventTimestampMs < appliedMs;

/**
 * The identifiers of the entitlements that have no expiry or whose expiry is
 * not in the past at `nowMs`. An expiry that does not parse as a date counts as
 * expired.
 */
export const activeEntitlements = (
  customer: CustomerInfo,
  nowMs: number,
): string[] =>
  Object.keys(customer.entitlements).filter((id) => {
    const expiresDate = customer.entitlements[id]?.expires_date;
    return (
      expiresDate === null ||
      (typeof expiresDate === "string" && Date.parse(expiresDate) >= nowMs)
    );
  });

const isUserNotFound = (error: unknown): boolean =>
  typeof error === "object" &&
  error !== null &&
  (error as { code?: unknown }).code === "auth/user-not-found";

const messageOf = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

/**
 * Makes a function that runs the tasks of one key one after another, in the
 * order of the calls, and the tasks of different keys at the same time. A task
 * that fails does not stop the next task of its key.
 */
const createKeyedQueue = () => {
  const tails = new Map<string, Promise<void>>();
  return async (key: string, task: () => Promise<void>): Promise<void> => {
    const previous = tails.get(key) ?? Promise.resolve();
    const current = previous.then(task);
    const tail = current.catch(() => undefined);
    tails.set(key, tail);
    try {
      await current;
    } finally {
      if (tails.get(key) === tail) {
        tails.delete(key);
      }
    }
  };
};

/**
 * Makes the HTTPS handler that verifies a RevenueCat Firebase integration
 * request and writes the `revenueCatEntitlements` claim of each user that the
 * event names: the destination user, and the origin user of a transfer.
 *
 * Firebase Auth has no compare-and-set, so the read of the watermark and the
 * claim write of one user are serialized through a queue that all the requests
 * of one handler share. This orders overlapping events of one user only inside
 * one instance; `index.ts` limits the function to one instance.
 */
export const createHandler = ({
  auth,
  getSecret,
  now,
  logger,
}: HandlerDependencies) => {
  const serializeByUser = createKeyedQueue();
  return async (
    request: WebhookRequest,
    response: WebhookResponse,
  ): Promise<void> => {
    try {
      const payload = verifyPayload(request.body, getSecret());
      const event = payload.event;
      const eventTimestampMs =
        typeof event.event_timestamp_ms === "number"
          ? event.event_timestamp_ms
          : undefined;

      // Keyed by user ID: a transfer whose origin is also its destination writes
      // the claim once.
      const updates = new Map<string, ClaimUpdate>();
      if (isUserId(event.app_user_id)) {
        updates.set(event.app_user_id, {
          userId: event.app_user_id,
          customer: payload.customer_info,
        });
      }
      if (isTransfer(payload) && isUserId(payload.event.origin_app_user_id)) {
        const origin = payload.event.origin_app_user_id;
        updates.set(origin, {
          userId: origin,
          customer: payload.origin_customer_info,
        });
      }

      const nowMs = now();
      await Promise.all(
        // Each user is queued on its own, and no task waits for the queue of
        // another user, so two transfers in opposite directions cannot block
        // each other.
        [...updates.values()].map(({ userId, customer }) =>
          serializeByUser(userId, async () => {
            try {
              const { customClaims } = await auth.getUser(userId);

              // The watermark stops a stale event from granting claims again,
              // and the queue keeps a write of this user from landing between
              // this read and the write below.
              if (
                isStale(eventTimestampMs, customClaims?.[EVENT_TIMESTAMP_CLAIM])
              ) {
                logger.info(
                  `Skipped a stale ${event.type ?? "unknown"} event for user ${userId}.`,
                );
                return;
              }

              await auth.setCustomUserClaims(userId, {
                ...customClaims,
                [ENTITLEMENTS_CLAIM]: activeEntitlements(customer, nowMs),
                ...(eventTimestampMs === undefined
                  ? {}
                  : { [EVENT_TIMESTAMP_CLAIM]: eventTimestampMs }),
              });
            } catch (error) {
              // As upstream does, a failed claim write is logged and the request
              // still answers 200. A RevenueCat app user ID that is not a
              // Firebase user, such as an anonymous RevenueCat ID, can never get
              // a claim, so it is logged as a warning only.
              if (isUserNotFound(error)) {
                logger.warn(
                  `Skipped the claims of user ${userId}, who does not exist.`,
                );
                return;
              }
              logger.error(
                `Could not write the claims of user ${userId}: ${messageOf(error)}`,
              );
            }
          }),
        ),
      );

      response.status(200).json({});
    } catch (error) {
      let failure: WebhookError;
      if (error instanceof WebhookError) {
        failure = error;
        logger.warn(
          `The webhook answered ${failure.status}: ${failure.message}`,
        );
      } else {
        failure = new WebhookError(
          500,
          "The webhook failed for an unknown reason.",
        );
        logger.error(`The webhook failed: ${messageOf(error)}`);
      }
      response.status(failure.status).json({ message: failure.message });
    }
  };
};
