// The rankings of the statistics page: counts, ranks, the order of equal counts, the artists, "You".
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/model.dart';
import 'package:ong_music/src/data/rankings.dart';

import 'fixtures.dart';

void main() {
  /// A play of [title] by [requester], in the one stream of the sheet.
  List<String> play(String title, {String requester = '', String genre = 'GAME OST'}) =>
      sRow(date: '2024-01-01 20:00:00', title: title, requester: requester, genre: genre);

  final catalogue = catalogueOf(
    highlights: [hRow(title: 'Never Played - A Video', requester: 'nobody')],
    songs: [
      start('2024-01-01'),
      play('Zelda - Song of Storms', requester: 'b'),
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

    test('every song played, by plays; equal counts share a rank, in the order of their tracks', () {
      expect(
        [for (final s in songs.entries) s.track],
        [
          // 2 plays each: "route 1" (as written on its latest play) before "song of storms"
          'route 1',
          'Song of Storms',
          // 1 play each, by track
          'Alone',
          'Another Alone',
          'Lost Woods',
          'Pallet Town',
        ],
      );
      expect(songs.counts, [2, 2, 1, 1, 1, 1]);
      expect(songs.ranks, [1, 1, 3, 3, 3, 3]);
      expect(songs.top, 2);
      expect(songs.total, catalogue.playCount);
    });

    test('a song of a highlight alone, never played, is not in it', () {
      expect(catalogue.songCount, songs.length + 1);
      expect(songs.entries.map((s) => s.track), isNot(contains('A Video')));
    });

    test('ranks 1, 2, 2, 4', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          for (final (title, n) in [('A', 3), ('B', 2), ('C', 2), ('D', 1)])
            for (var i = 0; i < n; i++) play(title),
        ],
      );
      expect(CatalogueRankings(c).songs.ranks, [1, 2, 2, 4]);
    });
  });

  group('artists', () {
    final rankings = CatalogueRankings(catalogue);
    final artists = rankings.artists;

    test('one artist whatever the case and the accents, under the most played spelling', () {
      expect([for (final a in artists.entries) a.name], ['Pokémon', 'Zelda']);
      expect(artists.counts, [3, 3]);
      expect(artists.ranks, [1, 1]);
      // "Pokémon - Route 1" and "pokemon - route 1" are one song
      expect([for (final a in artists.entries) a.songCount], [2, 2]);
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

  test('genres: every genre played, by plays, its share against the plays counted', () {
    final genres = CatalogueRankings(catalogue).genres;
    expect(genres.entries, [Genre.anime, Genre.gameOst, Genre.classical, Genre.popular]);
    expect(genres.counts, [3, 3, 1, 1]);
    expect(genres.ranks, [1, 1, 3, 3]);
    expect(genres.total, catalogue.playCount);
  });

  test(
    'requesters: by requests (the plays they asked for), names folded for the order; the highlights not counted',
    () {
      final requesters = CatalogueRankings(catalogue).requesters;
      expect([for (final r in requesters.entries) r.name], ['a', 'c', 'b', 'Émile']);
      expect(requesters.counts, [3, 2, 1, 1]);
      expect(requesters.ranks, [1, 2, 3, 3]);
      expect(CatalogueRankings(catalogue).requesterCount, 4);
      // their different songs: "Pokémon - Route 1" and "pokemon - route 1" are one
      expect([for (final r in requesters.entries) CatalogueRankings(catalogue).songsRequestedBy(r)], [3, 2, 1, 1]);
    },
  );

  group('the requests of one requester alone ("You")', () {
    final a = catalogue.requesterNamed('a')!;
    final c = catalogue.requesterNamed('c')!;

    test('songs, artists and genres count them alone', () {
      final rankings = CatalogueRankings(catalogue, requesterId: a.id);
      expect([for (final s in rankings.songs.entries) s.track], ['Lost Woods', 'route 1', 'Song of Storms']);
      expect(rankings.songs.counts, [1, 1, 1]);
      expect([for (final x in rankings.artists.entries) (x.name, x.songCount)], [('Zelda', 2), ('Pokémon', 1)]);
      expect(rankings.artists.counts, [2, 1]);
      expect(rankings.playsWithoutArtist, 0);
      expect(rankings.genres.entries, [Genre.gameOst, Genre.anime]);
      expect(rankings.genres.total, 3);
    });

    test('the requesters: theirs alone, at its rank among all, the bars against the first of all', () {
      final rankings = CatalogueRankings(catalogue, requesterId: c.id);
      expect(rankings.requesters.entries, [c]);
      expect(rankings.requesters.ranks, [2]);
      expect(rankings.requesters.counts, [2]);
      expect(rankings.requesters.top, 3);
      expect(rankings.requesterCount, 4);
    });

    test('a requester of highlights alone has nothing to rank', () {
      final nobody = catalogue.requesterNamed('nobody')!;
      final rankings = CatalogueRankings(catalogue, requesterId: nobody.id);
      expect(rankings.songs.isEmpty, isTrue);
      expect(rankings.requesters.isEmpty, isTrue);
      expect(rankings.requesters.top, 3);
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
      expect(rankings.songsOf(const ArtistEntry('pokemon')).ranks, [1, 2]);
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

    test('of a genre, and of a requester: their plays, equal counts in the order of the tracks', () {
      expect(songsOf(rankings, const GenreEntry(Genre.gameOst)), [('Song of Storms', 2), ('Lost Woods', 1)]);
      expect(songsOf(rankings, const RequesterEntry('a')), [('Lost Woods', 1), ('route 1', 1), ('Song of Storms', 1)]);
      expect(rankings.nameOf(const RequesterEntry('emile')), 'Émile');
      expect(rankings.nameOf(const GenreEntry(Genre.anime)), 'Anime');
    });

    test('with the requests of one requester alone', () {
      final c = CatalogueRankings(catalogue, requesterId: catalogue.requesterNamed('c')!.id);
      expect(songsOf(c, const ArtistEntry('pokemon')), [('Pallet Town', 1), ('route 1', 1)]);
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
  });

  test('the alphabetical order: of the folded names, equal names in the order of the next ones, then in theirs', () {
    expect(alphabeticalOrder(['b', 'a', 'c', 'a']), [1, 3, 0, 2]);
    // past the first three code units, and a name before the longer ones it begins
    final names = ['abcd', 'abc', 'abcc', 'ab', 'abd', 'é', 'z', 'abc'];
    expect([for (final i in alphabeticalOrder(names)) names[i]], [...names]..sort());
    expect(alphabeticalOrder(names), [3, 1, 7, 2, 0, 4, 6, 5]);
    expect(alphabeticalOrder(['a', 'a', 'a'], then: ['z', 'x', 'y']), [1, 2, 0]);
  });

  test('the alphabetical order is that of a sort of the strings, for any names', () {
    final random = Random(7);
    const letters = ['a', 'b', 'é', ' ', '1', '\u{1F600}', 'あ'];
    for (var round = 0; round < 50; round++) {
      final names = [
        for (var i = random.nextInt(300); i > 0; i--)
          [for (var j = random.nextInt(6); j > 0; j--) letters[random.nextInt(letters.length)]].join(),
      ];
      final then = [for (final _ in names) letters[random.nextInt(2)]];
      final expected = List.generate(names.length, (i) => i)
        ..sort((a, b) {
          final byName = names[a].compareTo(names[b]);
          if (byName != 0) return byName;
          final byThen = then[a].compareTo(then[b]);
          return byThen != 0 ? byThen : a - b;
        });
      expect(alphabeticalOrder(names, then: then), expected, reason: '$names');
    }
  });
}
