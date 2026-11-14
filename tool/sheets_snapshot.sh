#!/usr/bin/env bash
# The daily copy of the two sheets (the "snapshot") that the app shows on a first load until Google answers
# (lib/src/data/sheet_snapshot.dart). Run by .github/workflows/sheets_snapshot.yml; runs locally as well (bash, curl,
# python3, git; no secret: the exports are the public requests the app makes).
#
#   tool/sheets_snapshot.sh make <out-dir> [<published-dir>]
#       Downloads both CSV exports, checks them, and writes <out-dir>/highlights.csv, songs.csv (the bytes Google
#       answered, which the app's parser reads as it reads Google's own answer) and snapshot.json ({"madeAt": UTC
#       time the downloads started, row counts}). <published-dir> holds the snapshot published now, if any: a sheet
#       that lost more than SNAPSHOT_MAX_LOSS of its rows against it is refused. Fails (exit 1, <out-dir> left
#       untouched) on any doubt: an answer that is not a 200, not text/csv, an error page, a CSV that does not read
#       to its end or whose rows do not all have the width of its header, a header without the columns the parser
#       requires (lib/src/data/parser.dart), too few rows.
#
#   tool/sheets_snapshot.sh publish <out-dir> [<remote> [<branch>]]
#       From the git repository of the current directory: makes ONE orphan commit of the three files and force-pushes
#       it to <branch> (default sheets-snapshot) of <remote> (default origin), replacing the previous one (no history
#       grows) — when the branch does not exist, when a sheet changed, or when its commit is older than
#       SNAPSHOT_MAX_AGE_DAYS (default 30). Otherwise pushes nothing. Prints "published" or "unchanged".
#
# Environment (defaults in brackets; the tests of tool/sheets_snapshot_test.sh change them):
#   SNAPSHOT_EXPORT_BASE   the export address, the sheet name appended [the spreadsheet of lib/src/data/sheets.dart]
#   SNAPSHOT_MIN_HIGHLIGHT_ROWS, SNAPSHOT_MIN_SONG_ROWS   fewest data rows [1000, 10000: about half of November 2026]
#   SNAPSHOT_MAX_LOSS      the largest share of rows a sheet may lose against the published snapshot [0.1]
#   SNAPSHOT_ACCEPT_SMALLER=1   takes a sheet that lost more (rows really archived), by hand
#   SNAPSHOT_RETRIES       curl retries of a failed download (timeouts, 5xx) [2]
#   SNAPSHOT_MAX_AGE_DAYS  see publish [30]
set -euo pipefail

export_base=${SNAPSHOT_EXPORT_BASE:-'https://docs.google.com/spreadsheets/d/14ARzE_zSMNhp0ZQV34ti2741PbA-5wAjsXRAW8EgJ-4/gviz/tq?tqx=out:csv&headers=1&sheet='}
files=(highlights.csv songs.csv snapshot.json)

fail() {
  echo "::error::sheets snapshot: $*" >&2
  exit 1
}

# download <sheet> <file>: the export of <sheet> into <file>, 200 and text/csv only
download() {
  local sheet=$1 file=$2 answer status type
  # --compressed: gzip on the wire (the Songs sheet: 4 MB, 0.9 MB gzipped), the file is the text
  answer=$(curl --silent --show-error --compressed --location \
    --retry "${SNAPSHOT_RETRIES:-2}" --retry-delay 10 --connect-timeout 30 --max-time 300 \
    --user-agent 'ong-music-sheets-snapshot' \
    --output "$file" --write-out '%{http_code} %{content_type}' "${export_base}${sheet}") ||
    fail "$sheet: download failed ($answer)"
  status=${answer%% *}
  type=$(printf '%s' "${answer#* }" | tr '[:upper:]' '[:lower:]')
  [[ "$status" == 200 ]] || fail "$sheet: HTTP $status"
  # text/csv; charset=utf-8 from Google; an error page is text/html, whatever its status
  [[ "$type" == text/csv* ]] || fail "$sheet: content type '${type}', not text/csv"
}

make_snapshot() {
  local out=$1 published=${2:-}
  # global: the EXIT trap runs after this function returned
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  local made_at
  made_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  download 'Youtube%20Catalogue' "$work/highlights.csv"
  download 'Songs' "$work/songs.csv"
  python3 -I - "$work" "$made_at" "$published" <<'EOF' || exit 1
import csv, io, json, os, sys

work, made_at, published = sys.argv[1], sys.argv[2], sys.argv[3]
env = os.environ
max_loss = float(env.get('SNAPSHOT_MAX_LOSS', '0.1'))
accept_smaller = env.get('SNAPSHOT_ACCEPT_SMALLER') == '1'

def fail(message):
    print(f'::error::sheets snapshot: {message}', file=sys.stderr)
    sys.exit(1)

def rows_of(name, path):
    with open(path, encoding='utf-8', newline='') as f:
        text = f.read()
    if text.lstrip().startswith('<'):
        fail(f'{name}: a web page, not CSV')
    try:
        # strict: a quote left open (an export cut short) is an error, not a last cell
        rows = list(csv.reader(io.StringIO(text.lstrip('﻿'), newline=''), strict=True))
    except csv.Error as e:
        fail(f'{name}: not a CSV that reads to its end ({e})')
    if not rows:
        fail(f'{name}: empty')
    width = len(rows[0])
    for i, row in enumerate(rows):
        if len(row) != width:
            fail(f'{name}: row {i + 1} has {len(row)} cells, the header {width} (cut short?)')
    return rows

# The headers the parser requires (lib/src/data/parser.dart: HighlightColumns, SongColumns and the checks of
# CatalogueLoad), any of the names it accepts, trimmed, case ignored.
required = {
    'highlights': [['video title', 'title'], ['upload date']],
    'songs': [['title']],
}
minimum = {
    'highlights': int(env.get('SNAPSHOT_MIN_HIGHLIGHT_ROWS', '1000')),
    'songs': int(env.get('SNAPSHOT_MIN_SONG_ROWS', '10000')),
}
previous = {}
if published and os.path.isfile(os.path.join(published, 'snapshot.json')):
    with open(os.path.join(published, 'snapshot.json'), encoding='utf-8') as f:
        meta = json.load(f)
    previous = {'highlights': meta.get('highlightsRows'), 'songs': meta.get('songsRows')}

counts = {}
for name in ('highlights', 'songs'):
    rows = rows_of(name, os.path.join(work, f'{name}.csv'))
    header = {cell.strip().lower() for cell in rows[0]}
    for names in required[name]:
        if not header & set(names):
            fail(f'{name}: no "{names[0]}" column in the header {rows[0]}')
    # data rows that hold something
    count = sum(1 for row in rows[1:] if any(cell.strip() for cell in row))
    if count < minimum[name]:
        fail(f'{name}: {count} rows, fewer than {minimum[name]}')
    before = previous.get(name)
    if isinstance(before, int) and count < before * (1 - max_loss):
        message = f'{name}: {count} rows against {before} in the published snapshot'
        if not accept_smaller:
            fail(f'{message}: refused (SNAPSHOT_ACCEPT_SMALLER=1 to take it)')
        print(f'{message}: taken (SNAPSHOT_ACCEPT_SMALLER=1)', file=sys.stderr)
    counts[name] = count

with open(os.path.join(work, 'snapshot.json'), 'w', encoding='utf-8') as f:
    json.dump({'madeAt': made_at, 'highlightsRows': counts['highlights'], 'songsRows': counts['songs']}, f, indent=2)
    f.write('\n')
print(f"highlights: {counts['highlights']} rows, songs: {counts['songs']} rows, made at {made_at}")
EOF
  mkdir -p "$out"
  for f in "${files[@]}"; do
    mv "$work/$f" "$out/$f"
  done
}

publish() {
  local out=$1 remote=${2:-origin} branch=${3:-sheets-snapshot}
  local max_age_days=${SNAPSHOT_MAX_AGE_DAYS:-30}
  for f in "${files[@]}"; do
    [[ -f "$out/$f" ]] || fail "publish: $out/$f is missing"
  done
  local previous='' reason=''
  if git fetch --quiet --depth=1 "$remote" "+refs/heads/${branch}:refs/snapshot/previous" 2>/dev/null; then
    previous=$(git rev-parse refs/snapshot/previous)
  fi
  if [[ -z "$previous" ]]; then
    reason='first snapshot'
  else
    local f
    for f in highlights.csv songs.csv; do
      if [[ "$(git rev-parse "${previous}:${f}" 2>/dev/null || true)" != "$(git hash-object "$out/$f")" ]]; then
        reason="$f changed"
        break
      fi
    done
    if [[ -z "$reason" ]]; then
      local age_days=$(( ($(date +%s) - $(git log -1 --format=%ct "$previous")) / 86400 ))
      if (( age_days >= max_age_days )); then
        reason="unchanged, but the snapshot is ${age_days} days old"
      fi
    fi
  fi
  if [[ -z "$reason" ]]; then
    echo "unchanged"
    return
  fi
  # one commit without parent, made without touching the working tree
  local tree commit
  tree=$(
    for f in "${files[@]}"; do
      printf '100644 blob %s\t%s\n' "$(git hash-object -w "$out/$f")" "$f"
    done | git mktree
  )
  commit=$(
    GIT_AUTHOR_NAME='github-actions[bot]' GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
      GIT_COMMITTER_NAME='github-actions[bot]' GIT_COMMITTER_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
      git commit-tree "$tree" -m "Snapshot of the sheets: $reason"
  )
  # replaces exactly the commit read above: a snapshot pushed meanwhile by another run is not lost silently
  git push --quiet --force-with-lease="refs/heads/${branch}:${previous}" "$remote" "${commit}:refs/heads/${branch}"
  echo "published ($reason)"
}

case "${1:-}" in
  make) [[ $# -ge 2 ]] || fail 'usage: make <out-dir> [<published-dir>]'; make_snapshot "$2" "${3:-}" ;;
  publish) [[ $# -ge 2 ]] || fail 'usage: publish <out-dir> [<remote> [<branch>]]'; publish "$2" "${3:-}" "${4:-}" ;;
  *) fail 'usage: tool/sheets_snapshot.sh make|publish ...' ;;
esac
