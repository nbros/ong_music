/// Number, date and duration formatting of the design (English, no `intl`).
library;

import '../data/model.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `31430` → `31,430`.
String formatCount(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// `1 song`, `12 songs`: [n] formatted, then [singular] or [plural]
/// (default: [singular] + `s`).
String plural(int n, String singular, [String? plural]) =>
    '${formatCount(n)} ${n == 1 ? singular : plural ?? '${singular}s'}';

/// `17 Oct` in [currentYear], `26 Mar 2025` otherwise; empty for null.
String formatShortDate(CalendarDate? date, {required int currentYear}) {
  if (date == null) return '';
  final short = '${date.day} ${_months[date.month - 1]}';
  return date.year == currentYear ? short : '$short ${date.year}';
}

/// `Thu 15 Oct 2026`.
String formatFullDate(CalendarDate date) =>
    '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]} ${date.year}';

/// `8 h 03`; empty for 0 minutes.
String formatDuration(int minutes) =>
    minutes <= 0 ? '' : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';

/// `12 songs · 8 h 03`: the size of a stream.
String formatStreamSize(LiveStream stream) {
  final duration = formatDuration(stream.durationMinutes);
  return '${plural(stream.playCount, 'song')}${duration.isEmpty ? '' : ' · $duration'}';
}

/// How long ago [time] was, to follow "Updated": `just now`, `5 minutes ago`,
/// `2 hours ago`, `yesterday`, `3 days ago`, then `on 3 Nov` / `on 3 Nov 2025`.
String formatAgo(DateTime time, DateTime now) {
  final elapsed = now.difference(time);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inMinutes < 60) return '${plural(elapsed.inMinutes, 'minute')} ago';
  if (elapsed.inHours < 24) return '${plural(elapsed.inHours, 'hour')} ago';
  final local = time.toLocal();
  final nowLocal = now.toLocal();
  // calendar days between the two local dates (UTC midnights: no DST hour)
  final days = DateTime.utc(
    nowLocal.year,
    nowLocal.month,
    nowLocal.day,
  ).difference(DateTime.utc(local.year, local.month, local.day)).inDays;
  if (days <= 1) return 'yesterday';
  if (days < 14) return '$days days ago';
  return 'on ${formatShortDate(CalendarDate(local.year, local.month, local.day), currentYear: nowLocal.year)}';
}

/// The day of [time] seen from [now], on the local calendar: `today`,
/// `tomorrow`, then `Fri 13 Nov`, with the year when it is not the current one
/// (`Mon 4 Jan 2027`).
String formatDayFrom(DateTime time, DateTime now) {
  final local = time.toLocal();
  final nowLocal = now.toLocal();
  // calendar days between the two local dates (UTC midnights: no DST hour)
  final days = DateTime.utc(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime.utc(nowLocal.year, nowLocal.month, nowLocal.day)).inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  final date = '${_weekdays[local.weekday - 1]} ${local.day} ${_months[local.month - 1]}';
  return local.year == nowLocal.year ? date : '$date ${local.year}';
}
