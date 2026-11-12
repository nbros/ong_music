/// Turns the CSV text of the two sheets into a [Catalogue].
///
/// Pure Dart (no Flutter import): runs in an isolate, in `dart run` scripts
/// and in unit tests.
library;

import 'dart:math' as math;

import 'catalogue.dart';
import 'csv.dart';
import 'model.dart';
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

List<List<String>> _decode(String text, String sheet) {
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) throw CatalogueFormatException('$sheet: empty payload');
  if (trimmed.startsWith('<')) throw CatalogueFormatException('$sheet: HTML instead of CSV');
  // composeMarks: cells typed with decomposed accents search and display like the others
  return decodeCsv(composeMarks(text.startsWith('\uFEFF') ? text.substring(1) : text));
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

/// Parses both sheets and builds the catalogue.
///
/// Throws [CatalogueFormatException] when a payload does not look like its
/// sheet: no title column header, HTML, or no highlight / no play at all.
Catalogue parseCatalogue(String highlightsCsv, String songsCsv) {
  final hRows = _decode(highlightsCsv, 'Highlights');
  final sRows = _decode(songsCsv, 'Songs');
  final hCols = ColumnResolver(hRows.first);
  final sCols = ColumnResolver(sRows.first);
  if (hCols.find(HighlightColumns.title) == null || hCols.find(HighlightColumns.uploadDate) == null) {
    throw const CatalogueFormatException('Highlights: "Video Title" / "Upload Date" header not found');
  }
  if (sCols.find(SongColumns.title) == null) {
    throw const CatalogueFormatException('Songs: "Title" header not found');
  }
  final b = _Builder(hRows, hCols, sRows, sCols)..build();
  if (b.highlights.isEmpty) throw const CatalogueFormatException('Highlights: no row');
  if (b.plays.isEmpty) throw const CatalogueFormatException('Songs: no row');
  return Catalogue(
    highlights: b.highlights,
    plays: b.plays,
    streams: b.streams,
    requesters: b.requesters,
    titles: b.titles,
    songs: b.songs,
  );
}

/// [parseCatalogue] taking one record argument, for `compute` / `Isolate.run`.
Catalogue parseCatalogueRecord(({String highlightsCsv, String songsCsv}) sheets) =>
    parseCatalogue(sheets.highlightsCsv, sheets.songsCsv);

class _StreamDraft {
  _StreamDraft(this.date, this.start);
  CalendarDate date;
  final int start;
  int count = 0;
  int minutes = 0;
}

class _PlayDraft {
  _PlayDraft(this.time, this.date, this.titleId, this.genre, this.type, this.requester, this.flag, this.stream);
  final String time;
  final CalendarDate date;
  final int titleId;
  final Genre genre;
  final PlayType type;
  final int? requester;
  final PlayFlag flag;
  final _StreamDraft stream;
  int? highlight;
}

class _Builder {
  _Builder(this.hRows, this.hCols, this.sRows, this.sCols);

  final List<List<String>> hRows, sRows;
  final ColumnResolver hCols, sCols;

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

  void build() {
    final sDate = sCols.resolve(SongColumns.date),
        sUptime = sCols.resolve(SongColumns.uptime),
        sOrder = sCols.resolve(SongColumns.order),
        sRequester = sCols.resolve(SongColumns.requester),
        sTitle = sCols.resolve(SongColumns.title),
        sGenre = sCols.resolve(SongColumns.genre),
        sType = sCols.resolve(SongColumns.type),
        sNotes = sCols.resolve(SongColumns.notes);
    final hUpload = hCols.resolve(HighlightColumns.uploadDate),
        hOrder = hCols.resolve(HighlightColumns.order),
        hTitle = hCols.resolve(HighlightColumns.title),
        hGenre = hCols.resolve(HighlightColumns.genre),
        hLink = hCols.resolve(HighlightColumns.link),
        hRequester = hCols.resolve(HighlightColumns.requester),
        hStream = hCols.resolve(HighlightColumns.streamSource),
        hVocals = hCols.resolve(HighlightColumns.vocals),
        hNotes = hCols.resolve(HighlightColumns.notes);

    for (var i = 1; i < sRows.length; i++) {
      _countSpelling(_cell(sRows[i], sRequester));
    }
    for (var i = 1; i < hRows.length; i++) {
      _countSpelling(_cell(hRows[i], hRequester));
    }

    // --- Ong Log: plays and streams
    final drafts = <_PlayDraft>[];
    final streamDrafts = <_StreamDraft>[];
    _StreamDraft? current;
    for (var i = 1; i < sRows.length; i++) {
      final row = sRows[i];
      final when = CalendarDate.parseCell(_cell(row, sDate));
      if (when == null) continue;
      if (_cell(row, sOrder).trim() == '0') {
        current = _StreamDraft(when.date, drafts.length);
        streamDrafts.add(current);
        continue;
      }
      final title = collapseSpaces(_cell(row, sTitle));
      if (title.isEmpty || title == '-' || title == '~~') continue;
      if (current == null) {
        current = _StreamDraft(when.date, drafts.length);
        streamDrafts.add(current);
      }
      current.count++;
      current.minutes = math.max(current.minutes, _uptimeMinutes(_cell(row, sUptime)));
      drafts.add(
        _PlayDraft(
          when.time,
          when.date,
          _title(title),
          Genre.parse(_cell(row, sGenre)),
          PlayType.parse(_cell(row, sType)),
          _requester(_cell(row, sRequester)),
          PlayFlag.parse(_cell(row, sNotes)),
          current,
        ),
      );
    }
    final kept = streamDrafts.where((s) => s.count > 0).toList();
    // a few "Stream Start" rows carry a mistyped date: trust the first song
    for (final s in kept) {
      final first = drafts[s.start].date;
      if (s.date.daysUntil(first).abs() > 1) s.date = first;
    }
    final streamIndex = <_StreamDraft, int>{for (var i = 0; i < kept.length; i++) kept[i]: i};

    // --- highlights
    final playsByKey = <String, List<int>>{};
    for (var i = 0; i < drafts.length; i++) {
      final key = _titleKeys[drafts[i].titleId];
      if (key.isNotEmpty) (playsByKey[key] ??= []).add(i);
    }
    final hl = <Highlight>[];
    var seq = 1;
    for (var i = 1; i < hRows.length; i++) {
      final row = hRows[i];
      final order = _cell(row, hOrder).trim();
      if (_digits.hasMatch(order)) seq = int.tryParse(order) ?? seq;
      final title = collapseSpaces(_cell(row, hTitle));
      final upload = _cell(row, hUpload).trim();
      if (title.isEmpty || upload.isEmpty || upload == 'Premiere') continue;
      final link = _cell(row, hLink).trim();
      final streamDate = CalendarDate.tryParse(_cell(row, hStream));
      final key = songKey(title);
      int? playId;
      if (streamDate != null && key.isNotEmpty) {
        for (final p in playsByKey[key] ?? const <int>[]) {
          if (drafts[p].date.daysUntil(streamDate).abs() <= 1) {
            playId = p;
            break;
          }
        }
      }
      final notes = _cell(row, hNotes).trim();
      var requester = _requester(_cell(row, hRequester));
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
          genre: Genre.parse(_cell(row, hGenre)),
          link: link,
          youtubeId: youtubeId,
          requesterId: requester,
          streamDate: streamDate,
          uploadDate: CalendarDate.tryParse(upload),
          vocals: Vocals.parse(_cell(row, hVocals)),
          notes: notes,
          playId: playId,
        ),
      );
    }
    highlights = List.unmodifiable(hl);

    // --- plays, streams
    plays = List.unmodifiable([
      for (var i = 0; i < drafts.length; i++)
        Play(
          id: i,
          time: drafts[i].time,
          rowDate: drafts[i].date,
          titleId: drafts[i].titleId,
          title: titles[drafts[i].titleId],
          songKey: _titleKeys[drafts[i].titleId],
          genre: drafts[i].genre,
          type: drafts[i].type,
          requesterId: drafts[i].requester,
          flag: drafts[i].flag,
          streamId: streamIndex[drafts[i].stream]!,
          highlightId: drafts[i].highlight,
        ),
    ]);
    final streamHighlights = List.generate(kept.length, (_) => <int>[]);
    for (final h in highlights) {
      if (h.playId != null) streamHighlights[plays[h.playId!].streamId].add(h.id);
    }
    streams = List.unmodifiable([
      for (var i = 0; i < kept.length; i++)
        LiveStream(
          id: i,
          date: kept[i].date,
          firstPlayId: kept[i].start,
          playCount: kept[i].count,
          durationMinutes: kept[i].minutes,
          highlightIds: List.unmodifiable(streamHighlights[i]),
        ),
    ]);

    // --- requesters
    final counts = List.filled(_requesterFolds.length, 0);
    for (final p in plays) {
      if (p.requesterId != null) counts[p.requesterId!]++;
    }
    requesters = List.unmodifiable([
      for (var i = 0; i < _requesterFolds.length; i++)
        Requester(
          id: i,
          name: _mostFrequent(_spellings[_requesterFolds[i]]!),
          folded: _requesterFolds[i],
          requestCount: counts[i],
        ),
    ]);

    // --- songs
    final songPlays = <String, List<int>>{};
    final songHighlights = <String, List<int>>{};
    for (final p in plays) {
      if (p.songKey.isNotEmpty) (songPlays[p.songKey] ??= []).add(p.id);
    }
    for (final h in highlights) {
      if (h.songKey.isNotEmpty) (songHighlights[h.songKey] ??= []).add(h.id);
    }
    for (final key in {...songPlays.keys, ...songHighlights.keys}) {
      final ps = songPlays[key] ?? const <int>[];
      final hs = songHighlights[key] ?? const <int>[];
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
