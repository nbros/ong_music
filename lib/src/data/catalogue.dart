/// The immutable in-memory catalogue and its queries.
///
/// Pure Dart. Build one with `parseCatalogue` (parser.dart).
library;

import 'dart:typed_data';

import 'model.dart';
import 'slices.dart';
import 'text.dart';

/// A genre and how many rows have it.
typedef GenreCount = ({Genre genre, int count});

/// The position of [id] in [ids], strictly descending (a result, newest
/// first: built from the last id to the first), or -1: O(log n).
int _indexOfDescending(Int32List ids, int id) {
  var lo = 0, hi = ids.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final at = ids[mid];
    if (at == id) return mid;
    if (at > id) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return -1;
}

/// The position of the first id below [bound] in [ids], strictly descending:
/// `ids.length` when there is none. O(log n).
int _firstBelowDescending(Int32List ids, int bound) {
  var lo = 0, hi = ids.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (ids[mid] >= bound) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// The highlights matching a query, newest first.
final class HighlightResults {
  HighlightResults._(this.tokens, this.ids, this.counts);

  /// The folded query tokens, for [matchRanges].
  final List<String> tokens;

  /// Ids (indices in `Catalogue.highlights`) of the matches, newest first.
  final Int32List ids;

  /// How many highlights each filter would keep if it were chosen, the others
  /// staying as they are.
  final HighlightCounts counts;

  int get length => ids.length;
  bool get isEmpty => ids.isEmpty;

  /// The position of highlight [id] in the result, or -1. O(log n).
  int indexOf(int id) => _indexOfDescending(ids, id);
}

/// How many highlights a search would find with one more or one other filter
/// chosen, the query and the other filters unchanged: the counts of the
/// Highlights chips (see `Catalogue.searchHighlights`).
final class HighlightCounts {
  HighlightCounts._(this._genres, this.requester, this.keys);

  final Int32List _genres;

  /// Number of highlights the search would find filtering on its requester.
  final int requester;

  /// Number of highlights the search would find filtering on its keys.
  final int keys;

  /// Number of highlights the search would find with [genre] instead of its
  /// own genre, if any: genres exclude each other.
  int genre(Genre genre) => _genres[genre.index];
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

  /// The position of play [id] in the result, or -1. O(log n).
  int indexOf(int id) => _indexOfDescending(ids, id);

  /// The position of the first play of [stream] in the result (its newest),
  /// or -1 when the result has none of its plays. O(log n): the plays of a
  /// stream have consecutive ids.
  int firstOf(LiveStream stream) {
    final at = _firstBelowDescending(ids, stream.firstPlayId + stream.playCount);
    return at < ids.length && ids[at] >= stream.firstPlayId ? at : -1;
  }

  /// Whether the row at [index] is the first of its stream in the result, i.e.
  /// whether a list grouped by stream shows a stream header above it.
  bool startsStream(int index) => index == 0 || _plays[ids[index - 1]].streamId != _plays[ids[index]].streamId;
}

/// The sheets, parsed and cross-linked. Immutable; all queries are in memory.
///
/// Ids are indices: `highlights[h.id] == h`, `plays[p.id] == p`, etc.
///
/// A catalogue is first made from the "Youtube Catalogue" sheet alone (`parseHighlights`): the Highlights list needs
/// nothing else, and the Songs sheet, seven times larger, comes later (see `CatalogueNotifier.songsWanted`). Such a catalogue has no
/// [plays], [streams], [titles] or songs ([hasSongs] is false), and its [requesters] are those of the highlights,
/// counted from that sheet alone. [withSongs] completes it with the Songs sheet: the complete catalogue shares its
/// [highlights], the same objects, and keeps the ids of its requesters, so that a list of highlights stays as it is
/// when the Songs sheet comes (see [highlightsOnly]).
///
/// **An id is only valid with the catalogue it came from.** A refresh replaces
/// the catalogue, and a row inserted or removed in the middle of a sheet shifts
/// every later id. So a view that outlives a build (a detail sheet, a selected
/// row) must keep the [Catalogue] it was opened with, or the entity objects, and
/// never look an old id up in a newer catalogue. To find "the same thing" again
/// across catalogues use what does not move: `Song.key`, a stream's date, a
/// highlight's `seq` (`Highlight.key` also tells apart the rows sharing one), a
/// requester's folded name. The catalogue instance itself
/// is kept when a refresh finds the sheets unchanged. A catalogue and the one [withSongs] made from it share their
/// highlights and the ids of the requesters of the highlights: an id of a highlight is valid in both.
final class Catalogue {
  Catalogue._({
    required this.highlights,
    required this.plays,
    required this.streams,
    required this.requesters,
    required this.titles,
    required Map<String, Song> songs,
    required List<String> titleFolds,
    required List<String> requesterFolds,
    required Map<String, int> requesterByFold,
    required List<String> highlightFields,
    required List<String> highlightKeys,
    required List<GenreCount> highlightGenreCounts,
    required List<GenreCount> playGenreCounts,
    required Int32List highlightRequests,
    required Map<String, Map<String, int>> spellings,
    required Int32List? highlightPlays,
    required Catalogue? highlightsOnly,
  }) : _songs = songs,
       _titleFolds = titleFolds,
       _requesterFolds = requesterFolds,
       _requesterByFold = requesterByFold,
       _highlightFields = highlightFields,
       _highlightKeys = highlightKeys,
       _highlightGenreCounts = highlightGenreCounts,
       _playGenreCounts = playGenreCounts,
       _highlightRequests = highlightRequests,
       _spellings = spellings,
       _highlightPlays = highlightPlays,
       _highlightsOnly = highlightsOnly;

  /// Assembles the catalogue of the highlights alone and computes its indexes, in steps (see `HighlightsLoad`),
  /// then [done] receives it. Only the parser does this (`parseHighlights`).
  ///
  /// [requesters] are those of the highlights, [spellings] their names as written in the sheet (folded name, then
  /// count of each spelling), which [withSongs] adds to those of the Songs sheet. The loop over the highlights
  /// (2,000 in the real sheets, whose titles are folded) has a pause point every [pauseEvery] of them (at least 1);
  /// the others cost a fraction of a millisecond together and run in one step.
  static Iterable<void> assembleHighlights({
    required List<Highlight> highlights,
    required List<Requester> requesters,
    required Map<String, Map<String, int>> spellings,
    required void Function(Catalogue catalogue) done,
    int pauseEvery = rowsPerPause,
  }) sync* {
    if (pauseEvery < 1) throw ArgumentError.value(pauseEvery, 'pauseEvery', 'must be at least 1');
    final requesterFolds = List<String>.unmodifiable([for (final r in requesters) r.folded]);
    final requesterByFold = {for (final r in requesters) r.folded: r.id};
    yield null;
    // fields joined by a newline: a query token never contains whitespace, so never spans two fields
    final highlightFields = <String>[];
    for (var i = 0; i < highlights.length; i++) {
      final h = highlights[i];
      highlightFields.add(
        '${fold(h.title)}\n${h.requesterId == null ? '' : requesterFolds[h.requesterId!]}\n${_genreFolds[h.genre.index]}',
      );
      if (i % pauseEvery == 0) yield null;
    }
    final highlightKeys = [for (final h in highlights) h.key];
    final highlightGenreCounts = _countGenres(highlights.map((h) => h.genre));
    final highlightRequests = Int32List(requesters.length);
    for (final h in highlights) {
      if (h.requesterId != null) highlightRequests[h.requesterId!]++;
    }
    done(
      Catalogue._(
        highlights: highlights,
        plays: const [],
        streams: const [],
        requesters: requesters,
        titles: const [],
        songs: const {},
        titleFolds: const [],
        requesterFolds: requesterFolds,
        requesterByFold: requesterByFold,
        highlightFields: highlightFields,
        highlightKeys: highlightKeys,
        highlightGenreCounts: highlightGenreCounts,
        playGenreCounts: const [],
        highlightRequests: highlightRequests,
        spellings: spellings,
        highlightPlays: null,
        highlightsOnly: null,
      ),
    );
  }

  /// This catalogue completed with [songs], the Songs sheet parsed against its highlights (`parseSongs`, given
  /// [highlightsOnly]): it shares the highlights of this one, and the indexes made of them alone. Cheap: nothing is
  /// computed. Throws an [ArgumentError] when [songs] was parsed against other highlights.
  Catalogue withSongs(SongsPart songs) {
    final base = highlightsOnly;
    if (songs.highlightCount != base.highlights.length || songs.requesters.length < base.requesters.length) {
      throw ArgumentError.value(songs, 'songs', 'parsed against other highlights');
    }
    return Catalogue._(
      highlights: base.highlights,
      plays: songs.plays,
      streams: songs.streams,
      requesters: songs.requesters,
      titles: songs.titles,
      songs: songs.songs,
      titleFolds: songs.titleFolds,
      requesterFolds: songs.requesterFolds,
      requesterByFold: songs.requesterByFold,
      highlightFields: base._highlightFields,
      highlightKeys: base._highlightKeys,
      highlightGenreCounts: base._highlightGenreCounts,
      playGenreCounts: songs.playGenreCounts,
      highlightRequests: base._highlightRequests,
      spellings: base._spellings,
      highlightPlays: songs.highlightPlays,
      highlightsOnly: base,
    );
  }

  /// Highlights in sheet order (oldest upload first).
  final List<Highlight> highlights;

  /// Ong Log plays in sheet order (oldest first). Empty without [hasSongs].
  final List<Play> plays;

  /// Streams, oldest first. Every stream has at least one play. Empty without [hasSongs].
  final List<LiveStream> streams;

  /// Requesters (of plays or highlights): those of the highlights first, in order of first appearance in their
  /// sheet, then those of the plays alone. Without [hasSongs], only those of the highlights, their names as written
  /// in that sheet, and no request counted.
  final List<Requester> requesters;

  /// Distinct play titles as written (whitespace collapsed); `Play.titleId`
  /// indexes it. Empty without [hasSongs].
  final List<String> titles;

  final Map<String, Song> _songs;

  final List<String> _titleFolds;
  final List<String> _requesterFolds;
  final Map<String, int> _requesterByFold;
  final List<String> _highlightFields;
  final List<String> _highlightKeys;
  final List<GenreCount> _highlightGenreCounts;
  final List<GenreCount> _playGenreCounts;
  final Int32List _highlightRequests;
  final Map<String, Map<String, int>> _spellings;

  /// The play of each highlight (`playOf`), -1 for none; null without [hasSongs].
  final Int32List? _highlightPlays;
  final Catalogue? _highlightsOnly;

  /// Whether the Songs sheet is in: the Ong Log, the plays of the highlights, the request counts.
  bool get hasSongs => _highlightPlays != null;

  /// The catalogue of the highlights alone this one was completed from ([withSongs]); itself without [hasSongs].
  /// Two catalogues with the same one show the same highlights, with the same ids.
  Catalogue get highlightsOnly => _highlightsOnly ?? this;

  /// The folded names of [requesters], by id (for `parseSongs`).
  List<String> get requesterFolds => _requesterFolds;

  /// The names of the requesters of the highlights as written in their sheet: folded name, then the count of each
  /// spelling, in order of first appearance (for `parseSongs`, which adds those of the Songs sheet).
  Map<String, Map<String, int>> get requesterSpellings => _spellings;

  static final List<String> _genreFolds = [for (final g in Genre.values) fold(g.label)];
  static final List<String> _typeFolds = [for (final t in PlayType.values) fold(t.label)];

  static List<GenreCount> _countGenres(Iterable<Genre> genres) {
    final counts = List.filled(Genre.values.length, 0);
    for (final g in genres) {
      counts[g.index]++;
    }
    return _genreCounts(counts);
  }

  /// The genres of [counts] (by [Genre.index]) that have rows, largest count first, ties in [Genre] order.
  static List<GenreCount> _genreCounts(List<int> counts) {
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

  /// The play linked to a highlight: the Ong Log row this video shows (same `Highlight.songKey`, played within one
  /// day of its `Highlight.streamDate`), or null. Null for all without [hasSongs].
  Play? playOf(Highlight highlight) {
    final id = _highlightPlays?[highlight.id] ?? -1;
    return id < 0 ? null : plays[id];
  }

  // ---------------------------------------------------------------- counts

  /// Highlight count per genre, largest first (ties in [Genre] order); genres
  /// with no highlight are left out. [Genre.other] is included.
  List<GenreCount> get highlightGenreCounts => _highlightGenreCounts;

  /// Play count per genre, largest first (ties in [Genre] order); genres with
  /// no play are left out. [Genre.other] is included.
  List<GenreCount> get playGenreCounts => _playGenreCounts;

  /// Number of highlights [requester] requested (`Requester.requestCount`
  /// counts their plays).
  int highlightRequestCount(Requester requester) =>
      requester.id < _highlightRequests.length ? _highlightRequests[requester.id] : 0;

  /// Number of highlights whose `Highlight.key` is in [keys]; keys of no
  /// highlight of this catalogue do not count.
  int highlightCountWithKeys(Set<String> keys) => keys.isEmpty ? 0 : _highlightKeys.where(keys.contains).length;

  // ---------------------------------------------------------------- search

  /// Highlights matching [query] (every token in the title, requester or genre
  /// label) and, when given, of [genre], requested by requester [requesterId]
  /// and with a `Highlight.key` in [keys]; newest first.
  ///
  /// With [onlyRequester] or [onlyKeys] false, [requesterId] or [keys] do not
  /// filter: they are only counted. The same pass gives the
  /// `HighlightResults.counts`.
  HighlightResults searchHighlights({
    String query = '',
    Genre? genre,
    int? requesterId,
    bool onlyRequester = true,
    Set<String>? keys,
    bool onlyKeys = true,
  }) {
    final tokens = tokenize(query);
    final ids = <int>[];
    final genres = Int32List(Genre.values.length);
    var requesterCount = 0, keyCount = 0;
    for (var i = highlights.length - 1; i >= 0; i--) {
      final h = highlights[i];
      final ofGenre = genre == null || h.genre == genre;
      final ofRequester = requesterId != null && h.requesterId == requesterId;
      final withKey = keys != null && keys.contains(_highlightKeys[i]);
      final byRequester = !onlyRequester || requesterId == null || ofRequester;
      final byKeys = !onlyKeys || keys == null || withKey;
      // what the highlight counts for, if it matches the query
      final forGenre = byRequester && byKeys;
      final forRequester = ofRequester && ofGenre && byKeys;
      final forKeys = withKey && ofGenre && byRequester;
      if (!forGenre && !forRequester && !forKeys) continue;
      final fields = _highlightFields[i];
      if (!tokens.every(fields.contains)) continue;
      if (forGenre) {
        genres[h.genre.index]++;
        if (ofGenre) ids.add(i);
      }
      if (forRequester) requesterCount++;
      if (forKeys) keyCount++;
    }
    return HighlightResults._(tokens, Int32List.fromList(ids), HighlightCounts._(genres, requesterCount, keyCount));
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

/// What the Songs sheet adds to a catalogue of highlights ([Catalogue.withSongs]): the plays, streams, titles and
/// songs, the requesters of both sheets, the links between plays and highlights, and their indexes. Made by
/// `parseSongs` against the highlights of one catalogue, and only valid with it. Holds nothing of the highlights
/// themselves: made on a background isolate, it comes back without a copy of them.
final class SongsPart {
  SongsPart._({
    required this.plays,
    required this.streams,
    required this.requesters,
    required this.titles,
    required this.songs,
    required this.titleFolds,
    required this.requesterFolds,
    required this.requesterByFold,
    required this.playGenreCounts,
    required this.highlightPlays,
  });

  /// Computes the indexes of the plays, in steps (see `SongsLoad`), then [done] receives the part. Only the parser
  /// does this (`parseSongs`). [highlightPlays] holds the play of each highlight, -1 for none.
  ///
  /// The loops over the titles (11,000 in the real sheets) and the plays (31,000) have a pause point every
  /// [pauseEvery] of them (at least 1); the one over the requesters (1,700) runs in one step.
  static Iterable<void> assemble({
    required List<Play> plays,
    required List<LiveStream> streams,
    required List<Requester> requesters,
    required List<String> titles,
    required Map<String, Song> songs,
    required Int32List highlightPlays,
    required void Function(SongsPart songs) done,
    int pauseEvery = rowsPerPause,
  }) sync* {
    if (pauseEvery < 1) throw ArgumentError.value(pauseEvery, 'pauseEvery', 'must be at least 1');
    final titleFolds = <String>[];
    for (var i = 0; i < titles.length; i++) {
      titleFolds.add(fold(titles[i]));
      if (i % pauseEvery == 0) yield null;
    }
    final requesterFolds = List<String>.unmodifiable([for (final r in requesters) r.folded]);
    final requesterByFold = {for (final r in requesters) r.folded: r.id};
    yield null;
    final playGenres = List.filled(Genre.values.length, 0);
    for (var i = 0; i < plays.length; i++) {
      playGenres[plays[i].genre.index]++;
      if (i % pauseEvery == 0) yield null;
    }
    done(
      SongsPart._(
        plays: plays,
        streams: streams,
        requesters: requesters,
        titles: titles,
        songs: songs,
        titleFolds: titleFolds,
        requesterFolds: requesterFolds,
        requesterByFold: requesterByFold,
        playGenreCounts: Catalogue._genreCounts(playGenres),
        highlightPlays: highlightPlays,
      ),
    );
  }

  final List<Play> plays;
  final List<LiveStream> streams;

  /// The requesters of both sheets: those of the highlights first, with their ids.
  final List<Requester> requesters;
  final List<String> titles;
  final Map<String, Song> songs;
  final List<String> titleFolds;
  final List<String> requesterFolds;
  final Map<String, int> requesterByFold;
  final List<GenreCount> playGenreCounts;
  final Int32List highlightPlays;

  /// Number of highlights it was parsed against.
  int get highlightCount => highlightPlays.length;

  /// Number of plays.
  int get playCount => plays.length;
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
