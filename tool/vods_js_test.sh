#!/usr/bin/env bash
# The test of the JS module `ongVods` (tool/build_vods_js.sh) under Node: builds it, has the Dart VM make every call
# of the test with the app's code (tool/vods_js/expected.dart), makes them again on the built file in a context
# without DOM (tool/vods_js/test.cjs), and compares.
#
#   tool/vods_js_test.sh [<songs.csv> <highlights.csv> <vods.tsv> [<offsets.tsv>]]
#
# The small fixtures of tool/vods_js/fixtures always; with the real sheets (gviz CSV exports) and the files of the
# branch data, also `load` and `overview` on them and `stream` for the first part of every VOD, with their times.
# ONG_VODS_JS=<file> tests that built file instead of building one. Needs Node (18 or later) and the Dart SDK.
set -euo pipefail

args=()
for arg in "$@"; do
  case $arg in
    /*) args+=("$arg") ;;
    *) args+=("$PWD/$arg") ;;
  esac
done
js=${ONG_VODS_JS:-}
if [[ -n $js && $js != /* ]]; then
  js="$PWD/$js"
fi

cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [[ -z $js ]]; then
  js="$work/ong_vods.js"
  tool/build_vods_js.sh "$js"
fi
dart run tool/vods_js/expected.dart tool/vods_js/fixtures ${args[@]+"${args[@]}"} > "$work/expected.json"
node tool/vods_js/test.cjs "$js" "$work/expected.json"
