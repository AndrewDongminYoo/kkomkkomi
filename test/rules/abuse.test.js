// Direct API attempts against the same rules used by the anonymous publishing adapter.
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

const uid = "approved-publisher";
const pageId = "approved-page";
const visitId = "visit-1";
const fileName = "zone-before-photo.jpg";
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0x10]);
const pagePath = `clientPages/${pageId}`;
const reportPath = `${pagePath}/reports/${visitId}`;
const reservationPath = `${pagePath}/photoReservations/${visitId}/files/${fileName}`;
const photoPath = `${pagePath}/${visitId}/${fileName}`;
const grant = {
  enabled: true,
  pageLimit: 50,
  reportLimit: 1000,
  photoLimit: 2000,
  byteLimit: 1024 ** 3,
};
const page = {
  ownerUid: uid,
  companyName: "Clean",
  clientName: "Office",
  createdAt: new Date("2026-10-01"),
};
const zone = { name: "Lobby", note: "", beforePhoto: null, afterPhoto: null };
const report = {
  visitDate: "2026-10-01",
  publishedAt: new Date("2026-10-01"),
  zones: [zone],
};
let env;
const owner = () => env.authenticatedContext(uid);
const reader = () => env.unauthenticatedContext();
const admin = (call) => env.withSecurityRulesDisabled(call);

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-kkomkkomi",
    firestore: {
      rules: readFileSync(
        new URL("../../firestore.rules", import.meta.url),
        "utf8",
      ),
    },
    storage: {
      rules: readFileSync(
        new URL("../../storage.rules", import.meta.url),
        "utf8",
      ),
    },
  });
});
after(async () => env?.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await admin(async (context) => {
    await context
      .firestore()
      .doc(`publishingGrants/${uid}`)
      .set({ ...grant, ...usage(), reservations: {} });
    await context.firestore().doc(pagePath).set(page);
    await context.firestore().doc(reportPath).set(report);
  });
});

function usage(overrides = {}) {
  return {
    pages: 0,
    reports: 0,
    photos: 0,
    bytes: 0,
    type: "page",
    pageId,
    visitId: "",
    fileName: "",
    updatedAt: new Date("2000-01-01"),
    ...overrides,
  };
}

async function charge({
  context = owner(),
  type,
  target,
  data,
  usageOverride = {},
  extraTarget = null,
  stageOnly = false,
}) {
  const db = context.firestore();
  const account = uid;
  const segments = target.split("/");
  const ledger = db.doc(`publishingGrants/${account}`);
  if (type === "report") {
    const header = db.doc(
      `clientPages/${segments[1]}/reportValidation/${segments[3]}`,
    );
    if (!(await header.get()).exists) {
      const before = (await ledger.get()).data();
      const reservation = db.batch();
      reservation.update(ledger, {
        reports: before.reports + ((await db.doc(target).get()).exists ? 0 : 1),
        type: "reserveReport",
        pageId: segments[1],
        visitId: segments[3],
        fileName: "",
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        ...usageOverride,
      });
      reservation.set(header, {
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      await reservation.commit();
    }
    for (let index = 0; index < 7; index++) {
      // Payload tests isolate each bounded commit; the dedicated cooldown test never resets this clock.
      await admin((context) =>
        context
          .firestore()
          .doc(ledger.path)
          .update({ updatedAt: new Date("2000-01-01") }),
      );
      await db
        .doc(`${header.path}/chunks/${index}`)
        .set({ zones: data.zones.slice(index * 3, index * 3 + 3) });
    }
    await admin((context) =>
      context
        .firestore()
        .doc(ledger.path)
        .update({ updatedAt: new Date("2000-01-01") }),
    );
  }
  if (stageOnly) return;
  const previous = (await ledger.get()).data();
  const key = `${segments[1]}/${segments[3]}/${segments[5]}`;
  const exists =
    type === "photo"
      ? key in previous.reservations
      : (await db.doc(target).get()).exists;
  const batch = db.batch();
  batch.set(ledger, {
    ...previous,
    reservations:
      type === "photo"
        ? { ...previous.reservations, [key]: data.byteLimit }
        : previous.reservations,
    pages:
      previous.pages + (["page", "revoke"].includes(type) && !exists ? 1 : 0),
    reports: previous.reports,
    photos: previous.photos + (type === "photo" && !exists ? 1 : 0),
    bytes: previous.bytes + (type === "photo" && !exists ? data.byteLimit : 0),
    type,
    pageId: segments[1],
    visitId: ["page", "revoke"].includes(type) ? "" : segments[3],
    fileName: type === "photo" ? segments[5] : "",
    updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    ...usageOverride,
  });
  if (type !== "photo") batch.set(db.doc(target), data);
  if (extraTarget) {
    batch.set(db.doc(extraTarget), data);
  }
  return batch.commit();
}

describe("publication admission", () => {
  test("unapproved and replacement anonymous UIDs cannot create a page", async () => {
    for (const account of ["unapproved", "replacement"]) {
      await assertFails(
        env
          .authenticatedContext(account)
          .firestore()
          .doc(`clientPages/${account}`)
          .set({ ...page, ownerUid: account }),
      );
    }
  });
  test("clients cannot issue, copy, change or delete publication grants", async () => {
    const db = owner().firestore();
    await assertFails(
      db.doc(`publishingGrants/${uid}`).set({ ...grant, byteLimit: 2 ** 40 }),
    );
    await assertFails(db.doc(`publishingGrants/${uid}`).delete());
    await assertFails(db.doc("publishingGrants/replacement").set(grant));
  });
  test("an approved publisher creates a page with its atomic usage charge", async () => {
    await admin((context) => context.firestore().doc(pagePath).delete());
    await assertSucceeds(
      charge({ type: "page", target: pagePath, data: page }),
    );
    assert.equal(
      (await owner().firestore().doc(`publishingGrants/${uid}`).get()).data()
        .pages,
      1,
    );
    await assertSucceeds(reader().firestore().doc(pagePath).get());
  });
  test("an approved UID cannot bypass the adapter by writing an uncharged page or report", async () => {
    await assertFails(
      owner().firestore().doc("clientPages/uncharged").set(page),
    );
    await assertFails(
      owner().firestore().doc(`${pagePath}/reports/uncharged`).set(report),
    );
  });
  test("withdrawal stops writes while owner deletion and revoke remain available", async () => {
    await admin((context) =>
      context
        .firestore()
        .doc(`publishingGrants/${uid}`)
        .update({ enabled: false }),
    );
    await assertFails(
      owner().firestore().doc(`${pagePath}/reports/new`).set(report),
    );
    await assertSucceeds(
      owner().firestore().doc(pagePath).update({ revokedAt: new Date() }),
    );
    await assertSucceeds(owner().firestore().doc(reportPath).delete());
    await assertSucceeds(owner().firestore().doc(pagePath).delete());
  });
});

describe("publication budgets and payload", () => {
  test("exact report budget passes and one over fails", async () => {
    await admin((context) =>
      context
        .firestore()
        .doc(`publishingGrants/${uid}`)
        .update({ reportLimit: 1 }),
    );
    await admin((context) => context.firestore().doc(reportPath).delete());
    await assertSucceeds(
      charge({ type: "report", target: reportPath, data: report }),
    );
    await admin((context) =>
      context
        .firestore()
        .doc(`publishingGrants/${uid}`)
        .update({ updatedAt: new Date("2000-01-01") }),
    );
    await assertFails(
      charge({
        type: "report",
        target: `${pagePath}/reports/visit-2`,
        data: report,
      }),
    );
  });
  test("counter decreases, counterfeit charges and a second resource in one batch fail", async () => {
    await admin((context) =>
      context
        .firestore()
        .doc(`publishingGrants/${uid}`)
        .update(usage({ reports: 4 })),
    );
    await assertFails(
      charge({
        type: "report",
        target: `${pagePath}/reports/new`,
        data: report,
        usageOverride: { reports: 0 },
      }),
    );
    await assertFails(
      owner()
        .firestore()
        .doc(`publishingGrants/${uid}`)
        .update(
          usage({
            reports: 5,
            type: "report",
            visitId: "missing",
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
          }),
        ),
    );
    // Give the second target its own valid, quota-accounted draft: denial must come from the charge binding.
    await admin(async (context) => {
      const draft = context
        .firestore()
        .doc(`${pagePath}/reportValidation/unbound`);
      await draft.set({ createdAt: new Date("2026-10-01") });
      await context
        .firestore()
        .doc(`publishingGrants/${uid}`)
        .update({ reports: 1 });
      for (let index = 0; index < 7; index++)
        await context
          .firestore()
          .doc(`${draft.path}/chunks/${index}`)
          .set({ zones: index === 0 ? [{ ...zone, note: "change" }] : [] });
    });
    await assertFails(
      charge({
        type: "report",
        target: reportPath,
        data: { ...report, zones: [{ ...zone, note: "change" }] },
        extraTarget: `${pagePath}/reports/unbound`,
      }),
    );
  });
  test("every zone is bounded, including a malformed final zone", async () => {
    for (const zones of [
      Array(21).fill(zone),
      [...Array(19).fill(zone), { ...zone, note: "가".repeat(2001) }],
      [{ ...zone, extra: "data" }],
      [{ ...zone, beforePhoto: "clientPages/another/visit-1/photo.jpg" }],
    ]) {
      await assertFails(
        charge({
          type: "report",
          target: reportPath,
          data: { ...report, zones },
        }),
      );
    }
  });
  test("twenty valid zones with Unicode boundary text pass", async () => {
    await assertSucceeds(
      charge({
        type: "report",
        target: reportPath,
        data: {
          ...report,
          zones: Array(20).fill({
            ...zone,
            name: "가".repeat(100),
            note: "나".repeat(2000),
            beforePhoto: photoPath,
            afterPhoto: photoPath,
            beforePhotoSource: "gallery",
            afterPhotoSource: "gallery",
            status: "partlyDone",
            reason: "다".repeat(2000),
          }),
        },
      }),
    );
  });
  test("an identical report retry consumes no new allowance", async () => {
    await admin((context) =>
      context
        .firestore()
        .doc(`publishingGrants/${uid}`)
        .update(usage({ reports: 1000 })),
    );
    await assertSucceeds(owner().firestore().doc(reportPath).set(report));
    assert.equal(
      (await owner().firestore().doc(`publishingGrants/${uid}`).get()).data()
        .reports,
      1000,
    );
  });
  test("a fresh charge cannot skip the server cooldown", async () => {
    await admin((context) =>
      context
        .firestore()
        .doc(`publishingGrants/${uid}`)
        .update(usage({ updatedAt: new Date(Date.now() + 60_000) })),
    );
    await assertFails(
      charge({
        type: "report",
        target: reportPath,
        data: { ...report, zones: [{ ...zone, note: "new" }] },
      }),
    );
  });
});

describe("reserved photos and operator takedown", () => {
  test("unreserved uploads fail; a charged exact reservation permits a JPEG", async () => {
    await assertFails(
      owner().storage().ref(photoPath).put(jpeg, { contentType: "image/jpeg" }),
    );
    await assertSucceeds(
      charge({
        type: "photo",
        target: reservationPath,
        data: { ownerUid: uid, byteLimit: jpeg.length },
      }),
    );
    await assertSucceeds(
      owner().storage().ref(photoPath).put(jpeg, { contentType: "image/jpeg" }),
    );
    await assertSucceeds(reader().storage().ref(photoPath).getDownloadURL());
    await assertFails(
      owner().storage().ref(photoPath).put(jpeg, { contentType: "image/jpeg" }),
    );
  });
  test("reserved bytes cannot grow or overflow the grant", async () => {
    await admin((context) =>
      context
        .firestore()
        .doc(`publishingGrants/${uid}`)
        .update({ byteLimit: jpeg.length }),
    );
    await assertFails(
      charge({
        type: "photo",
        target: reservationPath,
        data: { ownerUid: uid, byteLimit: jpeg.length + 1 },
      }),
    );
    await assertSucceeds(
      charge({
        type: "photo",
        target: reservationPath,
        data: { ownerUid: uid, byteLimit: jpeg.length },
      }),
    );
    await assertFails(
      owner()
        .firestore()
        .doc(`publishingGrants/${uid}`)
        .update({
          reservations: {
            [`${pageId}/${visitId}/${fileName}`]: jpeg.length + 1,
          },
        }),
    );
    await assertFails(
      owner()
        .storage()
        .ref(photoPath)
        .put(new Uint8Array(jpeg.length + 1), { contentType: "image/jpeg" }),
    );
  });
  test("operator page blocking hides existing report and photo and prevents reopening", async () => {
    await admin(async (context) => {
      await context
        .storage()
        .ref(photoPath)
        .put(jpeg, { contentType: "image/jpeg" });
    });
    await assertSucceeds(reader().firestore().doc(reportPath).get());
    await assertSucceeds(reader().storage().ref(photoPath).getDownloadURL());
    await admin(async (context) => {
      const batch = context.firestore().batch();
      batch.update(context.firestore().doc(pagePath), {
        blockedAt: new Date(),
      });
      batch.set(context.firestore().doc(`blockedPages/${pageId}`), {
        blockedAt: new Date(),
      });
      await batch.commit();
    });
    await assertFails(reader().firestore().doc(pagePath).get());
    await assertFails(reader().firestore().doc(reportPath).get());
    await assertFails(reader().storage().ref(photoPath).getDownloadURL());
    await assertFails(
      owner()
        .firestore()
        .doc(pagePath)
        .update({ blockedAt: firebase.firestore.FieldValue.delete() }),
    );
    await assertFails(
      charge({
        type: "report",
        target: reportPath,
        data: { ...report, zones: [] },
      }),
    );
    await assertSucceeds(owner().storage().ref(photoPath).delete());
    await assertSucceeds(owner().firestore().doc(pagePath).delete());
    await assertFails(charge({ type: "page", target: pagePath, data: page }));
    await assertFails(
      owner().firestore().doc(`blockedPages/${pageId}`).delete(),
    );
    await assertFails(reader().firestore().doc(reportPath).get());
  });
});

test("private approval and validation records are not recipient-readable", async () => {
  await assertSucceeds(
    charge({ type: "report", target: reportPath, data: report }),
  );
  const paths = [
    `publishingGrants/${uid}`,
    `${pagePath}/reportValidation/${visitId}`,
    `${pagePath}/reportValidation/${visitId}/chunks/0`,
  ];
  for (const path of paths) {
    await assertSucceeds(owner().firestore().doc(path).get());
    await assertFails(reader().firestore().doc(path).get());
    await assertFails(
      env.authenticatedContext("another-approved").firestore().doc(path).get(),
    );
  }
});

test("concurrent real transactions cannot exceed the last page slot", async () => {
  await admin((context) =>
    context.firestore().doc(`publishingGrants/${uid}`).update({ pageLimit: 1 }),
  );
  const db = owner().firestore();
  const create = (id) =>
    db.runTransaction(async (transaction) => {
      const account = db.doc(`publishingGrants/${uid}`);
      const previous = (await transaction.get(account)).data();
      await transaction.get(db.doc(`clientPages/${id}`));
      await new Promise((resolve) => setTimeout(resolve, 1100));
      transaction.update(account, {
        pages: previous.pages + 1,
        type: "page",
        pageId: id,
        visitId: "",
        fileName: "",
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      transaction.set(db.doc(`clientPages/${id}`), page);
    });
  const results = await Promise.allSettled([
    create("race-a"),
    create("race-b"),
  ]);
  assert.equal(
    results.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.equal((await db.doc(`publishingGrants/${uid}`).get()).data().pages, 1);
});

test("removing and recreating a photo path charges again without a refund", async () => {
  await assertSucceeds(
    charge({
      type: "photo",
      target: reservationPath,
      data: { byteLimit: jpeg.length },
    }),
  );
  await assertSucceeds(
    owner().storage().ref(photoPath).put(jpeg, { contentType: "image/jpeg" }),
  );
  await assertFails(owner().storage().ref(photoPath).delete());
  const db = owner().firestore();
  await assertSucceeds(
    db.doc(`publishingGrants/${uid}`).update({
      type: "removePhoto",
      reservations: {},
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    }),
  );
  await assertSucceeds(owner().storage().ref(photoPath).delete());
  await assertFails(
    owner().storage().ref(photoPath).put(jpeg, { contentType: "image/jpeg" }),
  );
  await admin((context) =>
    context
      .firestore()
      .doc(`publishingGrants/${uid}`)
      .update({ updatedAt: new Date("2000-01-01") }),
  );
  await assertSucceeds(
    charge({
      type: "photo",
      target: reservationPath,
      data: { byteLimit: jpeg.length },
    }),
  );
  const ledger = (await db.doc(`publishingGrants/${uid}`).get()).data();
  assert.equal(ledger.photos, 2);
  assert.equal(ledger.bytes, jpeg.length * 2);
  await assertSucceeds(
    owner().storage().ref(photoPath).put(jpeg, { contentType: "image/jpeg" }),
  );
});

test("withdrawal denies new reservations but permits a charged closed page", async () => {
  await admin((context) =>
    context
      .firestore()
      .doc(`publishingGrants/${uid}`)
      .update({ enabled: false }),
  );
  await assertFails(
    charge({
      type: "photo",
      target: reservationPath,
      data: { byteLimit: jpeg.length },
    }),
  );
  await admin((context) => context.firestore().doc(pagePath).delete());
  await assertSucceeds(
    charge({
      type: "revoke",
      target: pagePath,
      data: { ...page, revokedAt: new Date() },
    }),
  );
  await assertFails(reader().firestore().doc(pagePath).get());
});

test("the maximum active reservation document fits and its structural cap is enforced", async () => {
  const boundaryFile = "maximum-reservation.jpg";
  const boundaryTarget = `${pagePath}/photoReservations/${visitId}/files/${boundaryFile}`;
  const boundaryPhoto = `${pagePath}/${visitId}/${boundaryFile}`;
  const longPage = "p".repeat(128),
    longVisit = "v".repeat(128);
  const reservations = Object.fromEntries(
    Array.from({ length: 2000 }, (_, index) => [
      `${longPage}/${longVisit}/${String(index).padStart(122, "f")}.jpg`,
      1,
    ]),
  );
  assert.equal(Object.keys(reservations)[0].length, 384);
  await admin((context) =>
    context
      .firestore()
      .doc(`publishingGrants/${uid}`)
      .update({ reservations, photos: 2000, bytes: 2000, photoLimit: 3000 }),
  );
  await assertFails(
    charge({ type: "photo", target: boundaryTarget, data: { byteLimit: 6 } }),
  );
  const key = Object.keys(reservations)[0];
  delete reservations[key];
  await assertSucceeds(
    owner()
      .firestore()
      .doc(`publishingGrants/${uid}`)
      .update({
        type: "removePhoto",
        pageId: longPage,
        visitId: longVisit,
        fileName: key.split("/")[2],
        reservations,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      }),
  );
  await admin((context) =>
    context
      .firestore()
      .doc(`publishingGrants/${uid}`)
      .update({ updatedAt: new Date("2000-01-01") }),
  );
  await assertSucceeds(
    charge({ type: "photo", target: boundaryTarget, data: { byteLimit: 6 } }),
  );
  const after = (
    await owner().firestore().doc(`publishingGrants/${uid}`).get()
  ).data();
  assert.equal(Object.keys(after.reservations).length, 2000);
  await admin(async (context) => {
    await assert.rejects(
      context.storage().ref(boundaryPhoto).getMetadata(),
      (error) => error.code === "storage/object-not-found",
    );
  });
  await assertSucceeds(
    owner()
      .storage()
      .ref(boundaryPhoto)
      .put(jpeg, { contentType: "image/jpeg" }),
  );
});

test("exact page and photo-count limits refuse one additional resource", async () => {
  await admin((context) =>
    context
      .firestore()
      .doc(`publishingGrants/${uid}`)
      .update({ pageLimit: 1, photoLimit: 1 }),
  );
  await admin((context) => context.firestore().doc(pagePath).delete());
  await assertSucceeds(charge({ type: "page", target: pagePath, data: page }));
  await admin((context) =>
    context
      .firestore()
      .doc(`publishingGrants/${uid}`)
      .update({ updatedAt: new Date("2000-01-01") }),
  );
  await assertFails(
    charge({ type: "page", target: "clientPages/over-page", data: page }),
  );
  await assertSucceeds(
    charge({ type: "photo", target: reservationPath, data: { byteLimit: 6 } }),
  );
  await admin((context) =>
    context
      .firestore()
      .doc(`publishingGrants/${uid}`)
      .update({ updatedAt: new Date("2000-01-01") }),
  );
  await assertFails(
    charge({
      type: "photo",
      target: `${pagePath}/photoReservations/${visitId}/files/second.jpg`,
      data: { byteLimit: 6 },
    }),
  );
});

test("legacy photo deletion remains available when the account has no grant", async () => {
  await admin(async (context) => {
    await context
      .storage()
      .ref(photoPath)
      .put(jpeg, { contentType: "image/jpeg" });
    await context.firestore().doc(`publishingGrants/${uid}`).delete();
  });
  await assertSucceeds(owner().storage().ref(photoPath).delete());
});

test("private report slots bound interrupted drafts and never expose incomplete reports", async () => {
  const db = owner().firestore();
  const id = "interrupted-draft";
  const header = db.doc(`${pagePath}/reportValidation/${id}`);
  const chunk = db.doc(`${header.path}/chunks/0`);
  await assertFails(chunk.set({ zones: [zone] }));
  await assertFails(
    header.set({ createdAt: firebase.firestore.FieldValue.serverTimestamp() }),
  );
  const slot = db.batch();
  slot.update(db.doc(`publishingGrants/${uid}`), {
    reports: 1,
    type: "reserveReport",
    pageId,
    visitId: id,
    fileName: "",
    updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
  });
  slot.set(header, {
    createdAt: firebase.firestore.FieldValue.serverTimestamp(),
  });
  await assertSucceeds(slot.commit());
  await assertSucceeds(chunk.set({ zones: [zone] }));
  assert.equal((await db.doc(`${pagePath}/reports/${id}`).get()).exists, false);
  assert.deepEqual(
    (
      await reader().firestore().collection(`${pagePath}/reports`).get()
    ).docs.map((doc) => doc.id),
    [visitId],
  );
  await assertFails(
    header.update({
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
    }),
  );
  await assertFails(db.doc(`${header.path}/chunks/7`).set({ zones: [] }));
  await assertFails(
    db.doc(`${header.path}/chunks/6`).set({ zones: Array(3).fill(zone) }),
  );
  await admin((context) =>
    context
      .firestore()
      .doc(`publishingGrants/${uid}`)
      .update({ enabled: false }),
  );
  await assertFails(chunk.set({ zones: [] }));
  await assertSucceeds(chunk.delete());
  await assertSucceeds(header.delete());
  assert.equal(
    (await db.doc(`publishingGrants/${uid}`).get()).data().reports,
    1,
  );
});

test("concurrent real transactions cannot reserve more than the last report slot", async () => {
  await admin((context) =>
    context
      .firestore()
      .doc(`publishingGrants/${uid}`)
      .update({ reportLimit: 1 }),
  );
  const db = owner().firestore();
  const reserve = (id) =>
    db.runTransaction(async (transaction) => {
      const ledger = db.doc(`publishingGrants/${uid}`);
      const header = db.doc(`${pagePath}/reportValidation/${id}`);
      const before = (await transaction.get(ledger)).data();
      await transaction.get(header);
      await transaction.get(db.doc(`${pagePath}/reports/${id}`));
      await new Promise((resolve) => setTimeout(resolve, 1100));
      transaction.update(ledger, {
        reports: before.reports + 1,
        type: "reserveReport",
        pageId,
        visitId: id,
        fileName: "",
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      transaction.set(header, {
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
    });
  const results = await Promise.allSettled([
    reserve("draft-a"),
    reserve("draft-b"),
  ]);
  assert.equal(
    results.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.equal(
    (await db.doc(`publishingGrants/${uid}`).get()).data().reports,
    1,
  );
});

test("a charged public report cannot bypass already validated chunk content", async () => {
  await assertSucceeds(
    charge({ type: "report", target: reportPath, data: report }),
  );
  await admin((context) =>
    context
      .firestore()
      .doc(`publishingGrants/${uid}`)
      .update({ updatedAt: new Date("2000-01-01") }),
  );
  const db = owner().firestore();
  const batch = db.batch();
  batch.update(db.doc(`publishingGrants/${uid}`), {
    type: "report",
    pageId,
    visitId,
    fileName: "",
    updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
  });
  batch.set(db.doc(reportPath), {
    ...report,
    zones: [{ ...zone, note: "not in validated chunks" }],
  });
  await assertFails(batch.commit());
  assert.deepEqual(
    (await reader().firestore().doc(reportPath).get()).data().zones,
    report.zones,
  );
});

test("real final report transactions pin all private chunks for both create and legacy update", async () => {
  const db = owner().firestore();
  for (const id of ["new-transaction", visitId]) {
    const payload = {
      ...report,
      zones: Array(20).fill({
        ...zone,
        name: "가".repeat(100),
        note: "나".repeat(2000),
        status: "partlyDone",
        reason: "다".repeat(2000),
        beforePhoto: `clientPages/${pageId}/${id}/${fileName}`,
        afterPhoto: `clientPages/${pageId}/${id}/${fileName}`,
        beforePhotoSource: "gallery",
        afterPhotoSource: "gallery",
      }),
    };
    const target = `${pagePath}/reports/${id}`;
    await assertSucceeds(
      charge({ type: "report", target, data: payload, stageOnly: true }),
    );
    await assertSucceeds(
      db.runTransaction(async (transaction) => {
        await transaction.get(db.doc(pagePath));
        await transaction.get(db.doc(target));
        const ledger = db.doc(`publishingGrants/${uid}`);
        const counters = (await transaction.get(ledger)).data();
        const header = db.doc(`${pagePath}/reportValidation/${id}`);
        await transaction.get(header);
        for (let index = 0; index < 7; index++)
          await transaction.get(db.doc(`${header.path}/chunks/${index}`));
        await new Promise((resolve) => setTimeout(resolve, 1100));
        transaction.update(ledger, {
          ...counters,
          type: "report",
          pageId,
          visitId: id,
          fileName: "",
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        });
        transaction.set(db.doc(target), payload);
      }),
    );
    assert.deepEqual(
      (await reader().firestore().doc(target).get()).data().zones,
      payload.zones,
    );
    await admin((context) =>
      context
        .firestore()
        .doc(`publishingGrants/${uid}`)
        .update({ updatedAt: new Date("2000-01-01") }),
    );
  }
  assert.equal(
    (await db.doc(`publishingGrants/${uid}`).get()).data().reports,
    1,
  );
});
