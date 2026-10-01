#!/usr/bin/env bash
# Renders the legacy Android launcher images from the launcher-*.svg pictures in this directory.
#
# Usage: CHROME=/path/to/chrome-headless-shell tool/app_icon/render.sh
#
# CHROME is a headless Chromium binary.
#
# symbol.svg is the master of the mark. These files hold a copy of its two paths,
# so a change to the mark must be repeated in each of them:
#   tool/app_icon/launcher-*.svg
#   android/app/src/*/res/drawable/ic_launcher_foreground.xml
#   ios/Runner/AppIcons/*.icon/Assets/Logo.svg
#   macos/AppIcons/*.icon/Assets/Logo.svg
#   tool/web_assets/icon.html and tool/web_assets/og.html
#   web/index.html (the header mark, the footer mark, and the icon link)
set -euo pipefail

: "${CHROME:?Set CHROME to a headless Chromium binary, for example chrome-headless-shell.}"

here="$(cd "$(dirname "$0")" && pwd)"
res="$(cd "${here}/../../android/app/src" && pwd)"

# render <source set>,<shape> <output> <size>
render() {
  "${CHROME}" --headless --hide-scrollbars --virtual-time-budget=4000 \
    --force-device-scale-factor=1 --default-background-color=00000000 \
    --window-size="$3,$3" --screenshot="$2" "file://${here}/legacy.html#$1"
}

for flavor in main development staging; do
  for density in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    dir="${res}/${flavor}/res/mipmap-${density%%:*}"
    size="${density##*:}"
    render "${flavor},square" "${dir}/ic_launcher.png" "${size}"
    render "${flavor},round" "${dir}/ic_launcher_round.png" "${size}"
  done
done
