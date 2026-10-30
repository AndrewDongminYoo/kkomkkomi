# iPhone gallery acceptance (#82)

## Scope and evidence

On 2026-10-30 the operator reported the results below on the physical iPhone 16 Pro after the new development app was installed.
The app was built from `a2cf0b334480774a3c28f821f4a81457bddcd505` plus the iOS native pin regeneration described below; the other uncommitted changes were acceptance documentation.
The [metadata spec](../specs/2026-10-07-report-photo-and-company-metadata.md) owns gallery behavior, and the [device acceptance spec](../specs/2026-10-30-gallery-device-acceptance.md) bounds this pass.

| Property        | Tested value                                                  |
| --------------- | ------------------------------------------------------------- |
| Device          | Physical iPhone 16 Pro                                        |
| OS              | iOS 27.0.1, read with `devicectl`                             |
| App             | `[DEV] Kkomkkomi`, `kr.donminzzi.kkomkkomi.dev`, `1.1.1+5`    |
| Build           | Release mode, development flavor, `lib/main_development.dart` |
| Local toolchain | Flutter 3.47.9, Dart 3.13.7                                   |
| CI toolchain    | Flutter 3.47.8; distinct from this device build               |
| Picker          | `image_picker` 1.2.4; iOS implementation 0.8.13+13            |

The preserved build passed code-signature verification and a file-hash comparison before its approved installation over the existing DEV app.
The installation succeeded, and a subsequent device query confirmed the bundle identifier and `1.1.1+5`.
The agent did not launch the app, import photos, uninstall an app or perform a production operation.
The observations below are operator-reported physical results, not agent screen captures.

## Prepared inputs

The non-private synthetic image has a yellow top-left marker, teal upper half, red lower-left region and pale lower-right region.
macOS `sips` encoded JPEG, PNG and HEIC copies at 1200 by 800 pixels, and `sips` and `file` identified each format before transfer.
The HEIC is a macOS-encoded sample, not an iPhone camera original.

| Input             | SHA-256 of prepared file                                           |
| ----------------- | ------------------------------------------------------------------ |
| `gallery-82.jpg`  | `cb0ccae6686995ed224e66bf4af49830c138095c4b162ca2d09381f7bbe82d95` |
| `gallery-82.png`  | `796e1a3afb80b35c54e0c301d69e7e74bd6546e42147460a7298e1a0785ce74e` |
| `gallery-82.heic` | `ca520df7528c78376f9990547cb33c6e7c8461a0ad535f57af29f5f66ba4e804` |

No on-device original-format inspection, picker-return bytes or stored-file bytes were captured.
The prepared source formats and the operator's successful selection report do not establish the encoding at every step of Photos import or native conversion.

## Operator observations

| Scenario                            | Reported result                                                                      |
| ----------------------------------- | ------------------------------------------------------------------------------------ |
| JPEG, PNG and HEIC source selection | All three worked normally                                                            |
| Source label                        | All three showed the existing gallery-source label                                   |
| Capture time                        | Not displayed for any of the three; the operator also reported no camera information |
| Cancel replacement                  | Previous photo remained                                                              |
| Leave and reopen the visit          | Photo remained                                                                       |

No app conversion change is justified by these successful cases alone.
The observed pass covers these inputs on this iPhone and build, not all HEIC variants or other devices.

## Automated and native checks

The focused picker, real photo-store, visit capture Cubit and visit capture view tests passed.
They check mocked picker arguments and errors, JPEG/PNG fixture processing, preservation and rendered notices; they do not prove physical HEIC conversion.
`flutter analyze --no-pub` and `dart format --output=none --set-exit-if-changed lib test` passed.
Development debug and release builds succeeded, and the preserved release artifact passed `codesign --verify --deep --strict`.

The iOS resolver regenerated both tracked `Package.resolved` files to match the existing `purchases_flutter` 11.0.0 upgrade: `purchases-hybrid-common` 20.0.0 and `purchases-ios-spm` 5.99.0.
The plugin's `Package.swift` requires the former exactly, and that package requires the latter exactly.
The project-level and workspace-level iOS files match.
No Dart dependency manifest, application behavior or native build setting changed for this pass.

## Remaining acceptance

- Android physical picking remains not run: the operator has no Android phone.
- Unsupported-input rejection, its physical failure notice and previous-photo preservation after rejection remain not observed; cancellation is separate evidence.
- Sensor-origin HEIC, other HEIC variants, on-device encodings, visible-orientation inspection and actual PDF/web output are not established by this report.
- Issue #82 stays open for its remaining physical acceptance and conversion decision.
- This pass authorizes no store upload, production deployment or public release.
