// The names of one person recombined into one requester (the table of `requester_aliases.dart`), and the running
// times written in Requester cells, which name no requester.
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/parser.dart';
import 'package:ong_music/src/data/rankings.dart';
import 'package:ong_music/src/data/requester_aliases.dart';
import 'package:ong_music/src/data/text.dart';

import 'fixtures.dart';

/// Amy wrote her name three ways, Bob two; Carol is in no group.
final _aliases = RequesterAliases([
  ['Amy', 'amy_alt', 'Amyy'],
  ['Bob', 'bob2'],
]);

/// Plays of [requesters] on one day, one per name, titled by their position.
List<List<String>> _songs(List<String> requesters) => [
  start('2024-01-01'),
  for (var i = 0; i < requesters.length; i++)
    sRow(date: '2024-01-01 20:00:00', title: 'Track $i', requester: requesters[i]),
];

void main() {
  group('the table of the app', () {
    final groups = requesterAliasGroups(requesterAliasTable);

    test('names one name in one group at most, compared folded', () {
      final groupOf = <String, int>{};
      for (var g = 0; g < groups.length; g++) {
        for (final name in groups[g]) {
          final other = groupOf[fold(name)] ?? g;
          expect(other, g, reason: '"$name" is in groups ${other + 1} and ${g + 1}');
          groupOf[fold(name)] = g;
        }
      }
    });

    test('every group holds two names at least, none empty or with a comma', () {
      expect(groups, isNotEmpty);
      for (final group in groups) {
        expect({for (final name in group) fold(name)}.length, greaterThanOrEqualTo(2), reason: '$group');
        for (final name in group) {
          expect(name, isNotEmpty, reason: '$group');
          expect(name.trim(), name, reason: '$group');
        }
      }
    });

    test('every name gives the key of its group, one of its names', () {
      final aliases = RequesterAliases.bundled;
      for (final group in groups) {
        final keys = {for (final name in group) aliases.keyOf(fold(name))};
        expect(keys, hasLength(1), reason: '$group');
        expect(group.map(fold), contains(keys.single));
        for (final name in group) {
          expect(aliases.searchTextOf(keys.single).split('\n'), contains(fold(name)));
        }
      }
      expect(aliases.keyOf('nobody in any group'), 'nobody in any group');
      expect(aliases.searchTextOf('nobody in any group'), 'nobody in any group');
    });

    test('the parse uses it by default', () {
      final group = groups.first;
      final c = catalogueOf(songs: _songs([group[0], group[1]]));
      expect(c.requesters, hasLength(1));
      expect(c.requesters.single.requestCount, 2);
      expect(c.aliases, same(RequesterAliases.bundled));
    });

    test('blank lines and spaces around the names do not count', () {
      expect(requesterAliasGroups('\n  a , B b,c\n\n   \nd,e  \n'), [
        ['a', 'B b', 'c'],
        ['d', 'e'],
      ]);
    });
  });

  group('a group of names', () {
    test('is one requester in both sheets, notes of the highlights included', () {
      final c = catalogueOf(
        highlights: [
          hRow(title: 'v1', requester: 'amy_alt'),
          hRow(title: 'v2', notes: 'Requested by Amyy, thanks'),
          hRow(title: 'v3', requester: 'Carol'),
          hRow(title: 'v4', requester: 'BOB2'),
        ],
        songs: _songs(['Amy', 'amy_alt', 'AMYY', 'Bob', 'Carol', 'amy_alt', 'bob2']),
        aliases: _aliases,
      );
      expect(c.requesters.map((r) => (r.name, r.requestCount)), [('amy_alt', 4), ('Carol', 1), ('Bob', 2)]);
      final amy = c.requesterNamed('amy')!;
      expect(c.highlights.map((h) => h.requesterId), [amy.id, amy.id, 1, 2]);
      expect(c.plays.map((p) => c.requester(p.requesterId)!.name), [
        'amy_alt', 'amy_alt', 'amy_alt', 'Bob', 'Carol', 'amy_alt', 'Bob', //
      ]);
      expect(c.highlightRequestCount(amy), 2);
      // Bob and bob2 once each in the Songs sheet, BOB2 in the highlights: Bob was met first
      // the catalogue of the highlights alone has them too, with the same ids
      final alone = c.highlightsOnly;
      expect(alone.requesters.map((r) => r.name), ['amy_alt', 'Carol', 'BOB2']);
      expect(alone.requesterNamed('AMYY')!.id, amy.id);
    });

    test('shows its most frequent spelling over both sheets, the first one met among equal ones', () {
      // the Songs sheet is met first, then the highlights: Amyy and amy_alt twice each, Amyy first
      var c = catalogueOf(
        highlights: [hRow(title: 'v', requester: 'amy_alt')],
        songs: _songs(['Amyy', 'amy_alt', 'Amyy', 'Amy']),
        aliases: _aliases,
      );
      expect(c.requesters.single.name, 'Amyy');
      expect(c.requesters.single.requestCount, 4);
      // one more highlight of amy_alt: it wins
      c = catalogueOf(
        highlights: [
          hRow(title: 'v', requester: 'amy_alt'),
          hRow(title: 'w', requester: 'amy_alt'),
        ],
        songs: _songs(['Amyy', 'amy_alt', 'Amyy', 'Amy']),
        aliases: _aliases,
      );
      expect(c.requesters.single.name, 'amy_alt');
      // spellings of one name count apart, as before: Amy and AMY once each, Amyy twice
      c = catalogueOf(songs: _songs(['Amy', 'AMY', 'Amyy', 'Amyy']), aliases: _aliases);
      expect(c.requesters.single.name, 'Amyy');
      // a name met only in the notes of a highlight is shown only when nothing else is
      c = catalogueOf(
        highlights: [hRow(title: 'v', notes: 'requested by amyy')],
        songs: _songs(['Carol']),
        aliases: _aliases,
      );
      expect(c.requesterNamed('Amy')!.name, 'amyy');
      expect(c.requesterNamed('Amy')!.requestCount, 0);
    });

    test('the order of the names in the table does not matter', () {
      final highlights = [hRow(title: 'v', requester: 'amy_alt'), hRow(title: 'w', requester: 'bob2')];
      final songs = _songs(['Amyy', 'amy_alt', 'Amy', 'Bob', 'Amy']);
      final a = catalogueOf(highlights: highlights, songs: songs, aliases: _aliases);
      final b = catalogueOf(
        highlights: highlights,
        songs: songs,
        aliases: RequesterAliases([
          ['bob2', 'Bob'],
          ['Amyy', 'Amy', 'amy_alt'],
        ]),
      );
      String describe(Catalogue c) =>
          c.requesters.map((r) => '${r.id} ${r.name} ${r.folded} ${r.requestCount}').join(';');
      expect(describe(b), describe(a));
      expect(a.requesters.map((r) => r.folded), ['amy', 'bob']);
    });

    test('is found by every one of its names, the user\'s own requests too', () {
      final c = catalogueOf(songs: _songs(['Amy', 'Amy', 'amy_alt']), aliases: _aliases);
      final amy = c.requesters.single;
      for (final name in ['Amy', 'amy_alt', 'Amyy', ' AMYY ']) {
        expect(c.requesterNamed(name), same(amy), reason: name);
        expect(c.isRequester(amy.id, fold(name.trim())), isTrue, reason: name);
      }
      expect(c.requesterNamed('Bob'), isNull);
      expect(c.isRequester(amy.id, 'bob'), isFalse);
      // the statistics of the user alone, Twitch name amy_alt
      final mine = CatalogueRankings(c, requesterId: c.requesterNamed('amy_alt')!.id);
      expect(mine.requesters.entries.single.name, 'Amy');
      expect(mine.requesters.counts.single, 3);
    });

    test('a query on any of its names finds its plays and highlights', () {
      final c = catalogueOf(
        highlights: [
          hRow(title: 'v1', requester: 'Amy'),
          hRow(title: 'v2', requester: 'Carol'),
        ],
        songs: _songs(['Amy', 'Amy', 'amy_alt', 'Carol']),
        aliases: _aliases,
      );
      expect(c.requesters.first.name, 'Amy');
      for (final query in ['amy', 'amy_alt', 'AMYY', 'y_al']) {
        expect(c.searchPlays(query: query).ids, [2, 1, 0], reason: query);
        expect(c.countPlays(query), 3, reason: query);
        expect(c.searchHighlights(query: query).ids, [0], reason: query);
      }
      // a token in one name and one in another do not make a match across them, nor across a title
      expect(c.searchPlays(query: 'amyy_alt').ids, isEmpty);
      expect(c.searchPlays(query: 'amy track').ids, [2, 1, 0]);
      expect(c.searchPlays(query: 'carol').ids, [3]);
      // the name shown does not hold the letters of amy_alt: nothing marked, nothing thrown
      final tokens = c.searchPlays(query: 'amy_alt').tokens;
      expect(matchRanges(c.requesters.first.name, tokens), isEmpty);
      expect(matchRanges(c.requesters.first.name, c.searchPlays(query: 'my').tokens), [(start: 1, end: 3)]);
    });

    test('whose names are not in the sheets changes nothing', () {
      final highlights = [hRow(title: 'v', requester: 'Carol')];
      final songs = _songs(['Carol', 'Dave', 'carol']);
      final none = catalogueOf(highlights: highlights, songs: songs, aliases: RequesterAliases.none);
      final some = catalogueOf(highlights: highlights, songs: songs, aliases: _aliases);
      List<Object> describe(Catalogue c) => [
        for (final r in c.requesters) (r.id, r.name, r.folded, r.requestCount),
        for (final p in c.plays) p.requesterId ?? -1,
        c.searchPlays(query: 'amy').length,
      ];
      expect(describe(some), describe(none));
    });

    test('keeps its key when a refresh shows it under another name: its page of songs stays', () {
      final before = catalogueOf(songs: _songs(['Amy', 'Amy', 'amy_alt']), aliases: _aliases);
      final after = catalogueOf(songs: _songs(['Amy', 'Amy', 'amy_alt', 'amy_alt', 'amy_alt']), aliases: _aliases);
      expect(before.requesters.single.name, 'Amy');
      expect(after.requesters.single.name, 'amy_alt');
      final entry = RequesterEntry(CatalogueRankings(before).requesters.entries.single.folded);
      expect(entry, RequesterEntry(CatalogueRankings(after).requesters.entries.single.folded));
      final rankings = CatalogueRankings(after);
      expect(rankings.nameOf(entry), 'amy_alt');
      expect(rankings.songsOf(entry).total, 5);
    });

    test('is the same whatever the steps of the load', () {
      final h = highlightsCsv([hRow(title: 'v', requester: 'amy_alt'), hRow(title: 'w', notes: 'requested by bob2')]);
      final s = songsCsv(_songs(['Amyy', 'Bob', 'amy_alt', '0:02:13', 'Amy', 'bob2']));
      String describe(Catalogue c) => [
        for (final r in c.requesters) '${r.id} ${r.name} ${r.folded} ${r.requestCount}',
        for (final p in c.plays) '${p.requesterId}',
        for (final h in c.highlights) '${h.requesterId}',
      ].join(';');
      final whole = parseCatalogue(h, s, aliases: _aliases);
      final load = CatalogueLoad(h, s, rowsPerStep: 1, unitsPerStep: 7, aliases: _aliases);
      while (load.step()) {}
      expect(describe(load.catalogue), describe(whole));
      final songs = parseSongs(parseHighlights(h, aliases: _aliases), s);
      expect(describe(parseHighlights(h, aliases: _aliases).withSongs(songs)), describe(whole));
    });
  });

  group('the other names of a group', () {
    final aliases = RequesterAliases([
      ['Amy', 'amy_alt', 'Amyy', 'amy_absent', 'AmyBis'],
      ['Bob', 'bob2'],
    ]);

    test('those the sheets hold, under their own most frequent spelling, the most written first', () {
      final c = catalogueOf(
        highlights: [
          hRow(title: 'v', requester: 'AMYY'),
          hRow(title: 'w', notes: 'requested by AmyBis'),
        ],
        // Amy 3 (amy once), Amyy 2 (Amyy once, AMYY twice, one of them in the highlights), amy_alt 2, Carol alone
        songs: _songs(['Amy', 'amy_alt', 'Amyy', 'AMYY', 'amy', 'Amy', 'amy_alt', 'Carol']),
        aliases: aliases,
      );
      final amy = c.requesterNamed('amy')!;
      expect(amy.name, 'Amy');
      // AMYY and amy_alt twice each: AMYY was met first; AmyBis, in the notes of a highlight alone, last; amy_absent
      // is in no sheet; amy, a spelling of the name shown, is not another name
      expect(amy.otherNames, ['AMYY', 'amy_alt', 'AmyBis']);
      expect(c.requesterNamed('Carol')!.otherNames, isEmpty);
    });

    test('none for a requester of one name, or a group met under one name alone', () {
      final c = catalogueOf(songs: _songs(['Bob', 'BOB', 'Carol']), aliases: aliases);
      expect(c.requesters.map((r) => r.name), ['Bob', 'Carol']);
      expect(c.requesters.map((r) => r.otherNames), everyElement(isEmpty));
    });

    test('equal counts in order of first appearance, whatever the order of the table', () {
      final songs = _songs(['amy_alt', 'AmyBis', 'Amy', 'Amy', 'Amyy']);
      for (final table in [
        aliases,
        RequesterAliases([
          ['AmyBis', 'Amyy', 'amy_alt', 'Amy'],
        ]),
      ]) {
        expect(catalogueOf(songs: songs, aliases: table).requesters.single.otherNames, ['amy_alt', 'AmyBis', 'Amyy']);
      }
    });
  });

  group('a running time in a Requester cell', () {
    test('names no requester, in both sheets', () {
      final c = catalogueOf(
        highlights: [
          hRow(title: 'v1', requester: '0:02:13'),
          hRow(title: 'v2', requester: 'Carol'),
          hRow(title: 'v3', notes: 'requested by 1:28:35'),
        ],
        songs: _songs(['0:02:13', '1:28:35', ' 12:05 ', '100:00:00', 'Carol', '0:02:13']),
        aliases: _aliases,
      );
      expect(c.requesters.map((r) => (r.name, r.requestCount)), [('Carol', 1)]);
      expect(c.plays.map((p) => p.requesterId), [null, null, null, null, 0, null]);
      expect(c.highlights.map((h) => h.requesterId), [null, 0, null]);
      // the rows are plays all the same
      expect(c.plays, hasLength(6));
      expect(c.requesterNamed('0:02:13'), isNull);
    });

    test('only when the cell is digits and colons alone', () {
      final names = ['12', ':12', '12:', '1:2a', 'a1:23', '1:23 x', '1.23'];
      final c = catalogueOf(songs: _songs(names), aliases: _aliases);
      expect(c.requesters.map((r) => r.name), names);
    });
  });
}
