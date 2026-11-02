// Publisher admission of docs/specs/2026-11-02-publisher-approval-request.md: the grant that a paid user creates for
// itself, and the approval request of a free user.
import assert from "node:assert/strict";
import { after, before, beforeEach, describe, test } from "node:test";
import { readFileSync } from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";

const rules = readFileSync(
  new URL("../../firestore.rules", import.meta.url),
  "utf8",
);
const paidUid = "paid-publisher";
const freeUid = "free-publisher";
const pageId = "paid-page";

/** The initial grant of docs/notes/report-abuse-operations.md, "Enrollment". */
const initialGrant = () => ({
  enabled: true,
  pageLimit: 50,
  reportLimit: 1000,
  photoLimit: 2000,
  byteLimit: 1073741824,
  pages: 0,
  reports: 0,
  photos: 0,
  bytes: 0,
  reservations: {},
  type: "page",
  pageId: "initial",
  visitId: "",
  fileName: "",
  updatedAt: new Date(Date.UTC(2000, 0, 1)),
});

let env;
const paid = (id = paidUid) =>
  env.authenticatedContext(id, { revenueCatEntitlements: ["basic"] });
const free = (id = freeUid) => env.authenticatedContext(id);
const admin = (call) => env.withSecurityRulesDisabled(call);
const serverTime = () => firebase.firestore.FieldValue.serverTimestamp();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-kkomkkomi",
    firestore: { rules },
  });
});
after(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

/** Creates the page with [id] and charges it to the grant of [uid], in one batch, as the app does. */
async function chargePage(context, uid, id = pageId) {
  const db = context.firestore();
  const ledger = db.doc(`publishingGrants/${uid}`);
  const before = (await ledger.get()).data();
  const batch = db.batch();
  batch.update(ledger, {
    pages: before.pages + 1,
    type: "page",
    pageId: id,
    visitId: "",
    fileName: "",
    updatedAt: serverTime(),
  });
  batch.set(db.doc(`clientPages/${id}`), {
    ownerUid: uid,
    companyName: "Fictional Cleaning",
    clientName: "Fictional Office",
    createdAt: new Date("2026-11-01"),
  });
  return batch.commit();
}

/** The body of the rules function [name], up to the next function or match. */
function functionBody(name) {
  const start = rules.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `firestore.rules has no function ${name}`);
  const rest = rules.slice(start + 1);
  const end = rest.search(/\n\s*(function |match )/);
  return rest.slice(0, end);
}

describe("a grant that a paid user creates", () => {
  test("a paid token creates its own grant with the exact initial document", async () => {
    const grant = paid().firestore().doc(`publishingGrants/${paidUid}`);
    await assertSucceeds(grant.set(initialGrant()));
    const stored = (await grant.get()).data();
    assert.equal(stored.enabled, true);
    assert.equal(stored.pageLimit, 50);
    assert.equal(
      stored.updatedAt.toDate().toISOString(),
      "2000-01-01T00:00:00.000Z",
    );
  });

  for (const [name, change] of [
    ["an extra key", (grant) => ({ ...grant, note: "x" })],
    ["a missing key", ({ reservations: _, ...grant }) => grant],
    ["a changed limit", (grant) => ({ ...grant, pageLimit: 51 })],
    ["a raised byte limit", (grant) => ({ ...grant, byteLimit: 2 ** 40 })],
    ["non-zero usage", (grant) => ({ ...grant, pages: 1 })],
    ["a reservation", (grant) => ({ ...grant, reservations: { a: 1 } })],
    ["a disabled grant", (grant) => ({ ...grant, enabled: false })],
    [
      "another updatedAt",
      (grant) => ({ ...grant, updatedAt: new Date(Date.UTC(2000, 0, 2)) }),
    ],
    [
      "updatedAt at the request time",
      (grant) => ({ ...grant, updatedAt: serverTime() }),
    ],
  ]) {
    test(`a paid token cannot create a grant with ${name}`, async () => {
      await assertFails(
        paid()
          .firestore()
          .doc(`publishingGrants/${paidUid}`)
          .set(change(initialGrant())),
      );
    });
  }

  test("a paid token cannot create the grant of another UID", async () => {
    await assertFails(
      paid()
        .firestore()
        .doc("publishingGrants/someone-else")
        .set(initialGrant()),
    );
  });

  for (const [name, context] of [
    ["a free token", () => free(paidUid)],
    [
      "a claim that holds no paid entitlement",
      () =>
        env.authenticatedContext(paidUid, { revenueCatEntitlements: ["free"] }),
    ],
    [
      "a claim that is not a list",
      () =>
        env.authenticatedContext(paidUid, { revenueCatEntitlements: "basic" }),
    ],
  ]) {
    test(`${name} cannot create a grant`, async () => {
      await assertFails(
        context()
          .firestore()
          .doc(`publishingGrants/${paidUid}`)
          .set(initialGrant()),
      );
    });
  }

  for (const [name, existing] of [
    ["an existing grant", { ...initialGrant(), pages: 7 }],
    ["a withdrawn grant", { ...initialGrant(), enabled: false }],
  ]) {
    test(`a paid token cannot create a grant over ${name}`, async () => {
      await admin((context) =>
        context.firestore().doc(`publishingGrants/${paidUid}`).set(existing),
      );
      await assertFails(
        paid()
          .firestore()
          .doc(`publishingGrants/${paidUid}`)
          .set(initialGrant()),
      );
      const stored = (
        await paid().firestore().doc(`publishingGrants/${paidUid}`).get()
      ).data();
      assert.equal(stored.enabled, existing.enabled);
      assert.equal(stored.pages, existing.pages);
    });
  }

  test("a page charge right after the paid create, in a separate write, succeeds", async () => {
    await assertSucceeds(
      paid().firestore().doc(`publishingGrants/${paidUid}`).set(initialGrant()),
    );
    await assertSucceeds(chargePage(paid(), paidUid));
    const stored = (
      await paid().firestore().doc(`publishingGrants/${paidUid}`).get()
    ).data();
    assert.equal(stored.pages, 1);
  });

  test("a page charge in the same batch as the paid create fails", async () => {
    const db = paid().firestore();
    const batch = db.batch();
    batch.set(db.doc(`publishingGrants/${paidUid}`), initialGrant());
    batch.set(db.doc(`clientPages/${pageId}`), {
      ownerUid: paidUid,
      clientName: "Fictional Office",
      createdAt: new Date("2026-11-01"),
    });
    await assertFails(batch.commit());
  });
});

describe("a grant after the subscription ends", () => {
  test("a grant that a paid token created still publishes with a free token, within its budgets", async () => {
    await assertSucceeds(
      paid().firestore().doc(`publishingGrants/${paidUid}`).set(initialGrant()),
    );
    await assertSucceeds(chargePage(free(paidUid), paidUid));
    await admin((context) =>
      context
        .firestore()
        .doc(`publishingGrants/${paidUid}`)
        .update({ pageLimit: 1, updatedAt: new Date(Date.UTC(2000, 0, 1)) }),
    );
    await assertFails(chargePage(free(paidUid), paidUid, "second-page"));
  });

  test("approved() and validUsage do not read paid()", () => {
    for (const name of ["approved", "validUsage", "charged", "grant"]) {
      assert.doesNotMatch(functionBody(name), /paid\(\)/, name);
    }
  });
});

describe("the approval request of a free user", () => {
  const request = (context, uid = freeUid) =>
    context.firestore().doc(`publishingRequests/${uid}`);

  test("the owner creates, gets and deletes its own request", async () => {
    await assertSucceeds(
      request(free()).set({
        requestedAt: serverTime(),
        companyName: "Fictional Cleaning",
      }),
    );
    const stored = (await assertSucceeds(request(free()).get())).data();
    assert.equal(stored.companyName, "Fictional Cleaning");
    await assertSucceeds(request(free()).delete());
    assert.equal((await request(free()).get()).exists, false);
  });

  test("the company name is optional and holds at most 100 characters", async () => {
    await assertSucceeds(request(free()).set({ requestedAt: serverTime() }));
    await assertSucceeds(request(free()).delete());
    await assertSucceeds(
      request(free()).set({
        requestedAt: serverTime(),
        companyName: "가".repeat(100),
      }),
    );
    await assertSucceeds(request(free()).delete());
    await assertFails(
      request(free()).set({
        requestedAt: serverTime(),
        companyName: "가".repeat(101),
      }),
    );
    await assertFails(
      request(free()).set({ requestedAt: serverTime(), companyName: 7 }),
    );
  });

  for (const [name, data] of [
    ["a requestedAt that is not the request time", { requestedAt: new Date() }],
    ["no requestedAt", { companyName: "Fictional Cleaning" }],
    [
      "a field that the record does not hold",
      { requestedAt: serverTime(), phone: "010-0000-0000" },
    ],
  ]) {
    test(`a request with ${name} fails`, async () => {
      await assertFails(request(free()).set(data));
    });
  }

  test("no client updates a request", async () => {
    await assertSucceeds(request(free()).set({ requestedAt: serverTime() }));
    await assertFails(request(free()).update({ companyName: "Other" }));
    await assertFails(
      request(free()).set({ requestedAt: serverTime(), companyName: "Other" }),
    );
  });

  test("no client lists the requests", async () => {
    await assertSucceeds(request(free()).set({ requestedAt: serverTime() }));
    await assertFails(
      free().firestore().collection("publishingRequests").get(),
    );
    await assertFails(
      env
        .unauthenticatedContext()
        .firestore()
        .collection("publishingRequests")
        .get(),
    );
  });

  test("another UID cannot create, get or delete the request", async () => {
    await assertFails(
      request(free("someone-else")).set({ requestedAt: serverTime() }),
    );
    await assertSucceeds(request(free()).set({ requestedAt: serverTime() }));
    await assertFails(request(free("someone-else")).get());
    await assertFails(request(free("someone-else")).delete());
    await assertFails(request(env.unauthenticatedContext()).get());
    await assertFails(request(paid()).get());
  });

  test("a request grants nothing", async () => {
    await assertSucceeds(request(free()).set({ requestedAt: serverTime() }));
    await assertFails(
      free().firestore().doc(`publishingGrants/${freeUid}`).set(initialGrant()),
    );
  });
});
