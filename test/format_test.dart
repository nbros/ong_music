import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/model.dart';
import 'package:ong_music/src/ui/format.dart';

void main() {
  test('formatCount', () {
    expect(formatCount(0), '0');
    expect(formatCount(999), '999');
    expect(formatCount(1953), '1,953');
    expect(formatCount(31430), '31,430');
    expect(formatCount(1234567), '1,234,567');
  });

  test('plural', () {
    expect(plural(1, 'song'), '1 song');
    expect(plural(2, 'song'), '2 songs');
    expect(plural(1413, 'stream'), '1,413 streams');
  });

  test('dates', () {
    final d = CalendarDate(2026, 10, 15);
    expect(formatShortDate(d, currentYear: 2026), '15 Oct');
    expect(formatShortDate(d, currentYear: 2027), '15 Oct 2026');
    expect(formatShortDate(null, currentYear: 2026), '');
    expect(formatFullDate(d), 'Thu 15 Oct 2026');
    expect(formatFullDate(CalendarDate(2024, 3, 3)), 'Sun 3 Mar 2024');
  });

  test('durations', () {
    expect(formatDuration(0), '');
    expect(formatDuration(483), '8 h 03');
    expect(formatDuration(59), '0 h 59');
  });

  test('formatAgo', () {
    // local times: the days are counted on the calendar of the device, so the
    // test must not depend on the time zone of the machine running it
    final now = DateTime(2026, 11, 12, 12);
    expect(formatAgo(now.subtract(const Duration(seconds: 30)), now), 'just now');
    expect(formatAgo(now.subtract(const Duration(minutes: 1)), now), '1 minute ago');
    expect(formatAgo(now.subtract(const Duration(minutes: 59)), now), '59 minutes ago');
    expect(formatAgo(now.subtract(const Duration(hours: 2)), now), '2 hours ago');
    expect(formatAgo(DateTime(2026, 11, 11, 6), now), 'yesterday');
    expect(formatAgo(DateTime(2026, 11, 10, 23), now), '2 days ago');
    expect(formatAgo(DateTime(2026, 11, 7, 12), now), '5 days ago');
    expect(formatAgo(DateTime(2026, 9, 3, 12), now), 'on 3 Sep');
    expect(formatAgo(DateTime(2025, 9, 3, 12), now), 'on 3 Sep 2025');
    // UTC times are shown on the local calendar too
    expect(formatAgo(DateTime(2026, 9, 3, 12).toUtc(), now.toUtc()), 'on 3 Sep');
  });

  test('formatDayFrom', () {
    // local times, as for formatAgo
    final now = DateTime(2026, 11, 12, 23, 30);
    expect(formatDayFrom(DateTime(2026, 11, 12, 23, 45), now), 'today');
    expect(formatDayFrom(DateTime(2026, 11, 13, 0, 5), now), 'tomorrow');
    expect(formatDayFrom(DateTime(2026, 11, 14, 9), now), 'Sat 14 Nov');
    expect(formatDayFrom(DateTime(2026, 12, 31, 9), now), 'Thu 31 Dec');
    expect(formatDayFrom(DateTime(2027, 1, 1, 9), now), 'Fri 1 Jan 2027');
    // UTC times are shown on the local calendar
    expect(formatDayFrom(DateTime(2026, 11, 14, 9).toUtc(), now.toUtc()), 'Sat 14 Nov');
  });
}
