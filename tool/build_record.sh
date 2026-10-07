#!/usr/bin/env bash
# Writes the build record that `store-upload.json` asks for before a binary upload: the commit of HEAD and the
# SHA-256 of the one file that matches the pattern. `./store-upload` then refuses a file whose record names another
# commit or another hash, so an upload never takes a file that an earlier build left behind.
#
# Usage: tool/build_record.sh <pattern> <record>
#
# A tree with uncommitted changes gets no record, because HEAD then does not name what the build holds, and the
# upload of that build stops. The `build` scripts of merry.yaml run this after each store build.
set -euo pipefail
shopt -s nullglob

pattern="$1"
record="$2"
rm -f "$record"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "build_record: the tree has uncommitted changes, so $record is not written and ./store-upload refuses this build." >&2
  exit 0
fi

# The pattern is a glob on purpose, because the name of the IPA comes from the app.
# shellcheck disable=SC2206
matches=($pattern)
if ((${#matches[@]} != 1)); then
  echo "build_record: expected one file for $pattern, found ${#matches[@]}." >&2
  exit 1
fi

checksum="$(shasum -a 256 "${matches[0]}" | cut -d ' ' -f 1)"
printf '%s %s\n' "$(git rev-parse HEAD)" "$checksum" >"$record"
echo "build_record: wrote $record for ${matches[0]}."
