# Project Agent Guide

Read `CLAUDE.md` for this project's development and release rules. Where this file and `CLAUDE.md` differ, `CLAUDE.md` holds.

## Store Uploads

Use the root `./store-upload` entrypoint and `store-upload.json` for binary and listing uploads.
Read `docs/notes/store-upload.md` before planning or executing a transfer.
Reuse existing project build and release gates; do not substitute a generic upload for a guarded native lane.
Every upload, of a binary or of a listing, is an external action that the operator runs or approves for that run, as `CLAUDE.md` says. A request to add or fix the pipeline does not authorize live uploads, review submission, or public release.
With that approval, inspect the offline plan, execute with its digest and a new receipt, and read back the exact remote build or asset slots.
For an asset slot that the lanes do not support, use the account-scoped API or browser route of the shared `store-upload` skill after that approval, instead of asking the operator to upload the file by hand.
Preserve authentication, permission, and processing failures and resume automation after the specific blocker is resolved.
