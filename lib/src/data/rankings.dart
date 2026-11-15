/// The rankings of the statistics page: every song, artist, genre and requester of the Ong Log, the most played (or
/// the most requesting) first.
///
/// Pure Dart. Made once per catalogue and per "You" state (`rankingsProvider`), each ranking when first shown.
library;

import 'dart:typed_data';

import 'catalogue.dart';
import 'model.dart';
import 'text.dart';

/// What the statistics page ranks.
enum RankingKind { songs, artists, genres, requesters }

/// An artist (or work) of the Ong Log: the part of the titles before their first ` - ` (see [splitTitle]), merged as
/// the songs are ([songKey]): whatever the case, the accents and the punctuation, so that `Pokémon` and `pokemon`
/// are one, and `NieR: Automata` and `NieR Automata`.
final class Artist {
  const Artist({required this.name, required this.folded, required this.songCount});

  /// Its most played spelling.
  final String name;

  /// The merge key of its spellings: their [songKey], or their [fold] for a name without letter or digit.
  final String folded;

  /// Number of different songs of it among the plays counted.
  final int songCount;

  @override
  String toString() => 'Artist($name, $songCount songs)';
}

/// The entries of one ranking, the most represented first; of equal counts, the senior first: the one whose first
/// play counted is the oldest. Entries with nothing to count are left out. Every entry has a rank of its own.
///
/// The plays are in the order of the sheet (`Catalogue.plays`), which is the order they were played in: the date and
/// time written on the rows are not: some carry a wrong day or year (some dozens in the real sheet). No two entries
/// share their first play (a play is of one song, of one artist at most, of one genre and of one requester at most),
/// so the order needs nothing else.
final class Ranking<T> {
  Ranking._(this.entries, this.counts, {required this.firstRank, required this.top, required this.total});

  /// [entries] ranked by [counts] (one per entry, those of 0 left out), equal counts in the order of [bySeniority]:
  /// the indices of the entries counted, each once, in the order of their first play counted.
  ///
  /// A counting sort, O(entries + largest count): the entries go into one bucket per count in the order of
  /// [bySeniority], no comparison.
  factory Ranking._sorted(List<T> entries, List<int> counts, Int32List bySeniority, {int? total}) {
    var largest = 0, kept = 0, sum = 0;
    for (final count in counts) {
      if (count <= 0) continue;
      kept++;
      sum += count;
      if (count > largest) largest = count;
    }
    assert(bySeniority.length == kept, 'every entry counted once in the order of seniority');
    // where each count begins, the largest first
    final starts = Int32List(largest + 2);
    for (final count in counts) {
      if (count > 0) starts[count]++;
    }
    var at = 0;
    for (var count = largest; count > 0; count--) {
      final n = starts[count];
      starts[count] = at;
      at += n;
    }
    final order = Int32List(kept);
    for (final i in bySeniority) {
      order[starts[counts[i]]++] = i;
    }
    final sortedCounts = Int32List(kept);
    for (var i = 0; i < kept; i++) {
      sortedCounts[i] = counts[order[i]];
    }
    return Ranking._(
      List.unmodifiable([for (final i in order) entries[i]]),
      sortedCounts,
      firstRank: 1,
      top: largest,
      total: total ?? sum,
    );
  }

  /// The entries, the most represented first.
  final List<T> entries;

  /// The count of each entry: plays, or requests for the requesters.
  final Int32List counts;

  /// The rank of the first entry: 1, or that of the user's own entry among all when the ranking keeps it alone.
  final int firstRank;

  /// The rank of the entry at [index], from 1: one per entry, none shared (1, 2, 3, 4 whatever the counts).
  int rankOf(int index) => firstRank + index;

  /// The rank of the last entry, [firstRank] when there is none.
  int get lastRank => isEmpty ? firstRank : firstRank + length - 1;

  /// The count the bars are drawn against: that of the first entry, or of the first one of the whole ranking when
  /// this one keeps only the user's own entry.
  final int top;

  /// The sum of the counts: the share of an entry is its count over it.
  final int total;

  int get length => entries.length;
  bool get isEmpty => entries.isEmpty;
}

/// The entries that the indices of [order] are of ([entryOf], -1 for none), each once, in the order of the first of
/// their indices in [order]: the songs (or the artists) of the titles in the order of their first play, in the order
/// of their own first play.
Int32List _entriesInOrder(Int32List order, Int32List entryOf, int entries) {
  final seen = Uint8List(entries);
  final out = Int32List(entries);
  var n = 0;
  for (final t in order) {
    final e = entryOf[t];
    if (e >= 0 && seen[e] == 0) {
      seen[e] = 1;
      out[n++] = e;
    }
  }
  return Int32List.sublistView(out, 0, n);
}

/// What the rankings of a catalogue share, whatever the "You" state: made once per catalogue, each part when first
/// needed.
final class _Tables {
  _Tables(this.catalogue);

  final Catalogue catalogue;

  /// The tables of [catalogue].
  static _Tables of(Catalogue catalogue) => _cache[catalogue] ??= _Tables(catalogue);

  static final _cache = Expando<_Tables>('ranking tables');

  /// The songs of the catalogue.
  late final List<Song> songs = List.unmodifiable(catalogue.songs);

  /// The index in [songs] of the song of each title (by `Play.titleId`), -1 for a title without letter or digit.
  late final Int32List titleSong = () {
    final index = {for (var i = 0; i < songs.length; i++) songs[i].key: i};
    final titleSong = Int32List(catalogue.titles.length)..fillRange(0, catalogue.titles.length, -1);
    // the key of each title, as the parser made it for its plays (every title has one)
    for (final p in catalogue.plays) {
      if (p.songKey.isNotEmpty) titleSong[p.titleId] = index[p.songKey] ?? -1;
    }
    return titleSong;
  }();

  /// The artists: the index of the artist of each title (-1 for a title without one), the merge key of each
  /// artist (see [Artist.folded]) and its most played spelling.
  late final ({Int32List ofTitle, List<String> folds, List<String> names}) artists = () {
    final titles = catalogue.titles;
    final playsOfTitle = Int32List(titles.length);
    for (final p in catalogue.plays) {
      playsOfTitle[p.titleId]++;
    }
    final index = <String, int>{};
    final spellings = <Map<String, int>>[];
    final ofTitle = Int32List(titles.length);
    for (var t = 0; t < titles.length; t++) {
      final artist = splitTitle(titles[t]).artist;
      if (artist.isEmpty) {
        ofTitle[t] = -1;
        continue;
      }
      final key = songKey(artist);
      final a = index.putIfAbsent(key.isEmpty ? fold(artist) : key, () {
        spellings.add({});
        return spellings.length - 1;
      });
      ofTitle[t] = a;
      spellings[a].update(artist, (n) => n + playsOfTitle[t], ifAbsent: () => playsOfTitle[t]);
    }
    final folds = List.filled(spellings.length, '');
    for (final MapEntry(key: folded, value: a) in index.entries) {
      folds[a] = folded;
    }
    return (
      ofTitle: ofTitle,
      folds: folds,
      names: [
        for (final counts in spellings)
          // the most played spelling; of equal ones, the first seen
          counts.entries.reduce((best, e) => e.value > best.value ? e : best).key,
      ],
    );
  }();

  /// The index of each artist by its merge key ([Artist.folded]).
  late final Map<String, int> artistByKey = {for (var a = 0; a < artists.folds.length; a++) artists.folds[a]: a};

  /// The number of different songs each requester asked for (by `Requester.id`).
  late final Int32List requesterSongs = () {
    final counts = Int32List(catalogue.requesters.length);
    final pairs = <int>{};
    for (final p in catalogue.plays) {
      final r = p.requesterId;
      final s = titleSong[p.titleId];
      if (r != null && s >= 0 && pairs.add(r * songs.length + s)) counts[r]++;
    }
    return counts;
  }();

  /// The requesters of the plays, by their requests (made once per catalogue: the "You" state does not change it).
  late final Ranking<Requester> requesters = () {
    final requesters = catalogue.requesters;
    final counts = Int32List(requesters.length);
    final bySeniority = Int32List(requesters.length);
    var seen = 0;
    for (final p in catalogue.plays) {
      final r = p.requesterId;
      if (r != null && counts[r]++ == 0) bySeniority[seen++] = r;
    }
    return Ranking._sorted(requesters, counts, Int32List.sublistView(bySeniority, 0, seen));
  }();
}

/// An entry of the Artists, Genres or Requesters ranking, by what stays of it from one catalogue to the next (a
/// refresh): the songs of the entry are ranked by [CatalogueRankings.songsOf].
sealed class RankedEntry {
  const RankedEntry();
}

/// An artist, by its merge key ([Artist.folded]).
final class ArtistEntry extends RankedEntry {
  const ArtistEntry(this.key);

  final String key;

  @override
  bool operator ==(Object other) => other is ArtistEntry && other.key == key;

  @override
  int get hashCode => Object.hash(ArtistEntry, key);
}

/// A genre.
final class GenreEntry extends RankedEntry {
  const GenreEntry(this.genre);

  final Genre genre;

  @override
  bool operator ==(Object other) => other is GenreEntry && other.genre == genre;

  @override
  int get hashCode => Object.hash(GenreEntry, genre);
}

/// A requester, by their key ([Requester.folded]): that of their group of names when they have several, which stays
/// when a refresh shows them under another name.
final class RequesterEntry extends RankedEntry {
  const RequesterEntry(this.folded);

  final String folded;

  @override
  bool operator ==(Object other) => other is RequesterEntry && other.folded == folded;

  @override
  int get hashCode => Object.hash(RequesterEntry, folded);
}

/// Makes ahead what the rankings of [catalogue] share (the tables of its songs, of its artists and the ranking of its
/// requesters: most of the cost of the first ranking shown, some milliseconds), so that the statistics page opens
/// without it. Nothing without the Songs sheet, nor a second time for one catalogue.
void makeRankingTables(Catalogue catalogue) {
  if (!catalogue.hasSongs || hasRankingTables(catalogue)) return;
  CatalogueRankings(catalogue)
    ..songs
    ..artists
    ..requesters;
}

/// Whether the tables of the rankings of [catalogue] are made (see [makeRankingTables]).
bool hasRankingTables(Catalogue catalogue) => _Tables._cache[catalogue] != null;

/// The four rankings of a catalogue, of every play or of the requests of one requester alone (the "You" chip). Each
/// one is made when first read; the tables they share once per catalogue.
///
/// Empty without the Songs sheet (`Catalogue.hasSongs`).
final class CatalogueRankings {
  CatalogueRankings(this.catalogue, {this.requesterId});

  final Catalogue catalogue;

  /// The requester whose requests alone are counted; null: every play.
  final int? requesterId;

  late final _Tables _tables = _Tables.of(catalogue);

  /// The plays counted, per title (`Play.titleId`) and per genre (`Genre.index`); and the titles and the genres
  /// counted, in the order of their first play counted.
  late final ({Int32List titles, Int32List genres, Int32List titleOrder, Int32List genreOrder}) _counted = () {
    final titles = Int32List(catalogue.titles.length);
    final genres = Int32List(Genre.values.length);
    final titleOrder = Int32List(titles.length);
    final genreOrder = Int32List(genres.length);
    var titlesSeen = 0, genresSeen = 0;
    final only = requesterId;
    for (final p in catalogue.plays) {
      if (only != null && p.requesterId != only) continue;
      if (titles[p.titleId]++ == 0) titleOrder[titlesSeen++] = p.titleId;
      final g = p.genre.index;
      if (genres[g]++ == 0) genreOrder[genresSeen++] = g;
    }
    return (
      titles: titles,
      genres: genres,
      titleOrder: Int32List.sublistView(titleOrder, 0, titlesSeen),
      genreOrder: Int32List.sublistView(genreOrder, 0, genresSeen),
    );
  }();

  /// Every song played (or requested), by its number of plays.
  late final Ranking<Song> songs = () {
    final t = _tables;
    final counts = Int32List(t.songs.length);
    final titles = _counted.titles;
    final titleSong = t.titleSong;
    for (var i = 0; i < titles.length; i++) {
      final s = titleSong[i];
      if (s >= 0) counts[s] += titles[i];
    }
    return Ranking._sorted(t.songs, counts, _entriesInOrder(_counted.titleOrder, titleSong, counts.length));
  }();

  /// Every artist of the titles played, by the number of plays of their titles; [Artist.songCount] counts their
  /// different songs. The titles without artist are left out: [playsWithoutArtist].
  late final Ranking<Artist> artists = () {
    final t = _tables;
    final artists = t.artists;
    final titleSong = t.titleSong;
    final songs = t.songs.length;
    final counts = Int32List(artists.names.length);
    final songCounts = Int32List(artists.names.length);
    final titles = _counted.titles;
    // (artist, song) pairs seen: two titles of one song by one artist (spelt otherwise) count it once
    final pairs = <int>{};
    var without = 0;
    for (var i = 0; i < titles.length; i++) {
      final n = titles[i];
      if (n == 0) continue;
      final a = artists.ofTitle[i];
      if (a < 0) {
        without += n;
        continue;
      }
      counts[a] += n;
      final s = titleSong[i];
      if (s >= 0 && pairs.add(a * songs + s)) songCounts[a]++;
    }
    _playsWithoutArtist = without;
    return Ranking._sorted(
      [
        for (var a = 0; a < counts.length; a++)
          Artist(name: artists.names[a], folded: artists.folds[a], songCount: songCounts[a]),
      ],
      counts,
      _entriesInOrder(_counted.titleOrder, artists.ofTitle, counts.length),
    );
  }();

  /// The plays counted whose title has no artist (no ` - `), which [artists] leaves out.
  int get playsWithoutArtist {
    artists;
    return _playsWithoutArtist;
  }

  int _playsWithoutArtist = 0;

  /// Every genre played, by its number of plays; `Ranking.total` is the number of plays counted.
  late final Ranking<Genre> genres = Ranking._sorted(Genre.values, _counted.genres, _counted.genreOrder);

  /// Every requester of a play, by their number of requests (the plays they requested, as `Requester.requestCount`).
  /// With [requesterId], that requester alone, at their rank among all of them, the bars against the first one.
  late final Ranking<Requester> requesters = () {
    final all = _tables.requesters;
    final only = requesterId;
    if (only == null) return all;
    final at = all.entries.indexWhere((r) => r.id == only);
    if (at < 0) return Ranking<Requester>._(const [], Int32List(0), firstRank: 1, top: all.top, total: 0);
    return Ranking._(
      [all.entries[at]],
      Int32List.fromList([all.counts[at]]),
      firstRank: all.rankOf(at),
      top: all.top,
      total: all.counts[at],
    );
  }();

  /// The number of different songs [requester] asked for (made once per catalogue).
  int songsRequestedBy(Requester requester) => _tables.requesterSongs[requester.id];

  /// The number of requesters of a play, whatever [requesterId].
  int get requesterCount => _tables.requesters.length;

  /// The songs of [entry], by the plays counted that are of it: of the titles of the artist (as [artists] counts
  /// them), logged under the genre, or requested by the requester; with [requesterId], of their requests alone. One
  /// pass over the plays, made by the caller once. Empty when the entry is not in this catalogue, or has nothing
  /// counted.
  ///
  /// Its `Ranking.total` is every play counted, as the row of the entry counts them: those of a title without letter
  /// or digit too, which are of no song (a few dozen in the real sheets).
  Ranking<Song> songsOf(RankedEntry entry) {
    final t = _tables;
    final counts = Int32List(t.songs.length);
    final bySeniority = Int32List(t.songs.length);
    final titleSong = t.titleSong;
    final only = requesterId;
    var total = 0, seen = 0;
    void count(bool Function(Play p) of) {
      for (final p in catalogue.plays) {
        if (only != null && p.requesterId != only) continue;
        if (!of(p)) continue;
        total++;
        final s = titleSong[p.titleId];
        if (s >= 0 && counts[s]++ == 0) bySeniority[seen++] = s;
      }
    }

    switch (entry) {
      case ArtistEntry(:final key):
        final a = catalogue.hasSongs ? t.artistByKey[key] : null;
        if (a != null) {
          final ofTitle = t.artists.ofTitle;
          count((p) => ofTitle[p.titleId] == a);
        }
      case GenreEntry(:final genre):
        count((p) => p.genre == genre);
      case RequesterEntry(:final folded):
        final r = catalogue.requesterNamed(folded)?.id;
        if (r != null) count((p) => p.requesterId == r);
    }
    return Ranking._sorted(t.songs, counts, Int32List.sublistView(bySeniority, 0, seen), total: total);
  }

  /// The name of [entry] in this catalogue (the artist's most played spelling, the genre's label, the requester's
  /// name), or null when it is not in it.
  String? nameOf(RankedEntry entry) => switch (entry) {
    ArtistEntry(:final key) => switch (_tables.artistByKey[key]) {
      final a? => _tables.artists.names[a],
      null => null,
    },
    GenreEntry(:final genre) => genre.label,
    RequesterEntry(:final folded) => catalogue.requesterNamed(folded)?.name,
  };

  /// The number of entries of the ranking of [kind].
  int lengthOf(RankingKind kind) => switch (kind) {
    RankingKind.songs => songs.length,
    RankingKind.artists => artists.length,
    RankingKind.genres => genres.length,
    RankingKind.requesters => requesters.length,
  };
}
