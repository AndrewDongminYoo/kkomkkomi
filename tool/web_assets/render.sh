#!/usr/bin/env bash
# Renders web/og.png and the two icons under web/icons/ from the cards in this directory.
#
# Usage: CHROME=/path/to/chrome-headless-shell tool/web_assets/render.sh
#
# CHROME is a headless Chromium binary. The card loads its font from Google Fonts,
# so the render needs a network connection.
set -euo pipefail

: "${CHROME:?Set CHROME to a headless Chromium binary, for example chrome-headless-shell.}"

here="$(cd "$(dirname "$0")" && pwd)"
web="$(cd "${here}/../../web" && pwd)"

# render <card> <output> <width> <height>
render() {
  "${CHROME}" --headless --hide-scrollbars --virtual-time-budget=8000 \
    --force-device-scale-factor=1 --window-size="$3,$4" \
    --screenshot="$2" "file://${here}/$1"
}

render og.html "${web}/og.png" 1200 630
render icon.html "${web}/icons/Icon-192.png" 192 192
render icon.html "${web}/icons/Icon-512.png" 512 512
