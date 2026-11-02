import { createHmac } from "node:crypto";

import * as nJwt from "njwt";

import {
  activeEntitlements,
  createHandler,
  ENTITLEMENTS_CLAIM,
  EVENT_TIMESTAMP_CLAIM,
} from "../src/handler";
import {
  FakeAuth,
  FakeLogger,
  FakeResponse,
  SECRET,
  signToken,
} from "./support";

const NOW = Date.UTC(2026, 10, 2, 0, 0, 0);
const IN_TWO_DAYS = new Date(NOW + 2 * 24 * 60 * 60 * 1000).toISOString();
const TWO_DAYS_AGO = new Date(NOW - 2 * 24 * 60 * 60 * 1000).toISOString();
const EVENT_TIMESTAMP_MS = 1_790_000_000_000;

type Entitlements = Record<string, { expires_date: string | null }>;

const purchase = ({
  userId = "firebase-user",
  entitlements = { basic: { expires_date: IN_TWO_DAYS } } as Entitlements,
  withTimestamp = true,
} = {}) => ({
  event: {
    id: "event-1",
    type: "INITIAL_PURCHASE",
    app_user_id: userId,
    aliases: [userId],
    ...(withTimestamp ? { event_timestamp_ms: EVENT_TIMESTAMP_MS } : {}),
  },
  customer_info: { original_app_user_id: userId, entitlements },
});

const transfer = ({
  destinationUserId = "new-owner" as string | undefined,
  destinationEntitlements = {
    pro: { expires_date: IN_TWO_DAYS },
  } as Entitlements,
  originUserId = "old-owner",
  originEntitlements = {} as Entitlements,
  eventTimestampMs = EVENT_TIMESTAMP_MS,
} = {}) => ({
  event: {
    id: "event-transfer",
    type: "TRANSFER",
    event_timestamp_ms: eventTimestampMs,
    ...(destinationUserId === undefined
      ? {}
      : { app_user_id: destinationUserId }),
    origin_app_user_id: originUserId,
    transferred_from: [originUserId],
    transferred_to: destinationUserId === undefined ? [] : [destinationUserId],
  },
  customer_info: { entitlements: destinationEntitlements },
  origin_customer_info: { entitlements: originEntitlements },
});

const run = async (
  body: unknown,
  {
    auth = new FakeAuth({ "firebase-user": {} }),
    getSecret = (): string | undefined => SECRET,
  }: { auth?: FakeAuth; getSecret?: () => string | undefined } = {},
) => {
  const logger = new FakeLogger();
  const response = new FakeResponse();
  await createHandler({ auth, getSecret, now: () => NOW, logger })(
    { body },
    response,
  );
  return { auth, logger, response };
};

const claimsOf = (auth: FakeAuth, uid: string) => auth.users.get(uid);

describe("authentication", () => {
  it("writes the claim for a token signed with the shared secret", async () => {
    const { auth, response } = await run({ token: signToken(purchase()) });

    expect(response.statusCode).toBe(200);
    expect(response.body).toEqual({});
    expect(auth.writes).toEqual([
      {
        uid: "firebase-user",
        claims: {
          [ENTITLEMENTS_CLAIM]: ["basic"],
          [EVENT_TIMESTAMP_CLAIM]: EVENT_TIMESTAMP_MS,
        },
      },
    ]);
  });

  it.each([
    [
      "a token signed with another secret",
      () => ({ token: signToken(purchase(), { secret: "forged-secret" }) }),
    ],
    [
      "an expired token",
      () => ({ token: signToken(purchase(), { expiresInSeconds: -60 }) }),
    ],
    [
      "a token whose payload was changed after signing",
      () => {
        const [header, body, signature] = signToken(purchase()).split(".");
        const claims = JSON.parse(
          Buffer.from(body, "base64url").toString("utf8"),
        );
        const forged = {
          ...claims,
          payload: JSON.stringify(
            purchase({ entitlements: { pro: { expires_date: null } } }),
          ),
        };
        return {
          token: [
            header,
            Buffer.from(JSON.stringify(forged)).toString("base64url"),
            signature,
          ].join("."),
        };
      },
    ],
    [
      "an unsigned token",
      () => ({
        token: nJwt
          .create({ payload: JSON.stringify(purchase()) }, SECRET, "none")
          .compact(),
      }),
    ],
    [
      "a token signed with another algorithm",
      () => ({
        token: nJwt
          .create({ payload: JSON.stringify(purchase()) }, SECRET, "HS512")
          .compact(),
      }),
    ],
    [
      "a token without a payload claim",
      () => ({
        token: nJwt.create({ sub: "firebase-user" }, SECRET).compact(),
      }),
    ],
    [
      "a token whose payload is not JSON",
      () => ({ token: nJwt.create({ payload: "not json" }, SECRET).compact() }),
    ],
    ["a body without a token", () => ({})],
    ["an empty token", () => ({ token: "" })],
    ["a token that is not a JWT", () => ({ token: "not-a-jwt" })],
    ["no body", () => undefined],
  ])("answers 401 and writes nothing for %s", async (_name, body) => {
    const { auth, response } = await run(body());

    expect(response.statusCode).toBe(401);
    expect(response.body).toEqual({
      message:
        "The webhook token could not be verified with the shared secret.",
    });
    expect(auth.writes).toEqual([]);
  });

  it.each([
    ["an empty", ""],
    ["a missing", undefined],
  ])(
    "answers 500 and writes nothing with %s shared secret",
    async (_name, secret) => {
      // An HMAC with an empty key would accept a token that anyone can sign.
      const encode = (value: unknown) =>
        Buffer.from(JSON.stringify(value)).toString("base64url");
      const input = `${encode({ alg: "HS256", typ: "JWT" })}.${encode({ payload: JSON.stringify(purchase()) })}`;
      const token = `${input}.${createHmac("sha256", "").update(input).digest("base64url")}`;

      const { auth, response } = await run(
        { token },
        { getSecret: () => secret },
      );

      expect(response.statusCode).toBe(500);
      expect(response.body).toEqual({
        message: "The webhook shared secret is not configured.",
      });
      expect(auth.writes).toEqual([]);
    },
  );
});

describe("payload", () => {
  it.each([
    [
      "no event",
      { customer_info: { entitlements: {} } },
      "The webhook payload has no event.",
    ],
    [
      "a user without customer entitlements",
      { event: { app_user_id: "firebase-user" }, customer_info: {} },
      "The webhook payload has no customer entitlements.",
    ],
    [
      "a transfer origin without customer entitlements",
      {
        event: { type: "TRANSFER", origin_app_user_id: "old-owner" },
        customer_info: { entitlements: {} },
      },
      "The transfer payload has no origin customer entitlements.",
    ],
  ])(
    "answers 500 and writes nothing for %s",
    async (_name, payload, message) => {
      const { auth, response } = await run({ token: signToken(payload) });

      expect(response.statusCode).toBe(500);
      expect(response.body).toEqual({ message });
      expect(auth.writes).toEqual([]);
    },
  );

  it("answers 200 and writes nothing for an event without a user", async () => {
    const { auth, response } = await run({
      token: signToken({
        event: { type: "TEST" },
        customer_info: { entitlements: {} },
      }),
    });

    expect(response.statusCode).toBe(200);
    expect(auth.writes).toEqual([]);
  });
});

describe("claims", () => {
  it("keeps only the entitlements that have not expired", async () => {
    const { auth } = await run({
      token: signToken(
        purchase({
          entitlements: {
            basic: { expires_date: TWO_DAYS_AGO },
            pro: { expires_date: IN_TWO_DAYS },
            lifetime: { expires_date: null },
          },
        }),
      ),
    });

    expect(claimsOf(auth, "firebase-user")?.[ENTITLEMENTS_CLAIM]).toEqual([
      "pro",
      "lifetime",
    ]);
  });

  it("writes an empty list when every entitlement expired", async () => {
    const auth = new FakeAuth({
      "firebase-user": { [ENTITLEMENTS_CLAIM]: ["basic"] },
    });

    await run(
      {
        token: signToken(
          purchase({ entitlements: { basic: { expires_date: TWO_DAYS_AGO } } }),
        ),
      },
      { auth },
    );

    expect(claimsOf(auth, "firebase-user")?.[ENTITLEMENTS_CLAIM]).toEqual([]);
  });

  it("keeps the other custom claims of the user", async () => {
    const auth = new FakeAuth({
      "firebase-user": {
        admin: true,
        tier: "staff",
        [ENTITLEMENTS_CLAIM]: ["pro"],
      },
    });

    await run({ token: signToken(purchase()) }, { auth });

    expect(claimsOf(auth, "firebase-user")).toEqual({
      admin: true,
      tier: "staff",
      [ENTITLEMENTS_CLAIM]: ["basic"],
      [EVENT_TIMESTAMP_CLAIM]: EVENT_TIMESTAMP_MS,
    });
  });

  it("skips an event older than the last one applied to the user", async () => {
    const auth = new FakeAuth({
      "firebase-user": {
        [ENTITLEMENTS_CLAIM]: [],
        [EVENT_TIMESTAMP_CLAIM]: EVENT_TIMESTAMP_MS + 1,
      },
    });

    const { response, logger } = await run(
      { token: signToken(purchase()) },
      { auth },
    );

    expect(response.statusCode).toBe(200);
    expect(auth.writes).toEqual([]);
    expect(logger.messages).toEqual([
      {
        level: "info",
        message:
          "Skipped a stale INITIAL_PURCHASE event for user firebase-user.",
      },
    ]);
  });

  it("applies a retry that carries the timestamp already applied", async () => {
    const auth = new FakeAuth({
      "firebase-user": {
        [ENTITLEMENTS_CLAIM]: [],
        [EVENT_TIMESTAMP_CLAIM]: EVENT_TIMESTAMP_MS,
      },
    });

    await run({ token: signToken(purchase()) }, { auth });

    expect(claimsOf(auth, "firebase-user")?.[ENTITLEMENTS_CLAIM]).toEqual([
      "basic",
    ]);
  });

  it("applies a newer event over an older one", async () => {
    const auth = new FakeAuth({
      "firebase-user": {
        [ENTITLEMENTS_CLAIM]: ["pro"],
        [EVENT_TIMESTAMP_CLAIM]: EVENT_TIMESTAMP_MS - 1,
      },
    });

    await run({ token: signToken(purchase()) }, { auth });

    expect(claimsOf(auth, "firebase-user")).toEqual({
      [ENTITLEMENTS_CLAIM]: ["basic"],
      [EVENT_TIMESTAMP_CLAIM]: EVENT_TIMESTAMP_MS,
    });
  });

  it("writes no watermark for an event without a timestamp", async () => {
    const { auth } = await run({
      token: signToken(purchase({ withTimestamp: false })),
    });

    expect(claimsOf(auth, "firebase-user")).toEqual({
      [ENTITLEMENTS_CLAIM]: ["basic"],
    });
  });
});

describe("transfer", () => {
  it("writes the claims of the origin user from the origin customer", async () => {
    const auth = new FakeAuth({
      "new-owner": {},
      "old-owner": {
        [ENTITLEMENTS_CLAIM]: ["pro"],
        [EVENT_TIMESTAMP_CLAIM]: EVENT_TIMESTAMP_MS - 1,
      },
    });

    const { response } = await run({ token: signToken(transfer()) }, { auth });

    expect(response.statusCode).toBe(200);
    expect(claimsOf(auth, "new-owner")).toEqual({
      [ENTITLEMENTS_CLAIM]: ["pro"],
      [EVENT_TIMESTAMP_CLAIM]: EVENT_TIMESTAMP_MS,
    });
    expect(claimsOf(auth, "old-owner")).toEqual({
      [ENTITLEMENTS_CLAIM]: [],
      [EVENT_TIMESTAMP_CLAIM]: EVENT_TIMESTAMP_MS,
    });
  });

  it("revokes the origin user on a transfer without a destination user", async () => {
    const auth = new FakeAuth({
      "old-owner": { [ENTITLEMENTS_CLAIM]: ["pro"] },
    });

    await run(
      { token: signToken(transfer({ destinationUserId: undefined })) },
      { auth },
    );

    expect(auth.writes.map((write) => write.uid)).toEqual(["old-owner"]);
    expect(claimsOf(auth, "old-owner")?.[ENTITLEMENTS_CLAIM]).toEqual([]);
  });

  it("writes once when the origin user is also the destination user", async () => {
    const auth = new FakeAuth({ "same-user": {} });

    await run(
      {
        token: signToken(
          transfer({
            destinationUserId: "same-user",
            originUserId: "same-user",
            originEntitlements: { basic: { expires_date: IN_TWO_DAYS } },
          }),
        ),
      },
      { auth },
    );

    expect(auth.writes).toEqual([
      {
        uid: "same-user",
        claims: {
          [ENTITLEMENTS_CLAIM]: ["basic"],
          [EVENT_TIMESTAMP_CLAIM]: EVENT_TIMESTAMP_MS,
        },
      },
    ]);
  });

  it("does not grant the origin user again on a stale transfer", async () => {
    const auth = new FakeAuth({
      "new-owner": {},
      "old-owner": {
        [ENTITLEMENTS_CLAIM]: [],
        [EVENT_TIMESTAMP_CLAIM]: EVENT_TIMESTAMP_MS + 1,
      },
    });

    await run(
      {
        token: signToken(
          transfer({
            originEntitlements: { pro: { expires_date: IN_TWO_DAYS } },
          }),
        ),
      },
      { auth },
    );

    expect(auth.writes.map((write) => write.uid)).toEqual(["new-owner"]);
    expect(claimsOf(auth, "old-owner")?.[ENTITLEMENTS_CLAIM]).toEqual([]);
  });
});

describe("failures", () => {
  it("answers 200 and skips a user that Firebase Auth does not have", async () => {
    const auth = new FakeAuth({ "old-owner": {} });

    const { response, logger } = await run(
      { token: signToken(transfer()) },
      { auth },
    );

    expect(response.statusCode).toBe(200);
    expect(auth.writes.map((write) => write.uid)).toEqual(["old-owner"]);
    expect(logger.messages).toContainEqual({
      level: "warn",
      message: "Skipped the claims of user new-owner, who does not exist.",
    });
  });

  it("answers 500 and logs a claim write that fails, after it wrote the other user", async () => {
    const auth = new FakeAuth({ "new-owner": {}, "old-owner": {} });
    auth.failures.set(
      "new-owner",
      Object.assign(new Error("quota exceeded"), {
        code: "auth/internal-error",
      }),
    );

    const { response, logger } = await run(
      { token: signToken(transfer()) },
      { auth },
    );

    expect(response.statusCode).toBe(500);
    expect(response.body).toEqual({
      message: "A claim write failed, so the event can be sent again.",
    });
    expect(auth.writes.map((write) => write.uid)).toEqual(["old-owner"]);
    expect(logger.messages).toContainEqual({
      level: "error",
      message: "Could not write the claims of user new-owner: quota exceeded",
    });
  });

  it("applies the same event again after a claim write failed", async () => {
    const auth = new FakeAuth({ "new-owner": {}, "old-owner": {} });
    auth.failures.set(
      "new-owner",
      Object.assign(new Error("quota exceeded"), {
        code: "auth/internal-error",
      }),
    );
    const handler = createHandler({
      auth,
      getSecret: () => SECRET,
      now: () => NOW,
      logger: new FakeLogger(),
    });
    const token = signToken(transfer());

    const first = new FakeResponse();
    await handler({ body: { token } }, first);
    auth.failures.delete("new-owner");
    const retry = new FakeResponse();
    await handler({ body: { token } }, retry);

    expect(first.statusCode).toBe(500);
    expect(retry.statusCode).toBe(200);
    expect(auth.writes.map((write) => write.uid).sort()).toEqual([
      "new-owner",
      "old-owner",
      "old-owner",
    ]);
    expect(claimsOf(auth, "new-owner")?.[ENTITLEMENTS_CLAIM]).toEqual(["pro"]);
  });

  it("answers 500 and logs a failure that is not an error object", async () => {
    const auth = new FakeAuth({ "firebase-user": {} });
    auth.failures.set("firebase-user", "unavailable");

    const { response, logger } = await run(
      { token: signToken(purchase()) },
      { auth },
    );

    expect(response.statusCode).toBe(500);
    expect(auth.writes).toEqual([]);
    expect(logger.messages).toContainEqual({
      level: "error",
      message: "Could not write the claims of user firebase-user: unavailable",
    });
  });

  it("answers 500 when the shared secret cannot be read", async () => {
    const { auth, response, logger } = await run(
      { token: signToken(purchase()) },
      {
        getSecret: () => {
          throw new Error("secret unavailable");
        },
      },
    );

    expect(response.statusCode).toBe(500);
    expect(response.body).toEqual({
      message: "The webhook failed for an unknown reason.",
    });
    expect(auth.writes).toEqual([]);
    expect(logger.messages).toEqual([
      { level: "error", message: "The webhook failed: secret unavailable" },
    ]);
  });
});

describe("concurrency", () => {
  /**
   * A FakeAuth that holds the answer of the first read of `gatedUid` until
   * `release()`, after it read the claims, so that a second request can run in
   * the window between that read and its write.
   */
  class GatedAuth extends FakeAuth {
    private gated = false;
    private opened!: () => void;
    private readonly gate = new Promise<void>((resolve) => {
      this.opened = resolve;
    });

    constructor(
      private readonly gatedUid: string,
      users: Record<string, Record<string, unknown> | undefined>,
    ) {
      super(users);
    }

    override async getUser(
      uid: string,
    ): Promise<{ customClaims?: Record<string, unknown> }> {
      const user = await super.getUser(uid);
      if (uid === this.gatedUid && !this.gated) {
        this.gated = true;
        await this.gate;
      }
      return user;
    }

    release(): void {
      this.opened();
    }
  }

  const eventFor = (
    userId: string,
    eventTimestampMs: number,
    entitlements: Entitlements,
  ) => ({
    token: signToken({
      event: {
        type: "TEST",
        app_user_id: userId,
        event_timestamp_ms: eventTimestampMs,
      },
      customer_info: { entitlements },
    }),
  });

  const grant = eventFor("firebase-user", 1, {
    pro: { expires_date: IN_TWO_DAYS },
  });
  const revoke = eventFor("firebase-user", 2, {});

  const flush = () => new Promise<void>((resolve) => setImmediate(resolve));

  const handlerOf = (auth: FakeAuth) =>
    createHandler({
      auth,
      getSecret: () => SECRET,
      now: () => NOW,
      logger: new FakeLogger(),
    });

  it.each([
    ["an older grant arrives first", grant, revoke],
    ["a newer revoke arrives first", revoke, grant],
  ])(
    "keeps the newer event when two events of one user overlap: %s",
    async (_, first, second) => {
      const auth = new GatedAuth("firebase-user", { "firebase-user": {} });
      const handler = handlerOf(auth);

      const firstRequest = handler({ body: first }, new FakeResponse());
      await flush();
      const secondRequest = handler({ body: second }, new FakeResponse());
      await flush();
      auth.release();
      await Promise.all([firstRequest, secondRequest]);

      expect(claimsOf(auth, "firebase-user")).toEqual({
        [ENTITLEMENTS_CLAIM]: [],
        [EVENT_TIMESTAMP_CLAIM]: 2,
      });
    },
  );

  it("does not hold the events of one user behind those of another", async () => {
    const auth = new GatedAuth("firebase-user", {
      "firebase-user": {},
      "other-user": {},
    });
    const handler = handlerOf(auth);

    const gatedRequest = handler({ body: grant }, new FakeResponse());
    await flush();
    const otherResponse = new FakeResponse();
    await handler(
      { body: eventFor("other-user", 1, { basic: { expires_date: null } }) },
      otherResponse,
    );

    expect(otherResponse.statusCode).toBe(200);
    expect(claimsOf(auth, "other-user")?.[ENTITLEMENTS_CLAIM]).toEqual([
      "basic",
    ]);
    expect(auth.writes.map((write) => write.uid)).toEqual(["other-user"]);

    auth.release();
    await gatedRequest;
    expect(claimsOf(auth, "firebase-user")?.[ENTITLEMENTS_CLAIM]).toEqual([
      "pro",
    ]);
  });

  it("serves the next event of a user after an earlier one failed", async () => {
    const auth = new FakeAuth({ "firebase-user": {} });
    const handler = handlerOf(auth);
    auth.failures.set("firebase-user", new Error("backend down"));

    await handler({ body: grant }, new FakeResponse());
    auth.failures.delete("firebase-user");
    const response = new FakeResponse();
    await handler({ body: revoke }, response);

    expect(response.statusCode).toBe(200);
    expect(claimsOf(auth, "firebase-user")).toEqual({
      [ENTITLEMENTS_CLAIM]: [],
      [EVENT_TIMESTAMP_CLAIM]: 2,
    });
  });
});

describe("activeEntitlements", () => {
  it("keeps an entitlement that expires at the current time and drops one whose date does not parse", () => {
    expect(
      activeEntitlements(
        {
          entitlements: {
            now: { expires_date: new Date(NOW).toISOString() },
            garbled: { expires_date: "not a date" },
          },
        },
        NOW,
      ),
    ).toEqual(["now"]);
  });
});
