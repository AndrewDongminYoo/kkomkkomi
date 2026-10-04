// Tests of the web report page under web/report/, run by `node --test test/web/` without a browser and without a
// network: a fake fetch gives fixture documents, and a fake document makes the nodes.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";

import { configPath, start } from "../../web/report/app.js";
import {
  ReadError,
  createReader,
  decodePage,
  decodeReport,
  decodeValue,
  parseRoute,
  productionHosts,
  sortNewestFirst,
} from "../../web/report/data.js";
import {
  formatVisitDate,
  privacyPath,
  renderFailure,
  renderHistory,
  renderReport,
  texts,
} from "../../web/report/view.js";
import { FakeDocument } from "./fake_dom.mjs";
import {
  config,
  hallBefore,
  lobbyAfter,
  lobbyBefore,
  olderReportDocument,
  olderVisitId,
  pageDocument,
  pageId,
  reportDocument,
  visitId,
} from "./fixtures.mjs";

const repository = new URL("../../", import.meta.url);
const read = (path) => readFileSync(new URL(path, repository), "utf8");

const documentsUrl = `${productionHosts.firestore}/v1/projects/demo-kkomkkomi/databases/(default)/documents`;

/** A response with `status` and `body` as JSON. */
function answer(status, body = {}) {
  return { status, ok: status >= 200 && status < 300, json: async () => body };
}

/**
 * A fetch that answers from `routes`, a map from a URL without its query to a response or to a function that makes
 * one. It keeps every requested URL. A URL without a route answers 404.
 */
function fakeFetch(routes) {
  const requests = [];
  const fetch = async (url) => {
    requests.push(url);
    const route = routes[url.split("?")[0]];
    if (route === undefined) return answer(404);
    return typeof route === "function" ? route(url) : route;
  };
  return { fetch, requests };
}

/** The routes of a backend that holds the fixture page and its two reports. */
function fixtureBackend() {
  return {
    [configPath]: answer(200, config),
    [`${documentsUrl}/clientPages/${pageId}`]: answer(200, pageDocument),
    [`${documentsUrl}/clientPages/${pageId}/reports/${visitId}`]: answer(
      200,
      reportDocument,
    ),
    [`${documentsUrl}/clientPages/${pageId}/reports`]: answer(200, {
      documents: [olderReportDocument, reportDocument],
    }),
  };
}

/** Starts the page at `pathname` with `routes`, and returns the root, the document, and the requests. */
async function startAt(pathname, routes = fixtureBackend()) {
  const doc = new FakeDocument();
  const root = doc.createElement("main");
  const { fetch, requests } = fakeFetch(routes);
  await start({ doc, root, location: { pathname }, fetch });
  return { doc, root, requests };
}

const reader = createReader({ ...config, fetch: async () => answer(500) });

describe("parseRoute", () => {
  test("names the page of /r/<pageId> and the report of /r/<pageId>/<visitId>", () => {
    assert.deepEqual(parseRoute(`/r/${pageId}`), { pageId, visitId: null });
    assert.deepEqual(parseRoute(`/r/${pageId}/`), { pageId, visitId: null });
    assert.deepEqual(parseRoute(`/r/${pageId}/${visitId}`), {
      pageId,
      visitId,
    });
  });

  test("refuses every other path, and IDs that could name another document", () => {
    for (const path of [
      "/",
      "/r",
      "/r/",
      "/x/abc",
      `/r/${pageId}/${visitId}/more`,
      "/r/a.b",
      "/r/a%2Fb",
      "/r/abc/..",
      `/r/${"a".repeat(129)}`,
    ]) {
      assert.equal(parseRoute(path), null, path);
    }
  });
});

describe("decoding", () => {
  test("reads a client page, with a company name of null when none is saved", () => {
    assert.deepEqual(decodePage(pageDocument), {
      companyName: "깔끔클린",
      clientName: "행복빌딩",
    });
    const withoutCompany = {
      ...pageDocument,
      fields: { ...pageDocument.fields, companyName: { nullValue: null } },
    };
    assert.deepEqual(decodePage(withoutCompany), {
      companyName: null,
      clientName: "행복빌딩",
    });
    assert.deepEqual(decodePage({ name: "x" }), {
      companyName: null,
      clientName: "",
    });
  });

  test("reads a report with its zones in order, and an empty slot as null", () => {
    assert.deepEqual(decodeReport(reportDocument), {
      visitId,
      visitDate: "2026-10-01",
      publishedAt: "2026-10-01T09:00:00Z",
      zones: [
        {
          name: "로비",
          note: "바닥 왁스\n유리문 닦음",
          beforePhoto: lobbyBefore,
          afterPhoto: lobbyAfter,
        },
        { name: "복도", note: "", beforePhoto: hallBefore, afterPhoto: null },
        {
          name: "탕비실",
          note: "공사 중이라 사진을 못 찍었어요",
          beforePhoto: null,
          afterPhoto: null,
        },
      ],
      unbranded: false,
    });
  });

  test("reads a report without fields, and leaves out a zone that is no map", () => {
    const odd = {
      name: `x/reports/${visitId}`,
      fields: { zones: { arrayValue: { values: [{ stringValue: "x" }] } } },
    };
    assert.deepEqual(decodeReport(odd), {
      visitId,
      visitDate: "",
      publishedAt: "",
      zones: [],
      unbranded: false,
    });
    assert.deepEqual(decodeReport({ name: `x/reports/${visitId}` }).zones, []);
  });

  test("reads each kind of value of the REST API", () => {
    assert.equal(decodeValue(undefined), null);
    assert.equal(decodeValue({ nullValue: null }), null);
    assert.equal(decodeValue({ booleanValue: true }), true);
    assert.equal(decodeValue({ integerValue: "3" }), 3);
    assert.equal(decodeValue({ doubleValue: 1.5 }), 1.5);
    assert.deepEqual(decodeValue({ arrayValue: {} }), []);
    assert.deepEqual(decodeValue({ mapValue: {} }), {});
    assert.equal(decodeValue({ bytesValue: "AA==" }), null);
  });

  test("sorts the reports newest visit first, and of one date the one published last first", () => {
    const sorted = sortNewestFirst([
      { visitDate: "2026-09-24", publishedAt: "2026-09-24T09:00:00Z" },
      { visitDate: "2026-10-01", publishedAt: "2026-10-01T08:00:00Z" },
      { visitDate: "2026-10-01", publishedAt: "2026-10-01T09:00:00Z" },
    ]);
    assert.deepEqual(
      sorted.map((report) => report.publishedAt),
      ["2026-10-01T09:00:00Z", "2026-10-01T08:00:00Z", "2026-09-24T09:00:00Z"],
    );
  });
});

describe("sortNewestFirst with timestamps of different precision", () => {
  test("compares the publish times as times, not as texts", () => {
    const sorted = sortNewestFirst([
      { visitDate: "2026-10-01", publishedAt: "2026-10-01T09:00:00.5Z" },
      { visitDate: "2026-10-01", publishedAt: "2026-10-01T09:00:00.123456Z" },
    ]);
    assert.deepEqual(
      sorted.map((report) => report.publishedAt),
      ["2026-10-01T09:00:00.5Z", "2026-10-01T09:00:00.123456Z"],
    );
  });
});

describe("createReader", () => {
  test("reads the documents of the project through the REST API, with the key of the configuration", async () => {
    const { fetch, requests } = fakeFetch(fixtureBackend());
    const backend = createReader({ ...config, fetch });

    assert.deepEqual(await backend.page(pageId), {
      companyName: "깔끔클린",
      clientName: "행복빌딩",
    });
    assert.equal((await backend.report(pageId, visitId)).zones.length, 3);
    assert.deepEqual(requests, [
      `${documentsUrl}/clientPages/${pageId}?key=fixture-key`,
      `${documentsUrl}/clientPages/${pageId}/reports/${visitId}?key=fixture-key`,
    ]);
  });

  test("reads every page of the list of the reports, newest visit first", async () => {
    const list = `${documentsUrl}/clientPages/${pageId}/reports`;
    const { fetch, requests } = fakeFetch({
      [list]: (url) =>
        url.includes("pageToken=next")
          ? answer(200, { documents: [olderReportDocument] })
          : answer(200, { documents: [reportDocument], nextPageToken: "next" }),
    });
    const backend = createReader({ ...config, apiKey: null, fetch });

    const reports = await backend.reports(pageId);

    assert.deepEqual(
      reports.map((report) => report.visitId),
      [visitId, olderVisitId],
    );
    assert.deepEqual(requests, [
      `${list}?pageSize=100`,
      `${list}?pageSize=100&pageToken=next`,
    ]);
  });

  test("reads a page without reports as an empty list", async () => {
    const { fetch } = fakeFetch({
      [`${documentsUrl}/clientPages/${pageId}/reports`]: answer(200, {}),
    });

    assert.deepEqual(
      await createReader({ ...config, fetch }).reports(pageId),
      [],
    );
  });

  for (const [status, kind] of [
    [403, "unavailable"],
    [404, "missing"],
    [500, "failed"],
  ]) {
    test(`reads an answer ${status} as ${kind}`, async () => {
      const backend = createReader({
        ...config,
        fetch: async () => answer(status),
      });

      await assert.rejects(
        backend.page(pageId),
        (error) => error instanceof ReadError && error.kind === kind,
      );
    });
  }

  test("reads a 403 that names a reason, such as a blocked API key, as failed and not as a revoked page", async () => {
    const body = {
      error: {
        code: 403,
        status: "PERMISSION_DENIED",
        details: [
          {
            "@type": "type.googleapis.com/google.rpc.ErrorInfo",
            reason: "API_KEY_HTTP_REFERRER_BLOCKED",
          },
        ],
      },
    };
    const backend = createReader({
      ...config,
      fetch: async () => answer(403, body),
    });

    await assert.rejects(
      backend.page(pageId),
      (error) => error.kind === "failed",
    );
  });

  test("reads a 403 of the rules, whose body names no reason or is no JSON, as unavailable", async () => {
    const rules = {
      error: {
        code: 403,
        message: "Missing or insufficient permissions.",
        status: "PERMISSION_DENIED",
      },
    };
    for (const response of [
      answer(403, rules),
      { status: 403, ok: false, json: async () => JSON.parse("<html>") },
    ]) {
      const backend = createReader({ ...config, fetch: async () => response });

      await assert.rejects(
        backend.page(pageId),
        (error) => error.kind === "unavailable",
      );
    }
  });

  test("reads a request that does not reach the backend as failed", async () => {
    const backend = createReader({
      ...config,
      fetch: async () => {
        throw new TypeError("Failed to fetch");
      },
    });

    await assert.rejects(
      backend.page(pageId),
      (error) => error.kind === "failed",
    );
  });

  test("gives a photo URL that holds the encoded object path and no token", () => {
    assert.equal(
      reader.photoUrl(lobbyBefore),
      `https://firebasestorage.googleapis.com/v0/b/demo-kkomkkomi.appspot.com/o/${encodeURIComponent(lobbyBefore)}?alt=media`,
    );
    assert.doesNotMatch(reader.photoUrl(lobbyBefore), /token/);
  });
});

describe("renderReport", () => {
  const photoUrl = (path) => `https://photos.test/${path}`;

  function render(
    page = decodePage(pageDocument),
    report = decodeReport(reportDocument),
  ) {
    const doc = new FakeDocument();
    return renderReport(doc, { pageId, page, report, photoUrl });
  }

  test("shows the company name, the title, the client name, the visit date, each zone, and the footer, in order", () => {
    const view = render();

    assert.deepEqual(view.texts(), [
      "깔끔클린",
      "청소 완료 보고서",
      "행복빌딩",
      "2026년 10월 1일",
      "로비",
      "청소 전",
      "청소 후",
      "메모",
      "바닥 왁스\n유리문 닦음",
      "복도",
      "청소 전",
      "청소 후",
      "사진 없음",
      "탕비실",
      "청소 전",
      "사진 없음",
      "청소 후",
      "사진 없음",
      "메모",
      "공사 중이라 사진을 못 찍었어요",
      "이 거래처의 보고서 모두 보기",
      "꼼꼬미로 작성됨",
      "개인정보 처리방침",
    ]);
  });

  test("shows each photo from its URL, with the zone and the slot as its text", () => {
    const images = render().all("img");

    assert.deepEqual(
      images.map((image) => [
        image.getAttribute("src"),
        image.getAttribute("alt"),
      ]),
      [
        [photoUrl(lobbyBefore), "로비 청소 전"],
        [photoUrl(lobbyAfter), "로비 청소 후"],
        [photoUrl(hallBefore), "복도 청소 전"],
      ],
    );
    assert.ok(
      images.every((image) => image.getAttribute("loading") === "lazy"),
    );
  });

  test("shows a text in place of a photo that does not load", () => {
    const view = render();
    const image = view.all("img")[0];
    const frame = image.parent;

    image.dispatch("error");

    assert.deepEqual(frame.texts(), ["사진을 불러오지 못했어요"]);
    assert.equal(frame.all("img").length, 0);
  });

  test("links to the list of the reports of the client page, and to the privacy policy in the footer", () => {
    const view = render();

    assert.deepEqual(
      view.all("a").map((link) => link.getAttribute("href")),
      [`/r/${pageId}`, privacyPath],
    );
    assert.deepEqual(
      view
        .all("footer")[0]
        .all("a")
        .map((link) => link.getAttribute("href")),
      [privacyPath],
    );
  });

  test("leaves out the company line when no company name is saved", () => {
    const view = render({ companyName: null, clientName: "행복빌딩" });

    assert.equal(view.texts()[0], "청소 완료 보고서");
  });

  test("says so for a report without a zone", () => {
    const report = { ...decodeReport(reportDocument), zones: [] };

    assert.ok(render(undefined, report).texts().includes(texts.emptyReport));
  });

  test("offers nothing of a later milestone: no confirm control and no view state", () => {
    const view = render();

    assert.equal(view.all("button").length, 0);
    for (const text of view.texts())
      assert.doesNotMatch(text, /확인|열람/, text);
  });
});

describe("renderHistory", () => {
  test("lists the reports newest first, each as a link to its report", () => {
    const doc = new FakeDocument();
    const reports = sortNewestFirst([
      decodeReport(olderReportDocument),
      decodeReport(reportDocument),
    ]);

    const view = renderHistory(doc, {
      pageId,
      page: decodePage(pageDocument),
      reports,
    });

    assert.deepEqual(view.texts(), [
      "깔끔클린",
      "청소 보고서",
      "행복빌딩",
      "2026년 10월 1일",
      "2026년 9월 24일",
      "꼼꼬미로 작성됨",
      "개인정보 처리방침",
    ]);
    assert.deepEqual(
      view.all("a").map((link) => link.getAttribute("href")),
      [`/r/${pageId}/${visitId}`, `/r/${pageId}/${olderVisitId}`, privacyPath],
    );
  });

  test("says so for a page without reports", () => {
    const view = renderHistory(new FakeDocument(), {
      pageId,
      page: decodePage(pageDocument),
      reports: [],
    });

    assert.ok(view.texts().includes(texts.emptyHistory));
  });
});

describe("unbranded reports", () => {
  const unbrandedDocument = {
    ...reportDocument,
    fields: { ...reportDocument.fields, unbranded: { booleanValue: true } },
  };

  test("decodes unbranded only from the boolean true", () => {
    assert.equal(decodeReport(unbrandedDocument).unbranded, true);
    assert.equal(decodeReport(reportDocument).unbranded, false);
    const withValue = (value) => ({
      ...reportDocument,
      fields: { ...reportDocument.fields, unbranded: value },
    });
    assert.equal(
      decodeReport(withValue({ stringValue: "true" })).unbranded,
      false,
    );
    assert.equal(
      decodeReport(withValue({ booleanValue: false })).unbranded,
      false,
    );
  });

  test("a report without the footer keeps the privacy link", () => {
    const view = renderReport(new FakeDocument(), {
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

describe("renderFailure", () => {
  test("says that a revoked or unknown page cannot open, and offers no retry", () => {
    const view = renderFailure(new FakeDocument(), {
      kind: "unavailable",
      pageId,
      onRetry: () => {},
    });

    assert.deepEqual(view.texts(), [
      texts.unavailableTitle,
      texts.unavailableMessage,
      texts.footer,
      texts.privacyLink,
    ]);
    assert.equal(view.all("button").length, 0);
    assert.equal(view.getAttribute("role"), "alert");
  });

  test("links a missing report to the list of its page", () => {
    const view = renderFailure(new FakeDocument(), { kind: "missing", pageId });

    assert.deepEqual(view.texts(), [
      texts.missingTitle,
      texts.missingMessage,
      texts.historyLink,
      texts.footer,
      texts.privacyLink,
    ]);
    assert.equal(view.all("a")[0].getAttribute("href"), `/r/${pageId}`);
  });

  test("offers a retry after a failure that a retry can fix", () => {
    let retries = 0;
    const view = renderFailure(new FakeDocument(), {
      kind: "failed",
      onRetry: () => retries++,
    });

    view.all("button")[0].dispatch("click");

    assert.deepEqual(view.texts(), [
      texts.failedTitle,
      texts.failedMessage,
      texts.retry,
      texts.footer,
      texts.privacyLink,
    ]);
    assert.equal(retries, 1);
  });

  test("offers no retry without a handler", () => {
    assert.equal(
      renderFailure(new FakeDocument(), { kind: "failed" }).all("nav").length,
      0,
    );
  });
});

describe("start", () => {
  test("renders the sample report from the fixture data", async () => {
    const { doc, root, requests } = await startAt(`/r/${pageId}/${visitId}`);

    const texts = root.texts();
    assert.deepEqual(texts.slice(0, 5), [
      "깔끔클린",
      "청소 완료 보고서",
      "행복빌딩",
      "2026년 10월 1일",
      "로비",
    ]);
    assert.deepEqual(texts.slice(-2), ["꼼꼬미로 작성됨", "개인정보 처리방침"]);
    assert.equal(
      root.all("img")[0].getAttribute("src"),
      `https://firebasestorage.googleapis.com/v0/b/demo-kkomkkomi.appspot.com/o/${encodeURIComponent(lobbyBefore)}?alt=media`,
    );
    assert.equal(doc.title, "행복빌딩 청소 완료 보고서");
    // The configuration comes from Hosting, and no request leaves the fixture backend.
    assert.equal(requests[0], configPath);
    assert.equal(requests.length, 3);
  });

  test("renders the list of the reports of a client page", async () => {
    const { doc, root } = await startAt(`/r/${pageId}`);

    assert.deepEqual(root.texts().slice(3, 5), [
      "2026년 10월 1일",
      "2026년 9월 24일",
    ]);
    assert.equal(doc.title, "행복빌딩 청소 보고서");
  });

  test("says that a page the rules refuse cannot open: a revoked page or an unknown page ID", async () => {
    const routes = {
      ...fixtureBackend(),
      [`${documentsUrl}/clientPages/${pageId}`]: answer(403),
    };
    routes[`${documentsUrl}/clientPages/${pageId}/reports/${visitId}`] =
      answer(403);

    const { doc, root } = await startAt(`/r/${pageId}/${visitId}`, routes);

    assert.equal(root.texts()[0], texts.unavailableTitle);
    assert.equal(doc.title, texts.unavailableTitle);
  });

  test("says that a report is missing under an open page", async () => {
    const { root } = await startAt(`/r/${pageId}/${olderVisitId}`);

    assert.equal(root.texts()[0], texts.missingTitle);
  });

  test("says that a path that names no page cannot open, and reads nothing", async () => {
    const { root, requests } = await startAt("/r/");

    assert.equal(root.texts()[0], texts.unavailableTitle);
    assert.deepEqual(requests, []);
  });

  test("offers a retry when the configuration does not load, and shows the report after it", async () => {
    let configAnswers = [answer(503), answer(200, config)];
    const routes = {
      ...fixtureBackend(),
      [configPath]: () => configAnswers.shift(),
    };
    const { root } = await startAt(`/r/${pageId}/${visitId}`, routes);
    assert.equal(root.texts()[0], texts.failedTitle);

    root.all("button")[0].dispatch("click");
    await new Promise((resolve) => setTimeout(resolve, 0));

    assert.equal(root.texts()[1], "청소 완료 보고서");
    configAnswers = [];
  });

  test("says that the report did not load when the configuration names no project or no bucket", async () => {
    for (const broken of [
      { ...config, projectId: undefined },
      { ...config, storageBucket: undefined },
    ]) {
      const routes = { ...fixtureBackend(), [configPath]: answer(200, broken) };

      const { root, requests } = await startAt(`/r/${pageId}`, routes);

      assert.equal(root.texts()[0], texts.failedTitle);
      assert.deepEqual(requests, [configPath]);
    }
  });

  test("says that the report did not load when the network fails", async () => {
    const doc = new FakeDocument();
    const root = doc.createElement("main");
    const fetch = async () => {
      throw new TypeError("Failed to fetch");
    };

    await start({ doc, root, location: { pathname: `/r/${pageId}` }, fetch });

    assert.equal(root.texts()[0], texts.failedTitle);
  });

  test("shows a failure of another kind as a failed load", async () => {
    const routes = {
      ...fixtureBackend(),
      [configPath]: {
        ok: true,
        status: 200,
        json: async () => {
          throw new SyntaxError("bad");
        },
      },
    };

    const { root } = await startAt(`/r/${pageId}`, routes);

    assert.equal(root.texts()[0], texts.failedTitle);
  });
});

describe("formatVisitDate", () => {
  test("writes a date as the app does in Korean, and leaves another text as it is", () => {
    assert.equal(formatVisitDate("2026-01-05"), "2026년 1월 5일");
    assert.equal(formatVisitDate("soon"), "soon");
  });
});

describe("the files of the page", () => {
  test("Hosting rewrites every report path to the page, and the page exists", () => {
    const hosting = JSON.parse(read("firebase.json")).hosting;

    assert.equal(hosting.public, "web");
    assert.deepEqual(hosting.rewrites, [
      { source: "/r/**", destination: "/report/index.html" },
    ]);
    assert.ok(read("web/report/index.html").length > 0);
  });

  test("the page loads its own script and style, keeps itself out of search, and sends no referrer", () => {
    const html = read("web/report/index.html");

    assert.match(
      html,
      /<script type="module" src="\/report\/main\.js"><\/script>/,
    );
    assert.match(
      html,
      /<link rel="stylesheet" href="\/report\/report\.css" \/>/,
    );
    assert.match(html, /<meta name="robots" content="noindex, nofollow" \/>/);
    assert.match(html, /<meta name="referrer" content="no-referrer" \/>/);
    assert.match(html, /script-src 'self';/);
    assert.doesNotMatch(html, /unsafe-inline|unsafe-eval/);
  });

  test("no script of the page writes HTML, loads the Firebase SDK, or asks for a download URL", () => {
    for (const file of ["app.js", "data.js", "main.js", "view.js"]) {
      const source = read(`web/report/${file}`);
      assert.doesNotMatch(
        source,
        /innerHTML|outerHTML|insertAdjacentHTML|document\.write/,
        file,
      );
      assert.doesNotMatch(source, /gstatic|getDownloadURL|token=/, file);
    }
  });

  test("no tracked file of the page holds a Firebase API key", () => {
    for (const file of [
      "index.html",
      "app.js",
      "data.js",
      "main.js",
      "view.js",
      "report.css",
    ]) {
      assert.doesNotMatch(
        read(`web/report/${file}`),
        /AIza[0-9A-Za-z_-]{20,}/,
        file,
      );
    }
  });
});
