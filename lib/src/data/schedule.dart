/// A streaming schedule read from an iCalendar feed (RFC 5545), such as the
/// one Twitch publishes for a channel, and its occurrences around a time.
///
/// Supported: CRLF or LF line ends, folded lines, `DTSTART` / `DTEND` with a
/// `TZID` (IANA name, with or without the leading `/` Twitch writes), in UTC
/// (`…Z`) or floating, `DURATION` instead of `DTEND`, `RRULE` with
/// `FREQ=WEEKLY` (`BYDAY`, `INTERVAL`, `UNTIL`, `COUNT`, `WKST`), `EXDATE`,
/// `RECURRENCE-ID` (one moved or cancelled occurrence), `STATUS:CANCELLED`.
/// An event using anything else (all-day dates, another frequency, `RDATE`,
/// an unknown time zone...) is skipped and logged: it never yields a time that
/// could be wrong.
///
/// Call [loadTimeZones] once before [parseSchedule].
library;

import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../logger.dart';

// ------------------------------------------------------------ time zones

Future<void>? _zonesLoading;

/// The last transition of the time zone data: instants after it are beyond
/// the data for the zones that still change their clocks (see [_TzZone]).
int _dataEnd = 0;

/// Loads the time zone database, once (a few milliseconds: nothing is decoded
/// before the first schedule).
///
/// The data set is the smallest one of `package:timezone` ("10y": 5 years back,
/// 5 years ahead of its release), embedded in the code. Not a deferred import:
/// `flutter build web --web-content-hash`, used to publish the web app, refuses
/// them.
Future<void> loadTimeZones() => _zonesLoading ??= _loadTimeZones().catchError((Object e) {
  _zonesLoading = null;
  throw e;
});

Future<void> _loadTimeZones() async {
  tzdata.initializeTimeZones();
  var end = 0;
  for (final location in tz.timeZoneDatabase.locations.values) {
    final transitions = location.transitionAt;
    if (transitions.isNotEmpty && transitions.last > end) end = transitions.last;
  }
  _dataEnd = end;
}

const int _day = Duration.millisecondsPerDay;

/// A way to turn wall-clock times into instants.
sealed class _Zone {
  const _Zone();

  /// Offset east of UTC at [utc] (milliseconds since the epoch), in milliseconds.
  int offsetAt(int utc);

  /// False when the time zone data does not tell the offset at [utc].
  bool covers(int utc) => true;

  /// The instant of the wall-clock time [wall] (milliseconds since the epoch of
  /// that date and time read as UTC), null beyond the data. A time repeated
  /// when clocks go back is its first occurrence; a time skipped when they go
  /// forward is read with the offset before the gap (RFC 5545, 3.3.5).
  int? instantOf(int wall) {
    final before = offsetAt(wall - _day);
    final after = offsetAt(wall + _day);
    final int instant;
    if (offsetAt(wall - before) == before) {
      instant = wall - before;
    } else if (offsetAt(wall - after) == after) {
      instant = wall - after;
    } else {
      instant = wall - before;
    }
    return covers(instant) ? instant : null;
  }
}

final class _UtcZone extends _Zone {
  const _UtcZone();

  @override
  int offsetAt(int utc) => 0;

  @override
  String toString() => 'UTC';
}

/// The zone of the device: floating times, as RFC 5545 defines them.
final class _DeviceZone extends _Zone {
  const _DeviceZone();

  @override
  int offsetAt(int utc) => DateTime.fromMillisecondsSinceEpoch(utc).timeZoneOffset.inMilliseconds;

  @override
  String toString() => 'device';
}

final class _TzZone extends _Zone {
  _TzZone(this.location)
    // a zone whose last transition is in the last year of the data still
    // changes its clocks: the offset after that transition is unknown
    : _lastKnown = location.transitionAt.length > 1 && location.transitionAt.last > _dataEnd - 400 * _day
          ? location.transitionAt.last
          : null;

  final tz.Location location;
  final int? _lastKnown;

  @override
  int offsetAt(int utc) => location.timeZone(utc).offset.inMilliseconds;

  @override
  bool covers(int utc) => _lastKnown == null || utc <= _lastKnown;

  @override
  String toString() => location.name;
}

final _zones = <String, _TzZone?>{};

/// The zone named by a `TZID`, null when unknown.
_TzZone? _zoneNamed(String tzid) {
  if (!tz.timeZoneDatabase.isInitialized) throw StateError('loadTimeZones() was not called');
  // Twitch writes "/Australia/Sydney" (a leading slash marks a globally unique id in RFC 5545)
  final name = tzid.startsWith('/') ? tzid.substring(1) : tzid;
  return _zones.putIfAbsent(name, () {
    final location = tz.timeZoneDatabase.locations[name];
    return location == null ? null : _TzZone(location);
  });
}

// ------------------------------------------------------------ model

/// One occurrence of a scheduled stream.
final class StreamOccurrence {
  /// Creates an occurrence; [start] and [end] are converted to UTC.
  StreamOccurrence({required DateTime start, required DateTime end, required this.title})
    : start = start.toUtc(),
      end = end.toUtc();

  /// Start (UTC).
  final DateTime start;

  /// End (UTC), not before [start].
  final DateTime end;

  /// The `SUMMARY` of the event, possibly empty.
  final String title;

  @override
  bool operator ==(Object other) =>
      other is StreamOccurrence && other.start == start && other.end == end && other.title == title;

  @override
  int get hashCode => Object.hash(start, end, title);

  @override
  String toString() => 'StreamOccurrence($title, $start – $end)';
}

/// The occurrences around a time: the one in progress and the next one.
typedef ScheduleStatus = ({StreamOccurrence? current, StreamOccurrence? next});

/// The usable events of a feed.
final class StreamSchedule {
  StreamSchedule._(this._events, this.skippedCount);

  final List<_Event> _events;

  /// Number of events left out (unsupported or malformed; see the logs).
  final int skippedCount;

  /// Number of usable events (a recurring event counts once).
  int get eventCount => _events.length;

  /// At [now]: the occurrence in progress (the one that started first when
  /// several overlap) and the next one that has not started, within a year.
  /// An occurrence that starts at [now] is in progress.
  ScheduleStatus statusAt(DateTime now) {
    final at = now.millisecondsSinceEpoch;
    final horizon = at + 366 * _day;
    _Instance? current;
    _Instance? next;
    for (final event in _events) {
      for (final instance in event.instances()) {
        if (instance == null) {
          event.warnBeyondData();
          break;
        }
        if (instance.start > at) {
          if (instance.start <= horizon && (next == null || instance.start < next.start)) next = instance;
          break;
        }
        if (instance.end > at && (current == null || instance.start < current.start)) current = instance;
      }
    }
    return (current: current?.toOccurrence(), next: next?.toOccurrence());
  }

  /// The occurrences starting in [[from], [to]), by start time.
  List<StreamOccurrence> occurrencesBetween(DateTime from, DateTime to) {
    final start = from.millisecondsSinceEpoch;
    final end = to.millisecondsSinceEpoch;
    final found = <_Instance>[];
    for (final event in _events) {
      for (final instance in event.instances()) {
        if (instance == null || instance.start >= end) break;
        if (instance.start >= start) found.add(instance);
      }
    }
    found.sort((a, b) => a.start.compareTo(b.start));
    return [for (final i in found) i.toOccurrence()];
  }

  @override
  String toString() => 'StreamSchedule($eventCount events, $skippedCount skipped)';
}

final class _Instance {
  _Instance(this.event, this.start, this.end);

  final _Event event;
  final int start;
  final int end;

  StreamOccurrence toOccurrence() => StreamOccurrence(
    start: DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
    end: DateTime.fromMillisecondsSinceEpoch(end, isUtc: true),
    title: event.title,
  );
}

/// How long an occurrence lasts: [exact] milliseconds (from `DTEND`, or the
/// time part of a `DURATION`) after [days] calendar days (nominal days of a
/// `DURATION`, which follow the wall clock across a daylight saving change).
typedef _Length = ({int days, int exact});

final class _Rule {
  _Rule({required this.interval, required this.weekdays, required this.weekStart, this.count, this.until});

  final int interval;

  /// ISO weekdays (1 = Monday), ordered from [weekStart].
  final List<int> weekdays;
  final int weekStart;
  final int? count;
  final _Value? until;
}

final class _Event {
  _Event({
    required this.title,
    required this.zone,
    required this.startWall,
    required this.length,
    required this.rule,
    required this.excluded,
  });

  final String title;
  final _Zone zone;

  /// `DTSTART` as a wall-clock time in [zone].
  final int startWall;
  final _Length length;
  final _Rule? rule;

  /// Excluded start instants (`EXDATE`, overridden occurrences).
  final Set<int> excluded;

  bool _warned = false;

  void warnBeyondData() {
    if (_warned) return;
    _warned = true;
    logger.w('Schedule: "$title" goes beyond the time zone data, later occurrences left out');
  }

  int? _endOf(int start, int startWall) {
    if (length.days == 0) return start + length.exact;
    final endDay = zone.instantOf(startWall + length.days * _day);
    return endDay == null ? null : endDay + length.exact;
  }

  _Instance? _instanceAt(int wall, int start) {
    final end = _endOf(start, wall);
    return end == null ? null : _Instance(this, start, end);
  }

  /// The occurrences in order; a null element means the next one is beyond
  /// the time zone data (and ends the sequence).
  Iterable<_Instance?> instances() sync* {
    final rule = this.rule;
    if (rule == null) {
      final start = zone.instantOf(startWall);
      if (start == null) {
        yield null;
      } else if (!excluded.contains(start)) {
        final instance = _instanceAt(startWall, start);
        yield instance;
      }
      return;
    }
    final firstDay = _floorDiv(startWall, _day);
    final timeOfDay = startWall - firstDay * _day;
    int offsetInWeek(int weekday) => (weekday - rule.weekStart + 7) % 7;
    final firstWeek = firstDay - offsetInWeek(_weekdayOf(firstDay));
    final until = rule.until;
    final untilDay = until != null && until.isDate ? _floorDiv(until.wall, _day) : null;
    // beyond the data (null) is later than any occurrence within it
    final untilInstant = until != null && !until.isDate ? until.zone.instantOf(until.wall) : null;
    var generated = 0;
    // 10,000 weeks: about 190 years of a weekly event, a bound against a feed whose events never end
    for (var k = 0; k < 10000; k++) {
      final week = firstWeek + 7 * rule.interval * k;
      for (final weekday in rule.weekdays) {
        final day = week + offsetInWeek(weekday);
        if (day < firstDay) continue;
        if (untilDay != null && day > untilDay) return;
        final wall = day * _day + timeOfDay;
        final start = zone.instantOf(wall);
        if (start == null) {
          yield null;
          return;
        }
        if (untilInstant != null && start > untilInstant) return;
        generated++;
        if (rule.count != null && generated > rule.count!) return;
        if (excluded.contains(start)) continue;
        final instance = _instanceAt(wall, start);
        yield instance;
        if (instance == null) return;
      }
    }
  }
}

int _floorDiv(int a, int b) => (a - a % b) ~/ b;

/// ISO weekday (1 = Monday) of a day number (days since 1970-01-01, a Thursday).
int _weekdayOf(int day) => (day + 3) % 7 + 1;

// ------------------------------------------------------------ parsing

/// Thrown by [parseSchedule] when the text is not an iCalendar object.
class ScheduleFormatException extends FormatException {
  const ScheduleFormatException(super.message);
}

final class _Skip implements Exception {
  const _Skip(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

final class _Property {
  _Property(this.name, this.params, this.value);

  final String name;
  final Map<String, String> params;
  final String value;
}

/// A DATE or DATE-TIME value: [wall] is the date and time read as UTC
/// (midnight for a date).
final class _Value {
  _Value(this.zone, this.wall, {required this.isDate});

  final _Zone zone;
  final int wall;
  final bool isDate;
}

/// Parses an iCalendar feed. Unusable events are skipped (and logged); throws
/// [ScheduleFormatException] when [text] holds no `VCALENDAR`.
/// Requires [loadTimeZones].
StreamSchedule parseSchedule(String text) {
  // a byte-order mark would hide the first line
  final lines = _unfold(text.startsWith('\uFEFF') ? text.substring(1) : text);
  final components = <String>[];
  final calendarProps = <_Property>[];
  final events = <List<_Property>>[];
  var sawCalendar = false;
  List<_Property>? event;
  for (final line in lines) {
    if (line.isEmpty) continue;
    final property = _parseLine(line);
    if (property == null) {
      if (event != null && components.length == 2) event.add(_Property('X-INVALID', const {}, line));
      continue;
    }
    if (property.name == 'BEGIN') {
      final name = property.value.toUpperCase();
      if (components.isEmpty && name == 'VCALENDAR') sawCalendar = true;
      components.add(name);
      if (components.length == 2 && name == 'VEVENT') events.add(event = []);
      continue;
    }
    if (property.name == 'END') {
      if (components.isNotEmpty) components.removeLast();
      if (components.length < 2) event = null;
      continue;
    }
    if (components.length == 1) {
      calendarProps.add(property);
    } else if (event != null && components.length == 2) {
      event.add(property);
    }
  }
  if (!sawCalendar) throw const ScheduleFormatException('Not an iCalendar feed (no BEGIN:VCALENDAR)');

  // floating times: the calendar's zone when it names one (an extension most
  // producers write), else the device's (RFC 5545)
  _Zone floating = const _DeviceZone();
  final calendarZone = calendarProps.where((p) => p.name == 'X-WR-TIMEZONE').firstOrNull?.value;
  if (calendarZone != null) floating = _zoneNamed(calendarZone) ?? floating;

  // overrides of one occurrence (RECURRENCE-ID) are grouped with their event
  final byUid = <String, List<List<_Property>>>{};
  final withoutUid = <List<_Property>>[];
  for (final props in events) {
    final uid = _first(props, 'UID')?.value;
    (uid == null ? withoutUid : byUid.putIfAbsent(uid, () => [])).add(props);
  }
  final parsed = <_Event>[];
  var skipped = 0;
  void skip(List<_Property> props, Object reason) {
    skipped++;
    // never `_single` here: it throws for a repeated property, and this runs while skipping
    final title = _first(props, 'SUMMARY')?.value ?? '';
    logger.w('Schedule: event "${_unescape(title)}" (${_first(props, 'UID')?.value}) skipped: $reason');
  }

  for (final props in withoutUid) {
    try {
      if (_has(props, 'RECURRENCE-ID')) throw const _Skip('RECURRENCE-ID without UID');
      final e = _buildEvent(props, floating, const {});
      if (e != null) parsed.add(e);
    } on _Skip catch (reason) {
      skip(props, reason);
    }
  }
  for (final group in byUid.values) {
    final masters = group.where((p) => !_has(p, 'RECURRENCE-ID')).toList();
    final overrides = group.where((p) => _has(p, 'RECURRENCE-ID')).toList();
    try {
      if (masters.length > 1) throw const _Skip('several events with the same UID');
      final master = masters.firstOrNull;
      final moved = <int>{};
      final replacements = <_Event>[];
      for (final props in overrides) {
        final id = _single(props, 'RECURRENCE-ID')!;
        if (id.params.containsKey('RANGE')) throw const _Skip('RECURRENCE-ID with RANGE');
        final masterZone = master == null ? floating : _startOf(master, floating).zone;
        final value = _parseValue(id, masterZone);
        if (value.isDate) throw const _Skip('all-day RECURRENCE-ID');
        final instant = value.zone.instantOf(value.wall);
        if (instant != null) moved.add(instant);
        if (_has(props, 'RRULE')) throw const _Skip('RRULE in an overridden occurrence');
        final replacement = _buildEvent(props, floating, const {});
        if (replacement != null) replacements.add(replacement);
      }
      if (master != null) {
        final e = _buildEvent(master, floating, moved);
        if (e != null) parsed.add(e);
      }
      parsed.addAll(replacements);
    } on _Skip catch (reason) {
      skip(masters.firstOrNull ?? group.first, reason);
      skipped += group.length - 1;
    }
  }
  return StreamSchedule._(parsed, skipped);
}

/// The lines of [text], unfolded (RFC 5545, 3.1).
List<String> _unfold(String text) {
  final out = <String>[];
  for (final line in text.split(RegExp(r'\r\n|\n|\r'))) {
    if (line.isNotEmpty && (line[0] == ' ' || line[0] == '\t') && out.isNotEmpty) {
      out[out.length - 1] += line.substring(1);
    } else {
      out.add(line);
    }
  }
  return out;
}

/// `NAME;PARAM=a;PARAM2="b:c":value`; null when malformed.
_Property? _parseLine(String line) {
  var i = 0;
  final n = line.length;
  while (i < n && line[i] != ';' && line[i] != ':') {
    i++;
  }
  if (i == 0 || i == n) return null;
  final name = line.substring(0, i).toUpperCase();
  final params = <String, String>{};
  while (line[i] == ';') {
    final nameStart = ++i;
    while (i < n && line[i] != '=') {
      if (line[i] == ';' || line[i] == ':') return null;
      i++;
    }
    if (i == n) return null;
    final paramName = line.substring(nameStart, i).toUpperCase();
    i++;
    final value = StringBuffer();
    while (true) {
      if (i < n && line[i] == '"') {
        final close = line.indexOf('"', i + 1);
        if (close < 0) return null;
        value.write(line.substring(i + 1, close));
        i = close + 1;
      } else {
        final valueStart = i;
        while (i < n && line[i] != ';' && line[i] != ':' && line[i] != ',' && line[i] != '"') {
          i++;
        }
        value.write(line.substring(valueStart, i));
      }
      if (i < n && line[i] == ',') {
        value.write(',');
        i++;
        continue;
      }
      break;
    }
    if (i == n || params.containsKey(paramName)) return null;
    params[paramName] = value.toString();
  }
  if (line[i] != ':') return null;
  return _Property(name, params, line.substring(i + 1));
}

bool _has(List<_Property> props, String name) => props.any((p) => p.name == name);

/// The property [name] when it appears once, null when absent; skips the
/// event when it appears several times.
/// The first [name] property, without checking that it is the only one.
_Property? _first(List<_Property> props, String name) => props.where((p) => p.name == name).firstOrNull;

_Property? _single(List<_Property> props, String name) {
  _Property? found;
  for (final p in props) {
    if (p.name != name) continue;
    if (found != null) throw _Skip('several $name');
    found = p;
  }
  return found;
}

String _unescape(String text) => text.replaceAllMapped(
  RegExp(r'\\([\\;,nN])'),
  (m) => switch (m[1]!) {
    'n' || 'N' => '\n',
    final c => c,
  },
);

/// Properties that change the occurrences and are not supported.
const _unsupported = {'RDATE', 'EXRULE'};

_Value _startOf(List<_Property> props, _Zone floating) {
  final dtStart = _single(props, 'DTSTART') ?? (throw const _Skip('no DTSTART'));
  return _parseValue(dtStart, floating);
}

/// The event of [props], whose occurrences starting at [moved] are replaced;
/// null for a cancelled event. Throws [_Skip].
_Event? _buildEvent(List<_Property> props, _Zone floating, Set<int> moved) {
  if (_has(props, 'X-INVALID')) throw const _Skip('malformed line');
  for (final name in _unsupported) {
    if (_has(props, name)) throw _Skip('$name not supported');
  }
  final status = _single(props, 'STATUS')?.value.toUpperCase();
  final title = _unescape(_single(props, 'SUMMARY')?.value ?? '');
  final start = _startOf(props, floating);
  if (start.isDate) throw const _Skip('all-day event');
  final zone = start.zone;
  final startInstant = zone.instantOf(start.wall);

  final dtEnd = _single(props, 'DTEND');
  final durationProp = _single(props, 'DURATION');
  final _Length length;
  if (dtEnd != null && durationProp != null) {
    throw const _Skip('both DTEND and DURATION');
  } else if (dtEnd != null) {
    final end = _parseValue(dtEnd, zone);
    if (end.isDate) throw const _Skip('DTEND is a date');
    final endInstant = end.zone.instantOf(end.wall);
    if (startInstant == null || endInstant == null) throw const _Skip('beyond the time zone data');
    if (endInstant <= startInstant) throw const _Skip('DTEND not after DTSTART');
    length = (days: 0, exact: endInstant - startInstant);
  } else if (durationProp != null) {
    length = _parseDuration(durationProp.value);
  } else {
    length = (days: 0, exact: 0);
  }

  final excluded = {...moved};
  for (final exdate in props.where((p) => p.name == 'EXDATE')) {
    for (final value in exdate.value.split(',')) {
      final v = _parseValue(_Property('EXDATE', exdate.params, value), zone);
      if (v.isDate) throw const _Skip('all-day EXDATE');
      final instant = v.zone.instantOf(v.wall);
      // beyond the data: so are the occurrences it would remove
      if (instant != null) excluded.add(instant);
    }
  }

  final rrule = _single(props, 'RRULE');
  final rule = rrule == null ? null : _parseRule(rrule.value, start, zone);
  if (status == 'CANCELLED') return null;
  if (startInstant == null && rule == null) throw const _Skip('beyond the time zone data');
  return _Event(title: title, zone: zone, startWall: start.wall, length: length, rule: rule, excluded: excluded);
}

final _dateTime = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z?))?$');

/// A DATE or DATE-TIME property value; floating times are in [floating].
_Value _parseValue(_Property p, _Zone floating) {
  final m = _dateTime.firstMatch(p.value.trim());
  if (m == null) throw _Skip('invalid ${p.name} "${p.value}"');
  final declared = p.params['VALUE']?.toUpperCase();
  final isDate = m[4] == null;
  if (declared != null && declared != (isDate ? 'DATE' : 'DATE-TIME')) throw _Skip('invalid ${p.name} "${p.value}"');
  final year = int.parse(m[1]!), month = int.parse(m[2]!), day = int.parse(m[3]!);
  final hour = isDate ? 0 : int.parse(m[4]!), minute = isDate ? 0 : int.parse(m[5]!);
  final second = isDate ? 0 : int.parse(m[6]!);
  final wall = DateTime.utc(year, month, day, hour, minute, second);
  if (wall.month != month || wall.day != day || hour > 23 || minute > 59 || second > 59) {
    throw _Skip('invalid ${p.name} "${p.value}"');
  }
  final tzid = p.params['TZID'];
  final utc = m[7] == 'Z';
  final _Zone zone;
  if (utc && tzid != null) {
    throw _Skip('${p.name} in UTC with a TZID');
  } else if (utc) {
    zone = const _UtcZone();
  } else if (tzid != null && !isDate) {
    zone = _zoneNamed(tzid) ?? (throw _Skip('unknown time zone "$tzid"'));
  } else {
    zone = floating;
  }
  return _Value(zone, wall.millisecondsSinceEpoch, isDate: isDate);
}

final _durationPattern = RegExp(r'^([+-])?P(?:(\d+)W|(\d+D)?(?:T(\d+H)?(\d+M)?(\d+S)?)?)$');

_Length _parseDuration(String text) {
  final m = _durationPattern.firstMatch(text.trim());
  if (m == null || text.trim().endsWith('T') || text.trim().endsWith('P')) throw _Skip('invalid DURATION "$text"');
  if (m[1] == '-') throw _Skip('negative DURATION "$text"');
  int part(int group) {
    final s = m[group];
    return s == null ? 0 : int.parse(s.replaceAll(RegExp(r'\D'), ''));
  }

  final days = part(2) * 7 + part(3);
  final exact = Duration(hours: part(4), minutes: part(5), seconds: part(6)).inMilliseconds;
  return (days: days, exact: exact);
}

const _dayCodes = {'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6, 'SU': 7};

_Rule _parseRule(String text, _Value start, _Zone zone) {
  final parts = <String, String>{};
  for (final part in text.split(';')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    if (eq <= 0) throw _Skip('invalid RRULE "$text"');
    final key = part.substring(0, eq).toUpperCase();
    if (parts.containsKey(key)) throw _Skip('invalid RRULE "$text"');
    parts[key] = part.substring(eq + 1).toUpperCase();
  }
  final freq = parts.remove('FREQ');
  if (freq != 'WEEKLY') throw _Skip('RRULE FREQ=$freq not supported');
  int positive(String? value, String name) {
    final n = value == null ? null : int.tryParse(value);
    if (n == null || n < 1) throw _Skip('invalid RRULE $name "$value"');
    return n;
  }

  final interval = parts.containsKey('INTERVAL') ? positive(parts.remove('INTERVAL'), 'INTERVAL') : 1;
  final count = parts.containsKey('COUNT') ? positive(parts.remove('COUNT'), 'COUNT') : null;
  _Value? until;
  final untilText = parts.remove('UNTIL');
  if (untilText != null) {
    if (count != null) throw const _Skip('RRULE with both COUNT and UNTIL');
    until = _parseValue(_Property('UNTIL', const {}, untilText), zone);
  }
  int dayCode(String code) => _dayCodes[code] ?? (throw _Skip('RRULE day "$code" not supported'));
  final weekStart = parts.containsKey('WKST') ? dayCode(parts.remove('WKST')!) : DateTime.monday;
  final startDay = _floorDiv(start.wall, _day);
  final byDay = parts.remove('BYDAY');
  final days = byDay == null ? {_weekdayOf(startDay)} : {for (final code in byDay.split(',')) dayCode(code)};
  if (parts.isNotEmpty) throw _Skip('RRULE ${parts.keys.join(', ')} not supported');
  // RFC 5545 leaves a DTSTART that does not match its rule undefined
  if (!days.contains(_weekdayOf(startDay))) throw const _Skip('DTSTART does not match its RRULE');
  final ordered = days.toList()..sort((a, b) => ((a - weekStart + 7) % 7).compareTo((b - weekStart + 7) % 7));
  return _Rule(interval: interval, weekdays: ordered, weekStart: weekStart, count: count, until: until);
}
