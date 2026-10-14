# Project Agent Guide

Read `CLAUDE.md` for this project's development and release rules. Where this file and `CLAUDE.md` differ, `CLAUDE.md` holds.

## Store Uploads

`store-upload.json` is the offline profile of the personal `app-store-assets` runtime, which the `tools/app-store-assets` submodule pins.
The `export_store_snapshot` lane reads the App Store Connect state of its iOS target, and the offline `doctor` and `plan` commands of that runtime check the profile and plan a listing change without a store call; `CLAUDE.md`, section "Release", gives the commands.
No command of the runtime uploads yet.
Reuse existing project build and release gates; do not substitute a generic upload for a guarded native lane.
Every upload, deletion, or review submission, of a binary or of a listing, is an external action that the operator runs or approves for that run, as `CLAUDE.md` says. A request to add or fix the pipeline does not authorize live uploads, review submission, or public release.
Preserve authentication, permission, and processing failures and resume automation after the specific blocker is resolved.
