import { getAuth } from "firebase-admin/auth";

import { ENTITLEMENTS_CLAIM } from "../src/handler";
import { revenueCatWebhook } from "../src/index";
import { FakeAuth, FakeResponse, SECRET, signToken } from "./support";

jest.mock("firebase-admin/app", () => ({ initializeApp: jest.fn() }));
jest.mock("firebase-admin/auth", () => {
  const { FakeAuth: Auth } =
    jest.requireActual<typeof import("./support")>("./support");
  const auth = new Auth({ "firebase-user": { admin: true } });
  return { getAuth: () => auth };
});

const fakeAuth = getAuth() as unknown as FakeAuth;

describe("revenueCatWebhook", () => {
  const originalSecret = process.env.REVENUECAT_WEBHOOK_SECRET;

  afterEach(() => {
    if (originalSecret === undefined) {
      delete process.env.REVENUECAT_WEBHOOK_SECRET;
    } else {
      process.env.REVENUECAT_WEBHOOK_SECRET = originalSecret;
    }
  });

  it("runs on one instance in asia-northeast3 with the REVENUECAT_WEBHOOK_SECRET secret", () => {
    expect(revenueCatWebhook.__endpoint).toMatchObject({
      platform: "gcfv2",
      region: ["asia-northeast3"],
      maxInstances: 1,
      httpsTrigger: {},
      secretEnvironmentVariables: [{ key: "REVENUECAT_WEBHOOK_SECRET" }],
    });
  });

  it("verifies with the secret value and writes through the Firebase Admin Auth", async () => {
    process.env.REVENUECAT_WEBHOOK_SECRET = SECRET;
    const response = new FakeResponse();
    const token = signToken({
      event: { type: "RENEWAL", app_user_id: "firebase-user" },
      customer_info: { entitlements: { pro: { expires_date: null } } },
    });

    await revenueCatWebhook({ body: { token } } as never, response as never);

    expect(response.statusCode).toBe(200);
    expect(fakeAuth.users.get("firebase-user")).toEqual({
      admin: true,
      [ENTITLEMENTS_CLAIM]: ["pro"],
    });
  });
});
