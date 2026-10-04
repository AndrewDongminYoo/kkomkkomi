# M3-01: report branding in the rules and the web report

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The backend refuses a report without the footer unless its writer holds a paid entitlement, and the web report hides the footer text of such a report.

**Architecture:** `firestore.rules` gets one optional report key, `unbranded`, guarded by the custom claim `revenueCatEntitlements` of the writer's token. The web report decodes the key and leaves out the footer text when it is `true`. The app writes no `unbranded` key yet, so every report still shows the footer after this pull request.

**Tech Stack:** Firestore security rules, `@firebase/rules-unit-testing` in Node, the plain JavaScript web report under `web/report/`, Flutter ARB files.

**Spec:** [`docs/specs/2026-10-04-m3-subscriptions-design.md`](../specs/2026-10-04-m3-subscriptions-design.md), sections "Trust boundary" and "Deploys". The split is [`2026-10-05-m3-subscriptions.md`](2026-10-05-m3-subscriptions.md). Refs #36.

## Global Constraints

- The claim name is `revenueCatEntitlements`, with an uppercase `C`. It is a list of entitlement identifiers: the code example of RevenueCat's "Firebase Integration" page reads it as `claims.revenueCatEntitlements.includes(...)`.
- The paid entitlements are `basic` and `pro`. Any other identifier is not paid.
- The only allowed value of `unbranded` is `true`. A report without the key shows the footer, so every report that exists today keeps it.
- The privacy policy link stays in every footer. Only the footer text goes away.
- The Free footer text is `꼼꼬미로 작성됨` (operator, 2026-10-04), in `web/report/view.js` and in `lib/l10n/arb/app_ko.arb`. The English ARB value `Report made with Kkomkkomi` stays as it is.
- Name no price, billing term, or fee anywhere: the repository is public.
- This pull request deploys nothing. A deploy of the rules or Hosting needs the operator's approval after the merge, as `CLAUDE.md` requires.

## Review Focus

1. A token whose claim is missing, empty, a string instead of a list, or holds only an unknown entitlement: the rules refuse `unbranded`.
2. `unbranded: false` or `unbranded: "true"`: the rules refuse it, and the web report shows the footer for any value that is not the boolean `true`.
3. A paid owner who writes a report with the footer (no key): the rules accept it, because the app falls back to the footer when the claim is late.
4. The history page of a client: it shows the footer text unless the page lists at least one report and every listed report is unbranded.
5. A stranger with a paid claim: the rules still refuse any write under a page that the stranger does not own.

---

### Task 1: The rules accept `unbranded` only with a paid claim

**Files:**

- Modify: `firestore.rules` (functions `isReport` and a new `paid`)
- Test: `test/rules/rules.test.js` (block `describe("firestore: writers", ...)`)

**Interfaces:**

- Consumes: the existing `report()` fixture and `signedIn(uid)` helper of `test/rules/rules.test.js`.
- Produces: the report key `unbranded` (`true` only), which Task 2 decodes and PR 3 writes.

- [ ] **Step 1: Write the failing tests**

Add a helper next to `signedIn` and these tests at the end of the `firestore: writers` block. `authenticatedContext(uid, tokenOptions)` spreads `tokenOptions` into the token, so the claim reaches `request.auth.token`.

```js
const withEntitlements = (uid, entitlements) =>
  env.authenticatedContext(uid, { revenueCatEntitlements: entitlements });

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
```

- [ ] **Step 2: Run the tests to verify that they fail**

Run: `merry run rules` (needs Java 21 and the Firebase CLI; when the machine has only an older Java, push and read the `rules` CI job instead, and say so in the pull request body).
Expected: the first test fails at its first `assertSucceeds`, because `isReport` refuses the unknown key `unbranded`.

- [ ] **Step 3: Write the minimal rules**

In `firestore.rules`, add `paid` after `signedIn` and extend `isReport`:

```text
    // The entitlements that the RevenueCat Firebase extension writes into the token of a paying user. A missing claim
    // or a claim that is not a list is not paid.
    function paid() {
      return signedIn()
        && request.auth.token.get('revenueCatEntitlements', []) is list
        && request.auth.token.get('revenueCatEntitlements', []).hasAny(['basic', 'pro']);
    }

    // A report without the footer of the Free plan carries unbranded: true, and only a paid writer may write it.
    function isReport(data) {
      return data.keys().hasOnly(['visitDate', 'publishedAt', 'zones', 'unbranded'])
        && data.keys().hasAll(['visitDate', 'publishedAt', 'zones'])
        && data.visitDate is string
        && data.publishedAt is timestamp
        && data.zones is list
        && (!data.keys().hasAny(['unbranded']) || (data.unbranded == true && paid()));
    }
```

- [ ] **Step 4: Run the tests to verify that they pass**

Run: `merry run rules` (or the `rules` CI job, as in Step 2).
Expected: every test passes, the earlier report tests included.

- [ ] **Step 5: Commit**

```bash
git add firestore.rules test/rules/rules.test.js
git commit -m "feat(rules): accept a report without the footer only from a paid writer"
```

### Task 2: The web report hides the footer text of an unbranded report

**Files:**

- Modify: `web/report/data.js` (`decodeReport`)
- Modify: `web/report/view.js` (`texts.footer`, `footer`, `renderReport`, `renderHistory`)
- Test: `test/web/report.test.mjs`

**Interfaces:**

- Consumes: the key `unbranded` of Task 1.
- Produces: `decodeReport(document).unbranded`, a boolean that is `true` only for the Firestore value `{ booleanValue: true }`.

- [ ] **Step 1: Write the failing tests**

In `test/web/report.test.mjs`, add `unbranded: false` to every `assert.deepEqual(decodeReport(...), {...})` expectation, change each expected `"꼼꼬미로 만든 보고서"` to `"꼼꼬미로 작성됨"`, and add:

```js
describe("unbranded reports", () => {
  const unbrandedDocument = {
    ...reportDocument,
    fields: { ...reportDocument.fields, unbranded: { booleanValue: true } },
  };

  test("decodes unbranded only from the boolean true", () => {
    assert.equal(decodeReport(unbrandedDocument).unbranded, true);
    assert.equal(decodeReport(reportDocument).unbranded, false);
    const asText = {
      ...reportDocument,
      fields: { ...reportDocument.fields, unbranded: { stringValue: "true" } },
    };
    assert.equal(decodeReport(asText).unbranded, false);
  });

  test("a report without the footer keeps the privacy link", () => {
    const doc = new FakeDocument();
    const view = renderReport(doc, {
      pageId,
      page: decodePage(pageDocument),
      report: decodeReport(unbrandedDocument),
      photoUrl: (path) => `https://photos.test/${path}`,
    });
    assert.ok(!view.texts().includes(texts.footer));
    assert.ok(view.texts().includes(texts.privacyLink));
  });

  test("the history shows the footer text unless every listed report is unbranded", () => {
    const history = (reports) =>
      renderHistory(new FakeDocument(), {
        pageId,
        page: decodePage(pageDocument),
        reports,
      }).texts();
    const unbranded = decodeReport(unbrandedDocument);
    const branded = decodeReport(olderReportDocument);
    assert.ok(!history([unbranded]).includes(texts.footer));
    assert.ok(history([unbranded, branded]).includes(texts.footer));
    assert.ok(history([]).includes(texts.footer));
    assert.ok(history([unbranded]).includes(texts.privacyLink));
  });
});
```

- [ ] **Step 2: Run the tests to verify that they fail**

Run: `merry run web`
Expected: FAIL. `decodeReport` has no `unbranded`, and the footer text is still `꼼꼬미로 만든 보고서`.

- [ ] **Step 3: Write the minimal implementation**

In `web/report/data.js`, `decodeReport` returns one more field:

```js
    unbranded: fields.unbranded === true,
```

In `web/report/view.js`, set `texts.footer` to `"꼼꼬미로 작성됨"`, and give `footer` a flag:

```js
/** The footer of a sheet: the footer text of the Free plan unless `branded` is false, and the privacy policy link. */
function footer(doc, { branded = true } = {}) {
  return element(doc, "footer", { className: "footer" }, [
    ...(branded ? [element(doc, "p", { text: texts.footer })] : []),
    element(doc, "a", {
      text: texts.privacyLink,
      attributes: { href: privacyPath },
    }),
  ]);
}
```

`renderReport` calls `footer(doc, { branded: !report.unbranded })`.
`renderHistory` calls `footer(doc, { branded: reports.length === 0 || reports.some((report) => !report.unbranded) })`.

- [ ] **Step 4: Run the tests to verify that they pass**

Run: `merry run web`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add web/report/data.js web/report/view.js test/web/report.test.mjs
git commit -m "feat(web): hide the footer text of a report without the footer"
```

### Task 3: The app prints the new Free footer text

**Files:**

- Modify: `lib/l10n/arb/app_ko.arb` (key `reportFooter`)
- Test: `test/presentation/visit_report/view/visit_report_page_test.dart` (each expectation that reads the Korean ARB value)

**Interfaces:**

- Consumes: nothing from Tasks 1 and 2.
- Produces: `l10n.reportFooter` = `꼼꼬미로 작성됨` in Korean.

- [ ] **Step 1: Write the failing test change**

In `test/presentation/visit_report/view/visit_report_page_test.dart`, change each expected `'꼼꼬미로 만든 보고서'` that comes from the ARB file to `'꼼꼬미로 작성됨'`.
Leave the tests that build their own `ReportLabels` (`test/export/report_pdf_test.dart`, `test/presentation/visit_report/cubit/visit_report_cubit_test.dart`) as they are, because their footer is a test input.

- [ ] **Step 2: Run the test to verify that it fails**

Run: `flutter test test/presentation/visit_report/view/visit_report_page_test.dart`
Expected: FAIL on the footer expectations.

- [ ] **Step 3: Change the ARB value and regenerate**

Set `"reportFooter": "꼼꼬미로 작성됨"` in `lib/l10n/arb/app_ko.arb`, then run `merry run l10n`.

- [ ] **Step 4: Run the gates**

Run: `merry run check`, then `merry run coverage`.
Expected: both pass, and coverage of `lib` stays at 100%.

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/arb/app_ko.arb test/presentation/visit_report/view/visit_report_page_test.dart
git commit -m "feat(l10n): print the Free footer text of M3 on the report"
```

### Task 4: Records

**Files:**

- Create: `docs/plans/2026-10-05-m3-subscriptions.md` and this brief, `docs/plans/2026-10-05-m3-01-report-branding.md`, as the first commit of the pull request.
- Modify: `CLAUDE.md`, "Current state" and "Milestones": M1 and M3 are both in progress (operator, 2026-10-05). M1 waits for the first test distribution (#40), and M3 follows `docs/plans/2026-10-05-m3-subscriptions.md`. Keep the rule that work stays inside a milestone in progress.
- Modify: `CLAUDE.md`, the "Web" bullet of "Architecture": after the sentence about `textContent`, add that a report with `unbranded: true` shows no footer text and keeps the privacy link, and that `firestore.rules` accepts that key only from a writer whose `revenueCatEntitlements` claim holds `basic` or `pro`.

- [ ] **Step 1: Run `npx cspell@9 --config cspell.json "**/*.md"` and `trunk check` on the changed Markdown.**
- [ ] **Step 2: Commit** with `docs: describe the report footer of the M3 plans`.

The pull request body lists the deploys that the merge makes due: the rules, then Hosting, each with the operator's approval.
