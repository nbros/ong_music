#!/usr/bin/env bash
# the bash -c scripts below take their values as arguments, not expanded in their text
# shellcheck disable=SC2016
# Tests of tool/sheets_snapshot.sh, offline: `bash tool/sheets_snapshot_test.sh`.
#
# make: against a local server answering each case (a good export, an error page with status 200, an export cut
# short, a sheet that shrank, a 500...): only the good ones write a snapshot. The links of the songs, from an xlsx
# made here (formulas written in every way the sheet writes them, links of cells, addresses of YouTube in their
# forms): the file expected to the byte; a bad xlsx (an error page, no sheet "Songs", links lost...) never stops the
# sheets, the published links stay. publish: into a bare repository made here: a first commit without parent,
# nothing pushed when nothing changed, a commit over the published one when a sheet or the links changed or when the
# snapshot is a month old (the branch keeps its history, never forced).
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
check() { # check <name> <expected status: 0|1 (any failure)|2> <command...>
  local name=$1 expected=$2 status=0
  shift 2
  "$@" >"$tmp/out" 2>&1 || status=$?
  if [[ ($expected == 0 && $status == 0) || ($expected == 1 && $status != 0) || ($expected == 2 && $status == 2) ]]; then
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
import http.server, io, sys, urllib.parse, zipfile
from xml.sax.saxutils import escape

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

XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
NS = ('xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')
RELS = 'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"'
KIND = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'

def xlsx(rows, sheet='Songs', header='Title '):
    """An xlsx export: a sheet "Other" first, then [sheet], its row 1 the CSV header (title column E, header [header]),
    then [rows], each (title, formula or None, link of the cell or None)."""
    shared = []
    def string(text):
        shared.append(text)
        return len(shared) - 1
    def cell(ref, text):
        return f'<c r="{ref}" t="s"><v>{string(text)}</v></c>'
    xml_rows = ['<row r="1">' + ''.join(cell(f'{chr(65 + i)}1', h if i != 4 else header) for i, h in enumerate(S[:9]))
                + '</row>']
    links, rels = [], []
    for i, (title, formula, link) in enumerate(rows):
        r = i + 2
        if formula is not None:
            e = f'<c r="E{r}" s="3" t="str"><f>{escape(formula)}</f><v>{escape(title)}</v></c>'
        else:
            e = cell(f'E{r}', title)
        if link is not None:
            rels.append(f'<Relationship Id="rId{r}" Type="{KIND}hyperlink" Target="{escape(link)}" TargetMode="External"/>')
            links.append(f'<hyperlink r:id="rId{r}" ref="E{r}"/>')
        xml_rows.append(f'<row r="{r}"><c r="A{r}"><v>45000.5</v></c><c r="D{r}" t="s"><v>{string("x")}</v></c>{e}</row>')
    sheet_xml = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet {NS}><sheetData>'
                 + ''.join(xml_rows) + '</sheetData>' + (f'<hyperlinks>{"".join(links)}</hyperlinks>' if links else '')
                 + '</worksheet>')
    other = f'<?xml version="1.0" encoding="UTF-8"?><worksheet {NS}><sheetData><row r="1">{cell("E1", "Title")}</row><row r="2"><c r="E2" t="str"><f>HYPERLINK("https://youtu.be/OOOOOOOOOOO","Other")</f><v>Other</v></c></row></sheetData></worksheet>'
    strings = (f'<?xml version="1.0" encoding="UTF-8"?><sst {NS}>'
               + ''.join(f'<si><t xml:space="preserve">{escape(t)}</t></si>' for t in shared) + '</sst>')
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types/>')
        z.writestr('xl/workbook.xml', f'<?xml version="1.0"?><workbook {NS}><sheets><sheet name="Other" sheetId="2" r:id="rId7"/>'
                                      f'<sheet name="{sheet}" sheetId="1" r:id="rId4"/></sheets></workbook>')
        z.writestr('xl/_rels/workbook.xml.rels', f'<?xml version="1.0"?><Relationships {RELS}>'
                   f'<Relationship Id="rId2" Type="{KIND}sharedStrings" Target="sharedStrings.xml"/>'
                   f'<Relationship Id="rId4" Type="{KIND}worksheet" Target="worksheets/sheet7.xml"/>'
                   f'<Relationship Id="rId7" Type="{KIND}worksheet" Target="/xl/worksheets/sheet1.xml"/></Relationships>')
        z.writestr('xl/worksheets/sheet1.xml', other)
        z.writestr('xl/worksheets/sheet7.xml', sheet_xml)
        z.writestr('xl/worksheets/_rels/sheet7.xml.rels', f'<?xml version="1.0"?><Relationships {RELS}>'
                   f'<Relationship Id="rId1" Type="{KIND}comments" Target="../comments1.xml"/>{"".join(rels)}</Relationships>')
        z.writestr('xl/sharedStrings.xml', strings)
    return out.getvalue()

def hl(url, title, sep=','):
    return f'HYPERLINK("{url}"{sep}"{title.replace(chr(34), chr(34) * 2)}")'

# the rows of the good xlsx: every form of the sheet (the lines expected are in the test below)
LINK_ROWS = [
    ('Song 1', hl('https://www.youtube.com/watch?v=AAAAAAAAAA1', 'Song 1'), None),
    ('Song 1', hl('https://youtu.be/AAAAAAAAAA1?si=share', 'Song 1'), None),
    ('Song 1', ' hyperlink("http://youtube.com/watch?v=AAAAAAAAAA1&t=30" , "Song 1")', None),
    ('Song 2', hl('https://music.youtube.com/watch?v=BBBBBBBBBB2&feature=share', 'Song 2', '; '), None),
    ('Say "hi"', hl('https://www.youtube.com/shorts/CCCCCCCCCC3', 'Say "hi"'), None),
    ('Song  4', 'Hyperlink("https://soundcloud.com/artist/track","Song  4")', None),
    ('Song 5', None, 'https://www.twitch.tv/videos/735606179'),
    ('Song 6', None, 'https://youtu.be/DDDDDDDDDD4'),
    ('Song 7', hl('https://youtu.be/EEEEEEEEEE5', 'Song 7'), 'https://example.com/the-formula-wins'),
    ('Song 8', hl('St7mQWwmo70', 'Song 8'), None),
    ('Song 9', hl('www.youtube.com/watch?v=FFFFFFFFFF6', 'Song 9'), None),
    ('Song 10', hl('https://www.google.com/url?sa=t&url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DGGGGGGGGGG7&usg=x', 'Song 10'), None),
    ('Song 11', hl('https://www.youtube.com/playlist?list=PL123', 'Song 11'), None),
    ('Song\t12', hl('https://youtu.be/HHHHHHHHHH8', 'Song 12'), None),
    ('Song 1', hl('https://youtu.be/IIIIIIIIII9', 'Song 1'), None),
    ('Zelda - Lullaby / Song of Storms',
     'HYPERLINK("https://youtu.be/KKKKKKKKKK2?t=1m30s","Zelda - Lullaby") & " / Song of Storms"', None),
    ('Seven Spires - Succumb', 'HYPERLINK("https://youtu.be/LLLLLLLLLL3", "Seven Spires - "&CHAR(22)&"Succumb"&CHAR(22))',
     None),
    ('Song 14', hl('https://www.youtube.com/watch?v=MMMMMMMMMM4&list=PL1&t=45s', 'Song 14'), None),
    # left out
    ('Moana', hl('Moana', 'Moana'), None),
    ('Song 15', hl('HTTPS:', 'Song 15'), None),
    ('Song 16', hl('https://youtu.be/bA98pYh244', 'Song 16'), None),
    ('Song 17', hl('http://classical/', 'Song 17'), None),
    ('Song 18', hl('mailto:a@b.c', 'Song 18'), None),
    ('Song 19', hl('https://www.youtube.com/watch?v?=18-Ye2L3ej8', 'Song 19'), None),
    ('', hl('https://youtu.be/JJJJJJJJJJ0', ''), None),
    # no link
    ('Song 20', None, None),
    ('Song 21', 'IFERROR(A1,"Song 21")', None),
    # a row of Song 2 without a link: its link and its place stay those of its last row with one
    ('Song 2', None, None),
]
FILLER = [(f'Filler {i}', hl(f'https://youtu.be/filler{i:05d}', f'Filler {i}'), None) for i in range(20)]

def links(extra=()):
    return xlsx(LINK_ROWS + FILLER + list(extra))

LINK_CASES = {
    'links-html': lambda: (200, 'text/html; charset=utf-8', b'<!DOCTYPE html><html>Sorry</html>'),
    'links-not-zip': lambda: (200, XLSX, b'PK but not a zip'),
    'links-404': lambda: (404, 'text/html', b'Not Found'),
    'links-no-songs': lambda: (200, XLSX, xlsx(LINK_ROWS + FILLER, sheet='Archive')),
    'links-no-title': lambda: (200, XLSX, xlsx(LINK_ROWS + FILLER, header='Name')),
    'links-few': lambda: (200, XLSX, xlsx(LINK_ROWS)),
    'links-unread': lambda: (200, XLSX, links([(f'Ref {i}', f'HYPERLINK(B{i},"Ref {i}")', None) for i in range(3)])),
    'links-shrunk': lambda: (200, XLSX, xlsx(FILLER + LINK_ROWS[:3])),
    'links-changed': lambda: (200, XLSX, links([('Song 22', hl('https://youtu.be/KKKKKKKKKK1', 'Song 22'), None)])),
}

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
        if url.path.endswith('/export'):
            # the links: good but for their own cases
            status, kind, body = LINK_CASES[case]() if case in LINK_CASES else (200, XLSX, links())
        else:
            status, kind, body = (CASES['good'] if case in LINK_CASES else CASES[case])(sheet)
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

export SNAPSHOT_MIN_HIGHLIGHT_ROWS=10 SNAPSHOT_MIN_SONG_ROWS=100 SNAPSHOT_MIN_LINK_ROWS=20 SNAPSHOT_RETRIES=0
export SNAPSHOT_LINKS_URL="http://127.0.0.1:$port/good/export?format=xlsx&gid=0"
make_case() { # make_case <case> <out> [<published>]
  SNAPSHOT_EXPORT_BASE="http://127.0.0.1:$port/$1/gviz/tq?tqx=out:csv&headers=1&sheet=" \
    SNAPSHOT_LINKS_URL="http://127.0.0.1:$port/$1/export?format=xlsx&gid=0" \
    bash "$script" make "$2" "${3:-}"
}
written() { [[ -f "$1/highlights.csv" && -f "$1/songs.csv" && -f "$1/snapshot.json" && -f "$1/song_links.tsv" ]]; }
sheets_only() { [[ -f "$1/highlights.csv" && -f "$1/songs.csv" && -f "$1/snapshot.json" && ! -e "$1/song_links.tsv" ]]; }
meta() { # meta <dir> <python expression on m, the snapshot.json of <dir>>
  python3 -I -c 'import json, sys; m = json.load(open(sys.argv[1])); assert eval(sys.argv[2]), m' "$1/snapshot.json" "$2"
}
nothing_written() { [[ ! -e "$1" ]]; }

# ------------------------------------------------------------------ make
check 'a good export is written' 0 make_case good "$tmp/good"
expect_output '  the links counted, those left out by reason' 'song links: 34 rows with a link kept (43 HYPERLINK formulas, 2 links of cells, 1 unwrapped from Google), 31 lines; left out: a page of YouTube that is no video: 1, a video without an id that reads: 2, no address: 4, no title: 1, not YouTube: 3;'
check '  with its four files' 0 written "$tmp/good"
check '  the CSV as the server gave it' 0 cmp "$tmp/good/songs.csv" <(curl -s "http://127.0.0.1:$port/good/x?sheet=Songs")
check '  the time in UTC and the row counts' 0 python3 -I -c '
import json, sys, datetime
m = json.load(open(sys.argv[1]))
assert m["madeAt"].endswith("Z"), m
datetime.datetime.strptime(m["madeAt"], "%Y-%m-%dT%H:%M:%SZ")
assert (m["highlightsRows"], m["songsRows"]) == (60, 200), m
' "$tmp/good/snapshot.json"
check '  the numbers of the links, made with the sheets' 0 meta "$tmp/good" \
  '(m["songLinksRows"], m["songLinks"], m["songLinksMadeAt"]) == (34, 31, m["madeAt"])'
printf 'link\ttitle\n' >"$tmp/expected_links.tsv"
printf '%s\t%s\n' >>"$tmp/expected_links.tsv" \
  BBBBBBBBBB2 'Song 2' \
  CCCCCCCCCC3 'Say "hi"' \
  DDDDDDDDDD4 'Song 6' \
  EEEEEEEEEE5 'Song 7' \
  FFFFFFFFFF6 'Song 9' \
  GGGGGGGGGG7 'Song 10' \
  HHHHHHHHHH8 'Song 12' \
  IIIIIIIIII9 'Song 1' \
  'KKKKKKKKKK2?t=90' 'Zelda - Lullaby / Song of Storms' \
  LLLLLLLLLL3 'Seven Spires - Succumb' \
  'MMMMMMMMMM4?t=45' 'Song 14'
for i in $(seq 0 19); do printf 'filler%05d\tFiller %s\n' "$i" "$i" >>"$tmp/expected_links.tsv"; done
check '  the links: every form read, YouTube videos only, a line per title, its last link, in the order of their rows' 0 \
  cmp "$tmp/good/song_links.tsv" "$tmp/expected_links.tsv"
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
for case in links-html links-not-zip links-404 links-no-songs links-no-title links-few links-unread; do
  check "$case: the sheets written, without links (exit 2)" 2 make_case "$case" "$tmp/$case"
  check "$case:   the sheets only" 0 sheets_only "$tmp/$case"
  check "$case:   no numbers of links" 0 meta "$tmp/$case" '"songLinks" not in m and m["songsRows"] == 200'
  check "$case: against a published snapshot (exit 2)" 2 make_case "$case" "$tmp/$case-kept" "$tmp/good"
  check "$case:   its links kept, as published" 0 cmp "$tmp/$case-kept/song_links.tsv" "$tmp/good/song_links.tsv"
  check "$case:   with their numbers" 0 meta "$tmp/$case-kept" \
    "m['songLinksMadeAt'] == '$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["songLinksMadeAt"])' "$tmp/good/snapshot.json")' and m['songLinks'] == 31"
done
check 'links-html: said why' 2 make_case links-html "$tmp/x"
expect_output '  content type' "song links: content type 'text/html; charset=utf-8', not application/vnd.openxmlformats"
expect_output '  the sheets written' 'the sheets are written, but not the links of the songs'
check 'links-not-zip: said why' 2 make_case links-not-zip "$tmp/x"
expect_output '  not an xlsx' 'song links: not an xlsx'
check 'links-404: said why' 2 make_case links-404 "$tmp/x"
expect_output '  HTTP 404' 'song links: HTTP 404'
check 'links-no-songs: said why' 2 make_case links-no-songs "$tmp/x"
expect_output '  no sheet' 'song links: no sheet "Songs"'
check 'links-no-title: said why' 2 make_case links-no-title "$tmp/x"
expect_output '  no title' 'song links: no "Title" column in row 1'
check 'links-few: said why' 2 make_case links-few "$tmp/x"
expect_output '  too few' 'song links: 14 rows with a link kept, fewer than 20'
check 'links-unread: said why' 2 make_case links-unread "$tmp/x"
expect_output '  formulas that do not read' 'song links: 3 of 46 HYPERLINK formulas do not read'
check 'links-shrunk against nothing published: taken' 0 make_case links-shrunk "$tmp/links-shrunk-alone"
check 'links-shrunk against the published snapshot: the published links kept (exit 2)' 2 make_case links-shrunk \
  "$tmp/links-shrunk" "$tmp/good"
expect_output '  said why' 'song links: 23 rows with a link kept against 34 in the published snapshot: refused'
check '  the published links kept' 0 cmp "$tmp/links-shrunk/song_links.tsv" "$tmp/good/song_links.tsv"
check 'links-shrunk, taken by hand (SNAPSHOT_ACCEPT_SMALLER=1)' 0 env SNAPSHOT_ACCEPT_SMALLER=1 \
  SNAPSHOT_EXPORT_BASE="http://127.0.0.1:$port/good/gviz/tq?sheet=" \
  SNAPSHOT_LINKS_URL="http://127.0.0.1:$port/links-shrunk/export" bash "$script" make "$tmp/links-shrunk-taken" "$tmp/good"
check '  its 23 rows' 0 meta "$tmp/links-shrunk-taken" 'm["songLinksRows"] == 23'
check 'links left over in <out-dir> by an earlier make are removed when none are made' 2 bash -c '
  cp -R "$1/good" "$1/reused"
  SNAPSHOT_EXPORT_BASE="http://127.0.0.1:$2/good/x?sheet=" SNAPSHOT_LINKS_URL="http://127.0.0.1:$2/links-404/export" \
    bash "$3" make "$1/reused"' _ "$tmp" "$port" "$script"
check '  gone' 0 sheets_only "$tmp/reused"
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
check '  holding the four files only' 0 test "$(git -C "$tmp/remote.git" ls-tree --name-only sheets-snapshot | tr '\n' ' ')" = 'highlights.csv snapshot.json song_links.tsv songs.csv '
check '  the default branch untouched' 0 test "$(git -C "$tmp/remote.git" rev-list --count master)" = 1
check 'the same sheets the next day (a new time only): nothing pushed' 0 bash -c '
  cp -R "$1/good" "$1/next-day" && sed -i.bak "s/\"madeAt\": \"[^\"]*\"/\"madeAt\": \"2099-01-01T00:00:00Z\"/" "$1/next-day/snapshot.json" && rm "$1/next-day/snapshot.json.bak"' _ "$tmp"
check '  publish says unchanged' 0 publish "$tmp/next-day"
expect_output '  unchanged' 'unchanged'
check '  the branch is where it was' 0 test "$(remote_branch)" = "$first"
check 'a sheet changed: published' 0 make_case good-changed "$tmp/changed" "$tmp/good"
check '  pushed' 0 publish "$tmp/changed"
expect_output '  because both sheets changed' 'published (highlights.csv, songs.csv changed)'
second=$(remote_branch)
check '  a second commit: the branch keeps its history' 0 test "$(git -C "$tmp/remote.git" rev-list --count sheets-snapshot)" = 2
check '  over the first one' 0 test "$(git -C "$tmp/remote.git" rev-parse 'sheets-snapshot^')" = "$first"
check '  whose sheets are still readable' 0 git -C "$tmp/remote.git" cat-file -e "$first:songs.csv"
check '  the difference of the sheet that changed, not the whole sheet' 0 bash -c '
  read -r added removed _ < <(git -C "$1/remote.git" diff --numstat "$2" "$3" -- highlights.csv)
  (( added + removed > 0 && added + removed < 20 ))' _ "$tmp" "$first" "$second"
check 'one sheet changed: published' 0 bash -c '
  cp -R "$1/changed" "$1/latest" && echo "a,row,more" >> "$1/latest/songs.csv"' _ "$tmp"
check '  pushed' 0 publish "$tmp/latest"
expect_output '  naming it alone' 'published (songs.csv changed)'
check '  a third commit' 0 test "$(git -C "$tmp/remote.git" rev-list --count sheets-snapshot)" = 3
check 'the links changed, not the sheets: published' 0 bash -c '
  SNAPSHOT_EXPORT_BASE="http://127.0.0.1:$2/good/x?sheet=" SNAPSHOT_LINKS_URL="http://127.0.0.1:$2/links-changed/export" \
    bash "$3" make "$1/links-new"
  cp "$1/latest/songs.csv" "$1/latest/highlights.csv" "$1/links-new/"' _ "$tmp" "$port" "$script"
check '  pushed' 0 publish "$tmp/links-new"
expect_output '  naming them alone' 'published (song_links.tsv changed)'
check '  a fourth commit' 0 test "$(git -C "$tmp/remote.git" rev-list --count sheets-snapshot)" = 4
check 'no links made, a sheet changed: published' 0 bash -c '
  cp -R "$1/links-new" "$1/no-links" && rm "$1/no-links/song_links.tsv" && echo "a,row,new" >> "$1/no-links/songs.csv"' _ "$tmp"
check '  pushed' 0 publish "$tmp/no-links"
expect_output '  for the sheet' 'published (songs.csv changed)'
check '  the published links stay in it' 0 test "$(git -C "$tmp/remote.git" rev-parse sheets-snapshot:song_links.tsv)" = \
  "$(git hash-object "$tmp/links-new/song_links.tsv")"
cp -R "$tmp/no-links" "$tmp/latest-2" && cp "$tmp/links-new/song_links.tsv" "$tmp/latest-2/"
rm -rf "$tmp/latest" && mv "$tmp/latest-2" "$tmp/latest"
# another run publishes between the reading of the branch and the push (a `git` that pushes its commit first)
mkdir "$tmp/bin"
real_git=$(command -v git)
cat > "$tmp/bin/git" <<WRAPPER
#!/usr/bin/env bash
if [[ "\${1:-}" == push && -n "\${RACE_COMMIT:-}" ]]; then
  "$real_git" push --quiet origin "\$RACE_COMMIT:refs/heads/sheets-snapshot"
fi
exec "$real_git" "\$@"
WRAPPER
chmod +x "$tmp/bin/git"
other_run=$(cd "$tmp/checkout" && git fetch --quiet origin sheets-snapshot && git -c user.name=t -c user.email=t@t \
  commit-tree "$(git rev-parse 'FETCH_HEAD^{tree}')" -p FETCH_HEAD -m 'the snapshot of another run')
check 'a snapshot pushed meanwhile by another run: this one fails' 1 bash -c '
  cp -R "$1/latest" "$1/raced" && echo "a,row,again" >> "$1/raced/songs.csv"
  cd "$1/checkout" && PATH="$1/bin:$PATH" RACE_COMMIT="$3" bash "$2" publish "$1/raced" 2>/dev/null' _ "$tmp" "$script" "$other_run"
check '  and the other snapshot stays: nothing published is replaced' 0 test "$(remote_branch)" = "$other_run"
# the published snapshot, 31 days old: the same sheets are pushed again (a push at least monthly)
old_commit=$(cd "$tmp/checkout" && GIT_COMMITTER_DATE="$(($(date +%s) - 31 * 86400)) +0000" \
  GIT_AUTHOR_DATE="$(($(date +%s) - 31 * 86400)) +0000" git -c user.name=t -c user.email=t@t \
  commit-tree "$(git -C "$tmp/remote.git" rev-parse 'sheets-snapshot^{tree}')" -m old)
(cd "$tmp/checkout" && git push --quiet --force origin "$old_commit:refs/heads/sheets-snapshot")
check 'unchanged but 31 days old: published again' 0 publish "$tmp/latest"
expect_output '  saying why' 'published (unchanged, but the snapshot is 31 days old)'
check '  a new commit' 0 test "$(remote_branch)" != "$old_commit"
check '  over the old one' 0 test "$(git -C "$tmp/remote.git" rev-parse 'sheets-snapshot^')" = "$old_commit"
check '  dated now' 0 test $(($(date +%s) - $(git -C "$tmp/remote.git" log -1 --format=%ct sheets-snapshot))) -lt 600
check 'unchanged and 29 days old: nothing pushed' 0 bash -c '
  cd "$1/checkout"
  c=$(GIT_COMMITTER_DATE="$(($(date +%s) - 29 * 86400)) +0000" git -c user.name=t -c user.email=t@t commit-tree "$(git -C "$1/remote.git" rev-parse "sheets-snapshot^{tree}")" -m old)
  git push --quiet --force origin "$c:refs/heads/sheets-snapshot"
  [[ "$(bash "$2" publish "$1/latest")" == unchanged ]] && [[ "$(git -C "$1/remote.git" rev-parse sheets-snapshot)" == "$c" ]]' _ "$tmp" "$script"
check 'a missing file: refused' 1 publish "$tmp/does-not-exist"

echo "$passed passed, $failed failed"
[[ $failed == 0 ]]
