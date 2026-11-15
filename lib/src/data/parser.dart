/// Turns the CSV text of the two sheets into a [Catalogue].
///
/// Pure Dart (no Flutter import): runs in an isolate, in `dart run` scripts
/// and in unit tests.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'catalogue.dart';
import 'csv.dart';
import 'model.dart';
import 'requester_aliases.dart';
import 'sheet_zone.dart';
import 'slices.dart';
import 'text.dart';

/// The payload is not one of the expected sheets (missing header, HTML page,
/// empty result...). A fetch that produces it must be rejected.
class CatalogueFormatException extends FormatException {
  /// Creates the exception.
  const CatalogueFormatException(super.message);
}

/// A column of a sheet: the header names it may have, and its index when no
/// header matches.
typedef ColumnSpec = ({List<String> names, int fallback});

/// Columns of the "Youtube Catalogue" sheet.
abstract final class HighlightColumns {
  static const ColumnSpec uploadDate = (names: ['upload date'], fallback: 0);
  static const ColumnSpec order = (names: ['order'], fallback: 1);
  static const ColumnSpec title = (names: ['video title', 'title'], fallback: 2);
  static const ColumnSpec genre = (names: ['genre'], fallback: 3);
  static const ColumnSpec link = (names: ['link to video', 'video link', 'link'], fallback: 4);
  static const ColumnSpec requester = (names: ['short video / requestor', 'requestor', 'requester'], fallback: 5);
  static const ColumnSpec streamSource = (names: ['stream source', 'stream date'], fallback: 6);
  static const ColumnSpec vocals = (names: ['vocals?', 'vocals'], fallback: 7);
  static const ColumnSpec notes = (names: ['additional notes', 'notes'], fallback: 9);
}

/// Columns of the "Songs" sheet (the Ong Log). Its date column has no header.
abstract final class SongColumns {
  static const ColumnSpec date = (names: ['date'], fallback: 0);
  static const ColumnSpec uptime = (names: ['uptime'], fallback: 1);
  static const ColumnSpec order = (names: ['order'], fallback: 2);
  static const ColumnSpec requester = (names: ['requester', 'requestor'], fallback: 3);
  static const ColumnSpec title = (names: ['title'], fallback: 4);
  static const ColumnSpec genre = (names: ['genre'], fallback: 5);
  static const ColumnSpec type = (
    names: ['request type/instrument', 'request type', 'type', 'instrument'],
    fallback: 6,
  );
  static const ColumnSpec notes = (names: ['notes'], fallback: 7);
}

/// Header-to-index resolution for one sheet.
final class ColumnResolver {
  /// Indexes [header] (cells trimmed, lowercased; the first of duplicates wins).
  ColumnResolver(List<Object?> header) {
    for (var i = 0; i < header.length; i++) {
      _byName.putIfAbsent((header[i]?.toString() ?? '').trim().toLowerCase(), () => i);
    }
  }

  final Map<String, int> _byName = {};

  /// Index of the first header of [spec] present, else null.
  int? find(ColumnSpec spec) {
    for (final name in spec.names) {
      final i = _byName[name];
      if (i != null) return i;
    }
    return null;
  }

  /// Index by header name, falling back to the spec's index.
  int resolve(ColumnSpec spec) => find(spec) ?? spec.fallback;
}

/// The rows of a sheet, in steps of [unitsPerStep] code units, then of [rowsPerStep] rows: added to [rows].
Iterable<void> _decode(
  String text,
  String sheet,
  List<List<String>> rows, {
  required int unitsPerStep,
  required int rowsPerStep,
}) sync* {
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) throw CatalogueFormatException('$sheet: empty payload');
  if (trimmed.startsWith('<')) throw CatalogueFormatException('$sheet: HTML instead of CSV');
  // composeMarks: cells typed with decomposed accents search and display like the others
  final composer = MarkComposer(text.startsWith('\uFEFF') ? text.substring(1) : text);
  while (composer.compose(unitsPerStep)) {
    yield null;
  }
  final reader = CsvReader(composer.result);
  while (reader.read(rowsPerStep)) {
    yield null;
  }
  rows.addAll(reader.rows);
}

String _cell(List<String> row, int index) => index < row.length ? row[index] : '';

String? _requesterCell(String cell) {
  final x = cell.trim();
  if (x.isEmpty || x == '-' || x == '?' || x.startsWith('http')) return null;
  return x;
}

final _uptime = RegExp(r'^(\d+):(\d\d):(\d\d)$');

/// A running time (`0:02:13`, `1:28:35`): what some rows of the Songs sheet carry in their Requester cell since
/// September 2025, the time of the "Concert Grand" part. It names no requester.
final _duration = RegExp(r'^\d+(?::\d+)+$');

/// The title of a marker the moderators write among the songs of the Songs sheet (its whitespace collapsed): a
/// second "Stream Start" of a stream, or a step of the "Concert Grand" (`Concert Grand Start`, `CG Played`,
/// `(concert grand)`, `End of Concert Grand`...). A title that only holds those words further in, or that begins
/// with a longer word (`Stream Started`), is a song's.
final _markerTitle = RegExp(
  r'^(?:stream start|\(? ?(?:start of |end of |end )?(?:concert grand|cg))\b',
  caseSensitive: false,
);

/// Whether [title] is that of a marker ([_markerTitle]). Most titles begin with another letter than those of the
/// markers: they are told apart without the regular expression (a millisecond for the 11,000 titles of the sheet).
bool _isMarkerTitle(String title) {
  if (title.isEmpty) return false;
  // ASCII letters lowercased; "(" stays itself
  final first = title.codeUnitAt(0) | 0x20;
  return (first == 0x73 || first == 0x63 || first == 0x65 || first == 0x28) && _markerTitle.hasMatch(title);
}

/// Whether a row of the Songs sheet of [requesterCell] and [genreCell] is a marker: a running time instead of a
/// requester, and no genre. With a genre it is a song played during the Concert Grand, without requester.
bool _isTimeMarker(String requesterCell, String genreCell) {
  final genre = genreCell.trim();
  return (genre.isEmpty || genre == '-') && _duration.hasMatch(requesterCell.trim());
}

final _youtube = RegExp(r'(?:youtu\.be/|v=)([\w-]{11})');

/// The ids of the YouTube videos linked in [text], in their order: the forms of
/// the "Link to Video" cells (`youtu.be/<id>`, `youtube.com/watch?v=<id>`),
/// wherever they are in it.
Iterable<String> youtubeIdsIn(String text) => _youtube.allMatches(text).map((m) => m[1]!);
final _requestedBy = RegExp(r'requested by "?([^"\s,.;]+)"?', caseSensitive: false);
final _digits = RegExp(r'^\d+$');

/// Beyond it an uptime is not one (over a century), and its minutes would not be exact in every build.
const _maxUptimeHours = 999999;

/// The uptime of a cell (`h:mm:ss`) in seconds, -1 when it is not one. Its minutes, `~/ 60`, are the length of a
/// stream; its seconds the position of a play in the VOD (`Catalogue.uptimeOf`).
int _uptimeSeconds(String cell) {
  final m = _uptime.firstMatch(cell.trim());
  if (m == null) return -1;
  // an absurdly long number must not reject the whole sheet (int.parse throws on native), and gives none in every
  // build
  final hours = tryParseExactInt(m[1]!);
  return hours == null || hours > _maxUptimeHours ? -1 : hours * 3600 + int.parse(m[2]!) * 60 + int.parse(m[3]!);
}

/// The largest uptime [Int32List] holds: beyond (68 years), a play has none (`Catalogue.uptimeOf`).
const _maxStoredUptime = 0x7fffffff;

/// The instant of a date cell with a time, in minutes since the epoch (see `Play.loggedMinute`), or null.
int? _instant(({CalendarDate date, int? minute})? cell) {
  final minute = cell?.minute;
  return minute == null ? null : SheetZone.epochMinute(cell!.date, minute);
}

/// Parses both sheets and builds the catalogue: [parseHighlights], then [parseSongs] against its highlights.
///
/// Throws [CatalogueFormatException] when a payload does not look like its
/// sheet: no title column header, HTML, or no highlight / no play at all.
///
/// The names of one group of [aliases] are one requester (see [RequesterAliases]); the app's by default.
Catalogue parseCatalogue(String highlightsCsv, String songsCsv, {RequesterAliases? aliases}) {
  final load = CatalogueLoad(highlightsCsv, songsCsv, aliases: aliases);
  while (load.step()) {}
  return load.catalogue;
}

/// Parses the "Youtube Catalogue" sheet alone: a catalogue without the Songs sheet (`Catalogue.hasSongs` false),
/// which the Highlights list needs no more than.
///
/// Throws [CatalogueFormatException] when the payload does not look like the sheet. [aliases] as for
/// [parseCatalogue]: the catalogue keeps them, and [parseSongs] uses them too.
Catalogue parseHighlights(String highlightsCsv, {RequesterAliases? aliases}) {
  final load = HighlightsLoad(highlightsCsv, aliases: aliases);
  while (load.step()) {}
  return load.catalogue;
}

/// Parses the "Songs" sheet against the highlights of [highlights] (its `Catalogue.highlightsOnly`): what
/// `Catalogue.withSongs` adds to it.
///
/// Throws [CatalogueFormatException] when the payload does not look like the sheet.
SongsPart parseSongs(Catalogue highlights, String songsCsv) {
  final load = SongsLoad(highlights, songsCsv);
  while (load.step()) {}
  return load.songs;
}

/// [parseHighlights] taking one record argument, for `compute` / `Isolate.run`: the sheet and the groups of names of
/// one requester (the app's by default).
Catalogue parseHighlightsRecord(({String highlightsCsv, RequesterAliases? aliases}) input) =>
    parseHighlights(input.highlightsCsv, aliases: input.aliases);

/// [parseSongs] taking one record argument, for `compute` / `Isolate.run`: only the [SongsPart] comes back, without
/// a copy of the highlights.
SongsPart parseSongsRecord(({Catalogue highlights, String songsCsv}) input) =>
    parseSongs(input.highlights, input.songsCsv);

/// Checks the arguments of a load in steps: a step of nothing would never end it.
void _checkSteps(int rowsPerStep, int unitsPerStep) {
  if (rowsPerStep < 1) throw ArgumentError.value(rowsPerStep, 'rowsPerStep', 'must be at least 1');
  if (unitsPerStep < 1) throw ArgumentError.value(unitsPerStep, 'unitsPerStep', 'must be at least 1');
}

/// [parseHighlights] in steps: each call of [step] does the work up to its next pause point, so that the load can
/// stop there and go on later. The web runs it in slices between frames (see `runInSlices`), which keeps the page
/// drawing.
///
/// It is the one parser of the sheet: [parseHighlights] runs the same steps to the end in one go. So the catalogue
/// is the same however the load is cut, and so are the exceptions.
///
/// The pause points come every [rowsPerStep] rows in the loops over rows (the CSV text, the builder, the indexes of
/// the catalogue) and every [unitsPerStep] code units in those over the text; the defaults, [rowsPerPause] and
/// [unitsPerPause], keep a step around a millisecond or less on a fast laptop.
final class HighlightsLoad {
  /// A load of the "Youtube Catalogue" sheet, nothing done yet. [aliases] as for [parseHighlights].
  HighlightsLoad(
    String highlightsCsv, {
    int rowsPerStep = rowsPerPause,
    int unitsPerStep = unitsPerPause,
    RequesterAliases? aliases,
  }) {
    _checkSteps(rowsPerStep, unitsPerStep);
    _steps = _load(highlightsCsv, rowsPerStep, unitsPerStep, aliases ?? RequesterAliases.bundled).iterator;
  }

  late final Iterator<void> _steps;
  Catalogue? _catalogue;

  /// The catalogue of the highlights, once [step] returned false.
  Catalogue get catalogue => _catalogue ?? (throw StateError('The highlights are not loaded yet'));

  /// Does the work up to the next pause point. Returns whether there is more to do: false once [catalogue] is
  /// there. Throws what [parseHighlights] throws, and the load is over then.
  bool step() => _steps.moveNext();

  Iterable<void> _load(String highlightsCsv, int rowsPerStep, int unitsPerStep, RequesterAliases aliases) sync* {
    final rows = <List<String>>[];
    yield* _decode(highlightsCsv, 'Highlights', rows, unitsPerStep: unitsPerStep, rowsPerStep: rowsPerStep);
    final cols = ColumnResolver(rows.first);
    if (cols.find(HighlightColumns.title) == null || cols.find(HighlightColumns.uploadDate) == null) {
      throw const CatalogueFormatException('Highlights: "Video Title" / "Upload Date" header not found');
    }
    final b = _HighlightsBuilder(rows, cols, rowsPerStep, aliases);
    yield* b.build();
    if (b.highlights.isEmpty) throw const CatalogueFormatException('Highlights: no row');
    yield* Catalogue.assembleHighlights(
      highlights: b.highlights,
      requesters: b.requesters,
      spellings: b.spellings,
      aliases: aliases,
      done: (catalogue) => _catalogue = catalogue,
      pauseEvery: rowsPerStep,
    );
  }
}

/// [parseSongs] in steps, as [HighlightsLoad] does for its sheet, with the aliases of the highlights' catalogue.
final class SongsLoad {
  /// A load of the "Songs" sheet against the highlights of [highlights], nothing done yet.
  SongsLoad(Catalogue highlights, String songsCsv, {int rowsPerStep = rowsPerPause, int unitsPerStep = unitsPerPause}) {
    _checkSteps(rowsPerStep, unitsPerStep);
    _steps = _load(highlights.highlightsOnly, songsCsv, rowsPerStep, unitsPerStep).iterator;
  }

  late final Iterator<void> _steps;
  SongsPart? _songs;

  /// What the sheet adds to the highlights, once [step] returned false.
  SongsPart get songs => _songs ?? (throw StateError('The songs are not loaded yet'));

  /// Does the work up to the next pause point. Returns whether there is more to do: false once [songs] is there.
  /// Throws what [parseSongs] throws, and the load is over then.
  bool step() => _steps.moveNext();

  Iterable<void> _load(Catalogue highlights, String songsCsv, int rowsPerStep, int unitsPerStep) sync* {
    final rows = <List<String>>[];
    yield* _decode(songsCsv, 'Songs', rows, unitsPerStep: unitsPerStep, rowsPerStep: rowsPerStep);
    final cols = ColumnResolver(rows.first);
    if (cols.find(SongColumns.title) == null) {
      throw const CatalogueFormatException('Songs: "Title" header not found');
    }
    final b = _SongsBuilder(highlights, rows, cols, rowsPerStep);
    yield* b.build();
    if (b.plays.isEmpty) throw const CatalogueFormatException('Songs: no row');
    yield* SongsPart.assemble(
      plays: b.plays,
      streams: b.streams,
      requesters: b.requesters,
      titles: b.titles,
      songs: b.songs,
      highlightPlays: b.highlightPlays,
      playUptimes: b.playUptimes,
      aliases: highlights.aliases,
      done: (songs) => _songs = songs,
      pauseEvery: rowsPerStep,
    );
  }
}

/// [parseCatalogue] in steps: a [HighlightsLoad], then a [SongsLoad] against its catalogue.
final class CatalogueLoad {
  /// A load of both sheets, nothing done yet.
  CatalogueLoad(
    String highlightsCsv,
    String songsCsv, {
    int rowsPerStep = rowsPerPause,
    int unitsPerStep = unitsPerPause,
    RequesterAliases? aliases,
  }) {
    _checkSteps(rowsPerStep, unitsPerStep);
    _steps = _load(highlightsCsv, songsCsv, rowsPerStep, unitsPerStep, aliases).iterator;
  }

  late final Iterator<void> _steps;
  Catalogue? _catalogue;

  /// The catalogue, once [step] returned false.
  Catalogue get catalogue => _catalogue ?? (throw StateError('The catalogue is not loaded yet'));

  /// Does the work up to the next pause point. Returns whether there is more to do: false once [catalogue] is
  /// there. Throws what [parseCatalogue] throws, and the load is over then.
  bool step() => _steps.moveNext();

  Iterable<void> _load(
    String highlightsCsv,
    String songsCsv,
    int rowsPerStep,
    int unitsPerStep,
    RequesterAliases? aliases,
  ) sync* {
    final highlights = HighlightsLoad(
      highlightsCsv,
      rowsPerStep: rowsPerStep,
      unitsPerStep: unitsPerStep,
      aliases: aliases,
    );
    while (highlights.step()) {
      yield null;
    }
    final songs = SongsLoad(highlights.catalogue, songsCsv, rowsPerStep: rowsPerStep, unitsPerStep: unitsPerStep);
    while (songs.step()) {
      yield null;
    }
    _catalogue = highlights.catalogue.withSongs(songs.songs);
  }
}

/// [parseCatalogue] taking one record argument, for `compute` / `Isolate.run`.
Catalogue parseCatalogueRecord(({String highlightsCsv, String songsCsv}) sheets) =>
    parseCatalogue(sheets.highlightsCsv, sheets.songsCsv);

class _StreamDraft {
  _StreamDraft(this.date, this.start, [this.startMinute]);

  /// Null until known: the date of its "Stream Start" row could not be read.
  CalendarDate? date;
  final int start;

  /// The instant of its "Stream Start" row (`LiveStream.startMinute`), null when the row has no time.
  int? startMinute;
  int count = 0;

  /// The largest uptime of its rows, markers included, in seconds ([_uptimeSeconds]); 0 without any.
  int seconds = 0;
}

class _PlayDraft {
  _PlayDraft(
    this.minute,
    this.date,
    this.titleId,
    this.genre,
    this.type,
    this.requester,
    this.flag,
    this.stream,
    this.uptime,
  );
  final int? minute;
  final CalendarDate date;
  final int titleId;
  final Genre genre;
  final PlayType type;
  final int? requester;
  final PlayFlag flag;
  final _StreamDraft stream;

  /// Seconds, -1 for none ([_uptimeSeconds]).
  final int uptime;
  int? highlight;
}

/// The requesters met in a sheet: their ids in order of first use, and the spellings of their names.
///
/// A requester is a folded name, or a group of [aliases] (its key, `RequesterAliases.keyOf`). The work on a cell is
/// done once per distinct cell, where it is first met: the rows only look the cell up in a map.
class _Requesters {
  _Requesters(this.spellings, this.aliases, [List<String> folds = const []])
    : _folds = [...folds],
      _ids = {for (var i = 0; i < folds.length; i++) folds[i]: i};

  /// Key, then the count of each spelling, in order of first appearance.
  final Map<String, Map<String, int>> spellings;
  final RequesterAliases aliases;
  final List<String> _folds;
  final Map<String, int> _ids;

  /// The id of each cell met by [id] (trimmed), -1 for one that names no requester.
  final Map<String, int> _idOfCell = {};

  /// The count of each spelling met by [countSpelling], in order of first appearance, until [addCountedSpellings].
  final Map<String, int> _counted = {};

  /// The keys, by id.
  List<String> get folds => _folds;

  /// The key of the requester [name] (a trimmed cell) names, or null: a running time names none.
  String? _keyOf(String name) => _duration.hasMatch(name) ? null : aliases.keyOf(fold(name));

  void countSpelling(String cell) {
    final name = _requesterCell(cell);
    if (name == null) return;
    _counted[name] = (_counted[name] ?? 0) + 1;
  }

  /// Adds the spellings [countSpelling] counted to [spellings], under the keys of their requesters: those of one key
  /// in the order the rows first gave them.
  void addCountedSpellings() {
    _counted.forEach((name, count) {
      final key = _keyOf(name);
      if (key == null) return;
      final counts = spellings.putIfAbsent(key, () => {});
      counts[name] = (counts[name] ?? 0) + count;
    });
    _counted.clear();
  }

  int? id(String cell) {
    final name = _requesterCell(cell);
    if (name == null) return null;
    final id = _idOfCell[name] ??= _newCell(name);
    return id < 0 ? null : id;
  }

  int _newCell(String name) {
    final key = _keyOf(name);
    if (key == null) return -1;
    final id = _ids.putIfAbsent(key, () {
      _folds.add(key);
      spellings.putIfAbsent(key, () => {name: 0});
      return _folds.length - 1;
    });
    // a name of a group met only in the notes of a highlight is one of its other names, under no count
    if (aliases.isGroup(key)) spellings.putIfAbsent(key, () => {}).putIfAbsent(name, () => 0);
    return id;
  }

  /// The requester of id [id], with the most frequent of its spellings, and for a group of [aliases] its other names.
  Requester requester(int id, int requestCount) {
    final key = _folds[id];
    final counts = spellings[key]!;
    final name = _mostFrequent(counts);
    return Requester(
      id: id,
      name: name,
      folded: key,
      requestCount: requestCount,
      otherNames: aliases.isGroup(key) ? _otherNames(counts, fold(name)) : const [],
    );
  }

  /// The names of [counts] (the spellings of a group) other than [shown] (folded), each under its most frequent
  /// spelling, the most counted first, then in order of first appearance.
  static List<String> _otherNames(Map<String, int> counts, String shown) {
    final byFold = <String, Map<String, int>>{};
    counts.forEach((name, count) {
      final f = fold(name);
      if (f != shown) (byFold[f] ??= {})[name] = count;
    });
    final names = [
      for (final (i, spellings) in byFold.values.indexed)
        (name: _mostFrequent(spellings), count: spellings.values.fold(0, (sum, n) => sum + n), order: i),
    ]..sort((a, b) => a.count != b.count ? b.count.compareTo(a.count) : a.order.compareTo(b.order));
    return List.unmodifiable([for (final n in names) n.name]);
  }

  static String _mostFrequent(Map<String, int> counts) {
    String? best;
    var bestCount = -1;
    counts.forEach((name, count) {
      if (count > bestCount) {
        best = name;
        bestCount = count;
      }
    });
    return best!;
  }
}

/// Calls [chunk] on the indexes from [from] to [to], [pauseEvery] at a time, with a pause point after each call.
Iterable<void> _inSteps(int pauseEvery, int from, int to, void Function(int from, int to) chunk) sync* {
  for (var i = from; i < to; i += pauseEvery) {
    chunk(i, to - i > pauseEvery ? i + pauseEvery : to);
    yield null;
  }
}

/// Builds the highlights and their requesters from the rows of the "Youtube Catalogue" sheet.
///
/// [build] only orders the work and its pause points; the loops over the rows are in methods of their own that do
/// [pauseEvery] rows at a time ([_inSteps]). Written as a generator, a loop is a state machine on the web, its locals
/// are kept off the registers, and a large one is not optimised: the whole build took half as long again.
class _HighlightsBuilder {
  _HighlightsBuilder(this.rows, ColumnResolver cols, this.pauseEvery, RequesterAliases aliases)
    : _requesters = _Requesters({}, aliases),
      _upload = cols.resolve(HighlightColumns.uploadDate),
      _order = cols.resolve(HighlightColumns.order),
      _title = cols.resolve(HighlightColumns.title),
      _genre = cols.resolve(HighlightColumns.genre),
      _link = cols.resolve(HighlightColumns.link),
      _requester = cols.resolve(HighlightColumns.requester),
      _stream = cols.resolve(HighlightColumns.streamSource),
      _vocals = cols.resolve(HighlightColumns.vocals),
      _notes = cols.resolve(HighlightColumns.notes);

  final List<List<String>> rows;
  final int pauseEvery;
  final int _upload, _order, _title, _genre, _link, _requester, _stream, _vocals, _notes;

  final _Requesters _requesters;
  final List<Highlight> _highlights = [];
  int _seq = 1;

  late final List<Highlight> highlights;
  late final List<Requester> requesters;
  Map<String, Map<String, int>> get spellings => _requesters.spellings;

  Iterable<void> build() sync* {
    yield* _inSteps(pauseEvery, 1, rows.length, _countSpellings);
    _requesters.addCountedSpellings();
    yield* _inSteps(pauseEvery, 1, rows.length, _addHighlights);
    highlights = List.unmodifiable(_highlights);
    requesters = List.unmodifiable([for (var i = 0; i < _requesters.folds.length; i++) _requesters.requester(i, 0)]);
  }

  void _countSpellings(int from, int to) {
    for (var i = from; i < to; i++) {
      _requesters.countSpelling(_cell(rows[i], _requester));
    }
  }

  void _addHighlights(int from, int to) {
    final hl = _highlights;
    var seq = _seq;
    for (var i = from; i < to; i++) {
      final row = rows[i];
      final order = _cell(row, _order).trim();
      if (_digits.hasMatch(order)) seq = tryParseExactInt(order) ?? seq;
      final title = collapseSpaces(_cell(row, _title));
      final upload = _cell(row, _upload).trim();
      if (title.isEmpty || upload.isEmpty || upload == 'Premiere') continue;
      final link = _cell(row, _link).trim();
      final notes = _cell(row, _notes).trim();
      var requester = _requesters.id(_cell(row, _requester));
      if (requester == null) {
        final m = _requestedBy.firstMatch(notes);
        if (m != null) requester = _requesters.id(m[1]!);
      }
      hl.add(
        Highlight(
          id: hl.length,
          seq: seq,
          title: title,
          songKey: songKey(title),
          genre: Genre.parse(_cell(row, _genre)),
          link: link,
          youtubeId: _youtube.firstMatch(link)?[1],
          requesterId: requester,
          streamDate: CalendarDate.tryParse(_cell(row, _stream)),
          uploadDate: CalendarDate.tryParse(upload),
          vocals: Vocals.parse(_cell(row, _vocals)),
          notes: notes,
        ),
      );
    }
    _seq = seq;
  }
}

/// Builds the plays, streams, songs and requesters from the rows of the "Songs" sheet and the highlights of a
/// catalogue: the requesters of the highlights keep their ids, their names count the spellings of both sheets.
///
/// As [_HighlightsBuilder]: [build] orders the work, the loops over the rows are in methods of their own. Every loop
/// over the rows, the plays, the requesters or the songs goes through [_inSteps]. The few others (over the streams,
/// 1,400 in the real sheets, and the highlights, 2,000, for their plays, streams and songs) run in one step: a
/// fraction of a millisecond together.
class _SongsBuilder {
  _SongsBuilder(Catalogue catalogue, this.sRows, ColumnResolver sCols, this.pauseEvery)
    : highlights = catalogue.highlights,
      _base = catalogue,
      _sDate = sCols.resolve(SongColumns.date),
      _sUptime = sCols.resolve(SongColumns.uptime),
      _sOrder = sCols.resolve(SongColumns.order),
      _sRequester = sCols.resolve(SongColumns.requester),
      _sTitle = sCols.resolve(SongColumns.title),
      _sGenre = sCols.resolve(SongColumns.genre),
      _sType = sCols.resolve(SongColumns.type),
      _sNotes = sCols.resolve(SongColumns.notes);

  final List<Highlight> highlights;
  final Catalogue _base;
  final List<List<String>> sRows;

  /// A pause point every this many rows of a loop.
  final int pauseEvery;

  final int _sDate, _sUptime, _sOrder, _sRequester, _sTitle, _sGenre, _sType, _sNotes;

  // the spellings of the Songs sheet first, then those of the highlights: the order in which the parse of both
  // sheets at once met them (the most frequent spelling wins, the first one met on a tie)
  late final _Requesters _requesters;

  final List<String> titles = [];
  final List<String> _titleKeys = [];
  final Map<String, int> _titleIds = {};

  late final List<Play> plays;
  late final List<LiveStream> streams;
  late final List<Requester> requesters;
  late final Int32List highlightPlays;
  late final Int32List playUptimes;
  final Map<String, Song> songs = {};

  // the work in progress of the loops, from one call to the next
  final List<_PlayDraft> _drafts = [];
  final List<_StreamDraft> _streamDrafts = [];
  _StreamDraft? _current;
  // The date of the last row of the current stream that has one. Some rows of songs were typed without their date:
  // they are of that day, at an unknown time.
  CalendarDate? _lastDate;
  late final Map<_StreamDraft, int> _streamIndex;
  final Map<String, List<int>> _playsByKey = {};
  final List<Play> _plays = [];
  late final List<int> _requestCounts;
  final List<Requester> _requesterList = [];
  final Map<String, List<int>> _songPlays = {};
  final Map<String, List<int>> _songHighlights = {};
  late final List<String> _songKeys;

  /// The id of [title], or -1 for the title of a marker ([_isMarkerTitle]): checked once per distinct title.
  int _title(String title) => _titleIds.putIfAbsent(title, () {
    if (_isMarkerTitle(title)) return -1;
    titles.add(title);
    _titleKeys.add(songKey(title));
    return titles.length - 1;
  });

  /// Builds the lists, in steps: a pause point every [pauseEvery] rows of each loop.
  Iterable<void> build() sync* {
    final spellings = <String, Map<String, int>>{};
    _requesters = _Requesters(spellings, _base.aliases, _base.requesterFolds);
    yield* _inSteps(pauseEvery, 1, sRows.length, _countSpellings);
    _requesters.addCountedSpellings();
    _addHighlightSpellings();
    yield null;

    // --- Ong Log: plays and streams
    yield* _inSteps(pauseEvery, 1, sRows.length, _addPlayDrafts);
    final drafts = _drafts;
    final kept = _streamDrafts.where((s) => s.count > 0).toList();
    // a few "Stream Start" rows carry no date, or a mistyped one: trust the first song
    for (final s in kept) {
      final first = drafts[s.start].date;
      final date = s.date;
      if (date == null || date.daysUntil(first).abs() > 1) {
        s.date = first;
        // the time of a mistyped day is no instant of the stream either
        s.startMinute = null;
      }
    }
    _streamIndex = <_StreamDraft, int>{for (var i = 0; i < kept.length; i++) kept[i]: i};
    yield null;

    // --- the plays of the highlights
    yield* _inSteps(pauseEvery, 0, drafts.length, _indexPlayDrafts);
    _linkHighlights();
    yield null;

    // --- plays, streams
    playUptimes = Int32List(drafts.length);
    yield* _inSteps(pauseEvery, 0, drafts.length, _addPlays);
    plays = List.unmodifiable(_plays);
    yield null;
    final streamHighlights = List.generate(kept.length, (_) => <int>[]);
    for (final h in highlights) {
      final play = highlightPlays[h.id];
      if (play >= 0) streamHighlights[plays[play].streamId].add(h.id);
    }
    streams = List.unmodifiable([
      for (var i = 0; i < kept.length; i++)
        LiveStream(
          id: i,
          date: kept[i].date!,
          firstPlayId: kept[i].start,
          playCount: kept[i].count,
          durationSeconds: kept[i].seconds,
          highlightIds: List.unmodifiable(streamHighlights[i]),
          startMinute: kept[i].startMinute,
        ),
    ]);
    yield null;

    // --- requesters
    _requestCounts = List.filled(_requesters.folds.length, 0);
    yield* _inSteps(pauseEvery, 0, plays.length, _countRequests);
    yield* _inSteps(pauseEvery, 0, _requesters.folds.length, _addRequesters);
    requesters = List.unmodifiable(_requesterList);

    // --- songs
    yield* _inSteps(pauseEvery, 0, plays.length, _indexSongPlays);
    for (final h in highlights) {
      if (h.songKey.isNotEmpty) (_songHighlights[h.songKey] ??= []).add(h.id);
    }
    _songKeys = [..._songPlays.keys, ..._songHighlights.keys.where((key) => !_songPlays.containsKey(key))];
    yield* _inSteps(pauseEvery, 0, _songKeys.length, _addSongs);
  }

  void _countSpellings(int from, int to) {
    for (var i = from; i < to; i++) {
      _requesters.countSpelling(_cell(sRows[i], _sRequester));
    }
  }

  /// Adds the spellings of the highlights' sheet to those of the Songs sheet. A name taken from the notes of a
  /// highlight, never written in a requester cell, is shown only when neither sheet has another one (it counts 0).
  void _addHighlightSpellings() {
    final spellings = _requesters.spellings;
    _base.requesterSpellings.forEach((key, counts) {
      final merged = spellings[key];
      if (merged == null) {
        spellings[key] = {...counts};
      } else {
        counts.forEach((name, count) {
          if (count > 0) {
            merged[name] = (merged[name] ?? 0) + count;
          } else {
            // under no count, never the name shown: one of the other names of a group
            merged.putIfAbsent(name, () => 0);
          }
        });
      }
    });
  }

  /// The plays of the rows [from] to [to], and their streams: a row of Order 0 starts a stream, a marker
  /// ([_isMarkerTitle], [_isTimeMarker]) is no play. (Its requester cell still counted a spelling in [_countSpellings],
  /// which reads every row: it is a running time or empty in the markers of the sheet.)
  void _addPlayDrafts(int from, int to) {
    final drafts = _drafts;
    var current = _current;
    var lastDate = _lastDate;
    for (var i = from; i < to; i++) {
      final row = sRows[i];
      final when = CalendarDate.parseCell(_cell(row, _sDate));
      if (_cell(row, _sOrder).trim() == '0') {
        // a "Stream Start" row starts a stream even when its date is missing or mistyped: without it, its songs
        // would go to the stream before
        current = _StreamDraft(when?.date, drafts.length, _instant(when));
        _streamDrafts.add(current);
        lastDate = when?.date;
        continue;
      }
      final title = collapseSpaces(_cell(row, _sTitle));
      if (title.isEmpty || title == '-' || title == '~~') continue;
      final date = when?.date ?? lastDate;
      // no date, and none yet in its stream to give it
      if (date == null) continue;
      lastDate = date;
      final requesterCell = _cell(row, _sRequester);
      final genreCell = _cell(row, _sGenre);
      final genre = Genre.parse(genreCell);
      // a cell of no genre ("-", empty) is of Genre.other
      final titleId = genre == Genre.other && _isTimeMarker(requesterCell, genreCell) ? -1 : _title(title);
      final uptime = _uptimeSeconds(_cell(row, _sUptime));
      if (titleId < 0) {
        // a marker is no play and starts no stream, but its uptime counts for its stream (the last marker of a
        // stream often carries its largest one), and its date for the rows after it
        if (current != null) current.seconds = math.max(current.seconds, uptime);
        continue;
      }
      if (current == null) {
        current = _StreamDraft(date, drafts.length);
        _streamDrafts.add(current);
      }
      current.count++;
      current.seconds = math.max(current.seconds, uptime);
      drafts.add(
        _PlayDraft(
          _instant(when),
          date,
          titleId,
          genre,
          PlayType.parse(_cell(row, _sType)),
          _requesters.id(requesterCell),
          PlayFlag.parse(_cell(row, _sNotes)),
          current,
          uptime,
        ),
      );
    }
    _current = current;
    _lastDate = lastDate;
  }

  void _indexPlayDrafts(int from, int to) {
    for (var i = from; i < to; i++) {
      final key = _titleKeys[_drafts[i].titleId];
      if (key.isNotEmpty) (_playsByKey[key] ??= []).add(i);
    }
  }

  /// The play of each highlight: the first of its song played within a day of its stream. A play shows the first
  /// highlight linked to it, or the first one with a video when that one has none.
  void _linkHighlights() {
    final drafts = _drafts;
    final links = Int32List(highlights.length)..fillRange(0, highlights.length, -1);
    for (final h in highlights) {
      final streamDate = h.streamDate;
      if (streamDate == null || h.songKey.isEmpty) continue;
      for (final p in _playsByKey[h.songKey] ?? const <int>[]) {
        if (drafts[p].date.daysUntil(streamDate).abs() <= 1) {
          links[h.id] = p;
          final draft = drafts[p];
          final previous = draft.highlight;
          if (previous == null || (highlights[previous].youtubeId == null && h.youtubeId != null)) {
            draft.highlight = h.id;
          }
          break;
        }
      }
    }
    highlightPlays = links;
  }

  void _addPlays(int from, int to) {
    final drafts = _drafts;
    final uptimes = playUptimes;
    for (var i = from; i < to; i++) {
      final uptime = drafts[i].uptime;
      uptimes[i] = uptime > _maxStoredUptime ? -1 : uptime;
      _plays.add(
        Play(
          id: i,
          loggedMinute: drafts[i].minute,
          rowDate: drafts[i].date,
          titleId: drafts[i].titleId,
          title: titles[drafts[i].titleId],
          songKey: _titleKeys[drafts[i].titleId],
          genre: drafts[i].genre,
          type: drafts[i].type,
          requesterId: drafts[i].requester,
          flag: drafts[i].flag,
          streamId: _streamIndex[drafts[i].stream]!,
          highlightId: drafts[i].highlight,
        ),
      );
    }
  }

  void _countRequests(int from, int to) {
    for (var i = from; i < to; i++) {
      final requester = plays[i].requesterId;
      if (requester != null) _requestCounts[requester]++;
    }
  }

  void _addRequesters(int from, int to) {
    for (var i = from; i < to; i++) {
      _requesterList.add(_requesters.requester(i, _requestCounts[i]));
    }
  }

  void _indexSongPlays(int from, int to) {
    for (var i = from; i < to; i++) {
      final p = plays[i];
      if (p.songKey.isNotEmpty) (_songPlays[p.songKey] ??= []).add(p.id);
    }
  }

  void _addSongs(int from, int to) {
    for (var i = from; i < to; i++) {
      final key = _songKeys[i];
      final ps = _songPlays[key] ?? const <int>[];
      final hs = _songHighlights[key] ?? const <int>[];
      var genre = Genre.other;
      for (final p in ps) {
        if (plays[p].genre != Genre.other) genre = plays[p].genre;
      }
      if (genre == Genre.other) {
        for (final h in hs) {
          if (highlights[h].genre != Genre.other) genre = highlights[h].genre;
        }
      }
      songs[key] = Song(
        key: key,
        title: ps.isNotEmpty ? plays[ps.last].title : highlights[hs.first].title,
        genre: genre,
        playIds: List.unmodifiable(ps),
        highlightIds: List.unmodifiable(hs),
        firstPlayed: ps.isEmpty ? null : streams[plays[ps.first].streamId].date,
        lastPlayed: ps.isEmpty ? null : streams[plays[ps.last].streamId].date,
      );
    }
  }
}
