import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/model.dart';
import 'package:ong_music/src/data/parser.dart';

import 'fixtures.dart';

void main() {
  group('column resolution', () {
    test('reads notes from the "Additional Notes" column (index 9), not "Vocals?" (7)', () {
      final c = catalogueOf(
        highlights: [hRow(title: 'Song', vocals: 'Yes', adult: 'No', notes: 'Great one')],
      );
      final h = c.highlights.single;
      expect(h.notes, 'Great one');
      expect(h.vocals, Vocals.yes);
    });

    test('resolves columns by header name, trimmed and case-insensitive, in any order', () {
      final highlights = csvOf([
        [
          ' additional NOTES ',
          'Video Title',
          'Upload Date',
          'LINK TO VIDEO',
          'Order',
          'Genre',
          'Stream Source',
          'Short Video / Requestor',
        ],
        [
          'the notes',
          'Zelda - Song of Storms',
          '2024-01-05',
          'https://youtu.be/abcdefghijk',
          '7',
          'GAME OST',
          '2024-01-01',
          'Alice',
        ],
      ]);
      final songs = csvOf([
        ['Title', 'Requester', 'Order', 'Genre', 'Uptime', 'Request Type/Instrument', 'Notes', 'Date'],
        ['Stream Start:', '-', '0', '-', '', '-', '-', '2024-01-01'],
        ['Zelda - Song of Storms', 'Bob', '1', 'ANIME', '1:30:00', 'Loop', 'Raffle', '2024-01-01 21:00:00'],
      ]);
      final c = parseCatalogue(highlights, songs);
      final h = c.highlights.single;
      expect(
        (h.seq, h.title, h.genre, h.youtubeId, h.notes),
        (7, 'Zelda - Song of Storms', Genre.gameOst, 'abcdefghijk', 'the notes'),
      );
      expect(c.requester(h.requesterId)!.name, 'Alice');
      final p = c.plays.single;
      expect(
        (p.title, p.genre, p.type, p.flag, p.time),
        ('Zelda - Song of Storms', Genre.anime, PlayType.loop, PlayFlag.raffle, '21:00'),
      );
      expect(c.requester(p.requesterId)!.name, 'Bob');
      expect(c.streams.single.durationMinutes, 90);
      expect(h.playId, p.id);
    });

    test('falls back to the historical index when a header is missing', () {
      final header = [...highlightHeader]..[9] = 'Comments';
      final highlights = csvOf([header, hRow(title: 'Song', notes: 'fallback notes')]);
      final c = parseCatalogue(highlights, songsCsv([start('2024-01-01'), sRow(date: '2024-01-01', title: 'x')]));
      expect(c.highlights.single.notes, 'fallback notes');
    });

    test('ColumnResolver: first duplicate wins, unknown is null', () {
      final r = ColumnResolver(['a', 'Title', ' title ', '']);
      expect(r.find(SongColumns.title), 1);
      expect(r.find(SongColumns.uptime), isNull);
      expect(r.resolve(SongColumns.uptime), 1);
    });
  });

  group('odd cells', () {
    test('a title typed with decomposed accents is composed, so it is found and grouped', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          sRow(date: '2024-01-01 20:00:00', title: 'Poke\u0301mon Colosseum - Miror B', requester: 'Ame\u0301lie'),
          sRow(date: '2024-01-01 21:00:00', title: 'Pokémon Colosseum - Miror B'),
        ],
      );
      expect(c.plays.first.title, 'Pokémon Colosseum - Miror B');
      expect(c.requester(c.plays.first.requesterId)!.name, 'Amélie');
      expect(c.searchPlays(query: 'pokemon colosseum').length, 2);
      expect(c.searchPlays(query: 'amelie').length, 1);
      expect(c.song(c.plays.first.songKey)!.playIds, [0, 1], reason: 'one song for both spellings');
    });

    test('an absurdly long number does not reject the sheet', () {
      final c = catalogueOf(
        highlights: [
          hRow(title: 'First', order: '7'),
          hRow(title: 'Second', order: '123456789012345678901234567890'),
        ],
        songs: [
          start('2024-01-01'),
          sRow(date: '2024-01-01 20:00:00', title: 'Some song', uptime: '123456789012345678901234567890:10:00'),
        ],
      );
      expect(c.highlights.map((h) => h.seq), [7, 7]);
      expect(c.streams.single.durationMinutes, 0);
    });
  });

  group('invalid payloads', () {
    final goodSongs = songsCsv([start('2024-01-01'), sRow(date: '2024-01-01', title: 'x')]);
    final goodHighlights = highlightsCsv([hRow(title: 'x')]);

    test('HTML instead of CSV', () {
      expect(
        () => parseCatalogue('<!DOCTYPE html><html>Sign in</html>', goodSongs),
        throwsA(isA<CatalogueFormatException>()),
      );
      expect(() => parseCatalogue(goodHighlights, '\n <html></html>'), throwsA(isA<CatalogueFormatException>()));
    });

    test('empty payload', () {
      expect(() => parseCatalogue('', goodSongs), throwsA(isA<CatalogueFormatException>()));
    });

    test('expected header missing', () {
      expect(
        () => parseCatalogue(
          csvOf([
            ['a', 'b'],
            ['1', '2'],
          ]),
          goodSongs,
        ),
        throwsA(isA<CatalogueFormatException>()),
      );
      expect(
        () => parseCatalogue(
          goodHighlights,
          csvOf([
            ['a', 'b'],
            ['1', '2'],
          ]),
        ),
        throwsA(isA<CatalogueFormatException>()),
      );
    });

    test('no row left', () {
      expect(() => parseCatalogue(highlightsCsv([]), goodSongs), throwsA(isA<CatalogueFormatException>()));
      expect(
        () => parseCatalogue(goodHighlights, songsCsv([start('2024-01-01')])),
        throwsA(isA<CatalogueFormatException>()),
      );
    });

    test('a UTF-8 BOM is ignored', () {
      expect(parseCatalogue('\uFEFF$goodHighlights', '\uFEFF$goodSongs').highlightCount, 1);
    });
  });

  group('highlights', () {
    test('carries the sequence number over non-numeric cells', () {
      final c = catalogueOf(
        highlights: [
          hRow(order: '5', title: 'a'),
          hRow(order: '', title: 'b'),
          hRow(order: '5b', title: 'c'),
          hRow(order: ' 6 ', title: 'd'),
        ],
      );
      expect(c.highlights.map((h) => h.seq), [5, 5, 5, 6]);
    });

    test('keeps only titled, uploaded, non-premiere rows; collapses whitespace', () {
      final c = catalogueOf(
        highlights: [
          hRow(title: '  '),
          hRow(upload: '', title: 'no upload'),
          hRow(upload: 'Premiere', title: 'pending'),
          hRow(title: '  Two \n  lines  '),
        ],
      );
      expect(c.highlights.map((h) => h.title), ['Two lines']);
      expect(c.highlights.single.id, 0);
    });

    test('extracts the YouTube id', () {
      final c = catalogueOf(
        highlights: [
          hRow(title: 'a', link: 'https://www.youtube.com/watch?v=8uAmnwSal6I&t=3'),
          hRow(title: 'b', link: 'https://youtu.be/hyLyW59nKP_'),
          hRow(title: 'c', link: 'https://www.twitch.tv/videos/1'),
          hRow(title: 'd'),
        ],
      );
      expect(c.highlights.map((h) => h.youtubeId), ['8uAmnwSal6I', 'hyLyW59nKP_', null, null]);
      expect(c.highlights[0].url, 'https://www.youtube.com/watch?v=8uAmnwSal6I');
      expect(c.highlights[2].url, 'https://www.twitch.tv/videos/1');
    });

    test('requester from the cell, else from "requested by" in the notes', () {
      final c = catalogueOf(
        highlights: [
          hRow(title: 'a', requester: 'Alice'),
          hRow(title: 'b', requester: '-', notes: 'Requested by "Bob_42", thanks!'),
          hRow(title: 'c', requester: 'https://clips.twitch.tv/x', notes: 'requested by carol.'),
          hRow(title: 'd', requester: '?'),
          hRow(title: 'e', requester: 'Alice', notes: 'requested by Dave'),
        ],
      );
      expect(c.highlights.map((h) => c.requester(h.requesterId)?.name), ['Alice', 'Bob_42', 'carol', null, 'Alice']);
    });

    test('dates, vocals, genre', () {
      final c = catalogueOf(
        highlights: [
          hRow(title: 'a', upload: '2024-03-05', stream: '2024/3/1', vocals: 'yes', genre: 'films/television'),
          hRow(title: 'b', upload: '3/5/2024', stream: 'unknown', vocals: 'No Singing', genre: 'Something else'),
          hRow(title: 'c', vocals: 'Maybe', genre: ' MUSICIAL '),
        ],
      );
      final [a, b, cc] = c.highlights;
      expect(
        (a.uploadDate, a.streamDate, a.date, a.vocals, a.genre),
        (CalendarDate(2024, 3, 5), CalendarDate(2024, 3, 1), CalendarDate(2024, 3, 1), Vocals.yes, Genre.filmTv),
      );
      expect(
        (b.uploadDate, b.streamDate, b.date, b.vocals, b.genre),
        (CalendarDate(2024, 3, 5), null, CalendarDate(2024, 3, 5), Vocals.no, Genre.other),
      );
      expect((cc.vocals, cc.genre), (Vocals.unknown, Genre.musicals));
    });
  });

  group('plays and streams', () {
    test('order 0 starts a stream; rows without date or with an empty / - / ~~ title are skipped', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          sRow(date: '2024-01-01\u00a023:27:55', title: 'One'),
          sRow(date: '', title: 'no date'),
          sRow(date: '2024-01-01', title: '-'),
          sRow(date: '2024-01-01', title: '~~'),
          sRow(date: '2024-01-01', title: '  '),
          sRow(date: '2024-01-02 1:05:00', title: 'Two'),
          start('2024-01-05'),
          sRow(date: '2024/01/05 21:07', title: 'Three'),
        ],
      );
      expect(c.plays.map((p) => p.title), ['One', 'Two', 'Three']);
      expect(c.plays.map((p) => p.time), ['23:27', '01:05', '21:07']);
      expect(c.plays.map((p) => p.streamId), [0, 0, 1]);
      expect(c.plays[1].rowDate, CalendarDate(2024, 1, 2));
      expect(c.streamOf(c.plays[1]).date, CalendarDate(2024, 1, 1));
      expect(c.streams.map((s) => (s.firstPlayId, s.playCount)), [(0, 2), (2, 1)]);
      expect(c.playsOf(c.streams[0]).map((p) => p.title), ['One', 'Two']);
    });

    test('streams without plays are dropped; plays before any stream start get one', () {
      final c = catalogueOf(
        songs: [
          sRow(date: '2024-01-01', title: 'Orphan'),
          start('2024-01-03'),
          start('2024-01-04'),
          sRow(date: '2024-01-04', title: 'Kept'),
        ],
      );
      expect(c.streams.map((s) => s.date.toIso()), ['2024-01-01', '2024-01-04']);
      expect(c.plays.map((p) => p.streamId), [0, 1]);
    });

    test('a stream start date more than one day off its first play is corrected', () {
      final c = catalogueOf(
        songs: [
          start('2019-02-30'), // invalid: not a date, the row is skipped
          start('2021-06-10'), // typo for 2020
          sRow(date: '2020-06-10 20:00:00', title: 'a'),
          start('2020-06-12'), // the first song is after midnight: kept
          sRow(date: '2020-06-13 00:30:00', title: 'b'),
        ],
      );
      expect(c.streams.map((s) => s.date.toIso()), ['2020-06-10', '2020-06-12']);
    });

    test('duration is the largest uptime in minutes', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          sRow(date: '2024-01-01', uptime: '0:10:00', title: 'a'),
          sRow(date: '2024-01-01', uptime: '8:03:05', title: 'b'),
          sRow(date: '2024-01-01', uptime: 'oops', title: 'c'),
          sRow(date: '2024-01-01', uptime: '2:24:36', title: 'd'),
        ],
      );
      expect(c.streams.single.durationMinutes, 483);
    });

    test('types, genres with typos, flags', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          for (final (type, genre, notes) in [
            ('Piano', 'POPULAR_MUSIC', 'Tier 3'),
            ('Keyboard', 'ONGORIGNAL', 'Raffle'),
            ('Looper', '[COMPOSITION]', 'tier 3'),
            ('Cat Piano', 'jazz/standards', ''),
            ('Composition', 'HYMN', ''),
            ('Violin', 'POP', ''),
          ])
            sRow(date: '2024-01-01', title: type, type: type, genre: genre, notes: notes),
        ],
      );
      expect(c.plays.map((p) => p.type), [
        PlayType.piano,
        PlayType.piano,
        PlayType.loop,
        PlayType.catPiano,
        PlayType.improv,
        PlayType.unknown,
      ]);
      expect(c.plays.map((p) => p.genre), [
        Genre.popular,
        Genre.ongriginal,
        Genre.ongriginal,
        Genre.jazz,
        Genre.hymns,
        Genre.other,
      ]);
      expect(c.plays.map((p) => p.flag), [
        PlayFlag.tier3,
        PlayFlag.raffle,
        PlayFlag.none,
        PlayFlag.none,
        PlayFlag.none,
        PlayFlag.none,
      ]);
    });

    test('distinct titles are shared', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          sRow(date: '2024-01-01', title: 'A  -  B'),
          sRow(date: '2024-01-01', title: 'A - B'),
          sRow(date: '2024-01-01', title: 'a - b'),
        ],
      );
      expect(c.titles, ['A - B', 'a - b']);
      expect(c.plays.map((p) => p.titleId), [0, 0, 1]);
    });
  });

  group('requesters', () {
    test('no requester for empty, -, ? and URLs', () {
      final c = catalogueOf(
        songs: [
          start('2024-01-01'),
          for (final r in ['', '-', '?', 'http://x', 'https://y']) sRow(date: '2024-01-01', title: 't', requester: r),
        ],
      );
      expect(c.plays.map((p) => p.requesterId), everyElement(isNull));
      expect(c.requesters, isEmpty);
    });

    test('merged case-insensitively under the most frequent spelling, with a play count', () {
      final c = catalogueOf(
        highlights: [hRow(title: 'v', requester: 'alinsa')],
        songs: [
          start('2024-01-01'),
          sRow(date: '2024-01-01', title: 'a', requester: 'Alinsa'),
          sRow(date: '2024-01-01', title: 'b', requester: 'ALINSA'),
          sRow(date: '2024-01-01', title: 'c', requester: 'Alinsa'),
          sRow(date: '2024-01-01', title: 'd', requester: 'Bob'),
        ],
      );
      expect(c.requesters.map((r) => (r.name, r.requestCount)), [('Alinsa', 3), ('Bob', 1)]);
      expect(c.requester(c.highlights.single.requesterId)!.name, 'Alinsa');
      expect(c.requesterNamed(' aLiNsA ')!.requestCount, 3);
      expect(c.requesterNamed('nobody'), isNull);
    });
  });

  group('links and songs', () {
    final c = catalogueOf(
      highlights: [
        hRow(
          title: 'Zelda - Song of Storms',
          stream: '2024-01-02',
          link: 'https://youtu.be/AAAAAAAAAAA',
        ), // night of the 1st
        hRow(title: 'zelda: song of storms!', stream: '2024-01-10'), // 3 days off: no link
        hRow(title: 'Zelda - Song of Storms', stream: '2024-01-01'), // links to the first match again
        hRow(title: 'Never Logged', stream: '2024-01-01', genre: 'ANIME'),
        hRow(title: '???', stream: '2024-01-01'),
      ],
      songs: [
        start('2024-01-01'),
        sRow(date: '2024-01-01 23:00:00', title: 'Zelda - Song of Storms', genre: 'GAME OST'),
        sRow(date: '2024-01-02 00:10:00', title: 'Zelda - Song of Storms', genre: 'Unknown'),
        sRow(date: '2024-01-02 00:20:00', title: '???'),
        start('2024-01-07'),
        sRow(date: '2024-01-07 20:00:00', title: 'ZELDA - SONG OF STORMS', genre: 'Unknown'),
      ],
    );

    test('a highlight links to the first play of the same song within one day', () {
      expect(c.highlights.map((h) => h.playId), [0, null, 0, null, null]);
      expect(c.playOf(c.highlights[0])!.id, 0);
    });

    test('a play keeps its first linked highlight that has a video', () {
      expect(c.plays.map((p) => p.highlightId), [0, null, null, null]);
      expect(c.highlightOf(c.plays[0])!.id, 0);
    });

    test('streams list the highlights of their plays', () {
      expect(c.streams.map((s) => s.highlightIds), [
        [0, 2],
        <int>[],
      ]);
    });

    test('plays and highlights are grouped by song key', () {
      final song = c.songOfPlay(c.plays[0])!;
      expect(song.key, 'zelda song of storms');
      expect(song.playIds, [0, 1, 3]);
      expect(song.highlightIds, [0, 1, 2]);
      expect(song.title, 'ZELDA - SONG OF STORMS'); // latest play
      expect(song.genre, Genre.gameOst); // latest genre that is not Other
      expect((song.firstPlayed, song.lastPlayed), (CalendarDate(2024, 1, 1), CalendarDate(2024, 1, 7)));
      final video = c.songOfHighlight(c.highlights[3])!;
      expect(
        (video.title, video.genre, video.playIds.length, video.firstPlayed),
        ('Never Logged', Genre.anime, 0, null),
      );
      expect(c.songOfPlay(c.plays[2]), isNull, reason: 'a title without letters is not a song');
      expect(c.song(''), isNull);
      expect(c.songCount, 2);
    });
  });

  test('CalendarDate', () {
    final d = CalendarDate(2024, 2, 29);
    expect((d.year, d.month, d.day, d.weekday, d.toIso()), (2024, 2, 29, DateTime.thursday, '2024-02-29'));
    expect(d.daysUntil(CalendarDate(2024, 3, 1)), 1);
    expect(CalendarDate.tryParse('2023-02-29'), isNull);
    expect(CalendarDate.tryParse('Premiere'), isNull);
    expect(CalendarDate.parseCell('7/4/2021 9:05:00'), (date: CalendarDate(2021, 7, 4), time: '09:05'));
    expect(CalendarDate.fromEpochDay(0).toIso(), '1970-01-01');
    expect(() => CalendarDate(2024, 13, 1), throwsArgumentError);
  });
}
