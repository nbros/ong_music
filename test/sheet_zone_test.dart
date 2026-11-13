import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/model.dart';
import 'package:ong_music/src/data/sheet_zone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The instant of the Eastern wall time `year-month-day hour:minute`.
DateTime _eastern(int year, int month, int day, int hour, int minute) =>
    SheetZone.instant(CalendarDate(year, month, day), hour * 60 + minute);

/// The fields of [wall], `YYYY-MM-DD HH:MM`.
String _fields(DateTime wall) =>
    '${wall.year.toString().padLeft(4, '0')}-${wall.month.toString().padLeft(2, '0')}-'
    '${wall.day.toString().padLeft(2, '0')} ${wall.hour.toString().padLeft(2, '0')}:'
    '${wall.minute.toString().padLeft(2, '0')}';

void main() {
  group('the Eastern time of the sheet', () {
    test('winter is UTC−5, summer UTC−4', () {
      expect(_eastern(2026, 1, 15, 12, 0), DateTime.utc(2026, 1, 15, 17));
      expect(_eastern(2026, 7, 4, 21, 0), DateTime.utc(2026, 7, 5, 1));
      // the example of the Ong Log: a stream of 12 November, a song after midnight
      expect(_eastern(2026, 11, 12, 21, 34), DateTime.utc(2026, 11, 13, 2, 34));
      expect(_eastern(2026, 11, 13, 1, 39), DateTime.utc(2026, 11, 13, 6, 39));
    });

    test('2026: daylight time from Sunday 8 March, 07:00 UTC, to Sunday 1 November, 06:00 UTC', () {
      // March 1 and November 1 2026 are Sundays themselves
      expect(_eastern(2026, 3, 8, 1, 59), DateTime.utc(2026, 3, 8, 6, 59));
      expect(_eastern(2026, 3, 8, 3, 0), DateTime.utc(2026, 3, 8, 7));
      expect(_eastern(2026, 3, 1, 12, 0), DateTime.utc(2026, 3, 1, 17), reason: 'the first Sunday is still winter');
      expect(_eastern(2026, 11, 1, 0, 59), DateTime.utc(2026, 11, 1, 4, 59));
      expect(_eastern(2026, 11, 1, 2, 0), DateTime.utc(2026, 11, 1, 7));
      expect(_eastern(2026, 10, 31, 23, 0), DateTime.utc(2026, 11, 1, 3));

      expect(_fields(SheetZone.wallTime(DateTime.utc(2026, 3, 8, 6, 59))), '2026-03-08 01:59');
      expect(_fields(SheetZone.wallTime(DateTime.utc(2026, 3, 8, 7))), '2026-03-08 03:00');
      expect(_fields(SheetZone.wallTime(DateTime.utc(2026, 11, 1, 5, 59))), '2026-11-01 01:59');
      expect(_fields(SheetZone.wallTime(DateTime.utc(2026, 11, 1, 6))), '2026-11-01 01:00');
    });

    test('a wall time that does not exist is read as standard time, one that exists twice as the first', () {
      // 02:00–02:59 on 8 March 2026 does not exist: 02:30 EST is 03:30 EDT
      expect(_eastern(2026, 3, 8, 2, 0), DateTime.utc(2026, 3, 8, 7));
      expect(_eastern(2026, 3, 8, 2, 30), DateTime.utc(2026, 3, 8, 7, 30));
      expect(_fields(SheetZone.wallTime(_eastern(2026, 3, 8, 2, 30))), '2026-03-08 03:30');
      // 01:00–01:59 on 1 November 2026 exists twice: the first time, in daylight time
      expect(_eastern(2026, 11, 1, 1, 0), DateTime.utc(2026, 11, 1, 5));
      expect(_eastern(2026, 11, 1, 1, 59), DateTime.utc(2026, 11, 1, 5, 59));
    });

    test('a leap year, a year boundary, 2017 and 2030', () {
      expect(_eastern(2024, 2, 29, 20, 0), DateTime.utc(2024, 3, 1, 1));
      // 2024: 10 March and 3 November
      expect(_eastern(2024, 3, 10, 1, 59), DateTime.utc(2024, 3, 10, 6, 59));
      expect(_eastern(2024, 3, 10, 3, 0), DateTime.utc(2024, 3, 10, 7));
      expect(_eastern(2024, 11, 3, 2, 0), DateTime.utc(2024, 11, 3, 7));
      expect(_eastern(2025, 12, 31, 21, 30), DateTime.utc(2026, 1, 1, 2, 30));
      expect(_fields(SheetZone.wallTime(DateTime.utc(2026, 1, 1, 3))), '2025-12-31 22:00');
      // 2017: 12 March and 5 November; the first rows of the sheet
      expect(_eastern(2017, 7, 6, 23, 27), DateTime.utc(2017, 7, 7, 3, 27));
      expect(_eastern(2017, 3, 12, 3, 0), DateTime.utc(2017, 3, 12, 7));
      expect(_eastern(2017, 11, 5, 1, 30), DateTime.utc(2017, 11, 5, 5, 30));
      expect(_eastern(2017, 11, 5, 2, 0), DateTime.utc(2017, 11, 5, 7));
      // 2030: 10 March and 3 November
      expect(_eastern(2030, 3, 10, 1, 59), DateTime.utc(2030, 3, 10, 6, 59));
      expect(_eastern(2030, 3, 10, 3, 0), DateTime.utc(2030, 3, 10, 7));
      expect(_eastern(2030, 11, 3, 1, 59), DateTime.utc(2030, 11, 3, 5, 59));
      expect(_eastern(2030, 11, 3, 2, 0), DateTime.utc(2030, 11, 3, 7));
    });

    test('wallTime keeps the seconds and takes a local DateTime as well as a UTC one', () {
      final wall = SheetZone.wallTime(DateTime.utc(2026, 11, 13, 8, 15, 42));
      expect((wall.isUtc, _fields(wall), wall.second), (true, '2026-11-13 03:15', 42));
      expect(_fields(SheetZone.wallTime(DateTime.utc(2026, 11, 13, 8, 15).toLocal())), '2026-11-13 03:15');
    });

    // The alarm if the US rule changes: the hand-written rule against the full time zone database.
    test('agrees with the time zone database (America/New_York) on every hour of 2017–2036, both ways', () {
      tzdata.initializeTimeZones();
      final newYork = tz.getLocation('America/New_York');
      String databaseWall(DateTime instant) => _fields(tz.TZDateTime.from(instant, newYork));

      // instant -> wall time
      var hours = 0;
      for (
        var t = DateTime.utc(2017, 1, 1, 5);
        t.isBefore(DateTime.utc(2037, 1, 1, 5));
        t = t.add(const Duration(hours: 1))
      ) {
        expect(_fields(SheetZone.wallTime(t)), databaseWall(t), reason: '$t');
        hours++;
      }
      expect(hours, 175320);

      // wall time -> instant: the database says which of UTC−4 and UTC−5 gives that wall time back; neither is a
      // gap (read as standard time), both a repeated hour (read as the first, UTC−4)
      var gaps = 0, repeated = 0;
      for (
        var day = CalendarDate(2017, 1, 1);
        day < CalendarDate(2037, 1, 1);
        day = CalendarDate.fromEpochDay(day.epochDay + 1)
      ) {
        for (var hour = 0; hour < 24; hour++) {
          final wall = '${day.toIso()} ${hour.toString().padLeft(2, '0')}:00';
          final utc = DateTime.utc(day.year, day.month, day.day, hour);
          final daylight = databaseWall(utc.add(const Duration(hours: 4))) == wall;
          final standard = databaseWall(utc.add(const Duration(hours: 5))) == wall;
          if (!daylight && !standard) gaps++;
          if (daylight && standard) repeated++;
          final expected = utc.add(Duration(hours: daylight ? 4 : 5));
          expect(SheetZone.instant(day, hour * 60), expected, reason: wall);
        }
      }
      expect((gaps, repeated), (20, 20), reason: 'one hour of each a year');
    });
  });
}
