# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Nullable observed in-app camera times for PDF/preview captions; picker, gallery and old photos have no capture time.

- Gallery selection for before/after photos, with gallery captions in the preview, PDF and web report.

- An optional business phone in the company profile, report preview and PDF, kept out of public web reports.

## [1.1.0] - 2026-10-07

The second test distribution: TestFlight and the Google Play internal testing track, build 3.
It holds every change after the 1.0.0 entry.

### Added

- A status for each zone of a visit: done, partly done, or not done, with what is left or why for a zone that is not done. The first page of the report counts the done zones and lists each zone that is not done with its reason, and the PDF, the preview, and the web report show the status after the name of the zone.
- Basic and Pro subscriptions, monthly or annual, from a plans screen that also restores purchases and opens the subscription management of the store.
- The Free plan holds up to 2 active clients. A paid plan leaves the "꼼꼬미로 작성됨" line out of the PDF and the web report.
- Close Link and Make New Link on the client screen, which close the report link of one client or replace it.
- Delete All Data on the company profile screen, which deletes what the app published, the anonymous account, and the data on the phone.
- The client name above the visit date on the visit screen.

### Changed

- A new layout of the completion report PDF, with Bold headings and square photo slots that show the whole photo. The preview of the report screen shows the same slots.
- The app has its own colors, and Korean text breaks between words, not inside a word.

### Fixed

- A stored, uploaded, or printed photo no longer keeps the location that the camera app recorded.
- A link whose deletion stopped part of the way, in Delete All Data, is deleted again at the next Delete All Data.

### Internal

- Store screenshots and the Play feature graphic are rendered from the app screens.

## [1.0.0] - 2026-10-02

The first test distribution: TestFlight and the Google Play internal testing track, build 1.

### Added

- A client list, with a detail screen per client to rename it, archive it, and keep its list of zones.
- Visits: start a visit on a date, take a paired before and after photo of each zone, and add a note to each zone. The next visit starts with the same zones and shows the photos of the last visit.
- A company profile whose name goes at the top of each report.
- A report screen that previews the cleaning report and shares it as a PDF through the share sheet of the phone.
- A link share: the app uploads the report and then shares a link to it. The link opens the report on a web page without an app or a sign-in, and a link below the report opens the earlier shared reports of the same client.
- Uploads that start again when the network comes back, and that resume after the app restarts.
- Recovery of a photo when Android closes the app while the camera app is open.
- Camera and photo library usage descriptions in Korean and English on iOS.
- A privacy policy page in Korean and English, linked from the footer of the web report page.
