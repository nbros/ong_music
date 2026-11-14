#!/usr/bin/env bash
# the bash -c scripts below take their values as arguments, not expanded in their text
# shellcheck disable=SC2016
# Tests of tool/sheets_snapshot.sh, offline: `bash tool/sheets_snapshot_test.sh`.
#
# make: against a local server answering each case (a good export, an error page with status 200, an export cut
# short, a sheet that shrank, a 500...): only the good ones write a snapshot. publish: into a bare repository made
# here: one orphan commit, nothing pushed when nothing changed, pushed again when a sheet changed or when the
# snapshot is a month old.
#
# The server listens on 127.0.0.1:${SNAPSHOT_TEST_PORT:-8807}. Needs bash, curl, python3, git.
set -euo pipefail
cd "$(dirname "$0")/.."
script="$PWD/tool/sheets_snapshot.sh"
port=${SNAPSHOT_TEST_PORT:-8807}
tmp=$(mktemp -d)
server_pid=''
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

passed=0
failed=0
check() { # check <name> <expected status: 0|1> <command...>
  local name=$1 expected=$2 status=0
  shift 2
  "$@" >"$tmp/out" 2>&1 || status=$?
  if [[ ($expected == 0 && $status == 0) || ($expected == 1 && $status != 0) ]]; then
    passed=$((passed + 1))
    echo "ok   $name"
  else
    failed=$((failed + 1))
    echo "FAIL $name (exit $status)"
    sed 's/^/     /' "$tmp/out"
  fi
}
expect_output() { # expect_output <name> <text>: the output of the last check holds <text>
  if grep -qF -- "$2" "$tmp/out"; then
    passed=$((passed + 1))
    echo "ok   $1"
  else
    failed=$((failed + 1))
    echo "FAIL $1: no '$2' in"
    sed 's/^/     /' "$tmp/out"
  fi
}

# ------------------------------------------------------------------ the server of the cases
cat >"$tmp/server.py" <<'EOF'
import http.server, sys, urllib.parse

def csv(rows):
    return ''.join(','.join('"' + c.replace('"', '""') + '"' for c in row) + '\n' for row in rows).encode()

H = ['Upload Date', 'Order', 'Video Title', 'Genre', 'Link to Video', 'Short Video / Requestor', 'Stream Source',
     'Vocals?', 'Adult', 'Additional Notes', '', '']
S = ['  ', 'Uptime', 'Order', 'Requester', 'Title ', 'Genre', 'Request Type/Instrument', 'Notes', 'Looper', 'File#',
     '', '', '']

def highlights(n):
    return csv([H] + [['2024-01-02', str(i), f'Video {i}', 'GAME OST', '', 'x', '', '', '', 'say "hi"\nok', '', '']
                      for i in range(n)])

def songs(n):
    return csv([S] + [['2024-01-01 20:00:00', '', str(i), 'x', f'Song {i}', 'GAME OST', 'Piano', '', '', '', '', '', '']
                      for i in range(n)])

CASES = {
    'good': lambda sheet: (200, 'text/csv; charset=utf-8', highlights(60) if sheet == 'h' else songs(200)),
    'good-changed': lambda sheet: (200, 'text/csv; charset=utf-8', highlights(61) if sheet == 'h' else songs(201)),
    'error-page-200': lambda sheet: (200, 'text/html; charset=utf-8', b'<!DOCTYPE html><html>Sorry, unable to open the file</html>'),
    'html-as-csv': lambda sheet: (200, 'text/csv', b'<html><body>Error</body></html>'),
    'truncated-quote': lambda sheet: (200, 'text/csv', highlights(60) if sheet == 'h' else songs(200)[:-20]),
    'truncated-row': lambda sheet: (200, 'text/csv', highlights(60) if sheet == 'h' else songs(200) + b'"2024-01-01","","1"\n'),
    'shrunk': lambda sheet: (200, 'text/csv', highlights(60) if sheet == 'h' else songs(150)),
    'shrunk-a-little': lambda sheet: (200, 'text/csv', highlights(60) if sheet == 'h' else songs(185)),
    'too-few': lambda sheet: (200, 'text/csv', highlights(5) if sheet == 'h' else songs(200)),
    'no-title': lambda sheet: (200, 'text/csv', highlights(60) if sheet == 'h' else songs(200).replace(b'"Title "', b'"Name"', 1)),
    'server-error': lambda sheet: (500, 'text/html', b'<html>500</html>'),
    'server-error-csv': lambda sheet: (500, 'text/csv', highlights(60) if sheet == 'h' else songs(200)),
    'csv-as-text': lambda sheet: (200, 'text/plain', highlights(60) if sheet == 'h' else songs(200)),
    'not-found': lambda sheet: (404, 'text/html', b'Not Found'),
}

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        case = url.path.strip('/').split('/')[0]
        sheet = 'h' if 'Youtube' in urllib.parse.unquote(url.query) else 's'
        status, kind, body = CASES[case](sheet)
        self.send_response(status)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()
EOF
python3 -I "$tmp/server.py" "$port" &
server_pid=$!
for _ in $(seq 50); do
  curl --silent --output /dev/null "http://127.0.0.1:$port/good/x?sheet=Songs" && break
  sleep 0.1
done

export SNAPSHOT_MIN_HIGHLIGHT_ROWS=10 SNAPSHOT_MIN_SONG_ROWS=100 SNAPSHOT_RETRIES=0
make_case() { # make_case <case> <out> [<published>]
  SNAPSHOT_EXPORT_BASE="http://127.0.0.1:$port/$1/gviz/tq?tqx=out:csv&headers=1&sheet=" \
    bash "$script" make "$2" "${3:-}"
}
written() { [[ -f "$1/highlights.csv" && -f "$1/songs.csv" && -f "$1/snapshot.json" ]]; }
nothing_written() { [[ ! -e "$1" ]]; }

# ------------------------------------------------------------------ make
check 'a good export is written' 0 make_case good "$tmp/good"
check '  with its three files' 0 written "$tmp/good"
check '  the CSV as the server gave it' 0 cmp "$tmp/good/songs.csv" <(curl -s "http://127.0.0.1:$port/good/x?sheet=Songs")
check '  the time in UTC and the row counts' 0 python3 -I -c '
import json, sys, datetime
m = json.load(open(sys.argv[1]))
assert m["madeAt"].endswith("Z"), m
datetime.datetime.strptime(m["madeAt"], "%Y-%m-%dT%H:%M:%SZ")
assert (m["highlightsRows"], m["songsRows"]) == (60, 200), m
' "$tmp/good/snapshot.json"
for case in error-page-200 html-as-csv truncated-quote truncated-row too-few no-title server-error server-error-csv \
  csv-as-text not-found; do
  check "$case: refused, nothing written" 1 make_case "$case" "$tmp/$case"
  check "$case:   nothing written" 0 nothing_written "$tmp/$case"
done
check 'error-page-200: said why' 1 make_case error-page-200 "$tmp/x"
expect_output '  content type' "content type 'text/html; charset=utf-8', not text/csv"
check 'truncated-quote: said why' 1 make_case truncated-quote "$tmp/x"
expect_output '  does not read to its end' 'not a CSV that reads to its end'
check 'server-error-csv (a 500 with a CSV body): said why' 1 make_case server-error-csv "$tmp/x"
expect_output '  HTTP 500' 'HTTP 500'
check 'csv-as-text: said why' 1 make_case csv-as-text "$tmp/x"
expect_output '  content type' "content type 'text/plain', not text/csv"
check 'html-as-csv: said why' 1 make_case html-as-csv "$tmp/x"
expect_output '  a web page' 'a web page, not CSV'
check 'truncated-row: said why' 1 make_case truncated-row "$tmp/x"
expect_output '  cut short' 'has 3 cells, the header 13'
check 'too-few: said why' 1 make_case too-few "$tmp/x"
expect_output '  too few' 'highlights: 5 rows, fewer than 10'
check 'no-title: said why' 1 make_case no-title "$tmp/x"
expect_output '  no title' 'songs: no "title" column'
check 'shrunk against nothing published: taken' 0 make_case shrunk "$tmp/shrunk-alone"
check 'shrunk by a quarter against the published snapshot: refused' 1 make_case shrunk "$tmp/shrunk" "$tmp/good"
expect_output '  said why' 'songs: 150 rows against 200 in the published snapshot: refused'
check '  nothing written' 0 nothing_written "$tmp/shrunk"
check 'shrunk, taken by hand (SNAPSHOT_ACCEPT_SMALLER=1)' 0 env SNAPSHOT_ACCEPT_SMALLER=1 \
  SNAPSHOT_EXPORT_BASE="http://127.0.0.1:$port/shrunk/gviz/tq?sheet=" bash "$script" make "$tmp/shrunk-taken" "$tmp/good"
check 'a loss of 7.5 %: taken (rows deleted by hand happen)' 0 make_case shrunk-a-little "$tmp/shrunk-a-little" "$tmp/good"
check 'a loss within SNAPSHOT_MAX_LOSS=0.25: taken' 0 env SNAPSHOT_MAX_LOSS=0.25 \
  SNAPSHOT_EXPORT_BASE="http://127.0.0.1:$port/shrunk/gviz/tq?sheet=" bash "$script" make "$tmp/shrunk-tolerated" "$tmp/good"
check 'a failed day leaves the previous snapshot untouched' 0 bash -c '
  cp -R "$1/good" "$1/kept" && before=$(cat "$1/kept/snapshot.json")
  ! SNAPSHOT_EXPORT_BASE="http://127.0.0.1:$2/server-error/x?sheet=" bash "$3" make "$1/kept" "$1/kept" 2>/dev/null
  [[ "$(cat "$1/kept/snapshot.json")" == "$before" ]]' _ "$tmp" "$port" "$script"

# ------------------------------------------------------------------ publish
git init --quiet --bare "$tmp/remote.git"
git init --quiet "$tmp/checkout"
git -C "$tmp/checkout" -c user.name=t -c user.email=t@t commit --quiet --allow-empty -m 'the default branch'
git -C "$tmp/checkout" remote add origin "$tmp/remote.git"
git -C "$tmp/checkout" push --quiet origin HEAD:refs/heads/master
publish() { (cd "$tmp/checkout" && bash "$script" publish "$@"); }
remote_branch() { git -C "$tmp/remote.git" rev-parse --verify --quiet refs/heads/sheets-snapshot; }

check 'no branch yet: published' 0 publish "$tmp/good"
expect_output '  as the first snapshot' 'published (first snapshot)'
first=$(remote_branch)
check '  one commit, without parent' 0 test "$(git -C "$tmp/remote.git" rev-list --count sheets-snapshot)" = 1
check '  holding the three files only' 0 test "$(git -C "$tmp/remote.git" ls-tree --name-only sheets-snapshot | tr '\n' ' ')" = 'highlights.csv snapshot.json songs.csv '
check '  the default branch untouched' 0 test "$(git -C "$tmp/remote.git" rev-list --count master)" = 1
check 'the same sheets the next day (a new time only): nothing pushed' 0 bash -c '
  cp -R "$1/good" "$1/next-day" && sed -i.bak "s/\"madeAt\": \"[^\"]*\"/\"madeAt\": \"2099-01-01T00:00:00Z\"/" "$1/next-day/snapshot.json" && rm "$1/next-day/snapshot.json.bak"' _ "$tmp"
check '  publish says unchanged' 0 publish "$tmp/next-day"
expect_output '  unchanged' 'unchanged'
check '  the branch is where it was' 0 test "$(remote_branch)" = "$first"
check 'a sheet changed: published' 0 make_case good-changed "$tmp/changed" "$tmp/good"
check '  pushed' 0 publish "$tmp/changed"
expect_output '  because a sheet changed' 'published (highlights.csv changed)'
second=$(remote_branch)
check '  still one commit: no history grows' 0 test "$(git -C "$tmp/remote.git" rev-list --count sheets-snapshot)" = 1
check '  a new one' 0 test "$second" != "$first"
# the published snapshot, 31 days old: the same sheets are pushed again (a push at least monthly)
old_commit=$(cd "$tmp/checkout" && GIT_COMMITTER_DATE="$(($(date +%s) - 31 * 86400)) +0000" \
  GIT_AUTHOR_DATE="$(($(date +%s) - 31 * 86400)) +0000" git -c user.name=t -c user.email=t@t \
  commit-tree "$(git -C "$tmp/remote.git" rev-parse 'sheets-snapshot^{tree}')" -m old)
(cd "$tmp/checkout" && git push --quiet --force origin "$old_commit:refs/heads/sheets-snapshot")
check 'unchanged but 31 days old: published again' 0 publish "$tmp/changed"
expect_output '  saying why' 'published (unchanged, but the snapshot is 31 days old)'
check '  a new commit' 0 test "$(remote_branch)" != "$old_commit"
check '  dated now' 0 test $(($(date +%s) - $(git -C "$tmp/remote.git" log -1 --format=%ct sheets-snapshot))) -lt 600
check 'unchanged and 29 days old: nothing pushed' 0 bash -c '
  cd "$1/checkout"
  c=$(GIT_COMMITTER_DATE="$(($(date +%s) - 29 * 86400)) +0000" git -c user.name=t -c user.email=t@t commit-tree "$(git -C "$1/remote.git" rev-parse "sheets-snapshot^{tree}")" -m old)
  git push --quiet --force origin "$c:refs/heads/sheets-snapshot"
  [[ "$(bash "$2" publish "$1/changed")" == unchanged ]] && [[ "$(git -C "$1/remote.git" rev-parse sheets-snapshot)" == "$c" ]]' _ "$tmp" "$script"
check 'a missing file: refused' 1 publish "$tmp/does-not-exist"

echo "$passed passed, $failed failed"
[[ $failed == 0 ]]
