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
