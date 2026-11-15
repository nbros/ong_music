// The rankings of the statistics page: counts, ranks (one per entry), the order of equal counts (the senior first),
// the artists, "You".
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/model.dart';
import 'package:ong_music/src/data/parser.dart';
import 'package:ong_music/src/data/rankings.dart';
import 'package:ong_music/src/data/text.dart';

import 'fixtures.dart';

/// A play of [title] by [requester], in the one stream of the sheet.
List<String> play(String title, {String requester = '', String genre = 'GAME OST'}) =>
    sRow(date: '2024-01-01 20:00:00', title: title, requester: requester, genre: genre);

/// The ranks of [ranking], first to last.
List<int> ranksOf(Ranking<Object> ranking) => [for (var i = 0; i < ranking.length; i++) ranking.rankOf(i)];

/// Checks that [ranking] gives every entry a rank of its own (1, 2, 3…), the largest counts first, equal counts the
/// senior first: the one whose first play counted ([firstPlay], a `Play.id`) is the oldest.
void expectRankedBySeniority<T>(Ranking<T> ranking, int? Function(T entry) firstPlay, String reason) {
  for (var i = 0; i < ranking.length; i++) {
    if (ranking.rankOf(i) != i + 1) fail('$reason: rank ${ranking.rankOf(i)} at ${i + 1}');
    expect(firstPlay(ranking.entries[i]), isNotNull, reason: '$reason: ${ranking.entries[i]} counted, never played');
    if (i == 0) continue;
    final count = ranking.counts[i], before = ranking.counts[i - 1];
    if (count > before) fail('$reason: $count after $before');
    if (count == before && firstPlay(ranking.entries[i])! <= firstPlay(ranking.entries[i - 1])!) {
      fail('$reason: ${ranking.entries[i]} after ${ranking.entries[i - 1]}, its elder, at $count');
    }
  }
}

/// The first play of every song, artist (by its merge key), genre and requester among [plays], and the merge key of
/// the artist of a title, made here as the statistics page means them.
({Map<String, int> songs, Map<String, int> artists, Map<Genre, int> genres, Map<int, int> requesters}) firstPlays(
  Iterable<Play> plays,
) {
  final songs = <String, int>{}, artists = <String, int>{}, genres = <Genre, int>{}, requesters = <int, int>{};
  for (final p in plays) {
    if (p.songKey.isNotEmpty) songs.putIfAbsent(p.songKey, () => p.id);
    final artist = p.artist;
    if (artist.isNotEmpty) {
      final key = songKey(artist);
      artists.putIfAbsent(key.isEmpty ? fold(artist) : key, () => p.id);
    }
    genres.putIfAbsent(p.genre, () => p.id);
    if (p.requesterId case final r?) requesters.putIfAbsent(r, () => p.id);
  }
  return (songs: songs, artists: artists, genres: genres, requesters: requesters);
}

void main() {
  // equal counts, everywhere, in an order of seniority that is not the alphabetical one
  final catalogue = catalogueOf(
    highlights: [hRow(title: 'Never Played - A Video', requester: 'nobody')],
    songs: [
      start('2024-01-01'),
      play('Zelda - Song of Storms', requester: 'zed'),
      play('Zelda - Song of Storms', requester: 'a'),
      play('Zelda - Lost Woods', requester: 'a'),
      play('Pokémon - Route 1', requester: 'c', genre: 'ANIME'),
      play('pokemon - route 1', requester: 'a', genre: 'ANIME'),
      play('POKEMON - Pallet Town', requester: 'c', genre: 'ANIME'),
      play('Alone', requester: 'Émile', genre: 'POPULAR MUSIC'),
      play('Another Alone', genre: 'CLASSICAL'),
    ],
  );

  group('songs', () {
    final songs = CatalogueRankings(catalogue).songs;

    test('every song played, by plays; equal counts the senior first, each its own rank', () {
      expect(
        [for (final s in songs.entries) s.track],
        [
          // 2 plays each: "Song of Storms" was played first
          'Song of Storms',
          'route 1',
          // 1 play each, in the order of the sheet
          'Lost Woods',
          'Pallet Town',
          'Alone',
          'Another Alone',
        ],
      );
      expect(songs.counts, [2, 2, 1, 1, 1, 1]);
      expect(ranksOf(songs), [1, 2, 3, 4, 5, 6]);
      expect(songs.lastRank, 6);
      expect(songs.top, 2);
      expect(songs.total, catalogue.playCount);
    });

    test('a song of a highlight alone, never played, is not in it', () {
      expect(catalogue.songCount, songs.length + 1);
      expect(songs.entries.map((s) => s.track), isNot(contains('A Video')));
    });

    test('ranks 1, 2, 3, 4 with two equal counts: the first played first, whatever the name', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          for (final title in ['C', 'C', 'A', 'A', 'A', 'B', 'B', 'D']) play(title),
        ],
      );
      final songs = CatalogueRankings(c).songs;
      expect([for (final s in songs.entries) s.track], ['A', 'C', 'B', 'D']);
      expect(ranksOf(songs), [1, 2, 3, 4]);
    });

    test('seniority is the first play, not the latest: an old song played again stays before', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          for (final title in ['Old', 'Young', 'Young', 'Old']) play(title),
        ],
      );
      expect([for (final s in CatalogueRankings(c).songs.entries) s.track], ['Old', 'Young']);
    });

    test('the order of the sheet, not the times written on its rows (some carry a wrong day or year)', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          sRow(date: '2024-01-01 20:00:00', title: 'First'),
          // a typo of the year: logged "before" the first
          sRow(date: '2023-01-01 20:10:00', title: 'Second'),
        ],
      );
      expect([for (final s in CatalogueRankings(c).songs.entries) s.track], ['First', 'Second']);
    });
  });

  group('artists', () {
    final rankings = CatalogueRankings(catalogue);
    final artists = rankings.artists;

    test('one artist whatever the case and the accents, under the most played spelling; the senior first', () {
      expect([for (final a in artists.entries) a.name], ['Zelda', 'Pokémon']);
      expect(artists.counts, [3, 3]);
      expect(ranksOf(artists), [1, 2]);
      // "Pokémon - Route 1" and "pokemon - route 1" are one song
      expect([for (final a in artists.entries) a.songCount], [2, 2]);
    });

    test('an artist is as senior as the first play of any of its titles', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          play('Beta - One'),
          play('Alpha - Two'),
          play('Alpha - Two'),
          // a later title of Beta: Beta is still the elder
          play('Beta - Three'),
        ],
      );
      expect([for (final a in CatalogueRankings(c).artists.entries) a.name], ['Beta', 'Alpha']);
    });

    test('one artist whatever the punctuation too, as the songs are merged', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          play('NieR: Automata - Weight of the World'),
          play('NieR: Automata - Weight of the World'),
          play('NieR Automata - Weight of the World'),
          play('NieR:Automata - City Ruins'),
          play('Boney M. - Rasputin'),
          play('Boney M - Rasputin'),
          // without letter or digit: by its folded spelling, apart from the others
          play('!!! - Slyd'),
        ],
      );
      final artists = CatalogueRankings(c).artists;
      expect([for (final a in artists.entries) a.name], ['NieR: Automata', 'Boney M.', '!!!']);
      expect(artists.counts, [4, 2, 1]);
      // "Weight of the World" is one song of one artist, however the artist is written
      expect([for (final a in artists.entries) a.songCount], [2, 1, 1]);
    });

    test('the plays of titles without artist are counted apart', () {
      expect(rankings.playsWithoutArtist, 2);
      expect(artists.total + rankings.playsWithoutArtist, catalogue.playCount);
    });
  });

  test('genres: every genre played, by plays, the senior first; its share against the plays counted', () {
    final genres = CatalogueRankings(catalogue).genres;
    expect(genres.entries, [Genre.gameOst, Genre.anime, Genre.popular, Genre.classical]);
    expect(genres.counts, [3, 3, 1, 1]);
    expect(ranksOf(genres), [1, 2, 3, 4]);
    expect(genres.total, catalogue.playCount);
  });

  test('requesters: by requests (the plays they asked for), the senior first (first request); the highlights not '
      'counted', () {
    final requesters = CatalogueRankings(catalogue).requesters;
    expect([for (final r in requesters.entries) r.name], ['a', 'c', 'zed', 'Émile']);
    expect(requesters.counts, [3, 2, 1, 1]);
    expect(ranksOf(requesters), [1, 2, 3, 4]);
    expect(CatalogueRankings(catalogue).requesterCount, 4);
    // their different songs: "Pokémon - Route 1" and "pokemon - route 1" are one
    expect([for (final r in requesters.entries) CatalogueRankings(catalogue).songsRequestedBy(r)], [3, 2, 1, 1]);
  });

  group('the requests of one requester alone ("You")', () {
    final a = catalogue.requesterNamed('a')!;
    final c = catalogue.requesterNamed('c')!;

    test('songs, artists and genres count them alone', () {
      final rankings = CatalogueRankings(catalogue, requesterId: a.id);
      expect([for (final s in rankings.songs.entries) s.track], ['Song of Storms', 'Lost Woods', 'route 1']);
      expect(rankings.songs.counts, [1, 1, 1]);
      expect(ranksOf(rankings.songs), [1, 2, 3]);
      expect([for (final x in rankings.artists.entries) (x.name, x.songCount)], [('Zelda', 2), ('Pokémon', 1)]);
      expect(rankings.artists.counts, [2, 1]);
      expect(rankings.playsWithoutArtist, 0);
      expect(rankings.genres.entries, [Genre.gameOst, Genre.anime]);
      expect(rankings.genres.total, 3);
    });

    test('equal counts by the seniority among their requests, not among every play', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          // played first by others
          play('Alpha - A', requester: 'other', genre: 'ANIME'),
          play('Beta - B', requester: 'other', genre: 'CLASSICAL'),
          // requested by "me" in the other order
          play('Beta - B', requester: 'me', genre: 'CLASSICAL'),
          play('Alpha - A', requester: 'me', genre: 'ANIME'),
        ],
      );
      final all = CatalogueRankings(c);
      expect([for (final s in all.songs.entries) s.track], ['A', 'B']);
      expect([for (final x in all.artists.entries) x.name], ['Alpha', 'Beta']);
      expect(all.genres.entries, [Genre.anime, Genre.classical]);
      final mine = CatalogueRankings(c, requesterId: c.requesterNamed('me')!.id);
      expect([for (final s in mine.songs.entries) s.track], ['B', 'A']);
      expect([for (final x in mine.artists.entries) x.name], ['Beta', 'Alpha']);
      expect(mine.genres.entries, [Genre.classical, Genre.anime]);
    });

    test('the requesters: theirs alone, at its own rank among all, the bars against the first of all', () {
      final rankings = CatalogueRankings(catalogue, requesterId: c.id);
      expect(rankings.requesters.entries, [c]);
      expect(ranksOf(rankings.requesters), [2]);
      expect(rankings.requesters.counts, [2]);
      expect(rankings.requesters.top, 3);
      expect(rankings.requesterCount, 4);
      // the last of two with one request: rank 4, not a shared 3
      final emile = CatalogueRankings(catalogue, requesterId: catalogue.requesterNamed('emile')!.id).requesters;
      expect(ranksOf(emile), [4]);
      expect(emile.lastRank, 4);
    });

    test('a requester of highlights alone has nothing to rank', () {
      final nobody = catalogue.requesterNamed('nobody')!;
      final rankings = CatalogueRankings(catalogue, requesterId: nobody.id);
      expect(rankings.songs.isEmpty, isTrue);
      expect(rankings.requesters.isEmpty, isTrue);
      expect(rankings.requesters.top, 3);
      expect(rankings.requesters.lastRank, 1);
    });
  });

  group('the songs of an entry', () {
    final rankings = CatalogueRankings(catalogue);
    List<(String, int)> songsOf(CatalogueRankings rankings, RankedEntry entry) {
      final songs = rankings.songsOf(entry);
      return [for (var i = 0; i < songs.length; i++) (songs.entries[i].track, songs.counts[i])];
    }

    test('of an artist: the plays of its titles, whatever their spelling', () {
      expect(songsOf(rankings, const ArtistEntry('pokemon')), [('route 1', 2), ('Pallet Town', 1)]);
      expect(rankings.songsOf(const ArtistEntry('pokemon')).total, 3);
      expect(ranksOf(rankings.songsOf(const ArtistEntry('pokemon'))), [1, 2]);
      expect(rankings.nameOf(const ArtistEntry('pokemon')), 'Pokémon');
    });

    test('every play of the entry counted in its total, as on its row: those of no song too', () {
      final withNoSong = catalogueOf(
        songs: [
          start('2024-01-01'),
          play('Pokémon - Route 1', requester: 'c', genre: 'ANIME'),
          // of no song: no letter nor digit
          play('???', requester: 'c', genre: 'ANIME'),
        ],
      );
      final all = CatalogueRankings(withNoSong);
      final anime = all.songsOf(const GenreEntry(Genre.anime));
      expect(anime.counts, [1]);
      expect(anime.total, 2);
      expect(anime.total, all.genres.counts.single);
      expect(all.songsOf(const RequesterEntry('c')).total, withNoSong.requesterNamed('c')!.requestCount);
    });

    test('of a genre, and of a requester: their plays, equal counts the senior first', () {
      expect(songsOf(rankings, const GenreEntry(Genre.gameOst)), [('Song of Storms', 2), ('Lost Woods', 1)]);
      final ofA = rankings.songsOf(const RequesterEntry('a'));
      expect(songsOf(rankings, const RequesterEntry('a')), [('Song of Storms', 1), ('Lost Woods', 1), ('route 1', 1)]);
      expect(ranksOf(ofA), [1, 2, 3]);
      expect(rankings.nameOf(const RequesterEntry('emile')), 'Émile');
      expect(rankings.nameOf(const GenreEntry(Genre.anime)), 'Anime');
    });

    test('the seniority of a song among the plays of the entry: its first play under the genre', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          play('X', genre: 'GAME OST'),
          play('Y', genre: 'ANIME'),
          play('X', genre: 'ANIME'),
        ],
      );
      expect(songsOf(CatalogueRankings(c), const GenreEntry(Genre.anime)), [('Y', 1), ('X', 1)]);
    });

    test('with the requests of one requester alone', () {
      final c = CatalogueRankings(catalogue, requesterId: catalogue.requesterNamed('c')!.id);
      expect(songsOf(c, const ArtistEntry('pokemon')), [('route 1', 1), ('Pallet Town', 1)]);
      expect(c.songsOf(const ArtistEntry('zelda')).isEmpty, isTrue);
    });

    test('of an entry the catalogue does not have: none', () {
      expect(rankings.songsOf(const ArtistEntry('mario')).isEmpty, isTrue);
      expect(rankings.nameOf(const ArtistEntry('mario')), isNull);
      expect(rankings.songsOf(const RequesterEntry('nobody')).isEmpty, isTrue);
      expect(rankings.songsOf(const RequesterEntry('zorro')).isEmpty, isTrue);
      expect(rankings.nameOf(const RequesterEntry('zorro')), isNull);
      expect(rankings.songsOf(const GenreEntry(Genre.jazz)).isEmpty, isTrue);
      expect(CatalogueRankings(catalogue.highlightsOnly).songsOf(const GenreEntry(Genre.anime)).isEmpty, isTrue);
    });

    test('entries are equal by their key', () {
      expect(
        const ArtistEntry('zelda'),
        ArtistEntry(
          'zel'
          'da',
        ),
      );
      expect(const ArtistEntry('zelda'), isNot(const RequesterEntry('zelda')));
      expect(const GenreEntry(Genre.anime).hashCode, GenreEntry(Genre.values[Genre.anime.index]).hashCode);
    });
  });

  test('a catalogue of the highlights alone: empty rankings, nothing thrown', () {
    final alone = CatalogueRankings(catalogue.highlightsOnly);
    expect(alone.songs.isEmpty, isTrue);
    expect(alone.artists.isEmpty, isTrue);
    expect(alone.playsWithoutArtist, 0);
    expect(alone.genres.isEmpty, isTrue);
    expect(alone.genres.total, 0);
    // its requesters are those of the highlights, with no request counted
    expect(alone.requesters.isEmpty, isTrue);
    expect(alone.songs.top, 0);
    expect(alone.songs.lastRank, 1);
  });

  test('sheets drawn at random: no shared rank in any ranking nor page of songs, equal counts the senior first', () {
    for (var seed = 0; seed < 6; seed++) {
      final sheets = generatedSheets(seed, plays: 800);
      final c = parseCatalogue(sheets.highlightsCsv, sheets.songsCsv);
      final requesters = [null, for (final r in c.requesters.take(4)) r.id];
      for (final id in requesters) {
        final rankings = CatalogueRankings(c, requesterId: id);
        final reason = 'seed $seed, requester $id';
        final first = firstPlays(c.plays.where((p) => id == null || p.requesterId == id));
        expectRankedBySeniority(rankings.songs, (s) => first.songs[s.key], '$reason, songs');
        expectRankedBySeniority(rankings.artists, (a) => first.artists[a.folded], '$reason, artists');
        expectRankedBySeniority(rankings.genres, (g) => first.genres[g], '$reason, genres');
        if (id == null) {
          expectRankedBySeniority(rankings.requesters, (r) => first.requesters[r.id], '$reason, requesters');
        }
        for (final genre in rankings.genres.entries) {
          final songs = rankings.songsOf(GenreEntry(genre));
          final ofGenre = firstPlays(c.plays.where((p) => (id == null || p.requesterId == id) && p.genre == genre));
          expectRankedBySeniority(songs, (s) => ofGenre.songs[s.key], '$reason, songs of $genre');
        }
        for (final artist in rankings.artists.entries.take(5)) {
          final songs = rankings.songsOf(ArtistEntry(artist.folded));
          final ofArtist = firstPlays(
            c.plays.where((p) {
              if (id != null && p.requesterId != id) return false;
              final key = songKey(p.artist);
              return p.artist.isNotEmpty && (key.isEmpty ? fold(p.artist) : key) == artist.folded;
            }),
          );
          expectRankedBySeniority(songs, (s) => ofArtist.songs[s.key], '$reason, songs of ${artist.name}');
        }
      }
      for (final r in CatalogueRankings(c).requesters.entries.take(5)) {
        final songs = CatalogueRankings(c).songsOf(RequesterEntry(r.folded));
        final ofRequester = firstPlays(c.plays.where((p) => p.requesterId == r.id));
        expectRankedBySeniority(songs, (s) => ofRequester.songs[s.key], 'seed $seed, songs of ${r.name}');
      }
    }
  });

  test('the user\'s own requester: their rank among all, theirs alone', () {
    final sheets = generatedSheets(2, plays: 800);
    final c = parseCatalogue(sheets.highlightsCsv, sheets.songsCsv);
    final all = CatalogueRankings(c).requesters;
    for (var i = 0; i < all.length; i++) {
      final mine = CatalogueRankings(c, requesterId: all.entries[i].id).requesters;
      expect(ranksOf(mine), [i + 1]);
      expect(mine.counts, [all.counts[i]]);
    }
  });
}
