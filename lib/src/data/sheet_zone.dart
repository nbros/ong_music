/// The time zone the Ong Log is written in: US Eastern (`America/New_York`).
///
/// Pure Dart, integer arithmetic. Not through `package:timezone`: the app bundles its smallest data set (5 years
/// back: the rows of 2017–2020 are outside), the catalogue is parsed on a background isolate where that database is
/// not loaded, and the parser reads one cell per row (33,000 rows; see [CalendarDate.parseCell] on why it avoids
/// `DateTime` there, on the web in particular).
library;

import 'model.dart';

/// US Eastern time, the zone of the dates and times of the "Songs" sheet.
///
/// Standard time UTC−5; daylight time UTC−4 from the second Sunday of March, 02:00 standard time (07:00 UTC), to
/// the first Sunday of November, 02:00 daylight time (06:00 UTC). That rule is in force since 2007 (the sheet
/// starts in 2017) and is applied to any year. The tests compare it with the full time zone database, hour by hour
/// over twenty years: they fail if the rule ever changes.
abstract final class SheetZone {
  /// The instant of the Eastern wall time [minuteOfDay] (0–1439) on [date], in minutes since 1970-01-01 00:00 UTC.
  ///
  /// A wall time that does not exist (02:00–02:59 on the March day) is read as standard time, so one hour later on
  /// the daylight clock. A wall time that exists twice (01:00–01:59 on the November day) is read as the first one,
  /// in daylight time.
  static int epochMinute(CalendarDate date, int minuteOfDay) {
    final wall = date.epochDay * Duration.minutesPerDay + minuteOfDay;
    _bounds(_yearOf(date.epochDay));
    // the daylight clock reads 03:00 at its start and 02:00 at its end (four hours behind UTC)
    final daylight = wall >= _start - 240 && wall < _end - 240;
    return wall + (daylight ? 240 : 300);
  }

  /// The instant of [epochMinute], UTC.
  static DateTime instant(CalendarDate date, int minuteOfDay) =>
      DateTime.fromMillisecondsSinceEpoch(epochMinute(date, minuteOfDay) * Duration.millisecondsPerMinute, isUtc: true);

  /// The Eastern wall time of [instant]: a UTC `DateTime` whose fields (year … second) are those of the wall clock
  /// in New York. The inverse of [instant] for the wall times that exist once. For the years a sheet date can hold
  /// (0–9999), not the last year of the range of `DateTime`.
  static DateTime wallTime(DateTime instant) {
    final ms = instant.millisecondsSinceEpoch;
    final minute = _floorDiv(ms, Duration.millisecondsPerMinute);
    // the year of the standard-time day: the transitions are far from New Year
    _bounds(_yearOf(_floorDiv(minute - 300, Duration.minutesPerDay)));
    final offset = minute >= _start && minute < _end ? 240 : 300;
    return DateTime.fromMillisecondsSinceEpoch(ms - offset * Duration.millisecondsPerMinute, isUtc: true);
  }

  // The daylight time of the last year asked for, in minutes since the epoch (UTC): the rows of the sheet come in
  // order, one computation per year.
  static int? _year;
  static int _start = 0;
  static int _end = 0;

  static void _bounds(int year) {
    if (year == _year) return;
    final march = CalendarDate(year, 3, 1).epochDay;
    final november = CalendarDate(year, 11, 1).epochDay;
    // second Sunday of March, first Sunday of November
    final marchSunday = march + _daysToSunday(march) + 7;
    final novemberSunday = november + _daysToSunday(november);
    _start = marchSunday * Duration.minutesPerDay + 7 * 60;
    _end = novemberSunday * Duration.minutesPerDay + 6 * 60;
    _year = year;
  }

  /// Days from [epochDay] to the next Sunday, 0 when it is one (1970-01-01 was a Thursday).
  static int _daysToSunday(int epochDay) => (3 - epochDay) % 7;

  /// The year of [epochDay] (proleptic Gregorian), see http://howardhinnant.github.io/date_algorithms.html.
  static int _yearOf(int epochDay) {
    final z = epochDay + 719468;
    final era = _floorDiv(z, 146097);
    final dayOfEra = z - era * 146097;
    final yearOfEra = (dayOfEra - dayOfEra ~/ 1460 + dayOfEra ~/ 36524 - dayOfEra ~/ 146096) ~/ 365;
    final dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra ~/ 4 - yearOfEra ~/ 100);
    final shiftedMonth = (5 * dayOfYear + 2) ~/ 153; // 0 = March
    return yearOfEra + era * 400 + (shiftedMonth >= 10 ? 1 : 0);
  }

  /// [a] / [b] rounded down ([b] > 0).
  static int _floorDiv(int a, int b) => (a - a % b) ~/ b;
}
