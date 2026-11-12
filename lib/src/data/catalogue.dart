/// The immutable in-memory catalogue and its queries.
///
/// Pure Dart. Build one with `parseCatalogue` (parser.dart).
library;

import 'dart:typed_data';

import 'model.dart';
import 'text.dart';

/// A genre and how many rows have it.
typedef GenreCount = ({Genre genre, int count});

/// The highlights matching a query, newest first.
final class HighlightResults {
  HighlightResults._(this.tokens, this.ids);

  /// The folded query tokens, for [matchRanges].
  final List<String> tokens;

  /// Ids (indices in `Catalogue.highlights`) of the matches, newest first.
  final Int32List ids;

  int get length => ids.length;
  bool get isEmpty => ids.isEmpty;
}

/// The plays matching a query, newest first.
final class PlayResults {
  PlayResults._(this.tokens, this.ids, this._plays, this.streamCount);

  /// The folded query tokens, for [matchRanges].
  final List<String> tokens;

  /// Ids (indices in `Catalogue.plays`) of the matches, newest first.
  final Int32List ids;

  final List<Play> _plays;

  /// Number of distinct streams among the matches.
  final int streamCount;

  int get length => ids.length;
  bool get isEmpty => ids.isEmpty;

  /// The play at position [index] of the result.
  Play operator [](int index) => _plays[ids[index]];

  /// Whether the row at [index] is the first of its stream in the result, i.e.
  /// whether a list grouped by stream shows a stream header above it.
  bool startsStream(int index) => index == 0 || _plays[ids[index - 1]].streamId != _plays[ids[index]].streamId;
}

/// Both sheets, parsed and cross-linked. Immutable; all queries are in memory.
///
/// Ids are indices: `highlights[h.id] == h`, `plays[p.id] == p`, etc.
///
/// **An id is only valid with the catalogue it came from.** A refresh replaces
/// the catalogue, and a row inserted or removed in the middle of a sheet shifts
/// every later id. So a view that outlives a build (a detail sheet, a selected
/// row) must keep the [Catalogue] it was opened with, or the entity objects, and
/// never look an old id up in a newer catalogue. To find "the same thing" again
/// across catalogues use what does not move: `Song.key`, a stream's date, a
/// highlight's `seq` (`Highlight.key` also tells apart the rows sharing one), a
/// requester's folded name. The catalogue instance itself
/// is kept when a refresh finds the sheets unchanged.
final class Catalogue {
  /// Assembles a catalogue; use `parseCatalogue` instead.
  Catalogue({
    required this.highlights,
    required this.plays,
    required this.streams,
    required this.requesters,
    required this.titles,
    required Map<String, Song> songs,
  }) : _songs = songs {
    _titleFolds = [for (final t in titles) fold(t)];
    _requesterFolds = [for (final r in requesters) r.folded];
    _requesterByFold = {for (final r in requesters) r.folded: r.id};
    // fields joined by a newline: a query token never contains whitespace, so never spans two fields
    _highlightFields = [
      for (final h in highlights)
        '${fold(h.title)}\n${h.requesterId == null ? '' : _requesterFolds[h.requesterId!]}\n${_genreFolds[h.genre.index]}',
    ];
    _highlightKeys = [for (final h in highlights) h.key];
    _highlightGenreCounts = _countGenres(highlights.map((h) => h.genre));
    _highlightRequests = Int32List(requesters.length);
    for (final h in highlights) {
      if (h.requesterId != null) _highlightRequests[h.requesterId!]++;
    }
    _playGenreCounts = _countGenres(plays.map((p) => p.genre));
  }

  /// Highlights in sheet order (oldest upload first).
  final List<Highlight> highlights;

  /// Ong Log plays in sheet order (oldest first).
  final List<Play> plays;

  /// Streams, oldest first. Every stream has at least one play.
  final List<LiveStream> streams;

  /// Requesters (of plays or highlights), in order of first appearance.
  final List<Requester> requesters;

  /// Distinct play titles as written (whitespace collapsed); `Play.titleId`
  /// indexes it.
  final List<String> titles;

  final Map<String, Song> _songs;

  late final List<String> _titleFolds;
  late final List<String> _requesterFolds;
  late final Map<String, int> _requesterByFold;
  late final List<String> _highlightFields;
  late final List<String> _highlightKeys;
  late final List<GenreCount> _highlightGenreCounts;
  late final List<GenreCount> _playGenreCounts;
  late final Int32List _highlightRequests;

  static final List<String> _genreFolds = [for (final g in Genre.values) fold(g.label)];
  static final List<String> _typeFolds = [for (final t in PlayType.values) fold(t.label)];

  static List<GenreCount> _countGenres(Iterable<Genre> genres) {
    final counts = List.filled(Genre.values.length, 0);
    for (final g in genres) {
      counts[g.index]++;
    }
    final result = [
      for (final g in Genre.values)
        if (counts[g.index] > 0) (genre: g, count: counts[g.index]),
    ]..sort((a, b) => a.count != b.count ? b.count.compareTo(a.count) : a.genre.index.compareTo(b.genre.index));
    return List.unmodifiable(result);
  }

  /// Number of highlights.
  int get highlightCount => highlights.length;

  /// Number of plays (songs played live).
  int get playCount => plays.length;

  /// Number of streams.
  int get streamCount => streams.length;

  /// All songs (grouped by song key), in no particular order.
  Iterable<Song> get songs => _songs.values;

  /// Number of distinct songs.
  int get songCount => _songs.length;

  // ---------------------------------------------------------------- lookups

  /// The song with this key (`Play.songKey`, `Highlight.songKey`), or null.
  Song? song(String key) => key.isEmpty ? null : _songs[key];

  /// The song of a play, or null when its title has no letter or digit.
  Song? songOfPlay(Play play) => song(play.songKey);

  /// The song of a highlight, or null when its title has no letter or digit.
  Song? songOfHighlight(Highlight highlight) => song(highlight.songKey);

  /// The stream a play belongs to.
  LiveStream streamOf(Play play) => streams[play.streamId];

  /// The plays of a stream, in order.
  List<Play> playsOf(LiveStream stream) => plays.sublist(stream.firstPlayId, stream.firstPlayId + stream.playCount);

  /// The requester of a play or highlight id, or null.
  Requester? requester(int? id) => id == null ? null : requesters[id];

  /// Looks a requester up by name, case- and accent-insensitively.
  Requester? requesterNamed(String name) {
    final id = _requesterByFold[fold(name.trim())];
    return id == null ? null : requesters[id];
  }

  /// Whether requester [id] is the user whose folded name is [foldedName]
  /// (see `myRequesterKeyProvider`). False when either is null or empty.
  bool isRequester(int? id, String? foldedName) =>
      id != null && foldedName != null && foldedName.isNotEmpty && _requesterFolds[id] == foldedName;

  /// The highlight linked to a play, or null.
  Highlight? highlightOf(Play play) => play.highlightId == null ? null : highlights[play.highlightId!];

  /// The play linked to a highlight, or null.
  Play? playOf(Highlight highlight) => highlight.playId == null ? null : plays[highlight.playId!];

  // ---------------------------------------------------------------- counts

  /// Highlight count per genre, largest first (ties in [Genre] order); genres
  /// with no highlight are left out. [Genre.other] is included.
  List<GenreCount> get highlightGenreCounts => _highlightGenreCounts;

  /// Play count per genre, largest first (ties in [Genre] order); genres with
  /// no play are left out. [Genre.other] is included.
  List<GenreCount> get playGenreCounts => _playGenreCounts;

  /// Number of highlights [requester] requested (`Requester.requestCount`
  /// counts their plays).
  int highlightRequestCount(Requester requester) => _highlightRequests[requester.id];

  /// Number of highlights whose `Highlight.key` is in [keys]; keys of no
  /// highlight of this catalogue do not count.
  int highlightCountWithKeys(Set<String> keys) => keys.isEmpty ? 0 : _highlightKeys.where(keys.contains).length;

  // ---------------------------------------------------------------- search

  /// Highlights matching [query] (every token in the title, requester or genre
  /// label) and, when given, of [genre], requested by requester [requesterId]
  /// and with a `Highlight.key` in [keys]; newest first.
  HighlightResults searchHighlights({String query = '', Genre? genre, int? requesterId, Set<String>? keys}) {
    final tokens = tokenize(query);
    final ids = <int>[];
    for (var i = highlights.length - 1; i >= 0; i--) {
      if (genre != null && highlights[i].genre != genre) continue;
      if (requesterId != null && highlights[i].requesterId != requesterId) continue;
      if (keys != null && !keys.contains(_highlightKeys[i])) continue;
      final fields = _highlightFields[i];
      if (tokens.every(fields.contains)) ids.add(i);
    }
    return HighlightResults._(tokens, Int32List.fromList(ids));
  }

  /// Plays matching [query] (every token in the title, requester, genre or
  /// type label), of [type] and [genre] and requested by requester
  /// [requesterId] when given, linked to a highlight when [withVideo]; newest
  /// first.
  PlayResults searchPlays({String query = '', PlayType? type, Genre? genre, bool withVideo = false, int? requesterId}) {
    final tokens = tokenize(query);
    final matcher = _PlayMatcher(this, tokens);
    final ids = Int32List(plays.length);
    var n = 0, streamCount = 0, lastStream = -1;
    for (var i = plays.length - 1; i >= 0; i--) {
      final p = plays[i];
      if (type != null && p.type != type) continue;
      if (genre != null && p.genre != genre) continue;
      if (withVideo && p.highlightId == null) continue;
      if (requesterId != null && p.requesterId != requesterId) continue;
      if (!matcher.matches(p)) continue;
      ids[n++] = i;
      // plays of a stream are contiguous, so are matches in reverse order
      if (p.streamId != lastStream) {
        streamCount++;
        lastStream = p.streamId;
      }
    }
    return PlayResults._(tokens, Int32List.sublistView(ids, 0, n), plays, streamCount);
  }

  /// How many plays match [query] (same rule as [searchPlays], no filter):
  /// the "N in the Ong Log" cross-link of a highlight search. 0 for an empty query.
  int countPlays(String query) {
    final tokens = tokenize(query);
    if (tokens.isEmpty) return 0;
    final matcher = _PlayMatcher(this, tokens);
    var n = 0;
    for (final p in plays) {
      if (matcher.matches(p)) n++;
    }
    return n;
  }
}

/// Matches plays against query tokens by testing each distinct title,
/// requester, genre and type once per token instead of once per play.
final class _PlayMatcher {
  _PlayMatcher(Catalogue c, this.tokens)
    : _title = [for (final t in tokens) _hits(c._titleFolds, t)],
      _requester = [for (final t in tokens) _hits(c._requesterFolds, t)],
      _genre = [for (final t in tokens) _hits(Catalogue._genreFolds, t)],
      _type = [for (final t in tokens) _hits(Catalogue._typeFolds, t, skipFirst: true)];

  final List<String> tokens;
  final List<Uint8List> _title, _requester, _genre, _type;

  static Uint8List _hits(List<String> folds, String token, {bool skipFirst = false}) {
    final hits = Uint8List(folds.length);
    for (var i = skipFirst ? 1 : 0; i < folds.length; i++) {
      if (folds[i].contains(token)) hits[i] = 1;
    }
    return hits;
  }

  bool matches(Play p) {
    for (var t = 0; t < tokens.length; t++) {
      if (_title[t][p.titleId] == 1 || _genre[t][p.genre.index] == 1 || _type[t][p.type.index] == 1) continue;
      final r = p.requesterId;
      if (r != null && _requester[t][r] == 1) continue;
      return false;
    }
    return true;
  }
}
