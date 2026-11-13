#!/usr/bin/env bash
# The tests that run in a browser (Chrome): `tool/browser_tests.sh`, then `tool/browser_tests.sh --wasm`.
#
# The site holds the app twice (`flutter build web --wasm`, see web/flutter_bootstrap.js), so they run twice:
# compiled to JavaScript (by the development compiler, not dart2js which builds the site: the same JavaScript
# numbers and browser APIs) and, with --wasm, to WebAssembly.
#
# Run by both workflows (flutter_ci.yml, and pages.yml before it deploys the site). Arguments go to `flutter test`.
set -euo pipefail
cd "$(dirname "$0")/.."

tests=(
  # what only runs in a browser: the web cache, the download the page starts, the catalogue loaded in slices, the
  # player, the links, the address and the history, full screen
  test/*_web_test.dart
  # what reads numbers in the sheets and in the calendar: integers are JavaScript numbers in one build and 64-bit in
  # the other (and on the VM, where `flutter test` runs them)
  test/parser_test.dart
  test/schedule_test.dart
  test/text_test.dart
)

flutter test --platform chrome "$@" "${tests[@]}"
