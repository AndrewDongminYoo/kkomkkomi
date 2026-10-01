// Reads a client page, its reports, and their photos from Firestore and Storage, through the security rules.
//
// The page calls the Firestore REST API and loads each photo from the Storage REST API without a download token,
// so the rules check every read and a revoked page stops each read at once. No Firebase SDK is loaded: Hosting
// gives the configuration of the project at /__/firebase/init.json, and the page needs only the project ID and the
// bucket from it.

/** The production hosts. A test gives the hosts of the emulators. */
export const productionHosts = {
  firestore: "https://firestore.googleapis.com",
  storage: "https://firebasestorage.googleapis.com",
};

// A page ID and a visit ID are hexadecimal in the app. The pattern is wider, and still keeps a path segment from
// reaching another document.
const idPattern = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * The page and the visit that a path names: `/r/<pageId>` for the list of the reports of a client page, and
 * `/r/<pageId>/<visitId>` for one report. Returns null for any other path.
 */
export function parseRoute(pathname) {
  const parts = pathname.split("/").filter((part) => part !== "");
  if (parts[0] !== "r" || parts.length < 2 || parts.length > 3) return null;
  const [, pageId, visitId] = parts;
  if (!idPattern.test(pageId)) return null;
  if (visitId === undefined) return { pageId, visitId: null };
  return idPattern.test(visitId) ? { pageId, visitId } : null;
}

/** A read failed. `kind` is "unavailable" for a page that the rules do not open, "missing" for a report that an
 * open page does not hold, and "failed" for every other failure, such as a missing network. */
export class ReadError extends Error {
  constructor(kind, message) {
    super(message);
    this.name = "ReadError";
    this.kind = kind;
  }
}

/**
 * Makes the reader of the project with `projectId` and the bucket `storageBucket`, which calls `fetch`.
 *
 * `apiKey` is the Web API key from the Hosting configuration. The reads need no sign-in: the rules open a page and
 * its reports to anyone who has the page ID.
 */
export function createReader({
  projectId,
  storageBucket,
  apiKey = null,
  fetch,
  hosts = productionHosts,
}) {
  const documents = `${hosts.firestore}/v1/projects/${encodeURIComponent(projectId)}/databases/(default)/documents`;

  async function get(path, params = {}) {
    const query = new URLSearchParams(params);
    if (apiKey) query.set("key", apiKey);
    const queryText = query.toString();
    let response;
    try {
      response = await fetch(
        `${documents}/${path}${queryText ? `?${queryText}` : ""}`,
      );
    } catch (error) {
      throw new ReadError(
        "failed",
        `The request did not reach Firestore: ${error}`,
      );
    }
    // A revoked page and a page ID that does not exist both fail the rules, so both read as unavailable. Google
    // answers 403 also for an API key that may not call Firestore, and then names the reason in an `ErrorInfo`
    // detail, which the rules never give: that read failed, and the link is not revoked.
    if (response.status === 403) {
      if (await namesErrorReason(response))
        throw new ReadError("failed", "Google refused the request itself");
      throw new ReadError("unavailable", "The rules refused the read");
    }
    if (response.status === 404)
      throw new ReadError("missing", "No document has this path");
    if (!response.ok)
      throw new ReadError("failed", `Firestore answered ${response.status}`);
    return response.json();
  }

  return {
    /** The client page with `pageId`. */
    async page(pageId) {
      return decodePage(await get(`clientPages/${pageId}`));
    },

    /** The report of the visit with `visitId` under the page with `pageId`. */
    async report(pageId, visitId) {
      return decodeReport(
        await get(`clientPages/${pageId}/reports/${visitId}`),
      );
    },

    /** Every report of the page with `pageId`, newest visit first. */
    async reports(pageId) {
      const reports = [];
      let pageToken = null;
      do {
        const params = { pageSize: "100" };
        if (pageToken) params.pageToken = pageToken;
        const answer = await get(`clientPages/${pageId}/reports`, params);
        for (const document of answer.documents ?? [])
          reports.push(decodeReport(document));
        pageToken = answer.nextPageToken ?? null;
      } while (pageToken);
      return sortNewestFirst(reports);
    },

    /** The URL that loads the photo at `objectPath`. The rules check each load, and the URL holds no token. */
    photoUrl(objectPath) {
      return `${hosts.storage}/v0/b/${encodeURIComponent(storageBucket)}/o/${encodeURIComponent(objectPath)}?alt=media`;
    },
  };
}

/** Whether the body of a failed `response` names a reason in an `ErrorInfo` detail, such as a blocked API key. */
async function namesErrorReason(response) {
  try {
    const body = await response.json();
    const details = body?.error?.details;
    return (
      Array.isArray(details) &&
      details.some((detail) => typeof detail?.reason === "string")
    );
  } catch {
    return false;
  }
}

/** The reports newest visit first, and of one date the one published last first. */
export function sortNewestFirst(reports) {
  // A timestamp of the REST API has 0, 3, 6, or 9 digits of fractions of a second, so it is compared as a time.
  const timeOf = (report) => Date.parse(report.publishedAt) || 0;
  return [...reports].sort(
    (a, b) => b.visitDate.localeCompare(a.visitDate) || timeOf(b) - timeOf(a),
  );
}

/** The value of a field of a Firestore REST document, as a plain JavaScript value. */
export function decodeValue(value) {
  if (value === undefined || value === null || "nullValue" in value)
    return null;
  if ("stringValue" in value) return value.stringValue;
  if ("timestampValue" in value) return value.timestampValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("arrayValue" in value)
    return (value.arrayValue.values ?? []).map(decodeValue);
  if ("mapValue" in value) return decodeFields(value.mapValue.fields ?? {});
  return null;
}

function decodeFields(fields) {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, decodeValue(value)]),
  );
}

/** The last segment of the name of a Firestore REST document, which is its ID. */
function idOf(document) {
  return document.name.slice(document.name.lastIndexOf("/") + 1);
}

/** A client page from its Firestore REST document. */
export function decodePage(document) {
  const fields = decodeFields(document.fields ?? {});
  return {
    companyName: textOrNull(fields.companyName),
    clientName: textOrNull(fields.clientName) ?? "",
  };
}

/** A report from its Firestore REST document. */
export function decodeReport(document) {
  const fields = decodeFields(document.fields ?? {});
  const zones = Array.isArray(fields.zones) ? fields.zones : [];
  return {
    visitId: idOf(document),
    visitDate: textOrNull(fields.visitDate) ?? "",
    publishedAt: textOrNull(fields.publishedAt) ?? "",
    zones: zones
      .filter((zone) => zone !== null && typeof zone === "object")
      .map((zone) => ({
        name: textOrNull(zone.name) ?? "",
        note: textOrNull(zone.note) ?? "",
        beforePhoto: textOrNull(zone.beforePhoto),
        afterPhoto: textOrNull(zone.afterPhoto),
      })),
  };
}

function textOrNull(value) {
  return typeof value === "string" ? value : null;
}
