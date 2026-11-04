# Project Agent Guide

Read `CLAUDE.md` for this project's development and release rules. Where this file and `CLAUDE.md` differ, `CLAUDE.md` holds.

## Store Uploads

`store-upload.json` is the offline profile of the personal `app-store-assets` runtime, which the `tools/app-store-assets` submodule pins.
The `export_store_snapshot` lane reads the App Store Connect state of its iOS target, and the offline `doctor` and `plan` commands of that runtime check the profile and plan a listing change without a store call; the commands follow below.
The pinned runtime also exposes `AppStoreAssets.transfer_screenshots`, which requires an exact plan, a separate approval record, live state checks, and an exclusive writer window.
The legacy screenshot metadata lane still loads `APP_STORE_ASSETS_ROOT` or a sibling checkout; this submodule pin does not protect that route.
Use the guarded entrypoint, the `store_screenshots_verify` and `store_screenshots_transfer` lanes, for an approved screenshot transfer.
Reuse existing project build and release gates; do not substitute a generic upload for a guarded native lane.
Every upload, deletion, or review submission, of a binary or of a listing, is an external action that the user runs or approves for that run, as `CLAUDE.md` says. A request to add or fix the pipeline does not authorize live uploads, review submission, or public release.
Preserve authentication, permission, and processing failures and resume automation after the specific blocker is resolved.
From the repository root, `PYTHONPATH=tools/app-store-assets python3 -B -m app_store_assets doctor --target ios` checks the runtime pin and the inputs, and `PYTHONPATH=tools/app-store-assets python3 -B -m app_store_assets plan --target ios --operation images` writes a plan that executes nothing and needs that snapshot.
Neither command makes a store call.
The existing listing, remote and asset snapshots remain bound to `1.1.1(5)`.
A binary-only version cut does not change the target of those records or their screenshot approvals: while `pubspec.yaml` names the newer version, the offline profile's listing/image checks refuse the target mismatch until a separate listing operation regenerates its records.
The binary `beta` and Android `internal` lanes use the production version checks above and do not run that listing transfer.
Do not hand-edit the immutable snapshots or reuse their approval for a new version.
`bundle exec fastlane ios store_screenshots_verify plan:<path> approval:<path>` runs the read-only mode and `store_screenshots_transfer` with the same options runs the transfer mode, both after the pin, doctor, and pin checks of `export_store_snapshot`; the paths are relative to the repository root, and keeping the plan and the approval under `build/store-assets/` keeps them out of the bound inputs.
