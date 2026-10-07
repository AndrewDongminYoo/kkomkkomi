// Builds the views of the report page as DOM nodes.
//
// Every text from the backend goes into `textContent`, never into HTML, because zone names and notes are what a
// worker typed. Each function takes the document that makes the nodes, so a test can give a document without a
// browser.

/** The texts of the page, which match the report of the app. */
export const texts = {
  reportTitle: "청소 완료 보고서",
  historyTitle: "청소 보고서",
  beforePhoto: "청소 전",
  afterPhoto: "청소 후",
  notPhotographed: "촬영하지 않음",
  partlyDone: "일부 완료",
  notDone: "못 함",
  photoFailed: "사진을 불러오지 못했어요",
  note: "메모",
  footer: "꼼꼬미로 작성됨",
  privacyLink: "개인정보 처리방침",
  emptyReport: "이 보고서에는 사진이나 메모가 없어요.",
  emptyHistory: "아직 올라온 보고서가 없어요.",
  historyLink: "이 거래처의 보고서 모두 보기",
  loading: "보고서를 불러오고 있어요.",
  unavailableTitle: "보고서를 열 수 없어요",
  unavailableMessage:
    "링크가 바뀌었거나 더 이상 볼 수 없는 보고서예요. 보고서를 보낸 분에게 새 링크를 받아 주세요.",
  missingTitle: "보고서를 찾을 수 없어요",
  missingMessage: "링크가 잘못됐거나 아직 올라오지 않은 보고서예요.",
  failedTitle: "보고서를 불러오지 못했어요",
  failedMessage: "인터넷 연결을 확인한 뒤 다시 시도해 주세요.",
  retry: "다시 시도하기",
};

/** The summary line of a report with `total` zones, of which `done` are done. */
export function summaryOf(done, total) {
  return `${total}곳 중 ${done}곳 완료`;
}

/** The text of the status of a zone that is not done, and an empty text for a done zone. */
export function statusOf(status) {
  if (status === "partlyDone") return texts.partlyDone;
  if (status === "notDone") return texts.notDone;
  return "";
}

/** The line of the summary for `zone`, which is not done: its name and its status, then its reason when it has one. */
export function exceptionLineOf(zone) {
  const head = `${zone.name} · ${statusOf(zone.status)}`;
  return zone.reason ? `${head}: ${zone.reason}` : head;
}

/** The text inside an empty photo slot of a zone with `status`. */
export function emptySlotOf(status) {
  return status === "notDone" ? texts.notDone : texts.notPhotographed;
}

/** The date of a visit, `YYYY-MM-DD`, as the app shows it in Korean: `2026년 10월 1일`. */
export function formatVisitDate(visitDate) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(visitDate);
  if (!match) return visitDate;
  return `${Number(match[1])}년 ${Number(match[2])}월 ${Number(match[3])}일`;
}

/** The path of the list of the reports of the page with `pageId`. */
export function historyPath(pageId) {
  return `/r/${encodeURIComponent(pageId)}`;
}

/** The path of the report of the visit with `visitId` under the page with `pageId`. */
export function reportPath(pageId, visitId) {
  return `/r/${encodeURIComponent(pageId)}/${encodeURIComponent(visitId)}`;
}

/** An element with `tag`, the class `className`, and `text` as its text, or `children` under it. */
function element(
  doc,
  tag,
  { className, text, attributes = {} } = {},
  children = [],
) {
  const node = doc.createElement(tag);
  if (className) node.setAttribute("class", className);
  for (const [name, value] of Object.entries(attributes))
    node.setAttribute(name, value);
  if (text !== undefined) node.textContent = text;
  for (const child of children) node.appendChild(child);
  return node;
}

/** The path of the privacy policy, which Hosting serves from `web/privacy/`. */
export const privacyPath = "/privacy/";

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

/** The head of a sheet: the company name, the title, and the client name. */
function sheetHead(doc, page, title, extra = []) {
  return element(doc, "header", { className: "sheet-head" }, [
    ...(page.companyName
      ? [element(doc, "p", { className: "company", text: page.companyName })]
      : []),
    element(doc, "h1", { text: title }),
    element(doc, "p", { className: "client", text: page.clientName }),
    ...extra,
  ]);
}

/** One photo slot: its label over the photo, or over an empty box that says `emptyText`. */
function photoSlot(doc, label, objectPath, photoUrl, zoneName, emptyText) {
  const frame = element(doc, "div", { className: "frame" });
  if (objectPath) {
    const image = element(doc, "img", {
      attributes: {
        src: photoUrl(objectPath),
        alt: `${zoneName} ${label}`,
        loading: "lazy",
        decoding: "async",
      },
    });
    // A photo that does not load, such as a photo of a page that was revoked since, leaves a text in its place.
    image.addEventListener("error", () => {
      frame.replaceChildren(
        element(doc, "span", { className: "empty", text: texts.photoFailed }),
      );
    });
    frame.appendChild(image);
  } else {
    frame.appendChild(
      element(doc, "span", { className: "empty", text: emptyText }),
    );
  }
  return element(doc, "figure", { className: "slot" }, [
    element(doc, "figcaption", { text: label }),
    frame,
  ]);
}

/** The count of the done zones of `zones`, then one line for each zone that is not done. */
function summary(doc, zones) {
  const done = zones.filter((zone) => zone.status === "done").length;
  const exceptions = zones.filter((zone) => zone.status !== "done");
  return element(doc, "section", { className: "summary" }, [
    element(doc, "p", {
      className: "summary-count",
      text: summaryOf(done, zones.length),
    }),
    ...(exceptions.length > 0
      ? [
          element(
            doc,
            "ul",
            { className: "exceptions" },
            exceptions.map((zone) =>
              element(doc, "li", { text: exceptionLineOf(zone) }),
            ),
          ),
        ]
      : []),
  ]);
}

/** The name of a zone, and after it the status of a zone that is not done, as a text inside a border. */
function zoneHeading(doc, zone) {
  if (zone.status === "done") return element(doc, "h2", { text: zone.name });
  return element(doc, "h2", {}, [
    element(doc, "span", { text: zone.name }),
    element(doc, "span", { className: "badge", text: statusOf(zone.status) }),
  ]);
}

function zoneSection(doc, zone, photoUrl) {
  const emptyText = emptySlotOf(zone.status);
  return element(doc, "section", { className: "zone" }, [
    zoneHeading(doc, zone),
    element(doc, "div", { className: "slots" }, [
      photoSlot(
        doc,
        texts.beforePhoto,
        zone.beforePhoto,
        photoUrl,
        zone.name,
        emptyText,
      ),
      photoSlot(
        doc,
        texts.afterPhoto,
        zone.afterPhoto,
        photoUrl,
        zone.name,
        emptyText,
      ),
    ]),
    ...(zone.note
      ? [
          element(doc, "div", { className: "note" }, [
            element(doc, "p", { className: "label", text: texts.note }),
            element(doc, "p", { className: "note-text", text: zone.note }),
          ]),
        ]
      : []),
  ]);
}

/** The report of one visit under the page with `pageId`. `photoUrl` gives the URL of a photo from its path. */
export function renderReport(doc, { pageId, page, report, photoUrl }) {
  return element(doc, "article", { className: "sheet" }, [
    sheetHead(doc, page, texts.reportTitle, [
      element(doc, "p", {
        className: "date",
        text: formatVisitDate(report.visitDate),
      }),
    ]),
    ...(report.zones.length === 0
      ? [element(doc, "p", { className: "message", text: texts.emptyReport })]
      : [
          summary(doc, report.zones),
          ...report.zones.map((zone) => zoneSection(doc, zone, photoUrl)),
        ]),
    element(doc, "nav", { className: "more" }, [
      element(doc, "a", {
        text: texts.historyLink,
        attributes: { href: historyPath(pageId) },
      }),
    ]),
    footer(doc, { branded: !report.unbranded }),
  ]);
}

/** The list of the reports of the page with `pageId`, newest visit first, each a link to its report. */
export function renderHistory(doc, { pageId, page, reports }) {
  return element(doc, "article", { className: "sheet" }, [
    sheetHead(doc, page, texts.historyTitle),
    reports.length === 0
      ? element(doc, "p", { className: "message", text: texts.emptyHistory })
      : element(
          doc,
          "ul",
          { className: "history" },
          reports.map((report) =>
            element(doc, "li", {}, [
              element(doc, "a", {
                text: formatVisitDate(report.visitDate),
                attributes: { href: reportPath(pageId, report.visitId) },
              }),
            ]),
          ),
        ),
    // The list shows the footer text unless it lists a report and every listed report is without the footer.
    footer(doc, {
      branded:
        reports.length === 0 || reports.some((report) => !report.unbranded),
    }),
  ]);
}

/** The view while the page reads the backend. */
export function renderLoading(doc) {
  return element(doc, "p", {
    className: "status",
    text: texts.loading,
    attributes: { role: "status" },
  });
}

/**
 * The view of a read that failed with `kind`: "unavailable", "missing", or "failed". A missing report under an open
 * page links to the list of the page, and a failure that a retry can fix offers the retry, which calls `onRetry`.
 */
export function renderFailure(doc, { kind, pageId = null, onRetry = null }) {
  const [title, message] = {
    unavailable: [texts.unavailableTitle, texts.unavailableMessage],
    missing: [texts.missingTitle, texts.missingMessage],
  }[kind] ?? [texts.failedTitle, texts.failedMessage];
  const actions = [];
  if (kind === "missing" && pageId) {
    actions.push(
      element(doc, "a", {
        text: texts.historyLink,
        attributes: { href: historyPath(pageId) },
      }),
    );
  }
  if (kind !== "unavailable" && kind !== "missing" && onRetry) {
    const button = element(doc, "button", {
      text: texts.retry,
      attributes: { type: "button" },
    });
    button.addEventListener("click", onRetry);
    actions.push(button);
  }
  return element(
    doc,
    "article",
    { className: "sheet notice", attributes: { role: "alert" } },
    [
      element(doc, "h1", { text: title }),
      element(doc, "p", { className: "message", text: message }),
      ...(actions.length > 0
        ? [element(doc, "nav", { className: "more" }, actions)]
        : []),
      footer(doc),
    ],
  );
}
