#!/usr/bin/env bash
# Renders the images of the app icon from the launcher-*.svg pictures in this directory:
# the legacy Android launcher images, the Play Store icons, the launch images of iOS and macOS, and the Windows icon.
#
# Usage: CHROME=/path/to/chrome-headless-shell tool/app_icon/render.sh
#
# CHROME is a headless Chromium binary. The Windows icon also needs python3.
#
# symbol.svg is the master of the mark: the double consonant of the name as a pair of matching strokes.
# The left stroke is the before photo and the right stroke is the after photo.
# On the brand color #0f7f7a the right stroke is #ffffff and the left stroke is #87bfbd.
# The left stroke has a solid color, because Icon Composer drew a stroke with fill-opacity as opaque.
# The format hook strips the comments of an SVG file, so this description is here.
#
# These files hold a copy of the two paths of the mark, so a change to the mark must be repeated in each of them:
#   tool/app_icon/launcher-*.svg
#   android/app/src/*/res/drawable/ic_launcher_foreground.xml
#   android/app/src/main/res/drawable/ic_launch_image.xml
#   ios/Runner/AppIcons/*.icon/Assets/Logo.svg
#   macos/AppIcons/*.icon/Assets/Logo.svg
#   tool/web_assets/icon.html and tool/web_assets/og.html
#   web/index.html (the header mark, the footer mark, and the icon link)
set -euo pipefail

: "${CHROME:?Set CHROME to a headless Chromium binary, for example chrome-headless-shell.}"

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
res="${root}/android/app/src"

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

# The Play Store icon of each source set, 512 pixels, as a full square in a 32-bit PNG, which Google Play asks for
# (https://developer.android.com/distribute/google-play/resources/icon-design-specifications).
for flavor in main development staging; do
  render "${flavor},full" "${res}/${flavor}/ic_launcher-playstore.png" 512
done

# The launch image is the square picture of the main source set, 150 points wide.
# macOS has no launch screen, and its image set of the same name holds the same images.
for scale in 1 2 3; do
  image="${root}/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@${scale}x.png"
  render "main,square" "${image}" "$((150 * scale))"
  cp "${image}" "${root}/macos/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@${scale}x.png"
done

# The Windows icon holds the square picture of the main source set at six sizes.
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT
images=()
for size in 16 24 32 48 64 256; do
  render "main,square" "${scratch}/${size}.png" "${size}"
  images+=("${scratch}/${size}.png")
done
python3 "${here}/ico.py" "${root}/windows/runner/resources/app_icon.ico" "${images[@]}"
