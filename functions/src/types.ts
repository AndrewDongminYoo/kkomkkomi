// Derived from functions/src/types.ts of RevenueCat/firestore-revenuecat-purchases
// at commit 8089f19e948b3326040425de158fa1233891d675 (Apache-2.0).
// Modified for kkomkkomi: the types keep only the fields that the claim writer
// reads, and the payload no longer carries an API version. See NOTICE.

/** One entitlement of a customer, as RevenueCat sends it. */
export interface Entitlement {
  /** An ISO 8601 date, or null for an entitlement that never expires. */
  expires_date: string | null;
}

/** The customer information that a webhook event carries. */
export interface CustomerInfo {
  entitlements: Record<string, Entitlement>;
}

interface BaseEvent {
  id?: string;
  type?: string;
  event_timestamp_ms?: number;
  // A transfer can revoke the previous owner without a new destination, so the
  // destination user ID may be absent.
  app_user_id?: string;
}

interface TransferEvent extends BaseEvent {
  type: "TRANSFER";
  origin_app_user_id?: string;
}

/** The verified JSON payload of a RevenueCat Firebase integration request. */
export type BodyPayload =
  | {
      event: BaseEvent;
      customer_info: CustomerInfo;
    }
  | {
      event: TransferEvent;
      customer_info: CustomerInfo;
      origin_customer_info: CustomerInfo;
    };

/** Whether the payload is a transfer, which also carries the origin customer. */
export const isTransfer = (
  payload: BodyPayload,
): payload is Extract<BodyPayload, { event: TransferEvent }> =>
  payload.event.type === "TRANSFER";
