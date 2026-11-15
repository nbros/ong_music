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

/// An artist (or work) of the Ong Log: the part of the titles before their first ` - ` (see [splitTitle]), with case
/// and accents folded, so that `Pokémon` and `pokemon` are one.
final class Artist {
  const Artist({required this.name, required this.folded, required this.songCount});

  /// Its most played spelling.
  final String name;

  /// [fold] of the spellings: the merge key.
  final String folded;

  /// Number of different songs of it among the plays counted.
  final int songCount;

  @override
  String toString() => 'Artist($name, $songCount songs)';
}

/// The entries of one ranking, the most represented first; equal counts in the alphabetical order of their folded
/// names. Entries with nothing to count are left out.
final class Ranking<T> {
  Ranking._(this.entries, this.counts, this.ranks, {required this.top, required this.total});

  /// [entries] ranked by [counts] (one per entry, those of 0 left out), equal counts in the order of [alphabetical]
  /// (the indices of the entries in the alphabetical order of their names, see [alphabeticalOrder]).
  ///
  /// A counting sort, O(entries + largest count): the entries go into one bucket per count in alphabetical order,
  /// no comparison of names (a sort of the 10,000 songs by name takes milliseconds, made once per catalogue).
  factory Ranking._sorted(List<T> entries, List<int> counts, Int32List alphabetical) {
    var largest = 0, kept = 0, total = 0;
    for (final count in counts) {
      if (count <= 0) continue;
      kept++;
      total += count;
      if (count > largest) largest = count;
    }
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
    for (final i in alphabetical) {
      final count = counts[i];
      if (count > 0) order[starts[count]++] = i;
    }
    final sortedCounts = Int32List(kept);
    final ranks = Int32List(kept);
    for (var i = 0; i < kept; i++) {
      final count = counts[order[i]];
      sortedCounts[i] = count;
      ranks[i] = i > 0 && count == sortedCounts[i - 1] ? ranks[i - 1] : i + 1;
    }
    return Ranking._(
      List.unmodifiable([for (final i in order) entries[i]]),
      sortedCounts,
      ranks,
      top: largest,
      total: total,
    );
  }

  /// The entries, the most represented first.
  final List<T> entries;

  /// The count of each entry: plays, or requests for the requesters.
  final Int32List counts;

  /// The rank of each entry, from 1: equal counts share one (1, 2, 2, 4).
  final Int32List ranks;

  /// The count the bars are drawn against: that of the first entry, or of the first one of the whole ranking when
  /// this one keeps only the user's own entry.
  final int top;

  /// The sum of the counts: the share of an entry is its count over it.
  final int total;

  int get length => entries.length;
  bool get isEmpty => entries.isEmpty;
}

/// The indices of [names] in their alphabetical order (of code units: they are folded); equal names in the order of
/// [then] when given (one per name), then in their order in [names].
///
/// Made once per catalogue, for the 10,000 songs among them: most comparisons are decided by the first three code
/// units of the names, packed in one integer (51 bits: exact in JavaScript too), without comparing the strings (under
/// WebAssembly, the order of the songs takes 11 ms instead of 17).
Int32List alphabeticalOrder(List<String> names, {List<String>? then}) {
  final prefixes = List<int>.generate(names.length, (i) {
    final name = names[i];
    var prefix = 0;
    for (var j = 0; j < 3; j++) {
      // 0 past the end: a name comes before the longer ones it begins
      prefix = prefix * 65537 + (j < name.length ? name.codeUnitAt(j) + 1 : 0);
    }
    return prefix;
  }, growable: false);
  final order = List.generate(names.length, (i) => i)
    ..sort((a, b) {
      final pa = prefixes[a], pb = prefixes[b];
      if (pa != pb) return pa < pb ? -1 : 1;
      var byName = names[a].compareTo(names[b]);
      if (byName == 0 && then != null) byName = then[a].compareTo(then[b]);
      return byName != 0 ? byName : a - b;
    });
  return Int32List.fromList(order);
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

  /// The indices of [songs] in alphabetical order: by the track shown, then by the key, which tells apart two songs
  /// whose tracks fold the same.
  late final Int32List songOrder = alphabeticalOrder(
    [for (final s in songs) fold(s.track)],
    then: [for (final s in songs) s.key],
  );

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

  /// The artists: the index of the artist of each title (-1 for a title without one), the folded name of each
  /// artist, its most played spelling, and their alphabetical order.
  late final ({Int32List ofTitle, List<String> folds, List<String> names, Int32List order}) artists = () {
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
      final a = index.putIfAbsent(fold(artist), () {
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
      order: alphabeticalOrder(folds),
    );
  }();

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

  static final Int32List genreOrder = alphabeticalOrder([for (final g in Genre.values) fold(g.label)]);
}

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

  /// The plays counted, per title (`Play.titleId`), and per genre (`Genre.index`).
  late final (Int32List, Int32List) _counted = () {
    final titles = Int32List(catalogue.titles.length);
    final genres = Int32List(Genre.values.length);
    final only = requesterId;
    for (final p in catalogue.plays) {
      if (only != null && p.requesterId != only) continue;
      titles[p.titleId]++;
      genres[p.genre.index]++;
    }
    return (titles, genres);
  }();

  /// Every song played (or requested), by its number of plays.
  late final Ranking<Song> songs = () {
    final t = _tables;
    final counts = Int32List(t.songs.length);
    final titles = _counted.$1;
    final titleSong = t.titleSong;
    for (var i = 0; i < titles.length; i++) {
      final s = titleSong[i];
      if (s >= 0) counts[s] += titles[i];
    }
    return Ranking._sorted(t.songs, counts, t.songOrder);
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
    final titles = _counted.$1;
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
      artists.order,
    );
  }();

  /// The plays counted whose title has no artist (no ` - `), which [artists] leaves out.
  int get playsWithoutArtist {
    artists;
    return _playsWithoutArtist;
  }

  int _playsWithoutArtist = 0;

  /// Every genre played, by its number of plays; `Ranking.total` is the number of plays counted.
  late final Ranking<Genre> genres = Ranking._sorted(Genre.values, _counted.$2, _Tables.genreOrder);

  /// Every requester of a play, by their number of requests (`Requester.requestCount`, the plays they requested).
  /// With [requesterId], that requester alone, at their rank among all of them, the bars against the first one.
  late final Ranking<Requester> requesters = () {
    final all = _allRequesters(catalogue);
    final only = requesterId;
    if (only == null) return all;
    final at = all.entries.indexWhere((r) => r.id == only);
    if (at < 0) return Ranking<Requester>._(const [], Int32List(0), Int32List(0), top: all.top, total: 0);
    return Ranking._(
      [all.entries[at]],
      Int32List.fromList([all.counts[at]]),
      Int32List.fromList([all.ranks[at]]),
      top: all.top,
      total: all.counts[at],
    );
  }();

  /// The number of different songs [requester] asked for (made once per catalogue).
  int songsRequestedBy(Requester requester) => _tables.requesterSongs[requester.id];

  /// The number of requesters of a play, whatever [requesterId].
  int get requesterCount => _allRequesters(catalogue).length;

  /// The ranking of every requester of [catalogue], made once (the "You" state does not change it).
  static Ranking<Requester> _allRequesters(Catalogue catalogue) => _requesters[catalogue] ??= Ranking._sorted(
    catalogue.requesters,
    [for (final r in catalogue.requesters) r.requestCount],
    alphabeticalOrder(catalogue.requesterFolds),
  );

  static final _requesters = Expando<Ranking<Requester>>('requester ranking');

  /// The number of entries of the ranking of [kind].
  int lengthOf(RankingKind kind) => switch (kind) {
    RankingKind.songs => songs.length,
    RankingKind.artists => artists.length,
    RankingKind.genres => genres.length,
    RankingKind.requesters => requesters.length,
  };
}
