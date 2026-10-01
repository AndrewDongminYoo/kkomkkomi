// Shows the view that the path names: one report at /r/<pageId>/<visitId>, the list of the reports of a client
// page at /r/<pageId>.

import { ReadError, createReader, parseRoute } from "./data.js";
import {
  renderFailure,
  renderHistory,
  renderLoading,
  renderReport,
  texts,
} from "./view.js";

/** Where Hosting gives the configuration of the Firebase project, so that no tracked file holds it. */
export const configPath = "/__/firebase/init.json";

/**
 * Reads what `location` names and shows it in `root`.
 *
 * `fetch` reads the configuration and the documents, and `doc` makes the nodes. `hosts` replaces the production
 * hosts in a test. The returned promise ends when the view is on the page.
 */
export async function start({ doc, root, location, fetch, hosts }) {
  const route = parseRoute(location.pathname);
  if (route === null) {
    show(
      doc,
      root,
      renderFailure(doc, { kind: "unavailable" }),
      texts.unavailableTitle,
    );
    return;
  }
  show(doc, root, renderLoading(doc), texts.reportTitle);
  try {
    const reader = createReader({ ...(await readConfig(fetch)), fetch, hosts });
    if (route.visitId === null) {
      const [page, reports] = await Promise.all([
        reader.page(route.pageId),
        reader.reports(route.pageId),
      ]);
      show(
        doc,
        root,
        renderHistory(doc, { pageId: route.pageId, page, reports }),
        `${page.clientName} ${texts.historyTitle}`,
      );
    } else {
      const [page, report] = await Promise.all([
        reader.page(route.pageId),
        reader.report(route.pageId, route.visitId),
      ]);
      show(
        doc,
        root,
        renderReport(doc, {
          pageId: route.pageId,
          page,
          report,
          photoUrl: reader.photoUrl,
        }),
        `${page.clientName} ${texts.reportTitle}`,
      );
    }
  } catch (error) {
    const kind = error instanceof ReadError ? error.kind : "failed";
    const onRetry = () => start({ doc, root, location, fetch, hosts });
    const titles = {
      unavailable: texts.unavailableTitle,
      missing: texts.missingTitle,
    };
    show(
      doc,
      root,
      renderFailure(doc, { kind, pageId: route.pageId, onRetry }),
      titles[kind] ?? texts.failedTitle,
    );
  }
}

async function readConfig(fetch) {
  let response;
  try {
    response = await fetch(configPath);
  } catch (error) {
    throw new ReadError("failed", `The configuration did not load: ${error}`);
  }
  if (!response.ok)
    throw new ReadError(
      "failed",
      `The configuration answered ${response.status}`,
    );
  const { projectId, storageBucket, apiKey } = await response.json();
  // Without the project or the bucket, every read would name a path that does not exist.
  if (typeof projectId !== "string" || typeof storageBucket !== "string") {
    throw new ReadError(
      "failed",
      "The configuration names no project or no bucket",
    );
  }
  return { projectId, storageBucket, apiKey };
}

function show(doc, root, view, title) {
  root.replaceChildren(view);
  doc.title = title;
}
