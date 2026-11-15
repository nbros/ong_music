import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/model.dart';
import 'package:ong_music/src/data/sheet_zone.dart';
import 'package:ong_music/src/data/sydney_zone.dart';
import 'package:ong_music/src/data/vods.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'fixtures.dart';

/// The Sydney date of the instant [utc].
String _sydney(DateTime utc) => SydneyZone.dateOf(utc.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute).toIso();

const _header = 'date\tpart\tid\tseconds\tposted\ttitle';

/// A video id of 11 characters from [n].
String _id(Object n) => 'vid${n.toString().padLeft(8, '_')}';

/// A file of [lines] after its header.
VodFile _file(List<String> lines) => VodFile.parse([_header, ...lines].join('\n'));

/// The catalogue of the plays [songs] (Songs sheet rows).
Catalogue _catalogue(List<List<String>> songs) => catalogueOf(songs: songs);

/// The links of [file] in [catalogue], one per play (null for none), as text.
List<String?> _links(Catalogue catalogue, VodFile file) {
  final links = VodLinks(catalogue, file);
  return [for (final p in catalogue.plays) links.linkOf(p)?.toString()];
}

void main() {
  group('the Sydney date', () {
    test('standard time UTC+10, daylight time UTC+11, the date changing at local midnight', () {
      // July: standard time, midnight at 14:00 UTC
      expect(_sydney(DateTime.utc(2025, 7, 1, 13, 59)), '2025-07-01');
      expect(_sydney(DateTime.utc(2025, 7, 1, 14)), '2025-07-02');
      // January: daylight time, midnight at 13:00 UTC
      expect(_sydney(DateTime.utc(2026, 1, 10, 12, 59)), '2026-01-10');
      expect(_sydney(DateTime.utc(2026, 1, 10, 13)), '2026-01-11');
      // New Year, in daylight time
      expect(_sydney(DateTime.utc(2025, 12, 31, 12, 59)), '2025-12-31');
      expect(_sydney(DateTime.utc(2025, 12, 31, 13)), '2026-01-01');
    });

    test('2026: daylight time until Sunday 5 April 03:00, from Sunday 4 October 02:00 (16:00 UTC the day before)', () {
      // the evening of Saturday 4 April, still daylight time: midnight at 13:00 UTC
      expect(_sydney(DateTime.utc(2026, 4, 4, 12, 59)), '2026-04-04');
      expect(_sydney(DateTime.utc(2026, 4, 4, 13)), '2026-04-05');
      // 03:00 daylight time becomes 02:00 standard time at 16:00 UTC; Sunday stays Sunday
      expect(_sydney(DateTime.utc(2026, 4, 4, 15, 59)), '2026-04-05');
      expect(_sydney(DateTime.utc(2026, 4, 4, 16)), '2026-04-05');
      // the evening of Sunday 5 April, standard time: midnight at 14:00 UTC
      expect(_sydney(DateTime.utc(2026, 4, 5, 13, 59)), '2026-04-05');
      expect(_sydney(DateTime.utc(2026, 4, 5, 14)), '2026-04-06');
      // Saturday 3 October, standard time: midnight at 14:00 UTC
      expect(_sydney(DateTime.utc(2026, 10, 3, 13, 59)), '2026-10-03');
      expect(_sydney(DateTime.utc(2026, 10, 3, 14)), '2026-10-04');
      // the evening of Sunday 4 October, daylight time: midnight at 13:00 UTC
      expect(_sydney(DateTime.utc(2026, 10, 4, 12, 59)), '2026-10-04');
      expect(_sydney(DateTime.utc(2026, 10, 4, 13)), '2026-10-05');
    });

    test(
      'the same date as the full time zone database, every hour of 2008–2031, and on the minutes of the changes',
      () {
        tzdata.initializeTimeZones();
        final sydney = tz.getLocation('Australia/Sydney');
        String database(DateTime utc) {
          final local = tz.TZDateTime.from(utc, sydney);
          return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-'
              '${local.day.toString().padLeft(2, '0')}';
        }

        var mismatches = 0;
        for (var t = DateTime.utc(2008); t.isBefore(DateTime.utc(2032)); t = t.add(const Duration(hours: 1))) {
          // on the hour, and a minute before it: the changes fall on the hour
          for (final at in [t, t.subtract(const Duration(minutes: 1))]) {
            if (_sydney(at) != database(at)) mismatches++;
          }
        }
        expect(mismatches, 0);
      },
    );

    test('a stream started on a Wednesday evening in New York is of Thursday in Sydney', () {
      // 21:34 EST on 12 November 2025 = 02:34 UTC on the 13th = 13:34 AEDT on the 13th
      final minute = SheetZone.epochMinute(CalendarDate(2025, 11, 12), 21 * 60 + 34);
      expect(SydneyZone.dateOf(minute).toIso(), '2025-11-13');
    });
  });

  group('the file', () {
    test('reads its six columns, the header, comments, blank lines, CRLF ends, a byte order mark', () {
      final file = VodFile.parse(
        '﻿$_header\r\n'
        '# a comment\r\n'
        '\r\n'
        '2026-11-10\t1\t${_id(1)}\t21600\t2026-11-12\tVOD for the 10th of November 2026\r\n'
        '  # an indented comment\n'
        '2026-11-03#2\t2\t${_id(2)}\t\t\tVOD Part 2\textra\tcolumns\n',
      );
      expect(file.ignored, isEmpty);
      expect(file.lines, hasLength(2));
      final first = file.lines.first;
      expect(first.key, StreamKey(CalendarDate(2026, 11, 10)));
      expect(first.part, 1);
      expect(first.id, _id(1));
      expect(first.seconds, 21600);
      expect(first.posted, '2026-11-12');
      expect(first.title, 'VOD for the 10th of November 2026');
      expect(first.lineNumber, 4);
      final second = file.lines.last;
      expect(second.key, StreamKey(CalendarDate(2026, 11, 3), 2));
      expect(second.seconds, isNull);
      expect(second.title, 'VOD Part 2', reason: 'the columns after the sixth are ignored');
    });

    test('a line that does not read is left out with its reason, never the file', () {
      final file = _file([
        '2026-11-10\t1',
        '2026-11-10\t1\tshort',
        '2026-11-10\t1\t${'x' * 10}!',
        '2026-11-10\t0\t${_id(1)}',
        '2026-11-10\t-1\t${_id(2)}',
        '2026-11-10\ttwo\t${_id(3)}',
        '2026-11-10\t\t${_id(4)}',
        '\t1\t${_id(5)}',
        '2026-02-30\t1\t${_id(6)}',
        '2026-11-1\t1\t${_id(7)}',
        '2026/11/10\t1\t${_id(8)}',
        '2026-11-10#\t1\t${_id(9)}',
        '2026-11-10#0\t1\t${_id(10)}',
        '2026-11-10 #2\t1\t${_id(11)}',
        '10/11/2026\t1\t${_id(12)}',
        '2026-11-10\t1\t${_id(13)}\tabc',
        '2026-11-10\t2\t${_id(14)}\t0',
        ' 2026-11-11 \t 1 \t ${_id(15)} \t 300 ',
      ]);
      expect([for (final n in file.ignored) n.lineNumber], [for (var i = 2; i <= 16; i++) i]);
      expect(file.ignored.first.reason, 'fewer than three columns');
      expect(file.ignored[1].reason, contains('id'));
      expect(file.ignored[3].reason, contains('part'));
      expect(file.ignored[7].reason, 'no date');
      expect(file.ignored[8].reason, contains('date'));
      expect(file.lines.map((l) => l.id), [_id(13), _id(14), _id(15)]);
      expect(file.lines[0].seconds, isNull, reason: 'a duration that does not read is unknown');
      expect(file.lines[1].seconds, isNull, reason: 'no video lasts 0 s');
      expect(file.notes.map((n) => n.lineNumber), [17, 18]);
      expect(file.lines[2].key, StreamKey(CalendarDate(2026, 11, 11)), reason: 'cells are trimmed');
      expect(file.lines[2].seconds, 300);
    });

    test('anything but a table is a file without VOD', () {
      for (final text in ['', 'nothing', '<!DOCTYPE html><html></html>', _header, '\n\n\n']) {
        final file = VodFile.parse(text);
        expect(file.isEmpty, isTrue, reason: text);
      }
    });

    test('of two lines of a stream and part, the later wins; a part after a hole is left out', () {
      final file = _file([
        '2026-11-10\t1\t${_id(1)}\t100',
        '2026-11-10\t2\t${_id(2)}\t200',
        '2026-11-12\t1\t${_id(3)}',
        '2026-11-10\t1\t${_id(4)}\t110',
        '2026-11-12\t3\t${_id(5)}',
        '2026-11-14\t2\t${_id(6)}',
        '2026-11-14#1\t2\t${_id(7)}',
      ]);
      final tenth = file.vodOf(StreamKey(CalendarDate(2026, 11, 10)))!;
      expect(tenth.map((l) => l.id), [_id(4), _id(2)], reason: 're-uploaded part 1');
      expect(file.replaced.first.$1.id, _id(1));
      expect(file.vodOf(StreamKey(CalendarDate(2026, 11, 12)))!.map((l) => l.id), [_id(3)]);
      expect(file.vodOf(StreamKey(CalendarDate(2026, 11, 14))), isNull, reason: 'no part 1');
      expect(file.afterHole.map((l) => l.id), [_id(5), _id(7)]);
      expect(file.replaced.last.$1.id, _id(6), reason: '#1 is the first stream of its date');
    });
  });

  group('the keys of the streams', () {
    test('the Sydney date of the instant of the "Stream Start" row, and the rank among the streams of that date', () {
      final c = _catalogue([
        // 21:00 EST on 9 November = 13:00 AEDT on the 10th
        start('2025-11-09 21:00:00'),
        sRow(date: '2025-11-09 21:05:00', title: 'A'),
        // 02:00 EST on the 10th = 18:00 AEDT on the 10th: the second stream of that Sydney date
        start('2025-11-10 02:00:00'),
        sRow(date: '2025-11-10 02:05:00', title: 'B'),
        // no time on the row: its date as written
        start('2025-11-10'),
        sRow(date: '2025-11-10 20:00:00', title: 'C'),
        // a mistyped date (a year off): the date of its first play, as written
        start('2024-11-20 21:00:00'),
        sRow(date: '2025-11-20 21:05:00', title: 'D'),
      ]);
      expect(streamKeys(c).map((k) => '$k'), ['2025-11-10', '2025-11-10#2', '2025-11-10#3', '2025-11-20']);
      expect(c.streams.last.startMinute, isNull);
    });

    test('the plays before any "Stream Start" row are a stream of the date of the first one', () {
      final c = _catalogue([
        sRow(date: '2025-11-09 21:05:00', title: 'A'),
        sRow(date: '2025-11-09 21:10:00', title: 'B'),
      ]);
      expect(streamKeys(c).map((k) => '$k'), ['2025-11-09']);
    });
  });

  group('the link of a play', () {
    // a stream of 10 November in Sydney
    List<String> play(String uptime, [String title = 'Song']) =>
        sRow(date: '2025-11-09 21:30:00', uptime: uptime, title: title);
    List<List<String>> stream(List<List<String>> plays) => [start('2025-11-09 21:00:00'), ...plays];

    test('its uptime in the only part, to the second; none at the end of a part of known length', () {
      final c = _catalogue(stream([play('0:00:05'), play('1:02:03'), play('5:59:59'), play('6:00:00')]));
      expect(c.uptimeOf(c.plays[1]), 3723);
      expect(_links(c, _file(['2025-11-10\t1\t${_id(1)}\t21600'])), [
        'https://youtu.be/${_id(1)}?t=5',
        'https://youtu.be/${_id(1)}?t=3723',
        'https://youtu.be/${_id(1)}?t=21599',
        null,
      ]);
      expect(
        _links(c, _file(['2025-11-10\t1\t${_id(1)}'])).last,
        'https://youtu.be/${_id(1)}?t=21600',
        reason: 'one part of unknown length: the uptime as it is',
      );
    });

    test('in part 2 at the uptime minus the length of part 1, without t at its start', () {
      final c = _catalogue(stream([play('1:00:00'), play('11:59:59'), play('12:00:00'), play('13:00:01')]));
      final file = _file(['2025-11-10\t2\t${_id(2)}\t7200', '2025-11-10\t1\t${_id(1)}\t43200']);
      expect(_links(c, file), [
        'https://youtu.be/${_id(1)}?t=3600',
        'https://youtu.be/${_id(1)}?t=43199',
        'https://youtu.be/${_id(2)}',
        'https://youtu.be/${_id(2)}?t=3601',
      ]);
      expect(VodLinks(c, file).positionOf(c.plays.last), (part: 2, video: file.lines.first, seconds: 3601));
      // past the end of the last part
      final short = _file(['2025-11-10\t1\t${_id(1)}\t43200', '2025-11-10\t2\t${_id(2)}\t3600']);
      expect(_links(c, short).last, isNull);
      // the last part of unknown length
      final open = _file(['2025-11-10\t1\t${_id(1)}\t43200', '2025-11-10\t2\t${_id(2)}']);
      expect(_links(c, open).last, 'https://youtu.be/${_id(2)}?t=3601');
    });

    test('no link at all while the length of part 1 of two is unknown', () {
      final c = _catalogue(stream([play('0:10:00'), play('13:00:00')]));
      expect(_links(c, _file(['2025-11-10\t1\t${_id(1)}', '2025-11-10\t2\t${_id(2)}\t7200'])), [null, null]);
    });

    test('three parts: a length needed for the subtraction unknown stops the plays after it', () {
      final c = _catalogue(stream([play('0:30:00'), play('1:30:00'), play('2:30:00')]));
      final file = _file([
        '2025-11-10\t1\t${_id(1)}\t3600',
        '2025-11-10\t2\t${_id(2)}',
        '2025-11-10\t3\t${_id(3)}\t3600',
      ]);
      expect(_links(c, file), ['https://youtu.be/${_id(1)}?t=1800', null, null]);
    });

    test('none for a play without uptime, or at 0:00:00 (the placeholder of the moderators)', () {
      final c = _catalogue(stream([play(''), play('0:00:00'), play('soon'), play('0:00:01')]));
      expect(c.uptimeOf(c.plays[0]), isNull);
      expect(c.uptimeOf(c.plays[1]), 0);
      expect(c.uptimeOf(c.plays[2]), isNull);
      expect(_links(c, _file(['2025-11-10\t1\t${_id(1)}\t21600'])), [
        null,
        null,
        null,
        'https://youtu.be/${_id(1)}?t=1',
      ]);
    });

    test('none for a stream without VOD; the two streams of one date by their rank', () {
      final c = _catalogue([
        ...stream([play('0:10:00', 'A')]),
        start('2025-11-10 02:00:00'),
        sRow(date: '2025-11-10 02:30:00', uptime: '0:20:00', title: 'B'),
        start('2025-11-12 02:00:00'),
        sRow(date: '2025-11-12 02:30:00', uptime: '0:20:00', title: 'C'),
      ]);
      final file = _file(['2025-11-10#2\t1\t${_id(2)}\t3600', '2025-11-10\t1\t${_id(1)}\t3600']);
      expect(_links(c, file), ['https://youtu.be/${_id(1)}?t=600', 'https://youtu.be/${_id(2)}?t=1200', null]);
      final links = VodLinks(c, file);
      expect(links.streamLinks(c.streams[0]).map((u) => '$u'), ['https://youtu.be/${_id(1)}']);
      expect(links.streamLinks(c.streams[2]), isEmpty);
    });

    test('a stream links to each of its parts from its start', () {
      final c = _catalogue(stream([play('0:10:00')]));
      final links = VodLinks(c, _file(['2025-11-10\t1\t${_id(1)}\t3600', '2025-11-10\t2\t${_id(2)}']));
      expect(links.streamLinks(c.streams.single).map((u) => '$u'), [
        'https://youtu.be/${_id(1)}',
        'https://youtu.be/${_id(2)}',
      ]);
      expect(links.vodOf(c.streams.single)!.length, 2);
    });

    test('the uptime of a play is kept to the second; a marker keeps none, its uptime still the stream\'s', () {
      final c = _catalogue(
        stream([
          play('2:03:04'),
          sRow(date: '2025-11-09 23:30:00', uptime: '3:00:59', title: 'End of Concert Grand', genre: '-'),
        ]),
      );
      expect(c.plays.single.title, 'Song');
      expect(c.uptimeOf(c.plays.single), 7384);
      expect(c.streams.single.durationMinutes, 180);
    });

    test('an uptime too long for the table is none, the length of the stream as before', () {
      final c = _catalogue(stream([play('999999:00:00')]));
      expect(c.uptimeOf(c.plays.single), isNull);
      expect(c.streams.single.durationMinutes, 999999 * 60);
    });
  });
}
