"""The links of the titles of the Songs sheet (the Ong Log) to their originals, for `song_links.tsv` of the snapshot.

    python3 -I tool/song_links.py <xlsx> <out-tsv> <out-meta-json> [<published-dir>]

Called by tool/sheets_snapshot.sh (see there), standard library only. The CSV export the app reads keeps the text of
a cell, not its link: the moderators write the title of a song as `HYPERLINK("<url>","<title>")` (sometimes followed
by more text, `HYPERLINK(...) & " / ..."`), or give the cell a link of its own (a `<hyperlink>` of the sheet, its target
in the relationships of the sheet), and only the xlsx export of the sheet keeps either. This reads that export with
an XML parser: the sheet named "Songs" (through xl/workbook.xml and its relationships), its column titled "Title"
(row 1), and for each row of it the value of the cell (what the CSV gives, never the label of a formula) and its link:
the first HYPERLINK of its formula whose address is a string literal (any case, spaces, `,` or `;`, `""` for a quote),
else the link of the cell.

Only YouTube videos are kept (more than 99 % of the links): the id of the video (youtu.be/, watch?v=, shorts/, live/,
embed/, on www., m., music.youtube.com, the address of a page of Google's results leading to one unwrapped), with its
start time `t=` in seconds when it has one (`1m30s`, `90s`, `90`); its other parameters (a playlist...) are dropped.
Any other link is left out, counted by reason: no address, not YouTube, a video without an id that reads (cut short,
pasted twice). The app never opens an address of the sheet: it makes `https://youtu.be/<id>` itself.

Writes <out-tsv>, UTF-8, tab-separated: a header `link`, `title`, then one line per title as written (whitespace
collapsed) with a link, in the order of its last row with a link: `<id>` or `<id>?t=<seconds>`, the link of that row
(the most recent: the moderators replace dead links), and the title. The app groups the lines by its own key of a song
(`songKey`, lib/src/data/text.dart), the last line of a song winning: nothing here knows of songs.
<out-meta-json>: {"songLinksRows": rows with a link kept, "songLinks": lines}.

Fails (exit 1, a line `::error::...` on stderr, nothing written) on any doubt: not an xlsx, no sheet "Songs", no
"Title" column, more than 1 % of its HYPERLINK formulas without an address that reads, fewer than
SNAPSHOT_MIN_LINK_ROWS rows with a link kept [10000], or a loss of more than SNAPSHOT_MAX_LOSS [0.1] of them against
the `songLinksRows` of <published-dir>/snapshot.json (unless SNAPSHOT_ACCEPT_SMALLER=1).
"""

import json
import os
import posixpath
import re
import sys
import time
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile

MAIN = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
REL = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}'
PACKAGE_REL = '{http://schemas.openxmlformats.org/package/2006/relationships}'

# the largest part of the archive read: the Songs sheet is 25 MB today
MAX_PART_BYTES = 400 * 1024 * 1024

# the address of a HYPERLINK call written as a string literal, wherever the call is in the formula
FORMULA = re.compile(r'\bhyperlink\s*\(\s*"((?:[^"]|"")*)"\s*[,;)]', re.IGNORECASE)
CELL_REF = re.compile(r'^\$?([A-Z]+)\$?(\d+)$')
VIDEO_ID = re.compile(r'^[A-Za-z0-9_-]{11}$')
YOUTUBE_HOSTS = {'youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com'}
SHORT_HOSTS = {'youtu.be', 'www.youtu.be'}
# the forms of address with the id as the segment after the first: /shorts/<id>, /embed/<id>...
ID_PATHS = {'shorts', 'embed', 'live'}
START = re.compile(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?$')


class Doubt(Exception):
    pass


def start_of(parts):
    """The start time of a video address, in seconds (`t=1m30s`, `t=90s`, `t=90`, in the query or after `#`), or 0."""
    for text in (parts.query, parts.fragment):
        value = (urllib.parse.parse_qs(text).get('t') or [''])[0].strip().lower()
        m = START.match(value) if value else None
        if m and any(m.groups()):
            h, mi, sec = (int(g or 0) for g in m.groups())
            return h * 3600 + mi * 60 + sec
    return 0


def link_of(url, inner=False):
    """(the link of [url] as the file writes it, None) or (None, why it is left out); a third value tells whether it
    was unwrapped from a link of Google's results."""
    url = url.strip()
    if not re.match(r'(?i)https?://', url):
        # an address of YouTube written without its scheme
        if re.match(r'(?i)((www|m|music)\.)?(youtube\.com|youtu\.be)/', url):
            url = 'https://' + url
        else:
            return None, 'no address', False
    try:
        parts = urllib.parse.urlsplit(url)
        host = (parts.hostname or '').lower()
    except ValueError:
        return None, 'no address', False
    if not host:
        return None, 'no address', False
    segments = [s for s in parts.path.split('/') if s]
    # a link of a page of Google's results (www.google.com/url?...&url=<address>): the address it leads to
    if re.match(r'^(www\.)?google\.[a-z.]+$', host) and segments == ['url'] and not inner:
        query = urllib.parse.parse_qs(parts.query)
        target = (query.get('url') or query.get('q') or [''])[0]
        link, reason, _ = link_of(target, inner=True)
        return link, reason, link is not None
    if host in SHORT_HOSTS:
        video = segments[0] if segments else ''
    elif host in YOUTUBE_HOSTS and segments == ['watch']:
        video = (urllib.parse.parse_qs(parts.query).get('v') or [''])[0]
    elif host in YOUTUBE_HOSTS and len(segments) >= 2 and segments[0] in ID_PATHS:
        video = segments[1]
    elif host in SHORT_HOSTS | YOUTUBE_HOSTS:
        return None, 'a page of YouTube that is no video', False
    else:
        return None, 'not YouTube', False
    if not VIDEO_ID.match(video):
        return None, 'a video without an id that reads', False
    start = start_of(parts)
    return (f'{video}?t={start}' if start else video), None, False


def column_number(letters):
    n = 0
    for c in letters:
        n = n * 26 + ord(c) - 64
    return n


def text_of(element):
    """The text of a shared or inline string: its `<t>`, or those of its runs, without the phonetic ones."""
    if element is None:
        return ''
    parts = []
    for child in element:
        if child.tag == MAIN + 't':
            parts.append(child.text or '')
        elif child.tag == MAIN + 'r':
            parts.extend(t.text or '' for t in child.iter(MAIN + 't'))
    return ''.join(parts)


class Book:
    def __init__(self, path):
        try:
            self.zip = zipfile.ZipFile(path)
        except (zipfile.BadZipFile, OSError) as e:
            raise Doubt(f'not an xlsx ({e})')
        self.names = set(self.zip.namelist())

    def part(self, name):
        if name not in self.names:
            raise Doubt(f'no part {name}')
        if self.zip.getinfo(name).file_size > MAX_PART_BYTES:
            raise Doubt(f'{name} larger than {MAX_PART_BYTES} bytes')
        return self.zip.open(name)

    def xml(self, name):
        try:
            with self.part(name) as f:
                return ET.parse(f).getroot()
        except ET.ParseError as e:
            raise Doubt(f'{name} does not read ({e})')

    def relationships(self, name):
        """The relationships of part [name]: {id: (type, target part or external address, external)}."""
        folder, base = posixpath.split(name)
        rels = posixpath.join(folder, '_rels', base + '.rels')
        if rels not in self.names:
            return {}
        result = {}
        for r in self.xml(rels).iter(PACKAGE_REL + 'Relationship'):
            target = r.get('Target', '')
            external = r.get('TargetMode') == 'External'
            if not external:
                target = target.lstrip('/') if target.startswith('/') else posixpath.normpath(
                    posixpath.join(folder, target))
            result[r.get('Id')] = (r.get('Type', ''), target, external)
        return result


def read_links(path):
    book = Book(path)
    workbook = 'xl/workbook.xml'
    rels = book.relationships(workbook)
    sheet = None
    for s in book.xml(workbook).iter(MAIN + 'sheet'):
        if (s.get('name') or '').strip() == 'Songs':
            rel = rels.get(s.get(REL + 'id'))
            if rel is None or rel[2]:
                raise Doubt('the sheet "Songs" has no part')
            sheet = rel[1]
    if sheet is None:
        raise Doubt('no sheet "Songs"')
    shared = []
    for kind, target, external in rels.values():
        if kind.endswith('/sharedStrings') and not external:
            shared = [text_of(si) for si in book.xml(target).iter(MAIN + 'si')]
    sheet_rels = book.relationships(sheet)

    # the cells of the title column, by row: (text, link of its formula); the column known from row 1
    title_column = None
    cells = {}
    formulas = unread = 0
    hyperlinks = []
    row_number = 0
    try:
        with book.part(sheet) as f:
            for _, element in ET.iterparse(f, events=('end',)):
                tag = element.tag
                if tag == MAIN + 'row':
                    row = int(element.get('r') or row_number + 1)
                    column = 0
                    for c in element.iter(MAIN + 'c'):
                        ref = CELL_REF.match(c.get('r') or '')
                        column = column_number(ref.group(1)) if ref else column + 1
                        if row == 1:
                            if title_column is None and value_of(c, shared).strip().lower() == 'title':
                                title_column = column
                            continue
                        if column != title_column:
                            continue
                        link = None
                        formula = c.find(MAIN + 'f')
                        if formula is not None and formula.text and 'hyperlink' in formula.text.lower():
                            formulas += 1
                            m = FORMULA.search(formula.text)
                            if m:
                                link = m.group(1).replace('""', '"')
                            else:
                                unread += 1
                        cells[row] = (value_of(c, shared), link)
                    row_number = row
                    if row == 1 and title_column is None:
                        raise Doubt('no "Title" column in row 1')
                    element.clear()
                elif tag == MAIN + 'hyperlink':
                    hyperlinks.append((element.get('ref') or '', element.get(REL + 'id')))
    except ET.ParseError as e:
        raise Doubt(f'{sheet} does not read ({e})')
    if title_column is None:
        raise Doubt('no "Title" column in row 1')
    if formulas and unread > formulas / 100:
        raise Doubt(f'{unread} of {formulas} HYPERLINK formulas do not read')

    # the links of the cells themselves, where no formula gives one
    by_cell = {}
    for ref, rid in hyperlinks:
        rel = sheet_rels.get(rid)
        if rel is None or not rel[2]:
            continue  # a link inside the workbook
        first, _, last = ref.partition(':')
        a, b = CELL_REF.match(first), CELL_REF.match(last or first)
        if not a or not b:
            continue
        if column_number(a.group(1)) <= title_column <= column_number(b.group(1)):
            for row in range(int(a.group(2)), int(b.group(2)) + 1):
                by_cell.setdefault(row, rel[1])
    # per title as written: the link of its last row with one; in the order of those rows
    lines = {}
    rows = from_cells = unwrapped = 0
    dropped = {}
    for row in sorted(cells):
        text, url = cells[row]
        if url is None and row in by_cell:
            url = by_cell[row]
            from_cells += 1
        if url is None:
            continue
        link, reason, from_google = link_of(url)
        title = ' '.join(text.split())
        if link is not None and not title:
            reason = 'no title'
        if reason is not None:
            dropped[reason] = dropped.get(reason, 0) + 1
            continue
        rows += 1
        unwrapped += from_google
        lines.pop(title, None)
        lines[title] = link
    return lines, {'rows': rows, 'formulas': formulas, 'cells': from_cells, 'unwrapped': unwrapped,
                   'dropped': dropped}


def value_of(c, shared):
    kind = c.get('t')
    if kind == 'inlineStr':
        return text_of(c.find(MAIN + 'is'))
    v = c.find(MAIN + 'v')
    text = (v.text or '') if v is not None else ''
    if kind == 's':
        try:
            return shared[int(text)]
        except (ValueError, IndexError):
            raise Doubt(f'cell {c.get("r")}: no shared string {text!r}')
    return text


def main():
    xlsx, out_tsv, out_meta = sys.argv[1:4]
    published = sys.argv[4] if len(sys.argv) > 4 else ''
    env = os.environ
    started = time.monotonic()
    try:
        lines, stats = read_links(xlsx)
        minimum = int(env.get('SNAPSHOT_MIN_LINK_ROWS', '10000'))
        if stats['rows'] < minimum:
            raise Doubt(f'{stats["rows"]} rows with a link kept, fewer than {minimum}')
        before = None
        if published and os.path.isfile(os.path.join(published, 'snapshot.json')):
            with open(os.path.join(published, 'snapshot.json'), encoding='utf-8') as f:
                before = json.load(f).get('songLinksRows')
        max_loss = float(env.get('SNAPSHOT_MAX_LOSS', '0.1'))
        if isinstance(before, int) and stats['rows'] < before * (1 - max_loss):
            message = f'{stats["rows"]} rows with a link kept against {before} in the published snapshot'
            if env.get('SNAPSHOT_ACCEPT_SMALLER') != '1':
                raise Doubt(f'{message}: refused (SNAPSHOT_ACCEPT_SMALLER=1 to take it)')
            print(f'song links: {message}: taken (SNAPSHOT_ACCEPT_SMALLER=1)', file=sys.stderr)
    except Doubt as e:
        print(f'::error::sheets snapshot: song links: {e}', file=sys.stderr)
        sys.exit(1)
    with open(out_tsv, 'w', encoding='utf-8', newline='\n') as f:
        f.write('link\ttitle\n')
        for title, link in lines.items():
            f.write(f'{link}\t{title}\n')
    with open(out_meta, 'w', encoding='utf-8') as f:
        json.dump({'songLinksRows': stats['rows'], 'songLinks': len(lines)}, f)
    dropped = ', '.join(f'{reason}: {n}' for reason, n in sorted(stats['dropped'].items())) or 'none'
    print(f'song links: {stats["rows"]} rows with a link kept ({stats["formulas"]} HYPERLINK formulas, '
          f'{stats["cells"]} links of cells, {stats["unwrapped"]} unwrapped from Google), {len(lines)} lines; '
          f'left out: {dropped}; read in {time.monotonic() - started:.1f} s')


if __name__ == '__main__':
    main()
