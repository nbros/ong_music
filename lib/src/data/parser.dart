/// Turns the CSV text of the two sheets into a [Catalogue].
///
/// Pure Dart (no Flutter import): runs in an isolate, in `dart run` scripts
/// and in unit tests.
library;

import 'dart:math' as math;

import 'catalogue.dart';
import 'csv.dart';
import 'model.dart';
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
final _youtube = RegExp(r'(?:youtu\.be/|v=)([\w-]{11})');
final _requestedBy = RegExp(r'requested by "?([^"\s,.;]+)"?', caseSensitive: false);
final _digits = RegExp(r'^\d+$');

int _uptimeMinutes(String cell) {
  final m = _uptime.firstMatch(cell.trim());
  if (m == null) return 0;
  // tryParse: an absurdly long number must not reject the whole sheet (int.parse throws on native)
  final hours = int.tryParse(m[1]!);
  return hours == null ? 0 : hours * 60 + int.parse(m[2]!);
}

/// The instant of a date cell with a time, in minutes since the epoch (see `Play.loggedMinute`), or null.
int? _instant(({CalendarDate date, int? minute})? cell) {
  final minute = cell?.minute;
  return minute == null ? null : SheetZone.epochMinute(cell!.date, minute);
}

/// Parses both sheets and builds the catalogue.
///
/// Throws [CatalogueFormatException] when a payload does not look like its
/// sheet: no title column header, HTML, or no highlight / no play at all.
Catalogue parseCatalogue(String highlightsCsv, String songsCsv) {
  final load = CatalogueLoad(highlightsCsv, songsCsv);
  while (load.step()) {}
  return load.catalogue;
}

/// [parseCatalogue] in steps: each call of [step] does the work up to its next pause point, so that the load can stop
/// there and go on later. The web runs it in slices between frames (see `runInSlices`), which keeps the page drawing.
///
/// It is the one parser: [parseCatalogue] runs the same steps to the end in one go. So the catalogue is the same
/// however the load is cut, and so are the exceptions.
///
/// The pause points come every [rowsPerStep] rows in the loops over rows (the CSV text, the builder, the indexes of
/// the catalogue) and every [unitsPerStep] code units in those over the text; the defaults, [rowsPerPause] and
/// [unitsPerPause], keep a step around a millisecond or less on a fast laptop.
final class CatalogueLoad {
  /// A load of both sheets, nothing done yet.
  CatalogueLoad(
    String highlightsCsv,
    String songsCsv, {
    int rowsPerStep = rowsPerPause,
    int unitsPerStep = unitsPerPause,
  }) {
    // a step of nothing would never end the load
    if (rowsPerStep < 1) throw ArgumentError.value(rowsPerStep, 'rowsPerStep', 'must be at least 1');
    if (unitsPerStep < 1) throw ArgumentError.value(unitsPerStep, 'unitsPerStep', 'must be at least 1');
    _steps = _load(highlightsCsv, songsCsv, rowsPerStep, unitsPerStep).iterator;
  }

  late final Iterator<void> _steps;
  Catalogue? _catalogue;

  /// The catalogue, once [step] returned false.
  Catalogue get catalogue => _catalogue ?? (throw StateError('The catalogue is not loaded yet'));

  /// Does the work up to the next pause point. Returns whether there is more to do: false once [catalogue] is
  /// there. Throws what [parseCatalogue] throws, and the load is over then.
  bool step() => _steps.moveNext();

  Iterable<void> _load(String highlightsCsv, String songsCsv, int rowsPerStep, int unitsPerStep) sync* {
    final hRows = <List<String>>[], sRows = <List<String>>[];
    yield* _decode(highlightsCsv, 'Highlights', hRows, unitsPerStep: unitsPerStep, rowsPerStep: rowsPerStep);
    yield* _decode(songsCsv, 'Songs', sRows, unitsPerStep: unitsPerStep, rowsPerStep: rowsPerStep);
    final hCols = ColumnResolver(hRows.first);
    final sCols = ColumnResolver(sRows.first);
    if (hCols.find(HighlightColumns.title) == null || hCols.find(HighlightColumns.uploadDate) == null) {
      throw const CatalogueFormatException('Highlights: "Video Title" / "Upload Date" header not found');
    }
    if (sCols.find(SongColumns.title) == null) {
      throw const CatalogueFormatException('Songs: "Title" header not found');
    }
    final b = _Builder(hRows, hCols, sRows, sCols, rowsPerStep);
    yield* b.build();
    if (b.highlights.isEmpty) throw const CatalogueFormatException('Highlights: no row');
    if (b.plays.isEmpty) throw const CatalogueFormatException('Songs: no row');
    yield* Catalogue.assemble(
      highlights: b.highlights,
      plays: b.plays,
      streams: b.streams,
      requesters: b.requesters,
      titles: b.titles,
      songs: b.songs,
      done: (catalogue) => _catalogue = catalogue,
      pauseEvery: rowsPerStep,
    );
  }
}

/// [parseCatalogue] taking one record argument, for `compute` / `Isolate.run`.
Catalogue parseCatalogueRecord(({String highlightsCsv, String songsCsv}) sheets) =>
    parseCatalogue(sheets.highlightsCsv, sheets.songsCsv);

class _StreamDraft {
  _StreamDraft(this.date, this.start);

  /// Null until known: the date of its "Stream Start" row could not be read.
  CalendarDate? date;
  final int start;
  int count = 0;
  int minutes = 0;
}

class _PlayDraft {
  _PlayDraft(this.minute, this.date, this.titleId, this.genre, this.type, this.requester, this.flag, this.stream);
  final int? minute;
  final CalendarDate date;
  final int titleId;
  final Genre genre;
  final PlayType type;
  final int? requester;
  final PlayFlag flag;
  final _StreamDraft stream;
  int? highlight;
}

/// Builds the lists of the catalogue from the rows of both sheets.
///
/// [build] only orders the work and its pause points; the loops over the rows are in methods of their own that do
/// [pauseEvery] rows at a time ([_inSteps]). Written as a generator, a loop is a state machine on the web, its locals
/// are kept off the registers, and a large one is not optimised: the whole build took half as long again.
///
/// Every loop over the rows of either sheet, the plays, the requesters or the songs goes through [_inSteps]. The
/// few others (over the streams, 1,400 in the real sheets, and the highlights again, 2,000, for their streams and
/// songs) run in one step: a fraction of a millisecond together.
class _Builder {
  _Builder(this.hRows, this.hCols, this.sRows, this.sCols, this.pauseEvery)
    : _sDate = sCols.resolve(SongColumns.date),
      _sUptime = sCols.resolve(SongColumns.uptime),
      _sOrder = sCols.resolve(SongColumns.order),
      _sRequester = sCols.resolve(SongColumns.requester),
      _sTitle = sCols.resolve(SongColumns.title),
      _sGenre = sCols.resolve(SongColumns.genre),
      _sType = sCols.resolve(SongColumns.type),
      _sNotes = sCols.resolve(SongColumns.notes),
      _hUpload = hCols.resolve(HighlightColumns.uploadDate),
      _hOrder = hCols.resolve(HighlightColumns.order),
      _hTitle = hCols.resolve(HighlightColumns.title),
      _hGenre = hCols.resolve(HighlightColumns.genre),
      _hLink = hCols.resolve(HighlightColumns.link),
      _hRequester = hCols.resolve(HighlightColumns.requester),
      _hStream = hCols.resolve(HighlightColumns.streamSource),
      _hVocals = hCols.resolve(HighlightColumns.vocals),
      _hNotes = hCols.resolve(HighlightColumns.notes);

  final List<List<String>> hRows, sRows;
  final ColumnResolver hCols, sCols;

  /// A pause point every this many rows of a loop.
  final int pauseEvery;

  final int _sDate, _sUptime, _sOrder, _sRequester, _sTitle, _sGenre, _sType, _sNotes;
  final int _hUpload, _hOrder, _hTitle, _hGenre, _hLink, _hRequester, _hStream, _hVocals, _hNotes;

  // requesters: folded name -> spelling counts, then id assignment on first use
  final Map<String, Map<String, int>> _spellings = {};
  final Map<String, int> _requesterIds = {};
  final List<String> _requesterFolds = [];

  final List<String> titles = [];
  final List<String> _titleKeys = [];
  final Map<String, int> _titleIds = {};

  late final List<Highlight> highlights;
  late final List<Play> plays;
  late final List<LiveStream> streams;
  late final List<Requester> requesters;
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
  final List<Highlight> _highlights = [];
  int _seq = 1;
  final List<Play> _plays = [];
  late final List<int> _requestCounts;
  final List<Requester> _requesters = [];
  final Map<String, List<int>> _songPlays = {};
  final Map<String, List<int>> _songHighlights = {};
  late final List<String> _songKeys;

  void _countSpelling(String cell) {
    final name = _requesterCell(cell);
    if (name == null) return;
    final counts = _spellings.putIfAbsent(fold(name), () => {});
    counts[name] = (counts[name] ?? 0) + 1;
  }

  int? _requester(String cell) {
    final name = _requesterCell(cell);
    if (name == null) return null;
    final key = fold(name);
    return _requesterIds.putIfAbsent(key, () {
      _requesterFolds.add(key);
      _spellings.putIfAbsent(key, () => {name: 0});
      return _requesterFolds.length - 1;
    });
  }

  int _title(String title) => _titleIds.putIfAbsent(title, () {
    titles.add(title);
    _titleKeys.add(songKey(title));
    return titles.length - 1;
  });

  /// Calls [chunk] on the indexes from [from] to [to], [pauseEvery] at a time, with a pause point after each call.
  Iterable<void> _inSteps(int from, int to, void Function(int from, int to) chunk) sync* {
    for (var i = from; i < to; i += pauseEvery) {
      chunk(i, to - i > pauseEvery ? i + pauseEvery : to);
      yield null;
    }
  }

  /// Builds the lists, in steps: a pause point every [pauseEvery] rows of each loop.
  Iterable<void> build() sync* {
    yield* _inSteps(1, sRows.length, (from, to) => _countSpellings(sRows, _sRequester, from, to));
    yield* _inSteps(1, hRows.length, (from, to) => _countSpellings(hRows, _hRequester, from, to));

    // --- Ong Log: plays and streams
    yield* _inSteps(1, sRows.length, _addPlayDrafts);
    final drafts = _drafts;
    final kept = _streamDrafts.where((s) => s.count > 0).toList();
    // a few "Stream Start" rows carry no date, or a mistyped one: trust the first song
    for (final s in kept) {
      final first = drafts[s.start].date;
      final date = s.date;
      if (date == null || date.daysUntil(first).abs() > 1) s.date = first;
    }
    _streamIndex = <_StreamDraft, int>{for (var i = 0; i < kept.length; i++) kept[i]: i};
    yield null;

    // --- highlights
    yield* _inSteps(0, drafts.length, _indexPlayDrafts);
    yield* _inSteps(1, hRows.length, _addHighlights);
    highlights = List.unmodifiable(_highlights);

    // --- plays, streams
    yield* _inSteps(0, drafts.length, _addPlays);
    plays = List.unmodifiable(_plays);
    yield null;
    final streamHighlights = List.generate(kept.length, (_) => <int>[]);
    for (final h in highlights) {
      if (h.playId != null) streamHighlights[plays[h.playId!].streamId].add(h.id);
    }
    streams = List.unmodifiable([
      for (var i = 0; i < kept.length; i++)
        LiveStream(
          id: i,
          date: kept[i].date!,
          firstPlayId: kept[i].start,
          playCount: kept[i].count,
          durationMinutes: kept[i].minutes,
          highlightIds: List.unmodifiable(streamHighlights[i]),
        ),
    ]);
    yield null;

    // --- requesters
    _requestCounts = List.filled(_requesterFolds.length, 0);
    yield* _inSteps(0, plays.length, _countRequests);
    yield* _inSteps(0, _requesterFolds.length, _addRequesters);
    requesters = List.unmodifiable(_requesters);

    // --- songs
    yield* _inSteps(0, plays.length, _indexSongPlays);
    for (final h in highlights) {
      if (h.songKey.isNotEmpty) (_songHighlights[h.songKey] ??= []).add(h.id);
    }
    _songKeys = [..._songPlays.keys, ..._songHighlights.keys.where((key) => !_songPlays.containsKey(key))];
    yield* _inSteps(0, _songKeys.length, _addSongs);
  }

  void _countSpellings(List<List<String>> rows, int column, int from, int to) {
    for (var i = from; i < to; i++) {
      _countSpelling(_cell(rows[i], column));
    }
  }

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
        current = _StreamDraft(when?.date, drafts.length);
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
      if (current == null) {
        current = _StreamDraft(date, drafts.length);
        _streamDrafts.add(current);
      }
      current.count++;
      current.minutes = math.max(current.minutes, _uptimeMinutes(_cell(row, _sUptime)));
      drafts.add(
        _PlayDraft(
          _instant(when),
          date,
          _title(title),
          Genre.parse(_cell(row, _sGenre)),
          PlayType.parse(_cell(row, _sType)),
          _requester(_cell(row, _sRequester)),
          PlayFlag.parse(_cell(row, _sNotes)),
          current,
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

  void _addHighlights(int from, int to) {
    final drafts = _drafts, hl = _highlights;
    var seq = _seq;
    for (var i = from; i < to; i++) {
      final row = hRows[i];
      final order = _cell(row, _hOrder).trim();
      if (_digits.hasMatch(order)) seq = int.tryParse(order) ?? seq;
      final title = collapseSpaces(_cell(row, _hTitle));
      final upload = _cell(row, _hUpload).trim();
      if (title.isEmpty || upload.isEmpty || upload == 'Premiere') continue;
      final link = _cell(row, _hLink).trim();
      final streamDate = CalendarDate.tryParse(_cell(row, _hStream));
      final key = songKey(title);
      int? playId;
      if (streamDate != null && key.isNotEmpty) {
        for (final p in _playsByKey[key] ?? const <int>[]) {
          if (drafts[p].date.daysUntil(streamDate).abs() <= 1) {
            playId = p;
            break;
          }
        }
      }
      final notes = _cell(row, _hNotes).trim();
      var requester = _requester(_cell(row, _hRequester));
      if (requester == null) {
        final m = _requestedBy.firstMatch(notes);
        if (m != null) requester = _requester(m[1]!);
      }
      final youtubeId = _youtube.firstMatch(link)?[1];
      final id = hl.length;
      if (playId != null) {
        final draft = drafts[playId];
        final previous = draft.highlight;
        if (previous == null || (hl[previous].youtubeId == null && youtubeId != null)) draft.highlight = id;
      }
      hl.add(
        Highlight(
          id: id,
          seq: seq,
          title: title,
          songKey: key,
          genre: Genre.parse(_cell(row, _hGenre)),
          link: link,
          youtubeId: youtubeId,
          requesterId: requester,
          streamDate: streamDate,
          uploadDate: CalendarDate.tryParse(upload),
          vocals: Vocals.parse(_cell(row, _hVocals)),
          notes: notes,
          playId: playId,
        ),
      );
    }
    _seq = seq;
  }

  void _addPlays(int from, int to) {
    final drafts = _drafts;
    for (var i = from; i < to; i++) {
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
      _requesters.add(
        Requester(
          id: i,
          name: _mostFrequent(_spellings[_requesterFolds[i]]!),
          folded: _requesterFolds[i],
          requestCount: _requestCounts[i],
        ),
      );
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
