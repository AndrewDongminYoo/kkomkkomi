# In-app Still Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The operator chose a single coordinator and approved implementation continuation; do not ask again about the accepted contract or dispatch a review fleet.

**Goal:** Complete the #61 camera producer with one mobile still capture and its directly observed shutter-request time.

**Architecture:** A presentation driver owns the Flutter camera plugin, a camera Cubit owns each session and lifecycle, and a route adapter implements the existing observed-capture port. App wires its mobile default lazily; bootstrap still uses the existing picker for Android recovery. The visit persists observed UTC only with a successful photo save.

**Tech Stack:** Flutter, bloc, camera 0.12.1, existing image/image_picker and SQLite version 8.

**Spec:** `docs/specs/2026-10-07-in-app-still-camera.md`, written camera contract approved by the operator on 2026-10-07.

## Global Constraints

- Preserve PRs #74/#76/#77/#78; base camera code on #78 and use a separate draft PR. No merge, deployment, purchase or store action.
- Mobile targets: Android/iOS. Existing resolved Android minimum is 24 and iOS deployment target is 15; do not raise either. Keep Windows CI passing.
- Rear camera only, one still per existing slot, immediate return/save. No video/audio/editing, wider M2 feature or report ratio change.
- Observe `Clock.now().toUtc()` immediately before shutter-request dispatch; never use completion, picker, file, Exif or restart time.
- Longest edge at most 1600 pixels, JPEG quality 80, visible orientation and whole image preserved; sanitize through `withoutLocation`.
- Camera access only when opening the preview; audio false and no microphone/legacy external-storage permission.
- Use `material_ui`, `KeepAllText`, Korean/English ARB copy and existing page/view/Cubit patterns.
- Unit/CI evidence and real iOS/Android acceptance remain distinct. #61 stays open until integrated device/output acceptance exists.

## Review Focus

- The permission prompt itself backgrounds the app: first permission grant must still produce a ready preview (Task 3).
- Cancellation while initialization/capture/normalization is pending: late answers never save a photo/time or reopen a route (Task 3).
- Stale Android picker data when a new in-app session is interrupted: no new picker intent is written for in-app camera (Task 1).
- A large rotated JPEG from a device: normalize orientation/size before saving and retain the whole image (Task 2).
- A retry or a replaced gallery photo: clock belongs to the successful request, and gallery replacement clears time (Tasks 3/4).

## Task 1: Separate external-picker recovery from in-app sessions

**Files:** Modify `lib/presentation/visit_capture/cubit/visit_capture_cubit.dart`; test `test/presentation/visit_capture/cubit/visit_capture_cubit_test.dart`.

**Interfaces:** Consume existing `InAppPhotoCapture`, `PhotoSource.camera` and `OpenCaptureRepository.clear/save`. Produce unchanged `capturePhoto(String zoneId, PhotoSlot slot, {PhotoSource source})`, with in-app preparation clearing the prior picker intent and gallery preparation retaining it.

- [x] Write tests proving no intent exists while an observed capture waits, a failed clear prevents capture and preserves the record, and gallery through a composite adapter still stores the gallery intent.
- [x] Run `flutter test test/presentation/visit_capture/cubit/visit_capture_cubit_test.dart`; expect new behavioral assertions to fail on current unconditional intent storage.
- [x] Change preparation only: clear for observed camera, save source-bearing intent for picker; preserve newest-save ordering and existing failure status.
- [x] Run the capture Cubit and lost-recovery test files; expect all passing, then commit.

## Task 2: Normalize camera files without weakening existing image boundaries

**Files:** Create `lib/presentation/still_camera/camera_photo_files.dart`; tests `test/presentation/still_camera/camera_photo_files_test.dart`.

**Interfaces:** `Uint8List normalizeCameraJpeg(Uint8List bytes)` returns sanitized oriented JPEG. `CameraPhotoFiles` defines `Future<String> normalize(String sourcePath)` and `Future<void> discard(String path)`; `TemporaryCameraPhotoFiles` owns new camera temporary files.

- [x] Write real-byte/file tests for rotated/large JPEG, size 1600, malformed/non-JPEG refusal, metadata absence, successful temporary output and failed/late-result cleanup.
- [x] Run the file tests, observe missing-feature then behavioral RED.
- [x] Implement decode/orient/resize/quality-80 encode/sanitize using `image`; normalize only known camera files and make cleanup safe for a missing owned file.
- [x] Run these tests and existing photo-store/sanitation tests; expect passing, then commit.

## Task 3: Driver, session lifecycle and preview

**Files:** Create `lib/presentation/adapters/camera_driver.dart`; `lib/presentation/still_camera/still_camera.dart`, `cubit/still_camera_cubit.dart`, `cubit/still_camera_state.dart`, `view/still_camera_page.dart`; mirror tests under `test/presentation/`. Modify `pubspec.yaml`, lockfile and both ARB files.

**Interfaces:** `StillCameraDriver` defines `Future<void> initialize()`, `Widget preview()`, `Future<String> takePicture()`, `Future<void> dispose()`. `CameraDriver` is its plugin adapter. `StillCameraCubit({required StillCameraDriver Function() driverFactory, required CameraPhotoFiles files, required Clock clock})` exposes `Future<void> start()`, `void setForeground({required bool foreground})`, `Future<void> capture()`, `Future<void> cancel()` and closes resources. Its terminal state holds either `ObservedCameraPhoto`, `PhotoCaptureException` or cancellation. `StillCameraPage.route` returns an `Object?` route result; failures are typed exceptions consumed by the route adapter.

- [x] Add the approved camera dependency and a directly declared test platform-interface dependency; resolve packages and verify SDK compatibility without changing minimum versions.
- [x] Write fake-platform driver tests for rear-camera selection, audio false, no rear camera, permission mapping, preview, capture, initialization failure and disposal.
- [x] Write controlled session tests for request-time vs delayed completion, one operation, cancellation, foreground loss/resume, first permission grant, late initialization/capture/normalization, failures, retries and cleanup/disposal.
- [x] Run each test group RED before implementing its component.
- [x] Implement the driver behind one plugin import boundary, session generations and serialized controller lifetime; return only successful normalized results from the still-current session.
- [x] Write widget tests for ready-only shutter, title/close semantics, back/cancel, success/failure results, lifecycle forwarding and narrow/largest-text layout; observe RED, then implement page/view using the existing theme and localization conventions.
- [x] Run the driver/session/view tests; expect all passing, then commit.

## Task 4: Wire the mobile default and camera-only permissions

**Files:** Create `lib/presentation/adapters/in_app_camera_photo_capture.dart`; modify `lib/app/view/app.dart`, `lib/presentation/presentation.dart`, Android main manifest, accurate camera usage strings, both privacy pages, `CLAUDE.md` and `CHANGELOG.md`. Tests: adapter tests, `test/app/view/app_test.dart`, an App-to-visit camera integration test and existing privacy tests.

**Interfaces:** `InAppCameraPhotoCapture({required Future<Object?> Function() openCamera, required PhotoCapture picker})` implements `InAppPhotoCapture`; camera route results become observations/errors, and gallery/lost retrieval delegate to picker. `App` preserves explicit capture injection and owns stable navigator wiring; new injectable driver/files dependencies are ordinary runtime interfaces used by tests. Bootstrap remains picker-only for startup recovery.

- [x] Write adapter/App tests for mobile default, no startup camera calls, unsupported-platform fallback, explicit injected capture preservation, gallery/recovery delegation and exception propagation; observe RED.
- [x] Implement stable mobile route wiring and retain the existing adapter on unsupported platforms.
- [x] Write an integration test that opens a slot, captures through the real route/adapter with a fake driver and controlled clock, reloads the saved record and checks observed UTC; replacing through gallery must clear time. Observe RED before finishing wiring.
- [x] Apply camera-only permission merges; remove audio/legacy-storage declarations and make camera hardware optional. Update purpose text and both privacy pages to describe actual behavior.
- [x] Run `merry run check`, `merry run coverage`, Trunk and development Android/iOS builds/manifest inspection as available. Expect clean repository checks, 100% coverage and compatible builds. Record any real-device gap explicitly; then commit.

## Task 5: Draft delivery and bounded review

- [ ] Publish a new draft PR linked to #61, documenting the dependency on #78 and approved request-observation semantics. Keep existing PRs intact.
- [ ] Read every required check on the exact final head; await terminal CI. Inspect paginated review threads and obtain one independent whole-branch review with at most one subsequent fix/review round as justified.
- [ ] For valid material findings, reproduce RED, fix, run affected/full gates and verify the new final head. Do not merge, deploy or close #61 based on a draft or unit tests.
- [ ] Report PR/commits, exact tests/CI/review evidence, remaining iOS/Android device gates and any genuine new scope blocker.

## Local implementation evidence

- Tasks 1–4 are implemented in the isolated camera branch, based on #78. Recovery, image, driver/session, UI and App adapter changes were exercised with behavioral RED/GREEN tests.
- Final Flutter suite: 1,741 tests. Web suite: 81 tests. Imported-library coverage: 100%, 4,009 of 4,009 lines. Format, analysis and Bloc lint pass.
- Development debug Android APK and unsigned development iOS app build. Merged Android manifest has CAMERA, no microphone/read/write storage permission, optional camera hardware and minSdk 24. Built iOS app retains target 15.0 and localized camera/gallery purpose strings with no microphone-purpose key.
- Initial merged-manifest checks exposed implied storage permission and required camera hardware; both were corrected and rebuilt. Session regressions also prevent obsolete initialization disposal failures from opening another controller and prevent a permission denial from triggering an automatic retry after lifecycle transitions.
- Real iOS/Android permission, capture, interruption, orientation and output acceptance remains pending. Task 5 delivery/review/CI results are recorded on the Draft PR and in the coordinator's local progress ledger; no merge or deployment is authorized here.

### Review repair 1

The independent review identified two camera-scope issues. Android CAMERA permission still implied a required rear camera despite the optional camera.any feature; explicit optional camera and autofocus features now remove that filter, verified in the rebuilt APK and merged manifest. An obsolete non-permission initialization error also terminated the resumed session; it now yields to queued resume after releasing the old driver. Access denial and release failure remain terminal, and cancellation ignores late initialization failure. Both findings were reproduced before repair. Full checks, 100% coverage and both development native builds passed after the repair.
