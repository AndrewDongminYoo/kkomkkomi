import * as nJwt from "njwt";

import { ClaimsAuth, WebhookLogger, WebhookResponse } from "../src/handler";

export const SECRET = "test-shared-secret";

/** Signs `payload` the way the RevenueCat Firebase integration does: as the JSON string of a `payload` claim. */
export const signToken = (
  payload: unknown,
  {
    secret = SECRET,
    expiresInSeconds = 60,
  }: { secret?: string; expiresInSeconds?: number } = {},
): string => {
  const jwt = nJwt.create(
    {
      iss: "https://firebase-extension.revenuecat.com/",
      payload: JSON.stringify(payload),
    },
    secret,
  );
  jwt.setExpiration(Date.now() + expiresInSeconds * 1000);
  return jwt.compact();
};

/** An in-memory Auth whose users hold custom claims. */
export class FakeAuth implements ClaimsAuth {
  readonly users = new Map<string, Record<string, unknown> | undefined>();
  readonly writes: Array<{
    uid: string;
    claims: Record<string, unknown> | null;
  }> = [];
  /** A failure that each call for the user throws, keyed by user ID. */
  readonly failures = new Map<string, unknown>();

  constructor(users: Record<string, Record<string, unknown> | undefined> = {}) {
    for (const [uid, claims] of Object.entries(users)) {
      this.users.set(uid, claims);
    }
  }

  async getUser(
    uid: string,
  ): Promise<{ customClaims?: Record<string, unknown> }> {
    this.throwIfFailing(uid);
    if (!this.users.has(uid)) {
      throw Object.assign(new Error(`There is no user record for ${uid}.`), {
        code: "auth/user-not-found",
      });
    }
    return { customClaims: this.users.get(uid) };
  }

  async setCustomUserClaims(
    uid: string,
    claims: Record<string, unknown> | null,
  ): Promise<void> {
    this.throwIfFailing(uid);
    this.writes.push({ uid, claims });
    this.users.set(uid, claims ?? undefined);
  }

  private throwIfFailing(uid: string): void {
    if (this.failures.has(uid)) {
      throw this.failures.get(uid);
    }
  }
}

/** A response that records its status and body. */
export class FakeResponse implements WebhookResponse {
  statusCode?: number;
  body?: unknown;

  status(code: number): this {
    this.statusCode = code;
    return this;
  }

  json(body: unknown): this {
    this.body = body;
    return this;
  }
}

/** A logger that records each message with its level. */
export class FakeLogger implements WebhookLogger {
  readonly messages: Array<{
    level: "info" | "warn" | "error";
    message: string;
  }> = [];

  info(message: string): void {
    this.messages.push({ level: "info", message });
  }

  warn(message: string): void {
    this.messages.push({ level: "warn", message });
  }

  error(message: string): void {
    this.messages.push({ level: "error", message });
  }
}
