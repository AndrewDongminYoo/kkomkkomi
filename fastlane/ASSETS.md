# App Store Screenshot Inputs

The iOS metadata lane reads originals from `fastlane/screenshots/ios/<locale>`.
It uses the sibling personal `app-store-assets` checkout or the absolute path in `APP_STORE_ASSETS_ROOT`.
Python 3.9 or newer and ImageMagick 7 must be available.

Validated copies live in `build/store-assets/ios-bundles/<manifest-hash>/screenshots`.
Originals remain unchanged.
Alpha channels, unsupported dimensions, damaged images, and more than ten images per locale/display class stop before credentials or upload.
The existing project generator and `tool/store_screenshots/check.sh` remain in use.

The lane passes the prepared path and `overwrite_screenshots: true`.
Fastlane replaces every screenshot set in each supplied locale, including remote classes absent locally; review the complete sets before running the lane.
Use `skip_screenshots:true` for explicit metadata-only upload.
An absent screenshot source directory retains the existing metadata-only fallback.
Do not infer capture-time build identity from the current checkout.
No real upload is part of local validation.
The README of the personal `app-store-assets` repository, which is private, describes the offline preparation and its evidence limits.
