#!/usr/bin/env bash
# Checks the store images: each one has its store size and no alpha channel, and each locale has the number of
# screenshots that the stores ask for. It prints the size and the channels of every image.
#
# Usage: tool/store_screenshots/check.sh [root]
#
# root is the directory that holds fastlane/, the repository root unless it is given. Needs ImageMagick 7.
set -euo pipefail
shopt -s nullglob

root="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

# check_image <file> <width> <height>
check_image() {
  local info width height channels depth color_type
  if [[ ! -f "$1" ]]; then
    fail "$1 is missing"
    return
  fi
  info="$(magick identify -format '%w %h %[channels]' "$1[0]")"
  read -r width height channels _ <<<"${info}"
  # Bytes 24 and 25 of a PNG are the bit depth and the color type of its IHDR chunk.
  read -r depth color_type <<<"$(od -An -tu1 -j24 -N2 "$1")"
  echo "${1#"${root}"/} ${width}x${height} ${channels} depth=${depth} color-type=${color_type}"
  [[ "${width}x${height}" == "$2x$3" ]] || fail "$1 is ${width}x${height}, not $2x$3"
  # srgb is three color channels without alpha; srgba has alpha, and gray is not the 24-bit color that Play asks for.
  [[ "${channels}" == "srgb" ]] || fail "$1 has the channels ${channels}, not srgb without alpha"
  # ImageMagick reads a palette PNG as srgb too, so the header must say 8-bit truecolor (color type 2): a palette
  # (3), gray (0 or 4), alpha (4 or 6), or 16-bit samples is not the 24-bit PNG without alpha that Play asks for.
  [[ "${depth}" == "8" && "${color_type}" == "2" ]] ||
    fail "$1 has the PNG bit depth ${depth} and color type ${color_type}, not 8-bit truecolor (type 2)"
}

# check_set <description> <min> <max> <width> <height> <file>...
check_set() {
  local description="$1" min="$2" max="$3" width="$4" height="$5"
  shift 5
  if (($# < min || $# > max)); then
    fail "${description} has $# images, not ${min} to ${max}"
  fi
  local file
  for file in "$@"; do
    check_image "${file}" "${width}" "${height}"
  done
}

for locale in ko en-US; do
  # App Store: 1 to 10 screenshots of the iPhone 6.9-inch size.
  check_set "iPhone ${locale}" 1 10 1320 2868 "${root}/fastlane/screenshots/ios/${locale}/"*.png
done
for locale in ko-KR en-US; do
  images="${root}/fastlane/metadata/android/${locale}/images"
  # Google Play: 2 to 8 phone screenshots, and 4 of them at 1080x1920 or larger for the recommended formats.
  check_set "Android ${locale}" 4 8 1080 1920 "${images}/phoneScreenshots/"*.png
  check_set "Feature graphic ${locale}" 1 1 1024 500 "${images}/featureGraphic.png"
done

if ((failures > 0)); then
  echo "${failures} problems in the store images" >&2
  exit 1
fi
echo "Every store image has its size and no alpha channel."
