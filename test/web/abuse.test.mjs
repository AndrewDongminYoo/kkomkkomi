import assert from "node:assert/strict";
import { test } from "node:test";
import {
  renderFailure,
  renderHistory,
  renderReport,
} from "../../web/report/view.js";
import { FakeDocument } from "./fake_dom.mjs";

test("report, history, unavailable and unbranded views retain the abuse contact", () => {
  const doc = new FakeDocument();
  const page = { clientName: "Private company name" };
  const report = {
    visitId: "visit-1",
    visitDate: "2026-10-08",
    zones: [],
    unbranded: true,
  };
  for (const view of [
    renderReport(doc, { pageId: "page-1", page, report, photoUrl: () => "" }),
    renderHistory(doc, { pageId: "page-1", page, reports: [report] }),
    renderFailure(doc, {
      kind: "unavailable",
      pageId: "page-1",
      visitId: "visit-1",
    }),
    renderFailure(doc, {
      kind: "unavailable",
      pageId: "page-1?secret#fragment",
    }),
  ]) {
    const action = view
      .all("a")
      .find((node) => node.textContent === "이 보고서 신고하기");
    assert.ok(action);
    assert.ok(
      !action.getAttribute("href").includes("+"),
      "mailto spaces use percent encoding",
    );
    const mail = new URL(action.getAttribute("href"));
    assert.equal(mail.pathname, "donminzzi@gmail.com");
    assert.ok(view.textContent.includes("donminzzi@gmail.com"));
    const body = mail.searchParams.get("body");
    assert.ok(body.includes("신고 이유:"));
    assert.ok(!body.includes(page.clientName));
    assert.ok(!body.includes("secret"));
    assert.ok(!body.includes("fragment"));
  }
  const view = renderReport(doc, {
    pageId: "page-1",
    page,
    report,
    photoUrl: () => "",
  });
  const mail = new URL(
    view
      .all("a")
      .find((node) => node.textContent === "이 보고서 신고하기")
      .getAttribute("href"),
  );
  assert.equal(
    mail.searchParams.get("body"),
    "보고서 주소: https://kkomkkomi.web.app/r/page-1/visit-1\n신고 이유:\n",
  );
});
