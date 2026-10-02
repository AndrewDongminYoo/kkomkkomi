# Brief: issue #7, recover a photo after Android destroys the app

Read `CLAUDE.md`, issue #7, and the decision list of pull request 6 before you write code.

## Decisions taken for the operator

The operator asked to continue without stopping, so these defaults apply. The pull request body repeats them.

- Repair this in M1. Issue #7 offers to wait for the camera preview of M2, which removes the camera app from the flow. M2 starts only after real use of M1, and a photo lost during that use falls on the evaluation itself, so the wait comes too late.
- After the restart, the app opens the visit that the capture belonged to, with the recovered photo in its slot.

## Step 1: confirm the plugin contract

Read the `image_picker` README and the plugin source of the version in `pubspec.lock`.
Confirm, with a citation in the pull request body:

- that `retrieveLostData` is for Android only, and what it returns on other platforms;
- when the app must call it, relative to startup;
- what it returns when the lost result was a cancel or an error.

Do not rely on memory for any of these.

## In scope

- A stored record of the open capture (visit, zone, and slot), written before the camera opens and removed when the capture ends in any way.
- A step at startup that, when a record exists, calls `retrieveLostData` through the photo capture port, keeps the file with `PhotoStore`, saves the visit with it, removes the record, and opens that visit.
- A record that points at a visit or zone that no longer exists is removed with no other effect.
- Tests through fake ports. No test touches a platform channel.

## Out of scope

- The camera preview of M2.
- iOS, where the system does not destroy the app in this way. Confirm that in step 1.

## Requirements

- If the stored record needs a schema change, add it as a migration from the current version, with a test that upgrades a database file of that version.
- Every user-facing string goes in both ARB files, in the `warm` voice. Load the `user-facing-copy` skill first.

## Acceptance criteria

- `merry run check` and `merry run coverage` pass.
- The pull request closes issue #7.
- The pull request body states that the recovery was not run on a device.
