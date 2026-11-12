import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/model.dart';

import 'fixtures.dart';

void main() {
  late Catalogue c;

  setUp(() {
    c = catalogueOf(
      highlights: [
        hRow(order: '1', title: 'Zelda - Song of Storms', genre: 'GAME OST', requester: 'Alinsa', stream: '2024-01-01'),
        hRow(order: '2', title: 'Chopin - Nocturne', genre: 'CLASSICAL', stream: '2024-01-01'),
        hRow(order: '3', title: 'Pokémon - Route 1', genre: 'GAME OST', requester: 'Bob', stream: '2024-01-03'),
        hRow(order: '4', title: 'Spirited Away - One Summer\'s Day', genre: 'ANIME', requester: 'Élodie'),
      ],
      songs: [
        start('2024-01-01'),
        sRow(
          date: '2024-01-01',
          title: 'Zelda - Song of Storms',
          genre: 'GAME OST',
          type: 'Piano',
          requester: 'Alinsa',
        ),
        sRow(date: '2024-01-01', title: 'Chopin - Nocturne', genre: 'CLASSICAL', type: 'Loop'),
        start('2024-01-03'),
        sRow(date: '2024-01-03', title: 'Zelda - Gerudo Valley', genre: 'GAME OST', type: 'Loop', requester: 'alinsa'),
        sRow(date: '2024-01-03', title: 'Pokemon - Route 1', genre: 'GAME OST', type: 'Cat piano', requester: 'Bob'),
        start('2024-01-05'),
        sRow(date: '2024-01-05', title: 'Clair de Lune', genre: 'CLASSICAL', type: 'Piano', requester: 'Élodie'),
      ],
    );
  });

  group('highlights', () {
    test('newest first, everything without query', () {
      final r = c.searchHighlights();
      expect(r.ids, [3, 2, 1, 0]);
      expect(r.tokens, isEmpty);
    });

    test('every token must match title, requester or genre', () {
      expect(c.searchHighlights(query: 'zelda').ids, [0]);
      expect(c.searchHighlights(query: 'game alinsa').ids, [0], reason: 'genre + requester');
      expect(c.searchHighlights(query: 'POKEMON route').ids, [2], reason: 'accent-insensitive');
      expect(c.searchHighlights(query: 'elodie').ids, [3]);
      expect(c.searchHighlights(query: 'zelda chopin').ids, isEmpty);
    });

    test('genre filter', () {
      expect(c.searchHighlights(genre: Genre.gameOst).ids, [2, 0]);
      expect(c.searchHighlights(query: 'route', genre: Genre.classical).ids, isEmpty);
    });

    test('requester filter, with the query and the genre', () {
      final alinsa = c.requesterNamed('alinsa')!;
      final elodie = c.requesterNamed('elodie')!;
      expect(c.searchHighlights(requesterId: alinsa.id).ids, [0]);
      expect(c.searchHighlights(requesterId: elodie.id).ids, [3]);
      expect(c.searchHighlights(query: 'zelda', genre: Genre.gameOst, requesterId: alinsa.id).ids, [0]);
      expect(c.searchHighlights(query: 'pokemon', requesterId: alinsa.id).ids, isEmpty);
      expect(c.searchHighlights(genre: Genre.anime, requesterId: alinsa.id).ids, isEmpty);
      expect(c.highlightRequestCount(alinsa), 1);
      expect(c.highlightRequestCount(c.requesterNamed('bob')!), 1);
    });

    test('genre counts, largest first (ties in Genre order), zero counts omitted', () {
      expect(c.highlightGenreCounts, [
        (genre: Genre.gameOst, count: 2),
        (genre: Genre.anime, count: 1),
        (genre: Genre.classical, count: 1),
      ]);
      expect(c.playGenreCounts.first, (genre: Genre.gameOst, count: 3));
    });

    test('cross-link count of plays for the same query', () {
      expect(c.countPlays('zelda'), 2);
      expect(c.countPlays('loop'), 2, reason: 'type label');
      expect(c.countPlays(''), 0);
    });
  });

  group('highlight chip counts', () {
    // me: Alinsa; favourites: 0, 1, 3
    late Catalogue h;
    late int me;
    late Set<String> favourites;

    setUp(() {
      h = catalogueOf(
        highlights: [
          hRow(order: '1', title: 'Zelda - Song of Storms', genre: 'GAME OST', requester: 'Alinsa'),
          hRow(order: '2', title: 'Zelda - Gerudo Valley', genre: 'GAME OST', requester: 'Bob'),
          hRow(order: '3', title: 'Zelda - Lost Woods', genre: 'ANIME', requester: 'Alinsa'),
          hRow(order: '4', title: 'Chopin - Nocturne', genre: 'CLASSICAL', requester: 'Alinsa'),
          hRow(order: '5', title: 'Pokémon - Route 1', genre: 'GAME OST', requester: 'Alinsa'),
          hRow(order: '6', title: 'Chopin - Ballade', genre: 'CLASSICAL', requester: 'Bob'),
        ],
      );
      me = h.requesterNamed('alinsa')!.id;
      favourites = {
        for (final i in [0, 1, 3]) h.highlights[i].key,
      };
    });

    /// The search of the Highlights list: the user is [me], the favourites
    /// are [favourites], "You" and the star filter when [mine] and [stars].
    HighlightResults search({String query = '', Genre? genre, bool mine = false, bool stars = false}) =>
        h.searchHighlights(
          query: query,
          genre: genre,
          requesterId: me,
          onlyRequester: mine,
          keys: favourites,
          onlyKeys: stars,
        );

    /// (Game OST, Anime, Classical, "You", star).
    (int, int, int, int, int) counts(HighlightResults r) => (
      r.counts.genre(Genre.gameOst),
      r.counts.genre(Genre.anime),
      r.counts.genre(Genre.classical),
      r.counts.requester,
      r.counts.keys,
    );

    test('without filter: the totals', () {
      expect(counts(search()), (3, 1, 2, 4, 3));
      expect(counts(search()).$1, h.highlightGenreCounts.first.count);
      expect(search().counts.requester, h.highlightRequestCount(h.requesters[me]));
      expect(search().counts.keys, h.highlightCountWithKeys(favourites));
      expect(search().counts.genre(Genre.popular), 0);
    });

    test('every count follows the query', () {
      expect(counts(search(query: 'zelda')), (2, 1, 0, 2, 2));
      expect(counts(search(query: 'chopin')), (0, 0, 2, 1, 1));
    });

    test('genres follow "You" and the star, not the genre selected', () {
      expect(counts(search(mine: true)), (2, 1, 1, 4, 2));
      expect(counts(search(stars: true)), (2, 0, 1, 2, 3));
      expect(counts(search(mine: true, stars: true)), (1, 0, 1, 2, 2));
      expect(counts(search(genre: Genre.gameOst)), (3, 1, 2, 2, 2));
      expect(counts(search(genre: Genre.classical, mine: true)), (2, 1, 1, 1, 1));
    });

    test('"You" follows the query, the genre and the star', () {
      expect(search(genre: Genre.gameOst).counts.requester, 2);
      expect(search(stars: true).counts.requester, 2);
      expect(search(query: 'zelda', genre: Genre.gameOst, stars: true).counts.requester, 1);
      expect(search(query: 'chopin', genre: Genre.gameOst).counts.requester, 0);
    });

    test('the star follows the query, the genre and "You"', () {
      expect(search(genre: Genre.gameOst).counts.keys, 2);
      expect(search(mine: true).counts.keys, 2);
      expect(search(query: 'zelda', genre: Genre.gameOst, mine: true).counts.keys, 1);
      expect(search(query: 'pokemon').counts.keys, 0);
    });

    test('nothing to count without requester or keys', () {
      final r = h.searchHighlights(query: 'zelda');
      expect((r.counts.requester, r.counts.keys), (0, 0));
      expect(r.counts.genre(Genre.gameOst), 2);
      expect(h.searchHighlights(keys: const {}).counts.keys, 0);
    });

    test('the count of each chip is the length of the list with that chip selected', () {
      for (final query in ['', 'zelda', 'chopin', 'alinsa', 'o', 'nothing']) {
        for (final genre in [null, Genre.gameOst, Genre.anime, Genre.classical]) {
          for (final mine in [false, true]) {
            for (final stars in [false, true]) {
              final r = search(query: query, genre: genre, mine: mine, stars: stars);
              final reason = '"$query" $genre mine: $mine stars: $stars';
              for (final g in [Genre.gameOst, Genre.anime, Genre.classical]) {
                expect(
                  r.counts.genre(g),
                  search(query: query, genre: g, mine: mine, stars: stars).length,
                  reason: reason,
                );
              }
              expect(
                r.counts.requester,
                search(query: query, genre: genre, mine: true, stars: stars).length,
                reason: reason,
              );
              expect(
                r.counts.keys,
                search(query: query, genre: genre, mine: mine, stars: true).length,
                reason: reason,
              );
              // the list itself is what the filters say, in order
              expect(r.ids, [
                for (var i = h.highlightCount - 1; i >= 0; i--)
                  if ((genre == null || h.highlights[i].genre == genre) &&
                      (!mine || h.highlights[i].requesterId == me) &&
                      (!stars || favourites.contains(h.highlights[i].key)) &&
                      h.searchHighlights(query: query).ids.contains(i))
                    i,
              ], reason: reason);
            }
          }
        }
      }
    });
  });

  group('plays', () {
    test('newest first, with stream count and stream starts', () {
      final r = c.searchPlays();
      expect(r.ids, [4, 3, 2, 1, 0]);
      expect(r.streamCount, 3);
      expect([for (var i = 0; i < r.length; i++) r.startsStream(i)], [true, true, false, true, false]);
      expect(r[0].title, 'Clair de Lune');
    });

    test('query over title, requester, genre and type', () {
      expect(c.searchPlays(query: 'alinsa loop').ids, [2]);
      expect(c.searchPlays(query: 'classical').ids, [4, 1]);
      expect(c.searchPlays(query: 'cat').ids, [3]);
      expect(c.searchPlays(query: 'pokémon').ids, [3]);
      expect(c.searchPlays(query: 'nothing').isEmpty, isTrue);
    });

    test('type, genre and video filters', () {
      expect(c.searchPlays(type: PlayType.loop).ids, [2, 1]);
      expect(c.searchPlays(type: PlayType.piano).ids, [4, 0]);
      expect(c.searchPlays(genre: Genre.classical).ids, [4, 1]);
      final withVideo = c.searchPlays(withVideo: true);
      expect(withVideo.ids, [3, 1, 0]);
      expect(withVideo.streamCount, 2);
      expect(c.searchPlays(query: 'zelda', withVideo: true, type: PlayType.piano).ids, [0]);
    });

    test('requester filter, with the query and the other filters', () {
      final alinsa = c.requesterNamed('alinsa')!.id;
      final mine = c.searchPlays(requesterId: alinsa);
      expect(mine.ids, [2, 0]);
      expect(mine.streamCount, 2);
      expect(c.searchPlays(requesterId: c.requesterNamed('bob')!.id).ids, [3]);
      expect(c.searchPlays(query: 'storms', requesterId: alinsa).ids, [0]);
      expect(c.searchPlays(type: PlayType.loop, requesterId: alinsa).ids, [2]);
      expect(c.searchPlays(genre: Genre.classical, requesterId: alinsa).ids, isEmpty);
      expect(c.searchPlays(withVideo: true, requesterId: alinsa).ids, [0]);
    });
  });

  group('lookups', () {
    test('song, stream and requester', () {
      final song = c.song('zelda song of storms')!;
      expect(song.playIds, [0]);
      expect(song.highlightIds, [0]);
      expect(c.song('pokemon route 1')!.playIds, [3]);
      final stream = c.streamOf(c.plays[3]);
      expect((stream.date, stream.playCount), (CalendarDate(2024, 1, 3), 2));
      expect(stream.highlightIds, [2]);
      expect(c.requesterNamed('ALINSA')!.requestCount, 2);
      expect(c.requesterNamed('elodie')!.name, 'Élodie');
    });

    test('isRequester compares folded names', () {
      final alinsa = c.plays[0].requesterId;
      expect(c.isRequester(alinsa, 'alinsa'), isTrue);
      expect(c.isRequester(alinsa, 'bob'), isFalse);
      expect(c.isRequester(alinsa, ''), isFalse);
      expect(c.isRequester(null, 'alinsa'), isFalse);
    });
  });
}
