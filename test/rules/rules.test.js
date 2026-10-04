// Tests of firestore.rules and storage.rules against the Firebase emulators.
//
// Run through `firebase emulators:exec` with a project ID that starts with `demo-`, which keeps the emulators away
// from every live project (merry.yaml owns the command). Each rule that allows something has a test that expects
// success next to the tests of its denials, so a rule that denies everything fails the suite. A list of the pages,
// a query across pages, and a list of photos have no rule that allows them, so their tests expect a denial only.

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

const projectId = "demo-kkomkkomi";
const owner = "owner-uid";
const stranger = "stranger-uid";
const openPage = "open-page";
const revokedPage = "revoked-page";
const visit = "visit-1";

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0x10]);
const limit = 5 * 1024 * 1024;

let env;

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
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc(`clientPages/${openPage}`).set(page(owner));
    await db
      .doc(`clientPages/${revokedPage}`)
      .set({ ...page(owner), revokedAt: new Date() });
    for (const pageId of [openPage, revokedPage]) {
      await db.doc(`clientPages/${pageId}/reports/${visit}`).set(report());
      await context
        .storage()
        .ref(photoPath(pageId))
        .put(jpeg, { contentType: "image/jpeg" });
    }
  });
});

function page(ownerUid) {
  return {
    ownerUid,
    companyName: "꼼꼬미 청소",
    clientName: "한빛 상가",
    createdAt: new Date("2026-10-01T00:00:00Z"),
  };
}

function report() {
  return {
    visitDate: "2026-10-01",
    publishedAt: new Date("2026-10-01T09:00:00Z"),
    zones: [{ name: "입구", note: "", beforePhoto: null, afterPhoto: null }],
  };
}

function photoPath(pageId, fileName = "zone-1-before-photo-1.jpg") {
  return `clientPages/${pageId}/${visit}/${fileName}`;
}

const reader = () => env.unauthenticatedContext();
const signedIn = (uid) => env.authenticatedContext(uid);
// `authenticatedContext` spreads its token options into the token, so the claim reaches `request.auth.token`.
const withEntitlements = (uid, entitlements) =>
  env.authenticatedContext(uid, { revenueCatEntitlements: entitlements });

describe("firestore: readers", () => {
  test("a reader gets an open page by its ID", async () => {
    await assertSucceeds(
      reader().firestore().doc(`clientPages/${openPage}`).get(),
    );
  });

  test("a reader cannot get a revoked page", async () => {
    await assertFails(
      reader().firestore().doc(`clientPages/${revokedPage}`).get(),
    );
  });

  test("a reader cannot list the pages", async () => {
    await assertFails(reader().firestore().collection("clientPages").get());
  });

  test("a signed-in stranger cannot list the pages either", async () => {
    await assertFails(
      signedIn(stranger).firestore().collection("clientPages").get(),
    );
  });

  test("a reader gets and lists the reports of an open page", async () => {
    const db = reader().firestore();
    await assertSucceeds(
      db.doc(`clientPages/${openPage}/reports/${visit}`).get(),
    );
    await assertSucceeds(
      db.collection(`clientPages/${openPage}/reports`).get(),
    );
  });

  test("a reader cannot get or list the reports of a revoked page", async () => {
    const db = reader().firestore();
    await assertFails(
      db.doc(`clientPages/${revokedPage}/reports/${visit}`).get(),
    );
    await assertFails(
      db.collection(`clientPages/${revokedPage}/reports`).get(),
    );
  });

  test("a reader cannot query the reports of every page at once", async () => {
    await assertFails(reader().firestore().collectionGroup("reports").get());
  });
});

describe("firestore: writers", () => {
  test("a signed-in user creates a page that it owns", async () => {
    await assertSucceeds(
      signedIn(owner).firestore().doc("clientPages/new-page").set(page(owner)),
    );
  });

  test("a signed-in user cannot create a page for another owner", async () => {
    await assertFails(
      signedIn(stranger)
        .firestore()
        .doc("clientPages/new-page")
        .set(page(owner)),
    );
  });

  test("a reader cannot create a page", async () => {
    await assertFails(
      reader().firestore().doc("clientPages/new-page").set(page(owner)),
    );
  });

  test("a page cannot be created with an unknown field or without its client name", async () => {
    const db = signedIn(owner).firestore();
    const { clientName, ...withoutClientName } = page(owner);
    await assertFails(
      db.doc("clientPages/new-page").set({ ...page(owner), extra: true }),
    );
    await assertFails(db.doc("clientPages/new-page").set(withoutClientName));
    await assertSucceeds(
      db.doc("clientPages/new-page").set({ ...page(owner), companyName: null }),
    );
  });

  test("a page can be created revoked, and no one reads it", async () => {
    await assertSucceeds(
      signedIn(owner)
        .firestore()
        .doc("clientPages/new-page")
        .set({ ...page(owner), revokedAt: new Date() }),
    );
    await assertFails(reader().firestore().doc("clientPages/new-page").get());
  });

  test("the owner updates its page, and a non-owner cannot", async () => {
    const renamed = { ...page(owner), clientName: "새 이름" };
    await assertSucceeds(
      signedIn(owner).firestore().doc(`clientPages/${openPage}`).set(renamed),
    );
    await assertFails(
      signedIn(stranger)
        .firestore()
        .doc(`clientPages/${openPage}`)
        .set(renamed),
    );
    await assertFails(
      reader().firestore().doc(`clientPages/${openPage}`).set(renamed),
    );
  });

  test("the owner cannot change the creation time of its page", async () => {
    await assertFails(
      signedIn(owner)
        .firestore()
        .doc(`clientPages/${openPage}`)
        .set({ ...page(owner), createdAt: new Date("2026-10-02T00:00:00Z") }),
    );
  });

  test("the writes of the app pass with the time of the server", async () => {
    const db = signedIn(owner).firestore();
    const serverTime = firebase.firestore.FieldValue.serverTimestamp();
    await assertSucceeds(
      db
        .doc(`clientPages/${openPage}/reports/visit-2`)
        .set({ ...report(), publishedAt: serverTime }),
    );
    await assertSucceeds(
      db
        .doc(`clientPages/${openPage}`)
        .set({ ...page(owner), revokedAt: serverTime }),
    );
  });

  test("a repeated revoke write and a repeated report write pass, as a job that runs again makes them", async () => {
    const db = signedIn(owner).firestore();
    const revoked = {
      ...page(owner),
      revokedAt: new Date("2026-10-02T09:00:00Z"),
    };
    await assertSucceeds(
      db.doc(`clientPages/${openPage}/reports/visit-2`).set(report()),
    );
    await assertSucceeds(
      db.doc(`clientPages/${openPage}/reports/visit-2`).set(report()),
    );
    await assertSucceeds(db.doc(`clientPages/${openPage}`).set(revoked));
    await assertSucceeds(db.doc(`clientPages/${openPage}`).set(revoked));
    // A revoke of a revoked page with another time passes too, so a retry is never refused for its time.
    await assertSucceeds(
      db.doc(`clientPages/${openPage}`).set({
        ...page(owner),
        revokedAt: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  test("the owner cannot give its page to another owner", async () => {
    await assertFails(
      signedIn(owner)
        .firestore()
        .doc(`clientPages/${openPage}`)
        .set(page(stranger)),
    );
  });

  test("the owner revokes its page, and a non-owner cannot", async () => {
    const revoked = { ...page(owner), revokedAt: new Date() };
    await assertFails(
      signedIn(stranger)
        .firestore()
        .doc(`clientPages/${openPage}`)
        .set(revoked),
    );
    await assertSucceeds(
      signedIn(owner).firestore().doc(`clientPages/${openPage}`).set(revoked),
    );
  });

  test("a revoked page stays revoked, and the owner can revoke it again", async () => {
    const db = signedIn(owner).firestore();
    await assertFails(db.doc(`clientPages/${revokedPage}`).set(page(owner)));
    await assertFails(
      db.doc(`clientPages/${revokedPage}`).update({ revokedAt: null }),
    );
    await assertSucceeds(
      db
        .doc(`clientPages/${revokedPage}`)
        .set({ ...page(owner), revokedAt: new Date() }),
    );
  });

  test("the owner writes a report, and a non-owner cannot", async () => {
    const path = `clientPages/${openPage}/reports/visit-2`;
    await assertSucceeds(signedIn(owner).firestore().doc(path).set(report()));
    await assertFails(signedIn(stranger).firestore().doc(path).set(report()));
    await assertFails(reader().firestore().doc(path).set(report()));
  });

  test("the owner cannot write a report under a revoked page or a missing page", async () => {
    const db = signedIn(owner).firestore();
    await assertFails(
      db.doc(`clientPages/${revokedPage}/reports/visit-2`).set(report()),
    );
    await assertFails(
      db.doc("clientPages/missing-page/reports/visit-2").set(report()),
    );
  });

  test("a report with an unknown field is refused", async () => {
    await assertFails(
      signedIn(owner)
        .firestore()
        .doc(`clientPages/${openPage}/reports/visit-2`)
        .set({ ...report(), extra: true }),
    );
  });

  test("a report without the footer needs a basic or pro entitlement in the token", async () => {
    const path = `clientPages/${openPage}/reports/visit-2`;
    const unbranded = { ...report(), unbranded: true };
    await assertSucceeds(
      withEntitlements(owner, ["basic"]).firestore().doc(path).set(unbranded),
    );
    await assertSucceeds(
      withEntitlements(owner, ["pro", "basic"])
        .firestore()
        .doc(path)
        .set(unbranded),
    );
    await assertFails(signedIn(owner).firestore().doc(path).set(unbranded));
    await assertFails(
      withEntitlements(owner, []).firestore().doc(path).set(unbranded),
    );
    await assertFails(
      withEntitlements(owner, ["team"]).firestore().doc(path).set(unbranded),
    );
    await assertFails(
      withEntitlements(owner, "basic").firestore().doc(path).set(unbranded),
    );
  });

  test("unbranded takes only the value true", async () => {
    const db = withEntitlements(owner, ["pro"]).firestore();
    const path = `clientPages/${openPage}/reports/visit-2`;
    await assertFails(db.doc(path).set({ ...report(), unbranded: false }));
    await assertFails(db.doc(path).set({ ...report(), unbranded: "true" }));
  });

  test("a paid owner may still write a report with the footer", async () => {
    await assertSucceeds(
      withEntitlements(owner, ["basic"])
        .firestore()
        .doc(`clientPages/${openPage}/reports/visit-2`)
        .set(report()),
    );
  });

  test("a paid stranger cannot write a report under a page of another owner", async () => {
    await assertFails(
      withEntitlements(stranger, ["pro"])
        .firestore()
        .doc(`clientPages/${openPage}/reports/visit-2`)
        .set({ ...report(), unbranded: true }),
    );
  });
});

describe("firestore: deletes", () => {
  /** Whether the document at [path] exists, read without the rules. */
  async function exists(path) {
    let found;
    await env.withSecurityRulesDisabled(async (context) => {
      found = (await context.firestore().doc(path).get()).exists;
    });
    return found;
  }

  test("the owner deletes the reports and then the page, open and revoked", async () => {
    const db = signedIn(owner).firestore();
    for (const pageId of [openPage, revokedPage]) {
      await assertSucceeds(
        db.doc(`clientPages/${pageId}/reports/${visit}`).delete(),
      );
      await assertSucceeds(db.doc(`clientPages/${pageId}`).delete());

      assert.equal(
        await exists(`clientPages/${pageId}/reports/${visit}`),
        false,
      );
      assert.equal(await exists(`clientPages/${pageId}`), false);
    }
  });

  test("a signed-in non-owner cannot delete a page or a report", async () => {
    const db = signedIn(stranger).firestore();
    for (const pageId of [openPage, revokedPage]) {
      await assertFails(
        db.doc(`clientPages/${pageId}/reports/${visit}`).delete(),
      );
      await assertFails(db.doc(`clientPages/${pageId}`).delete());
    }
    assert.equal(
      await exists(`clientPages/${openPage}/reports/${visit}`),
      true,
    );
    assert.equal(await exists(`clientPages/${openPage}`), true);
  });

  test("a reader without sign-in cannot delete a page or a report", async () => {
    const db = reader().firestore();
    for (const pageId of [openPage, revokedPage]) {
      await assertFails(
        db.doc(`clientPages/${pageId}/reports/${visit}`).delete(),
      );
      await assertFails(db.doc(`clientPages/${pageId}`).delete());
    }
    assert.equal(await exists(`clientPages/${openPage}`), true);
  });

  test("the owner repeats a delete of a report and a page that are gone, as a retry does", async () => {
    const db = signedIn(owner).firestore();
    await assertSucceeds(
      db.doc(`clientPages/${openPage}/reports/${visit}`).delete(),
    );
    await assertSucceeds(db.doc(`clientPages/${openPage}`).delete());

    // The page is gone too, so the rule of the report cannot read its owner.
    await assertSucceeds(
      db.doc(`clientPages/${openPage}/reports/${visit}`).delete(),
    );
    await assertSucceeds(db.doc(`clientPages/${openPage}`).delete());
    // A report that never existed under an existing page.
    await assertSucceeds(
      db.doc(`clientPages/${revokedPage}/reports/visit-9`).delete(),
    );
  });

  test("a reader without sign-in cannot delete a page or a report that is gone either", async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(`clientPages/${openPage}`).delete();
    });
    const db = reader().firestore();

    await assertFails(db.doc(`clientPages/${openPage}`).delete());
    await assertFails(
      db.doc(`clientPages/${openPage}/reports/visit-9`).delete(),
    );
  });

  test("the owner can delete a report while its page exists, and not when its page is gone", async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(`clientPages/${openPage}`).delete();
    });

    // A report under a missing page has no owner that the rule can read, which is why the app deletes the reports
    // before their page.
    await assertFails(
      signedIn(owner)
        .firestore()
        .doc(`clientPages/${openPage}/reports/${visit}`)
        .delete(),
    );
  });
});

describe("storage", () => {
  test("a reader gets a photo of an open page", async () => {
    await assertSucceeds(
      reader().storage().ref(photoPath(openPage)).getMetadata(),
    );
  });

  test("a reader cannot get a photo of a revoked page", async () => {
    await assertFails(
      reader().storage().ref(photoPath(revokedPage)).getMetadata(),
    );
  });

  test("a reader cannot list the photos of a page", async () => {
    await assertFails(
      reader().storage().ref(`clientPages/${openPage}/${visit}`).listAll(),
    );
  });

  test("the owner uploads a JPEG, and a non-owner and a reader cannot", async () => {
    const path = photoPath(openPage, "zone-2-after-photo-2.jpg");
    const metadata = { contentType: "image/jpeg" };
    await assertSucceeds(
      signedIn(owner).storage().ref(path).put(jpeg, metadata),
    );
    await assertFails(
      signedIn(stranger).storage().ref(path).put(jpeg, metadata),
    );
    await assertFails(reader().storage().ref(path).put(jpeg, metadata));
  });

  test("an upload that is not a JPEG is refused", async () => {
    await assertFails(
      signedIn(owner)
        .storage()
        .ref(photoPath(openPage, "zone-2-after.png"))
        .put(jpeg, { contentType: "image/png" }),
    );
  });

  test("an upload over the size limit is refused, and one at the limit is not", async () => {
    const ref = (name) =>
      signedIn(owner).storage().ref(photoPath(openPage, name));
    const metadata = { contentType: "image/jpeg" };
    await assertSucceeds(
      ref("at-limit.jpg").put(new Uint8Array(limit), metadata),
    );
    await assertFails(
      ref("over-limit.jpg").put(new Uint8Array(limit + 1), metadata),
    );
  });

  test("the owner cannot upload under a revoked page or a missing page", async () => {
    const metadata = { contentType: "image/jpeg" };
    const storage = signedIn(owner).storage();
    await assertFails(
      storage
        .ref(photoPath(revokedPage, "zone-2-after-photo-2.jpg"))
        .put(jpeg, metadata),
    );
    await assertFails(
      storage
        .ref(photoPath("missing-page", "zone-2-after-photo-2.jpg"))
        .put(jpeg, metadata),
    );
  });

  test("the owner deletes a photo, and a non-owner cannot", async () => {
    await assertFails(
      signedIn(stranger).storage().ref(photoPath(openPage)).delete(),
    );
    await assertSucceeds(
      signedIn(owner).storage().ref(photoPath(openPage)).delete(),
    );
  });

  test("the owner deletes a photo of a revoked page, which a revoke does", async () => {
    await assertFails(
      signedIn(stranger).storage().ref(photoPath(revokedPage)).delete(),
    );
    await assertSucceeds(
      signedIn(owner).storage().ref(photoPath(revokedPage)).delete(),
    );
  });

  test("a reader without sign-in cannot delete a photo", async () => {
    await assertFails(reader().storage().ref(photoPath(openPage)).delete());
  });

  test("the owner cannot delete a photo after its page is gone, so the app deletes the photos first", async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(`clientPages/${openPage}`).delete();
    });

    await assertFails(
      signedIn(owner).storage().ref(photoPath(openPage)).delete(),
    );
  });
});
