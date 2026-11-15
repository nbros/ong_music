#!/usr/bin/env bash
# Builds the JS module `ongVods` (tool/vods_js/ong_vods.dart: the app's own code for the VODs and their offsets) for
# the tool of the offsets of the browser extension:
#
#   tool/build_vods_js.sh <output file>
#
# One file, optimised (dart2js -O2), without source map: a classic script that needs no DOM and uses neither `eval`
# nor `new Function`, and that only defines `globalThis.ongVods` when it loads. Its `version` is the commit it was
# built from (`-dirty` when the checkout had changes), and the time of the build in UTC.
#
# Check it with tool/vods_js_test.sh (under Node).
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: tool/build_vods_js.sh <output file>" >&2
  exit 64
fi
output=$1
case $output in
  /*) ;;
  *) output="$PWD/$output" ;;
esac

cd "$(dirname "$0")/.."

commit=$(git rev-parse --short=12 HEAD)
if [[ -n $(git status --porcelain) ]]; then
  commit="${commit}-dirty"
fi
version="${commit} $(date -u +%Y-%m-%dT%H:%M:%SZ)"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

dart compile js -O2 --no-source-maps "-DONG_VODS_VERSION=${version}" -o "$work/ong_vods.js" tool/vods_js/ong_vods.dart

# what the file must not hold to run in an extension page, a content script or a service worker of Manifest V3
if grep -E -q '\beval\(|new Function\b|\bFunction\(' "$work/ong_vods.js"; then
  echo "build_vods_js.sh: the built file calls eval or new Function" >&2
  exit 1
fi

mkdir -p "$(dirname "$output")"
{
  echo "// ongVods ${version}: built by tool/build_vods_js.sh of ong_music from tool/vods_js/ong_vods.dart. Do not edit."
  cat "$work/ong_vods.js"
} > "$output.tmp"
mv "$output.tmp" "$output"
echo "ongVods ${version}: $output ($(wc -c < "$output" | tr -d ' ') bytes)"
