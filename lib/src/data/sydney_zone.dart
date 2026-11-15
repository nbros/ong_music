/// The time zone of the titles of the VODs: Australian Eastern time (`Australia/Sydney`), where Jonathan Ong streams.
///
/// Pure Dart, integer arithmetic, as `SheetZone` and for the same reasons: not through `package:timezone`, whose
/// database is not loaded on the isolate the catalogue is parsed on, nor kept for the years of the first streams.
library;

import 'model.dart';

/// Australian Eastern time: the date of the start of a stream in the title of its VOD (`VOD for the 10th of November
/// 2026`).
///
/// Standard time UTC+10; daylight time UTC+11 from the first Sunday of October, 02:00 standard time (16:00 UTC the
/// Saturday before), to the first Sunday of April, 03:00 daylight time (16:00 UTC the Saturday before). That rule is
/// in force since 2008 (the VODs begin in 2020) and is applied to any year. The tests compare it with the full time
/// zone database, hour by hour over twenty years: they fail if the rule ever changes.
abstract final class SydneyZone {
  /// The date in Sydney at [epochMinute] (minutes since 1970-01-01 00:00 UTC, as `Play.loggedMinute`).
  static CalendarDate dateOf(int epochMinute) {
    // the year of the UTC day: the changes of April and October are far from New Year, daylight time at both sides
    _bounds(CalendarDate.fromEpochDay(_floorDiv(epochMinute, Duration.minutesPerDay)).year);
    // southern hemisphere: daylight time from January to April and from October to December
    final daylight = epochMinute < _end || epochMinute >= _start;
    return CalendarDate.fromEpochDay(_floorDiv(epochMinute + (daylight ? 660 : 600), Duration.minutesPerDay));
  }

  // The changes of the last year asked for, in minutes since the epoch (UTC): the streams come in order, one
  // computation per year.
  static int? _year;
  static int _end = 0;
  static int _start = 0;

  static void _bounds(int year) {
    if (year == _year) return;
    final april = CalendarDate(year, 4, 1).epochDay;
    final october = CalendarDate(year, 10, 1).epochDay;
    // first Sunday of April and of October, at 16:00 UTC the day before
    _end = (april + _daysToSunday(april) - 1) * Duration.minutesPerDay + 16 * 60;
    _start = (october + _daysToSunday(october) - 1) * Duration.minutesPerDay + 16 * 60;
    _year = year;
  }

  /// Days from [epochDay] to the next Sunday, 0 when it is one (1970-01-01 was a Thursday).
  static int _daysToSunday(int epochDay) => (3 - epochDay) % 7;

  /// [a] / [b] rounded down ([b] > 0).
  static int _floorDiv(int a, int b) => (a - a % b) ~/ b;
}
