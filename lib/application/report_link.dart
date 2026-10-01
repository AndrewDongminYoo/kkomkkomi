/// The origin of the Firebase Hosting site that serves the web report page.
const reportSiteOrigin = 'https://kkomkkomi.web.app';

/// The link that opens the report of the visit with [visitId] under the client page with [pageId].
///
/// `firebase.json` rewrites every path under `/r/` to the report page. The page shows the report at
/// `/r/<pageId>/<visitId>` and the list of the reports of the client page at `/r/<pageId>`.
Uri reportLinkOf({required String pageId, required String visitId}) =>
    Uri.parse('$reportSiteOrigin/r/${Uri.encodeComponent(pageId)}/${Uri.encodeComponent(visitId)}');
