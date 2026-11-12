import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/schedule.dart';

/// The feed of `jonathanong` as Twitch served it on 2026-11-12 (CRLF lines).
const twitchFeed = [
  'BEGIN:VCALENDAR',
  'PRODID:-//twitch.tv//StreamSchedule//1.0',
  'VERSION:2.0',
  'CALSCALE:GREGORIAN',
  'REFRESH-INTERVAL;VALUE=DURATION:PT6H',
  'X-PUBLISHED-TTL:PT6H',
  'NAME:JonathanOng',
  'X-WR-CALNAME:JonathanOng',
  'BEGIN:VEVENT',
  'UID:0a79b507-a78c-43a4-98e1-95bdbe3beb49',
  'DTSTAMP:20201130T065519Z',
  'DTSTART;TZID=/Australia/Sydney:20201204T133000',
  'DTEND;TZID=/Australia/Sydney:20201204T213000',
  'SUMMARY:Symphonic Loops',
  'DESCRIPTION:Music.',
  'CATEGORIES:Music',
  'RRULE:FREQ=WEEKLY;BYDAY=FR',
  'END:VEVENT',
  'BEGIN:VEVENT',
  'UID:845f3d20-b657-4069-b9be-709c9f670d1e',
  'DTSTAMP:20240125T092142Z',
  'DTSTART;TZID=/Australia/Sydney:20240127T230000',
  'DTEND;TZID=/Australia/Sydney:20240128T060000',
  'SUMMARY:Symphonic Loops',
  'DESCRIPTION:Music.',
  'CATEGORIES:Music',
  'RRULE:FREQ=WEEKLY;BYDAY=SA',
  'END:VEVENT',
  'BEGIN:VEVENT',
  'UID:b78e1ac5-c27e-43de-8bb9-8b15a687e737',
  'DTSTAMP:20221015T160756Z',
  'DTSTART;TZID=/Australia/Sydney:20221018T133000',
  'DTEND;TZID=/Australia/Sydney:20221018T213000',
  'SUMMARY:Live Symphonic Loops',
  'DESCRIPTION:Music.',
  'CATEGORIES:Music',
  'RRULE:FREQ=WEEKLY;BYDAY=TU',
  'END:VEVENT',
  'END:VCALENDAR',
];

/// A calendar holding [events], each a list of property lines.
String calendar(List<List<String>> events, {List<String> header = const []}) => [
  'BEGIN:VCALENDAR',
  'VERSION:2.0',
  ...header,
  for (final (i, e) in events.indexed) ...['BEGIN:VEVENT', 'UID:event-$i', ...e, 'END:VEVENT'],
  'END:VCALENDAR',
].join('\r\n');

DateTime utc(int y, int mo, int d, [int h = 0, int mi = 0, int s = 0]) => DateTime.utc(y, mo, d, h, mi, s);

/// `start – end` of [o] in UTC, for compact expectations.
String span(StreamOccurrence? o) => o == null ? 'none' : '${o.start.toIso8601String()} – ${o.end.toIso8601String()}';

void main() {
  setUpAll(loadTimeZones);

  group('the Twitch feed', () {
    late StreamSchedule schedule;
    setUp(() => schedule = parseSchedule(twitchFeed.join('\r\n')));

    test('three weekly events, nothing skipped', () {
      expect(schedule.eventCount, 3);
      expect(schedule.skippedCount, 0);
    });

    test('Thursday evening in Sydney: the next stream is Friday 13:30 AEDT', () {
      // 2026-11-12 12:00 UTC = Thu 23:00 AEDT (UTC+11)
      final status = schedule.statusAt(utc(2026, 11, 12, 12));
      expect(status.current, isNull);
      expect(
        status.next,
        StreamOccurrence(start: utc(2026, 11, 13, 2, 30), end: utc(2026, 11, 13, 10, 30), title: 'Symphonic Loops'),
      );
    });

    test('the Saturday event crosses midnight', () {
      // Sun 03:00 AEDT: inside Sat 23:00 – Sun 06:00
      final status = schedule.statusAt(utc(2026, 11, 14, 16));
      expect(span(status.current), '2026-11-14T12:00:00.000Z – 2026-11-14T19:00:00.000Z');
      expect(status.current!.title, 'Symphonic Loops');
      // next: Tue 13:30 AEDT
      expect(span(status.next), '2026-11-17T02:30:00.000Z – 2026-11-17T10:30:00.000Z');
      expect(status.next!.title, 'Live Symphonic Loops');
    });

    test('around a start and an end', () {
      final start = utc(2026, 11, 13, 2, 30);
      final friday = span(StreamOccurrence(start: start, end: utc(2026, 11, 13, 10, 30), title: ''));
      const saturday = '2026-11-14T12:00:00.000Z – 2026-11-14T19:00:00.000Z';
      // just before the start: next, not current
      var status = schedule.statusAt(start.subtract(const Duration(seconds: 1)));
      expect((span(status.current), span(status.next)), ('none', friday));
      // at the start and just after: in progress, the next is Saturday
      for (final now in [start, start.add(const Duration(seconds: 1)), utc(2026, 11, 13, 10, 29, 59)]) {
        status = schedule.statusAt(now);
        expect((span(status.current), span(status.next)), (friday, saturday), reason: '$now');
      }
      // at the end: over
      status = schedule.statusAt(utc(2026, 11, 13, 10, 30));
      expect((span(status.current), span(status.next)), ('none', saturday));
      // between two
      status = schedule.statusAt(utc(2026, 11, 14, 3));
      expect((span(status.current), span(status.next)), ('none', saturday));
    });

    test('end of daylight saving (first Sunday of April): AEDT, then AEST', () {
      // 2026-04-05 03:00 AEDT -> 02:00 AEST
      expect(schedule.occurrencesBetween(utc(2026, 4, 3), utc(2026, 4, 11)).map(span), [
        // Fri 13:30 AEDT (UTC+11)
        '2026-04-03T02:30:00.000Z – 2026-04-03T10:30:00.000Z',
        // Sat 23:00 AEDT; DTEND gives an exact length (7 h, RFC 5545): ends Sun 05:00 AEST
        '2026-04-04T12:00:00.000Z – 2026-04-04T19:00:00.000Z',
        // Tue 13:30 AEST (UTC+10)
        '2026-04-07T03:30:00.000Z – 2026-04-07T11:30:00.000Z',
        '2026-04-10T03:30:00.000Z – 2026-04-10T11:30:00.000Z',
      ]);
      // the next Saturday is 23:00 AEST
      expect(span(schedule.statusAt(utc(2026, 4, 10, 12)).next), '2026-04-11T13:00:00.000Z – 2026-04-11T20:00:00.000Z');
    });

    test('start of daylight saving (first Sunday of October): AEST, then AEDT', () {
      // 2026-10-04 02:00 AEST -> 03:00 AEDT
      expect(schedule.occurrencesBetween(utc(2026, 10, 2), utc(2026, 10, 10)).map(span), [
        '2026-10-02T03:30:00.000Z – 2026-10-02T11:30:00.000Z',
        // Sat 23:00 AEST, 7 h: ends Sun 07:00 AEDT
        '2026-10-03T13:00:00.000Z – 2026-10-03T20:00:00.000Z',
        '2026-10-06T02:30:00.000Z – 2026-10-06T10:30:00.000Z',
        '2026-10-09T02:30:00.000Z – 2026-10-09T10:30:00.000Z',
      ]);
      // during the night of the change
      final status = schedule.statusAt(utc(2026, 10, 3, 17));
      expect(span(status.current), '2026-10-03T13:00:00.000Z – 2026-10-03T20:00:00.000Z');
    });

    test('LF line ends work too', () {
      expect(parseSchedule(twitchFeed.join('\n')).eventCount, 3);
    });
  });

  group('recurrence', () {
    // Mondays 19:00 AEDT = 08:00 UTC, 2 hours
    const monday = ['DTSTART;TZID=Australia/Sydney:20261102T190000', 'DURATION:PT2H'];
    List<String> starts(StreamSchedule s) => [
      for (final o in s.occurrencesBetween(utc(2026, 1, 1), utc(2027, 1, 1))) o.start.toIso8601String(),
    ];

    test('UNTIL is inclusive', () {
      final s = parseSchedule(
        calendar([
          [...monday, 'RRULE:FREQ=WEEKLY;UNTIL=20261116T080000Z'],
        ]),
      );
      expect(starts(s), ['2026-11-02T08:00:00.000Z', '2026-11-09T08:00:00.000Z', '2026-11-16T08:00:00.000Z']);
      expect(s.statusAt(utc(2026, 11, 16, 9)).current, isNotNull);
      expect(s.statusAt(utc(2026, 11, 16, 11)), (current: null, next: null));
    });

    test('UNTIL as a date', () {
      final s = parseSchedule(
        calendar([
          [...monday, 'RRULE:FREQ=WEEKLY;UNTIL=20261109'],
        ]),
      );
      expect(starts(s), ['2026-11-02T08:00:00.000Z', '2026-11-09T08:00:00.000Z']);
    });

    test('COUNT counts excluded occurrences too', () {
      final s = parseSchedule(
        calendar([
          [...monday, 'RRULE:FREQ=WEEKLY;COUNT=3', 'EXDATE;TZID=Australia/Sydney:20261109T190000'],
        ]),
      );
      expect(starts(s), ['2026-11-02T08:00:00.000Z', '2026-11-16T08:00:00.000Z']);
    });

    test('INTERVAL=2 with two days', () {
      final s = parseSchedule(
        calendar([
          [...monday, 'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH;COUNT=5'],
        ]),
      );
      expect(starts(s), [
        '2026-11-02T08:00:00.000Z',
        '2026-11-05T08:00:00.000Z',
        '2026-11-16T08:00:00.000Z',
        '2026-11-19T08:00:00.000Z',
        '2026-11-30T08:00:00.000Z',
      ]);
    });

    test('WKST changes the weeks counted by INTERVAL', () {
      // starting on a Sunday: with weeks from Monday, Sun 8 and Mon 9 are in different weeks
      const sunday = ['DTSTART:20261108T100000Z', 'DURATION:PT1H'];
      List<String> days(String rule) => [
        for (final o in parseSchedule(
          calendar([
            [...sunday, rule],
          ]),
        ).occurrencesBetween(utc(2026, 11, 1), utc(2026, 12, 1)))
          '${o.start.day}',
      ];
      expect(days('RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;COUNT=4'), ['8', '16', '22', '30']);
      expect(days('RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;WKST=SU;COUNT=4'), ['8', '9', '22', '23']);
    });

    test('EXDATE: several values and several lines, UTC or zoned', () {
      final s = parseSchedule(
        calendar([
          [
            ...monday,
            'RRULE:FREQ=WEEKLY;COUNT=5',
            'EXDATE;TZID=/Australia/Sydney:20261109T190000,20261123T190000',
            'EXDATE:20261116T080000Z',
          ],
        ]),
      );
      expect(starts(s), ['2026-11-02T08:00:00.000Z', '2026-11-30T08:00:00.000Z']);
      // excluded: not in progress
      expect(s.statusAt(utc(2026, 11, 9, 9)).current, isNull);
      expect(s.statusAt(utc(2026, 11, 9, 9)).next!.start, utc(2026, 11, 30, 8));
    });

    test('a non-recurring event', () {
      final s = parseSchedule(
        calendar([
          ['DTSTART:20261120T100000Z', 'DTEND:20261120T120000Z', 'SUMMARY:Special'],
        ]),
      );
      expect(span(s.statusAt(utc(2026, 11, 12)).next), '2026-11-20T10:00:00.000Z – 2026-11-20T12:00:00.000Z');
      expect(span(s.statusAt(utc(2026, 11, 20, 11)).current), '2026-11-20T10:00:00.000Z – 2026-11-20T12:00:00.000Z');
      expect(s.statusAt(utc(2026, 11, 20, 12)), (current: null, next: null));
    });

    test('nominal DURATION days follow the wall clock across a change', () {
      final s = parseSchedule(
        calendar([
          ['DTSTART;TZID=Australia/Sydney:20260404T120000', 'DURATION:P1DT1H'],
        ]),
      );
      // Sat 12:00 AEDT -> Sun 13:00 AEST: 26 hours
      expect(span(s.statusAt(utc(2026, 4, 4, 2)).current), '2026-04-04T01:00:00.000Z – 2026-04-05T03:00:00.000Z');
    });

    test('a time skipped or repeated by a clock change', () {
      final s = parseSchedule(
        calendar([
          // 02:30 does not exist on 4 Oct 2026: read with the offset before the gap (+10)
          ['DTSTART;TZID=Australia/Sydney:20261004T023000', 'DURATION:PT1H'],
          // 02:30 happens twice on 5 Apr 2026: the first one (+11)
          ['DTSTART;TZID=Australia/Sydney:20260405T023000', 'DURATION:PT1H'],
        ]),
      );
      expect(s.occurrencesBetween(utc(2026, 1, 1), utc(2027, 1, 1)).map((o) => o.start), [
        utc(2026, 4, 4, 15, 30),
        utc(2026, 10, 3, 16, 30),
      ]);
    });

    test('a moved occurrence (RECURRENCE-ID) and a cancelled one', () {
      final text = [
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:weekly',
        ...monday,
        'RRULE:FREQ=WEEKLY;COUNT=4',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:weekly',
        'RECURRENCE-ID;TZID=Australia/Sydney:20261109T190000',
        'DTSTART;TZID=Australia/Sydney:20261110T190000',
        'DURATION:PT2H',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:weekly',
        'RECURRENCE-ID:20261116T080000Z',
        'DTSTART:20261116T080000Z',
        'DURATION:PT2H',
        'STATUS:CANCELLED',
        'END:VEVENT',
        'END:VCALENDAR',
      ].join('\r\n');
      expect(starts(parseSchedule(text)), [
        '2026-11-02T08:00:00.000Z',
        '2026-11-10T08:00:00.000Z',
        '2026-11-23T08:00:00.000Z',
      ]);
    });
  });

  group('format', () {
    test('an event with a repeated property is skipped alone: the others are kept', () {
      const good = ['SUMMARY:good', 'DTSTART:20261113T000000Z', 'DURATION:PT1H'];
      for (final (name, bad) in [
        ('SUMMARY', ['SUMMARY:a', 'SUMMARY:b', 'DTSTART:20261114T000000Z', 'DURATION:PT1H']),
        ('DTSTART', ['DTSTART:20261114T000000Z', 'DTSTART:20261115T000000Z', 'DURATION:PT1H']),
      ]) {
        final s = parseSchedule(calendar([good, bad]));
        expect((s.eventCount, s.skippedCount), (1, 1), reason: 'two $name');
        expect(span(s.statusAt(utc(2026, 11, 12)).next), '2026-11-13T00:00:00.000Z – 2026-11-13T01:00:00.000Z');
      }
      // two UID lines: the first one names the event, nothing is lost
      final s = parseSchedule(
        calendar([
          good,
          ['UID:again', 'DTSTART:20261114T000000Z', 'DURATION:PT1H'],
        ]),
      );
      expect((s.eventCount, s.skippedCount), (2, 0));
    });

    test('a byte-order mark before the first line', () {
      final s = parseSchedule(
        '\uFEFF${calendar([
          ['DTSTART:20261113T000000Z', 'DURATION:PT1H'],
        ])}',
      );
      expect(s.eventCount, 1);
    });

    test('folded lines', () {
      final s = parseSchedule(
        [
          'BEGIN:VCALENDAR',
          'BEGIN:VEVENT',
          'UID:folded',
          'DTSTART;TZID=/Austra',
          ' lia/Sydney:20261120T',
          '\t133000',
          'DTEND;TZID="/Australia/Sydney":20261120T213000',
          'SUMMARY:Symphonic',
          '  Loops\\, live',
          'END:VEVENT',
          'END:VCALENDAR',
        ].join('\r\n'),
      );
      final next = s.statusAt(utc(2026, 11, 12)).next!;
      expect(span(next), '2026-11-20T02:30:00.000Z – 2026-11-20T10:30:00.000Z');
      expect(next.title, 'Symphonic Loops, live');
    });

    test('floating times: the calendar zone (X-WR-TIMEZONE), else the device zone', () {
      const event = ['DTSTART:20261120T200000', 'DTEND:20261120T220000'];
      final sydney = parseSchedule(
        calendar([event], header: ['X-WR-TIMEZONE:Australia/Sydney']),
      ).statusAt(utc(2026, 11, 12)).next!;
      expect(sydney.start, utc(2026, 11, 20, 9));
      final device = parseSchedule(calendar([event])).statusAt(utc(2026, 11, 12)).next!;
      expect(device.start, DateTime(2026, 11, 20, 20).toUtc());
      expect(device.end, DateTime(2026, 11, 20, 22).toUtc());
    });

    test('no DTEND nor DURATION: a start without length', () {
      final s = parseSchedule(
        calendar([
          ['DTSTART:20261120T100000Z'],
        ]),
      );
      expect(span(s.statusAt(utc(2026, 11, 12)).next), '2026-11-20T10:00:00.000Z – 2026-11-20T10:00:00.000Z');
      expect(s.statusAt(utc(2026, 11, 20, 10)).current, isNull);
    });

    test('an unknown TZID and a malformed event are skipped, the others kept', () {
      final s = parseSchedule(
        calendar([
          ['DTSTART;TZID=Mars/Olympus_Mons:20261120T100000', 'DURATION:PT1H', 'RRULE:FREQ=WEEKLY'],
          ['DTSTART:2026-11-20 10:00', 'DURATION:PT1H'],
          ['DTSTART:20261121T100000Z', 'DTEND:20261121T110000Z', 'BROKEN LINE'],
          ['DTSTART:20261122T100000Z', 'DURATION:PT1H', 'SUMMARY:Kept'],
        ]),
      );
      expect(s.skippedCount, 3);
      expect(s.eventCount, 1);
      expect(s.statusAt(utc(2026, 11, 12)).next!.title, 'Kept');
    });

    test('unsupported events are skipped', () {
      final unsupported = [
        // all-day
        ['DTSTART;VALUE=DATE:20261120', 'DTEND;VALUE=DATE:20261121'],
        // other frequencies, rule parts
        ['DTSTART:20261120T100000Z', 'DURATION:PT1H', 'RRULE:FREQ=DAILY'],
        ['DTSTART:20261120T100000Z', 'DURATION:PT1H', 'RRULE:FREQ=WEEKLY;BYHOUR=10'],
        ['DTSTART:20261120T100000Z', 'DURATION:PT1H', 'RRULE:FREQ=WEEKLY;BYDAY=1FR'],
        ['DTSTART:20261120T100000Z', 'DURATION:PT1H', 'RRULE:FREQ=WEEKLY;COUNT=2;UNTIL=20261230T000000Z'],
        // DTSTART on a Friday, rule on Mondays
        ['DTSTART:20261120T100000Z', 'DURATION:PT1H', 'RRULE:FREQ=WEEKLY;BYDAY=MO'],
        ['DTSTART:20261120T100000Z', 'DURATION:PT1H', 'RDATE:20261127T100000Z'],
        // UTC and a TZID at once, an end before the start, both DTEND and DURATION, bad duration
        ['DTSTART;TZID=Australia/Sydney:20261120T100000Z', 'DURATION:PT1H'],
        ['DTSTART:20261120T100000Z', 'DTEND:20261120T090000Z'],
        ['DTSTART:20261120T100000Z', 'DTEND:20261120T110000Z', 'DURATION:PT1H'],
        ['DTSTART:20261120T100000Z', 'DURATION:-PT1H'],
        ['DTSTART:20261120T100000Z', 'DURATION:PT'],
        ['DTSTART:20261131T100000Z', 'DURATION:PT1H'],
        ['DURATION:PT1H'],
      ];
      final s = parseSchedule(calendar(unsupported));
      expect(s.eventCount, 0);
      expect(s.skippedCount, unsupported.length);
      expect(s.statusAt(utc(2026, 11, 12)), (current: null, next: null));
    });

    test('a cancelled event is left out', () {
      final s = parseSchedule(
        calendar([
          ['DTSTART:20261120T100000Z', 'DURATION:PT1H', 'STATUS:CANCELLED'],
        ]),
      );
      expect((s.eventCount, s.skippedCount), (0, 0));
    });

    test('beyond the time zone data: no time rather than a wrong one', () {
      final s = parseSchedule(
        calendar([
          ['DTSTART;TZID=Australia/Sydney:20200103T133000', 'DURATION:PT8H', 'RRULE:FREQ=WEEKLY'],
          ['DTSTART:20200103T133000Z', 'DURATION:PT8H', 'RRULE:FREQ=WEEKLY'],
        ]),
      );
      expect(s.statusAt(utc(2026, 11, 12)).next!.start, utc(2026, 11, 13, 2, 30));
      // years after the data (which ends around 2030): only the UTC event
      expect(s.statusAt(utc(2035, 1, 1)).next!.start, utc(2035, 1, 5, 13, 30));
    });

    test('not a calendar', () {
      expect(() => parseSchedule('<html>Oops</html>'), throwsA(isA<ScheduleFormatException>()));
    });
  });
}
