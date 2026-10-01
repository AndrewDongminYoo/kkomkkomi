# M1 brief 5: Firebase startup and anonymous sign-in

Design: `docs/specs/2026-10-01-m1-local-first-design.md`, section "Phase B".
Read the design and `CLAUDE.md` before you write code.
This brief depends on brief 1, which must be merged first.

## Goal

The production flavor starts Firebase and signs in anonymously, and the other flavors run without Firebase.

## In scope

- Add `firebase_core` and `firebase_auth`.
- An identity port in `lib/application/` that returns the current user ID or reports that identity is unavailable.
- A Firebase adapter for that port, used by `lib/main_production.dart` only.
- An adapter that reports "unavailable", used by the development and staging entry points.
- Startup failure handling: when Firebase fails to start or sign-in fails, the app still opens and the local flow still works.

## Out of scope

- Firestore, Storage, publishing, and security rules.
- Any screen change.
- Account linking.

## Requirements

- Tracked code must not import `lib/firebase_options.dart`. Call `Firebase.initializeApp()` without options.
- Exactly one directory under `lib/` imports a `firebase_*` package, and a test fails when another directory imports one.
- No test starts Firebase. Tests use a fake identity port.
- Regenerate `pubspec.lock` in the same commit as the `pubspec.yaml` change.
- The Windows job in CI must stay green. If a Firebase plugin breaks the Windows build, stop and report it. Do not remove the Windows job.
- Do not run a platform build locally.

## Acceptance criteria

- Tests cover the production wiring through a fake, the "unavailable" adapter, and each startup failure path.
- `merry run check` passes.
- `merry run coverage` passes at 100 percent.
- `CLAUDE.md` states which flavor starts Firebase and which directory may import Firebase packages.
