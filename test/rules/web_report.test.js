// Tests of the reads of the web report page (web/report/data.js) against the Firebase emulators.
//
// The page reads without sign-in, through the Firestore REST API and the Storage REST API without a download
// token, so the rules decide each read. These tests give the reader of the page the emulator hosts and check what
// the rules let through. `firebase emulators:exec` sets the two host variables. The suite clears the emulators
// before each test, as rules.test.js does, so the package script runs the test files one at a time.

import { after, before, beforeEach, describe, test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";

import { createReader } from "../../web/report/data.js";

const projectId = "demo-kkomkkomi";
const openPage = "0123456789abcdef0123456789abcdef";
const revokedPage = "fedcba9876543210fedcba9876543210";
const unknownPage = "00000000000000000000000000000000";
const visit = "visit-1";
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46]);

let env;
let reader;

const photoPath = (pageId) =>
  `clientPages/${pageId}/${visit}/zone-1-before-photo-1.jpg`;

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
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
  let storageBucket;
  await env.withSecurityRulesDisabled(async (context) => {
    storageBucket = context.storage().ref().bucket;
  });
  reader = createReader({
    projectId,
    storageBucket,
    fetch,
    hosts: {
      firestore: `http://${env.emulators.firestore.host}:${env.emulators.firestore.port}`,
      storage: `http://${env.emulators.storage.host}:${env.emulators.storage.port}`,
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  // The documents in the shape that FirebasePublisher writes them.
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const page = {
      ownerUid: "owner-uid",
      companyName: "꼼꼬미 청소",
      clientName: "한빛 상가",
      createdAt: firebase.firestore.Timestamp.fromDate(
        new Date("2026-10-01T00:00:00Z"),
      ),
    };
    await db.doc(`clientPages/${openPage}`).set(page);
    await db.doc(`clientPages/${revokedPage}`).set({
      ...page,
      revokedAt: firebase.firestore.Timestamp.fromDate(
        new Date("2026-10-02T00:00:00Z"),
      ),
    });
    for (const pageId of [openPage, revokedPage]) {
      await db.doc(`clientPages/${pageId}/reports/${visit}`).set({
        visitDate: "2026-10-01",
        publishedAt: firebase.firestore.Timestamp.fromDate(
          new Date("2026-10-01T09:00:00Z"),
        ),
        zones: [
          {
            name: "입구",
            note: "바닥 왁스",
            beforePhoto: photoPath(pageId),
            afterPhoto: null,
          },
        ],
      });
      await context
        .storage()
        .ref(photoPath(pageId))
        .put(jpeg, { contentType: "image/jpeg" });
    }
  });
});

const isKind = (kind) => (error) => error.kind === kind;

describe("web report page: reads without sign-in", () => {
  test("reads an open page, its report, and the list of its reports", async () => {
    assert.deepEqual(await reader.page(openPage), {
      companyName: "꼼꼬미 청소",
      clientName: "한빛 상가",
    });
    assert.deepEqual(await reader.report(openPage, visit), {
      visitId: visit,
      visitDate: "2026-10-01",
      publishedAt: "2026-10-01T09:00:00Z",
      zones: [
        {
          name: "입구",
          note: "바닥 왁스",
          beforePhoto: photoPath(openPage),
          afterPhoto: null,
        },
      ],
    });
    assert.deepEqual(
      (await reader.reports(openPage)).map((report) => report.visitId),
      [visit],
    );
  });

  test("a revoked page, its report, and its list read as unavailable", async () => {
    await assert.rejects(reader.page(revokedPage), isKind("unavailable"));
    await assert.rejects(
      reader.report(revokedPage, visit),
      isKind("unavailable"),
    );
    await assert.rejects(reader.reports(revokedPage), isKind("unavailable"));
  });

  test("a page ID that no page has reads as unavailable, as a revoked page does", async () => {
    await assert.rejects(reader.page(unknownPage), isKind("unavailable"));
    await assert.rejects(
      reader.report(unknownPage, visit),
      isKind("unavailable"),
    );
  });

  test("a visit that an open page does not hold reads as missing", async () => {
    await assert.rejects(
      reader.report(openPage, "visit-unknown"),
      isKind("missing"),
    );
  });

  test("loads the photo of an open page from its URL, which holds no token", async () => {
    const url = reader.photoUrl(photoPath(openPage));
    const response = await fetch(url);

    assert.equal(response.status, 200);
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), jpeg);
    assert.doesNotMatch(url, /token/);
  });

  test("refuses the photo of a page after its revoke, which the rules check at each load", async () => {
    const url = reader.photoUrl(photoPath(openPage));
    assert.equal((await fetch(url)).status, 200);

    await env.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc(`clientPages/${openPage}`)
        .update({
          revokedAt: firebase.firestore.Timestamp.fromDate(
            new Date("2026-10-03T00:00:00Z"),
          ),
        });
    });

    assert.equal((await fetch(url)).status, 403);
    assert.equal(
      (await fetch(reader.photoUrl(photoPath(revokedPage)))).status,
      403,
    );
  });
});
