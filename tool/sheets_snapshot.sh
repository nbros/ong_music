#!/usr/bin/env bash
# The daily copy of the two sheets (the "snapshot") that the app shows on a first load until Google answers
# (lib/src/data/sheet_snapshot.dart), and the links of the titles of the Songs sheet, which the CSV export drops
# (song_links.tsv, read by the app as a data file: lib/src/data/song_links.dart). Run by
# .github/workflows/sheets_snapshot.yml; runs locally as well (bash, curl, python3, git; no secret: the exports are
# public, the CSV ones the very requests the app makes).
#
#   tool/sheets_snapshot.sh make <out-dir> [<published-dir>]
#       Downloads both CSV exports, checks them, and writes <out-dir>/highlights.csv, songs.csv (the bytes Google
#       answered, which the app's parser reads as it reads Google's own answer) and snapshot.json ({"madeAt": UTC
#       time the downloads started, row counts}). <published-dir> holds the snapshot published now, if any: a sheet
#       that lost more than SNAPSHOT_MAX_LOSS of its rows against it is refused. Fails (exit 1, <out-dir> left
#       untouched) on any doubt: an answer that is not a 200, not text/csv, an error page, a CSV that does not read
#       to its end or whose rows do not all have the width of its header, a header without the columns the parser
#       requires (lib/src/data/parser.dart), too few rows.
#       Then downloads the xlsx export of the Songs sheet (4 MB: too heavy for the app) and writes from it
#       <out-dir>/song_links.tsv, a YouTube video per title (tool/song_links.py, which says what it checks), with
#       songLinksRows, songLinks and songLinksMadeAt in snapshot.json. The links never stop the sheets: when that
#       step fails (the export refused, a doubt about its content, links lost against <published-dir>), the sheets
#       are written all the same, with the song_links.tsv of <published-dir> and its numbers, if any, and make
#       exits 2 (the workflow publishes, then fails visibly).
#
#   tool/sheets_snapshot.sh publish <out-dir> [<remote> [<branch>]]
#       From the git repository of the current directory: makes a commit of the files over the one published on
#       <branch> (default sheets-snapshot) of <remote> (default origin) and pushes it, not forced — when the branch
#       does not exist (a first commit, without parent), when a sheet or the links changed, or when its commit is
#       older than SNAPSHOT_MAX_AGE_DAYS (default 30). Otherwise pushes nothing. Prints "published" or "unchanged".
#       Without song_links.tsv in <out-dir>, the one published stays in the commit.
#       The branch keeps every snapshot: its history is the journal of the sheets, one commit per day they changed
#       (text that git stores as differences: some kilobytes a day once packed), and what was removed from a sheet
#       stays readable in it.
#
# Environment (defaults in brackets; the tests of tool/sheets_snapshot_test.sh change them):
#   SNAPSHOT_EXPORT_BASE   the export address, the sheet name appended [the spreadsheet of lib/src/data/sheets.dart]
#   SNAPSHOT_LINKS_URL     the xlsx export of the Songs sheet alone [the same spreadsheet, gid=0]
#   SNAPSHOT_MIN_HIGHLIGHT_ROWS, SNAPSHOT_MIN_SONG_ROWS   fewest data rows [1000, 10000: about half of November 2026]
#   SNAPSHOT_MIN_LINK_ROWS fewest rows of the Songs sheet with a link kept [10000: 28,757 in November 2026]
#   SNAPSHOT_MAX_LOSS      the largest share of rows a sheet, or of links, may lose against the published snapshot
#                          [0.1]
#   SNAPSHOT_ACCEPT_SMALLER=1   takes a sheet that lost more (rows really archived), or links, by hand
#   SNAPSHOT_RETRIES       curl retries of a failed download (timeouts, 5xx) [2]
#   SNAPSHOT_MAX_AGE_DAYS  see publish [30]
set -euo pipefail

export_base=${SNAPSHOT_EXPORT_BASE:-'https://docs.google.com/spreadsheets/d/14ARzE_zSMNhp0ZQV34ti2741PbA-5wAjsXRAW8EgJ-4/gviz/tq?tqx=out:csv&headers=1&sheet='}
links_url=${SNAPSHOT_LINKS_URL:-'https://docs.google.com/spreadsheets/d/14ARzE_zSMNhp0ZQV34ti2741PbA-5wAjsXRAW8EgJ-4/export?format=xlsx&gid=0'}
tool_dir=$(cd "$(dirname "$0")" && pwd)
# always there; song_links.tsv when its step went well, or kept from the published snapshot
files=(highlights.csv songs.csv snapshot.json)
links=song_links.tsv
xlsx_type=application/vnd.openxmlformats-officedocument.spreadsheetml.sheet

fail() {
  echo "::error::sheets snapshot: $*" >&2
  exit 1
}

# download <name> <url> <file> <type>: <url> into <file>, 200 and of content type <type> only
download() {
  # <max-time> and <retries>: those of the sheets unless given (the optional xlsx gets a shorter budget)
  local name=$1 url=$2 file=$3 expected=$4 max_time=${5:-300} retries=${6:-${SNAPSHOT_RETRIES:-2}} answer status type
  # --compressed: gzip on the wire (the Songs sheet: 4 MB, 0.9 MB gzipped), the file is the text
  answer=$(curl --silent --show-error --compressed --location \
    --retry "$retries" --retry-delay 10 --connect-timeout 30 --max-time "$max_time" --max-filesize 100000000 \
    --user-agent 'ong-music-sheets-snapshot' \
    --output "$file" --write-out '%{http_code} %{content_type}' "$url") ||
    fail "$name: download failed ($answer)"
  status=${answer%% *}
  type=$(printf '%s' "${answer#* }" | tr '[:upper:]' '[:lower:]')
  [[ "$status" == 200 ]] || fail "$name: HTTP $status"
  # text/csv; charset=utf-8 from Google; an error page is text/html, whatever its status
  [[ "$type" == "$expected"* ]] || fail "$name: content type '${type}', not $expected"
}

make_snapshot() {
  local out=$1 published=${2:-}
  # global: the EXIT trap runs after this function returned
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  local made_at
  made_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  download 'Youtube%20Catalogue' "${export_base}Youtube%20Catalogue" "$work/highlights.csv" text/csv
  download 'Songs' "${export_base}Songs" "$work/songs.csv" text/csv
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
  # the links, in a subshell: its failures (fail exits) stop it, not the sheets
  local links_failed=''
  if ! (
    # at most 2 × 120 s + 10 s: a stuck export must leave the job (15 minutes) the time to publish the sheets
    download 'song links' "$links_url" "$work/songs.xlsx" "$xlsx_type" 120 1 &&
      python3 -I "$tool_dir/song_links.py" "$work/songs.xlsx" "$work/$links" "$work/song_links.json" "$published"
  ); then
    links_failed=1
    rm -f "$work/$links" "$work/song_links.json"
    if [[ -n "$published" && -f "$published/$links" ]]; then
      cp "$published/$links" "$work/$links"
      echo "song links: not refreshed, the published ones kept" >&2
    else
      echo "song links: not refreshed, none published" >&2
    fi
  fi
  python3 -I - "$work" "$made_at" "$published" <<'EOF' || exit 1
import json, os, sys

work, made_at, published = sys.argv[1], sys.argv[2], sys.argv[3]
keys = ('songLinksRows', 'songLinks', 'songLinksMadeAt')
with open(os.path.join(work, 'snapshot.json'), encoding='utf-8') as f:
    meta = json.load(f)
fresh = os.path.join(work, 'song_links.json')
if os.path.isfile(fresh):
    with open(fresh, encoding='utf-8') as f:
        meta.update(json.load(f), songLinksMadeAt=made_at)
elif os.path.isfile(os.path.join(work, 'song_links.tsv')):
    # the published links, with their numbers
    with open(os.path.join(published, 'snapshot.json'), encoding='utf-8') as f:
        before = json.load(f)
    meta.update({key: before[key] for key in keys if key in before})
with open(os.path.join(work, 'snapshot.json'), 'w', encoding='utf-8') as f:
    json.dump(meta, f, indent=2)
    f.write('\n')
EOF
  mkdir -p "$out"
  for f in "${files[@]}"; do
    mv "$work/$f" "$out/$f"
  done
  if [[ -f "$work/$links" ]]; then
    mv "$work/$links" "$out/$links"
  else
    rm -f "$out/$links"
  fi
  if [[ -n "$links_failed" ]]; then
    echo "::error::sheets snapshot: the sheets are written, but not the links of the songs" >&2
    exit 2
  fi
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
    local f changed=''
    for f in highlights.csv songs.csv "$links"; do
      # no links made: those published stay (see below)
      [[ -f "$out/$f" ]] || continue
      if [[ "$(git rev-parse "${previous}:${f}" 2>/dev/null || true)" != "$(git hash-object "$out/$f")" ]]; then
        changed="${changed:+$changed, }$f"
      fi
    done
    if [[ -n "$changed" ]]; then
      reason="$changed changed"
    fi
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
  # one commit over the published one (the first has no parent), made without touching the working tree; without
  # links made, those published stay
  local tree commit kept_links=''
  if [[ ! -f "$out/$links" && -n "$previous" ]]; then
    kept_links=$(git rev-parse --verify --quiet "${previous}:${links}" || true)
  fi
  tree=$(
    {
      for f in "${files[@]}"; do
        printf '100644 blob %s\t%s\n' "$(git hash-object -w "$out/$f")" "$f"
      done
      if [[ -f "$out/$links" ]]; then
        printf '100644 blob %s\t%s\n' "$(git hash-object -w "$out/$links")" "$links"
      elif [[ -n "$kept_links" ]]; then
        printf '100644 blob %s\t%s\n' "$kept_links" "$links"
      fi
    } | git mktree
  )
  commit=$(
    GIT_AUTHOR_NAME='github-actions[bot]' GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
      GIT_COMMITTER_NAME='github-actions[bot]' GIT_COMMITTER_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
      git commit-tree "$tree" ${previous:+-p "$previous"} -m "Snapshot of the sheets: $reason"
  )
  # not forced: over a snapshot pushed meanwhile by another run, which is not the parent of this commit, the push
  # is refused and this run fails; nothing published is ever replaced
  git push --quiet "$remote" "${commit}:refs/heads/${branch}"
  echo "published ($reason)"
}

case "${1:-}" in
  make) [[ $# -ge 2 ]] || fail 'usage: make <out-dir> [<published-dir>]'; make_snapshot "$2" "${3:-}" ;;
  publish) [[ $# -ge 2 ]] || fail 'usage: publish <out-dir> [<remote> [<branch>]]'; publish "$2" "${3:-}" "${4:-}" ;;
  *) fail 'usage: tool/sheets_snapshot.sh make|publish ...' ;;
esac
