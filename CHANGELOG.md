# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
