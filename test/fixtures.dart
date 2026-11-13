import 'dart:math';

import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/parser.dart';
import 'package:ong_music/src/data/sheets.dart';

/// CSV text, every field quoted like the gviz export.
String csvOf(List<List<String>> rows) =>
    rows.map((row) => row.map((cell) => '"${cell.replaceAll('"', '""')}"').join(',')).join('\n');

const highlightHeader = [
  'Upload Date', 'Order', 'Video Title', 'Genre', 'Link to Video', 'Short Video / Requestor', //
  'Stream Source', 'Vocals?', 'Adult', 'Additional Notes',
];

const songHeader = [
  '  ',
  'Uptime',
  'Order',
  'Requester',
  'Title ',
  'Genre',
  'Request Type/Instrument',
  'Notes',
  'Looper',
  'File#',
];

/// A highlight row in the sheet's column order.
List<String> hRow({
  String upload = '2024-01-02',
  String order = '1',
  required String title,
  String genre = 'GAME OST',
  String link = '',
  String requester = '',
  String stream = '',
  String vocals = '',
  String adult = '',
  String notes = '',
}) => [upload, order, title, genre, link, requester, stream, vocals, adult, notes];

/// A song row in the sheet's column order.
List<String> sRow({
  required String date,
  String uptime = '',
  String order = '1',
  String requester = '',
  String title = '',
  String genre = 'GAME OST',
  String type = 'Piano',
  String notes = '',
}) => [date, uptime, order, requester, title, genre, type, notes, '', ''];

/// A "Stream Start" row.
List<String> start(String date) =>
    sRow(date: date, order: '0', requester: '-', title: 'Stream Start:', genre: '-', type: '-', notes: '-');

String highlightsCsv(List<List<String>> rows) => csvOf([highlightHeader, ...rows]);
String songsCsv(List<List<String>> rows) => csvOf([songHeader, ...rows]);

Catalogue catalogueOf({List<List<String>>? highlights, List<List<String>>? songs}) => parseCatalogue(
  highlightsCsv(highlights ?? [hRow(title: 'Some video')]),
  songsCsv(songs ?? [start('2024-01-01'), sRow(date: '2024-01-01 20:00:00', title: 'Some song')]),
);

/// A small valid pair of sheets; [tag] goes into a title to tell versions apart.
RawSheets sampleSheets({String tag = 'v1', int extraPlays = 0}) => RawSheets(
  highlightsCsv: highlightsCsv([hRow(title: 'Video $tag')]),
  songsCsv: songsCsv([
    start('2024-01-01'),
    sRow(date: '2024-01-01 20:00:00', title: 'Song $tag'),
    for (var i = 0; i < extraPlays; i++) sRow(date: '2024-01-01 21:00:00', title: 'Extra $i'),
  ]),
);

/// A pair of sheets drawn at random from [seed], with what the real ones hold: streams and their "Stream Start"
/// rows (some without a date), rows without date or with a time that is not a time of day, requesters spelt several
/// ways (decomposed accents among them), titles with runs of spaces, quotes and line breaks in cells, empty and
/// skipped rows, highlights linked to plays, links, "requested by" notes; CRLF row ends or a byte order mark at times.
/// [plays] rows of songs, a tenth as many highlights.
RawSheets generatedSheets(int seed, {int plays = 600}) {
  final rng = Random(seed);
  T pick<T>(List<T> items) => items[rng.nextInt(items.length)];
  const names = ['Alice', 'alice', 'ALICE', 'Bob', 'Zoé', 'Zoe\u0301', 'zoé', '-', '?', '', 'http://x', 'Chloë'];
  const words = ['Zelda', 'Song', 'of', 'Storms', 'Pokémon', 'Route', '1', 'Le\u0301on', '千と千尋', '"Quote"', 'a,b'];
  const genres = ['GAME OST', 'ANIME', 'Popular Music', 'MUSICIAL', ' jazz/standards ', '', 'Meme', '???'];
  const types = ['Piano', 'loop', 'Cat Piano', 'keyboard', 'Improv', '', '-'];
  String title() {
    final n = 1 + rng.nextInt(4);
    final parts = [for (var i = 0; i < n; i++) pick(words)];
    if (rng.nextInt(5) == 0) parts.insert(1, '-');
    return parts.join(rng.nextInt(6) == 0 ? '   ' : ' ') + (rng.nextInt(10) == 0 ? ' ' : '');
  }

  String date(int day) {
    final d = DateTime.utc(2019, 1, 1).add(Duration(days: day));
    final iso = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return switch (rng.nextInt(12)) {
      0 => '',
      1 => '${d.month}/${d.day}/${d.year} ${rng.nextInt(24)}:${rng.nextInt(60).toString().padLeft(2, '0')}',
      2 => '$iso 24:05:00',
      3 => iso,
      _ => '$iso ${rng.nextInt(24).toString().padLeft(2, '0')}:${rng.nextInt(60).toString().padLeft(2, '0')}:00',
    };
  }

  final songRows = <List<String>>[];
  final played = <(String, int)>[];
  var day = 0;
  for (var i = 0; i < plays; i++) {
    if (i == 0 || rng.nextInt(25) == 0) {
      day += 1 + rng.nextInt(4);
      songRows.add(rng.nextInt(8) == 0 ? start('') : start(date(day)));
      continue;
    }
    if (rng.nextInt(40) == 0) {
      songRows.add(List.filled(10, ''));
      continue;
    }
    final t = rng.nextInt(30) == 0 ? pick(['-', '~~', '']) : title();
    played.add((t, day));
    songRows.add(
      sRow(
        date: date(day),
        uptime: rng.nextBool() ? '${rng.nextInt(5)}:${rng.nextInt(60).toString().padLeft(2, '0')}:00' : '',
        order: '${1 + rng.nextInt(30)}',
        requester: pick(names),
        title: t,
        genre: pick(genres),
        type: pick(types),
        notes: pick(['', '', 'Tier 3', 'Raffle', 'line 1\nline 2', 'say "hi"']),
      ),
    );
  }
  final highlightRows = <List<String>>[];
  for (var i = 0; i < plays ~/ 10; i++) {
    final linked = played.isNotEmpty && rng.nextBool() ? pick(played) : (title(), day);
    final d = DateTime.utc(2019, 1, 1).add(Duration(days: linked.$2 + rng.nextInt(3) - 1));
    highlightRows.add(
      hRow(
        upload: pick(['2024-01-02', '3/4/2024', '', 'Premiere', '2023-12-31']),
        order: rng.nextInt(6) == 0 ? '' : '${i + 1}',
        title: linked.$1,
        genre: pick(genres),
        link: pick(['', 'https://youtu.be/abcdefghij${i % 10}', 'https://www.youtube.com/watch?v=0123456789$i', 'x']),
        requester: pick(names),
        stream: rng.nextInt(5) == 0 ? '' : '${d.year}-${d.month}-${d.day}',
        vocals: pick(['Yes', 'no', 'No singing', '-', '']),
        notes: pick(['', 'requested by "Bob"', 'Requested by Zoé.', 'line\r\nbreak']),
      ),
    );
  }
  String finish(String csv) {
    final text = rng.nextInt(3) == 0 ? csv.replaceAll('\n', '\r\n') : csv;
    return rng.nextInt(4) == 0 ? '\uFEFF$text' : text;
  }

  return RawSheets(highlightsCsv: finish(highlightsCsv(highlightRows)), songsCsv: finish(songsCsv(songRows)));
}
