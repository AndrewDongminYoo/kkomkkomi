#!/usr/bin/env bash
# Renders every store image from the repository, then checks them with check.sh:
#   1. the fixture photos under photos/, from photos.html;
#   2. the raw screens under build/store_screenshots/raw/, from render_screens.dart;
#   3. the framed screenshots, from frame.html and copy.js, into fastlane/screenshots/ios/<locale>/ (1320x2868) and
#      fastlane/metadata/android/<locale>/images/phoneScreenshots/ (1080x1920);
#   4. the Play feature graphic, from feature.html, into fastlane/metadata/android/<locale>/images/featureGraphic.png.
#
# Usage: CHROME=/path/to/chrome-headless-shell tool/store_screenshots/render.sh
#
# CHROME is a headless Chromium binary. The frames load their font from Google Fonts, so the render needs a network
# connection. It also needs Flutter and ImageMagick 7.
set -euo pipefail
shopt -s nullglob

: "${CHROME:?Set CHROME to a headless Chromium binary, for example chrome-headless-shell.}"
command -v magick >/dev/null || {
  echo "render.sh needs ImageMagick 7 (magick)." >&2
  exit 1
}

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
raw="${root}/build/store_screenshots/raw"
work="${root}/build/store_screenshots/work"
rm -rf "${raw}" "${work}"
mkdir -p "${work}"

# shoot <page and query> <output> <width> <height>
shoot() {
  "${CHROME}" --headless --hide-scrollbars --virtual-time-budget=8000 \
    --force-device-scale-factor=1 --window-size="$3,$4" \
    --screenshot="$2" "file://${here}/$1" 2>>"${work}/chrome.log" >/dev/null
  [[ -f "$2" ]] || {
    echo "Chromium wrote no image for $1; see ${work}/chrome.log." >&2
    exit 1
  }
}

# opaque <input> <output>: a Chromium screenshot can carry an alpha channel, and the stores refuse one.
opaque() {
  magick "$1" -background '#faf7f1' -alpha remove -alpha off "PNG24:$2"
}

echo "Fixture photos"
for scene in entrance pantry restroom; do
  for state in before after; do
    shoot "photos.html?scene=${scene}&state=${state}" "${work}/photo.png" 900 1200
    magick "${work}/photo.png" -strip -quality 85 "${here}/photos/${scene}-${state}.jpg"
    rm "${work}/photo.png"
  done
done

echo "Raw screens"
(cd "${root}" && flutter test tool/store_screenshots/render_screens.dart)

# frame <platform> <language> <output directory> <width> <height>
frame() {
  local screens=("${raw}/$1/$2/"*.png)
  if ((${#screens[@]} == 0)); then
    echo "No raw screens in ${raw}/$1/$2." >&2
    exit 1
  fi
  mkdir -p "$3"
  rm -f "$3/"*.png
  local screen name
  for screen in "${screens[@]}"; do
    name="$(basename "${screen}" .png)"
    shoot "frame.html?screen=${name}&lang=$2&image=file://${screen}" "${work}/frame.png" "$4" "$5"
    opaque "${work}/frame.png" "$3/${name}.png"
    rm "${work}/frame.png"
  done
}

echo "Frames"
frame ios ko "${root}/fastlane/screenshots/ios/ko" 1320 2868
frame ios en "${root}/fastlane/screenshots/ios/en-US" 1320 2868
frame android ko "${root}/fastlane/metadata/android/ko-KR/images/phoneScreenshots" 1080 1920
frame android en "${root}/fastlane/metadata/android/en-US/images/phoneScreenshots" 1080 1920

echo "Feature graphics"
for pair in ko:ko-KR en:en-US; do
  shoot "feature.html?lang=${pair%%:*}" "${work}/feature.png" 1024 500
  opaque "${work}/feature.png" "${root}/fastlane/metadata/android/${pair#*:}/images/featureGraphic.png"
  rm "${work}/feature.png"
done

echo "Check"
"${here}/check.sh" "${root}"
