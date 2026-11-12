/// The entities of the catalogue: highlights, plays, streams, songs, requesters.
///
/// Pure Dart. All objects are immutable; cross references are integer ids,
/// i.e. indices into the lists of the owning `Catalogue`.
library;

import 'text.dart';

/// Display genres. The sheets spell genres in many ways (with typos); [parse]
/// maps them, anything unknown is [other].
enum Genre {
  other('Other'),
  popular('Popular'),
  gameOst('Game OST'),
  filmTv('Film & TV'),
  anime('Anime'),
  disney('Disney'),
  classical('Classical'),
  musicals('Musicals'),
  jazz('Jazz'),
  ongriginal('Ongriginal'),
  christmas('Christmas'),
  hymns('Hymns'),
  meme('Meme'),
  traditional('Traditional');

  const Genre(this.label);

  /// English display name.
  final String label;

  static const Map<String, Genre> _cells = {
    'POPULAR MUSIC': popular,
    'POPULAR_MUSIC': popular,
    'GAME OST': gameOst,
    'FILMS/TELEVISION': filmTv,
    'FILM/TELEVISION': filmTv,
    'ANIME': anime,
    'DISNEY': disney,
    'CLASSICAL': classical,
    'MUSICALS': musicals,
    'MUSICAL': musicals,
    'MUSICIAL': musicals,
    'JAZZ/STANDARDS': jazz,
    'ONGRIGINAL': ongriginal,
    'ONGRIGNAL': ongriginal,
    'ONGORIGINAL': ongriginal,
    'ONGORIGNAL': ongriginal,
    'ORIGINAL': ongriginal,
    '[COMPOSITION]': ongriginal,
    'CHRISTMAS MUSIC': christmas,
    'HYMNS/WORSHIP': hymns,
    'HYMN': hymns,
    'MEME': meme,
    'TRADITIONAL': traditional,
  };

  /// The genre of a sheet cell (trimmed, case-insensitive).
  static Genre parse(String cell) => _cells[cell.trim().toUpperCase()] ?? other;
}

/// How a song was played (Ong Log "Request Type/Instrument" column).
enum PlayType {
  /// Empty or unrecognised cell. Its [label] is empty and it is not searchable.
  unknown(''),
  piano('Piano'),
  loop('Loop'),
  catPiano('Cat piano'),
  improv('Improv');

  const PlayType(this.label);

  /// English display name, empty for [unknown].
  final String label;

  /// The type of a sheet cell: `cat…` → [catPiano], anything containing `loop`
  /// → [loop], `piano` / `keyboard` / `keytar/piano` → [piano],
  /// `improv` / `composition` → [improv].
  static PlayType parse(String cell) {
    final t = cell.trim().toLowerCase();
    if (t.startsWith('cat')) return catPiano;
    if (t.contains('loop')) return loop;
    if (t == 'piano' || t == 'keyboard' || t == 'keytar/piano') return piano;
    if (t == 'improv' || t == 'composition') return improv;
    return unknown;
  }
}

/// Whether a highlight has vocals ("Vocals?" column).
enum Vocals {
  unknown,
  yes,
  no;

  /// `yes` → [yes]; `no` and `no singing` → [no]; anything else (`-`, `?`,
  /// `Maybe`, `Yes/No`, `NA`, typos) → [unknown].
  static Vocals parse(String cell) => switch (cell.trim().toLowerCase()) {
    'yes' => yes,
    'no' || 'no singing' => no,
    _ => unknown,
  };
}

/// A special kind of request, from the Ong Log "Notes" column.
enum PlayFlag {
  none(''),
  tier3('Tier 3'),
  raffle('Raffle');

  const PlayFlag(this.label);

  /// English display name (the cell value), empty for [none].
  final String label;

  /// Exact (trimmed) `Tier 3` or `Raffle`.
  static PlayFlag parse(String cell) => switch (cell.trim()) {
    'Tier 3' => tier3,
    'Raffle' => raffle,
    _ => none,
  };
}

/// A calendar date without time zone, as written in the sheets.
///
/// Never converted between time zones: [toDateTime] is midnight UTC of that
/// day, only meant for formatting.
final class CalendarDate implements Comparable<CalendarDate> {
  const CalendarDate._(this.epochDay);

  /// The date `year-month-day`; throws [ArgumentError] when it does not exist.
  factory CalendarDate(int year, int month, int day) {
    final date = _tryCreate(year, month, day);
    if (date == null) throw ArgumentError('Invalid date $year-$month-$day');
    return date;
  }

  /// The date at [epochDay] days after 1970-01-01.
  const CalendarDate.fromEpochDay(this.epochDay);

  /// Days since 1970-01-01.
  final int epochDay;

  static CalendarDate? _tryCreate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (year >= 0 && year <= 9999) {
      // the dates of the sheets (one per row): integer arithmetic, DateTime goes through a JS Date on the web
      final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
      if (day > (month == 2 ? (leap ? 29 : 28) : _monthDays[month - 1])) return null;
      // days from the civil date (proleptic Gregorian), see http://howardhinnant.github.io/date_algorithms.html
      final y = month <= 2 ? year - 1 : year;
      final era = (y >= 0 ? y : y - 399) ~/ 400;
      final yearOfEra = y - era * 400;
      final dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) ~/ 5 + day - 1;
      final dayOfEra = yearOfEra * 365 + yearOfEra ~/ 4 - yearOfEra ~/ 100 + dayOfYear;
      return CalendarDate._(era * 146097 + dayOfEra - 719468);
    }
    final dt = DateTime.utc(year, month, day);
    if (dt.month != month || dt.day != day) return null;
    return CalendarDate._(dt.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay);
  }

  static const _monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  /// Parses a sheet cell: `2024-03-05`, `2024/3/5 21:07`, `3/5/2024 9:07`
  /// (month first), optionally followed by a time. Anything after the time,
  /// such as seconds, is ignored. Returns null when the cell is not a date.
  /// The time, when present, is `HH:MM`.
  static ({CalendarDate date, String time})? parseCell(String cell) {
    // Scans what `^(\d{4})[-/](\d{1,2})[-/](\d{1,2})` or `^(\d{1,2})/(\d{1,2})/(\d{4})`, then
    // `(?:\s+(\d{1,2}):(\d{2}))?` match, without regular expressions (one cell per row: they are slow on native
    // platforms). Every `\d{1,2}` is followed by a separator or by nothing, so taking digits greedily is exact.
    final text = cell.trim();
    int year, month, day, end;
    final yearDigits = _digits(text, 0, 4);
    final isoMonth = yearDigits == 4 && _isSeparator(text, 4) ? _digits(text, 5, 2) : 0;
    final isoDay = isoMonth > 0 && _isSeparator(text, 5 + isoMonth) ? _digits(text, 6 + isoMonth, 2) : 0;
    if (isoDay > 0) {
      year = _number(text, 0, 4);
      month = _number(text, 5, isoMonth);
      day = _number(text, 6 + isoMonth, isoDay);
      end = 6 + isoMonth + isoDay;
    } else {
      final m = _digits(text, 0, 2);
      final d = m > 0 && _hasAt(text, m, 0x2F) ? _digits(text, m + 1, 2) : 0;
      if (d == 0 || !_hasAt(text, m + 1 + d, 0x2F) || _digits(text, m + d + 2, 4) != 4) return null;
      month = _number(text, 0, m);
      day = _number(text, m + 1, d);
      year = _number(text, m + d + 2, 4);
      end = m + d + 6;
    }
    final date = _tryCreate(year, month, day);
    if (date == null) return null;
    var i = end;
    while (i < text.length && isRegExpSpace(text.codeUnitAt(i))) {
      i++;
    }
    final hours = i > end ? _digits(text, i, 2) : 0;
    if (hours == 0 || !_hasAt(text, i + hours, 0x3A) || _digits(text, i + hours + 1, 2) != 2) {
      return (date: date, time: '');
    }
    return (date: date, time: '${hours == 1 ? '0' : ''}${text.substring(i, i + hours + 3)}');
  }

  /// Whether `text[i]` is the code unit [unit].
  static bool _hasAt(String text, int i, int unit) => i < text.length && text.codeUnitAt(i) == unit;

  /// Whether `text[i]` is `-` or `/`.
  static bool _isSeparator(String text, int i) => _hasAt(text, i, 0x2D) || _hasAt(text, i, 0x2F);

  /// Number of ASCII digits at `text[i]`, at most [max].
  static int _digits(String text, int i, int max) {
    var n = 0;
    while (n < max && i + n < text.length) {
      final unit = text.codeUnitAt(i + n);
      if (unit < 0x30 || unit > 0x39) break;
      n++;
    }
    return n;
  }

  /// The value of the [length] ASCII digits at `text[i]`.
  static int _number(String text, int i, int length) {
    var value = 0;
    for (var k = i; k < i + length; k++) {
      value = value * 10 + text.codeUnitAt(k) - 0x30;
    }
    return value;
  }

  /// The date of a sheet cell, see [parseCell].
  static CalendarDate? tryParse(String cell) => parseCell(cell)?.date;

  DateTime _utc() => DateTime.fromMillisecondsSinceEpoch(epochDay * Duration.millisecondsPerDay, isUtc: true);

  int get year => _utc().year;
  int get month => _utc().month;
  int get day => _utc().day;

  /// [DateTime.monday] (1) to [DateTime.sunday] (7).
  int get weekday => _utc().weekday;

  /// Midnight UTC of this day, for formatting only.
  DateTime toDateTime() => _utc();

  /// `other - this` in days.
  int daysUntil(CalendarDate other) => other.epochDay - epochDay;

  /// `YYYY-MM-DD`.
  String toIso() {
    final d = _utc();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  bool operator <(CalendarDate other) => epochDay < other.epochDay;
  bool operator >(CalendarDate other) => epochDay > other.epochDay;

  @override
  int compareTo(CalendarDate other) => epochDay.compareTo(other.epochDay);

  @override
  bool operator ==(Object other) => other is CalendarDate && other.epochDay == epochDay;

  @override
  int get hashCode => epochDay.hashCode;

  @override
  String toString() => toIso();
}

/// One row of the "Youtube Catalogue" sheet: a video of a moment of a stream.
final class Highlight {
  /// Creates a highlight; normally only the parser does this.
  const Highlight({
    required this.id,
    required this.seq,
    required this.title,
    required this.songKey,
    required this.genre,
    required this.link,
    required this.youtubeId,
    required this.requesterId,
    required this.streamDate,
    required this.uploadDate,
    required this.vocals,
    required this.notes,
    required this.playId,
  });

  /// Index in `Catalogue.highlights` (sheet order, oldest upload first).
  final int id;

  /// The "Order" number shown as `#seq`; rows without a number carry the
  /// previous row's, so several highlights can share one.
  final int seq;

  /// Title, whitespace collapsed.
  final String title;

  /// [songKey] of [title]; empty when it has no letter or digit.
  final String songKey;

  final Genre genre;

  /// The "Link to Video" cell as written (may be empty or not YouTube).
  final String link;

  /// The 11-character YouTube video id found in [link] (`watch?v=` or
  /// `youtu.be/`), or null. Thumbnail: `https://i.ytimg.com/vi/<id>/mqdefault.jpg`.
  final String? youtubeId;

  /// Index in `Catalogue.requesters`: the "Requestor" cell or, when it is
  /// empty, the name in `requested by "name"` in [notes]. Null when nobody.
  final int? requesterId;

  /// The date of the stream the video comes from ("Stream Source"), if known.
  final CalendarDate? streamDate;

  /// The YouTube upload date ("Upload Date").
  final CalendarDate? uploadDate;

  final Vocals vocals;

  /// "Additional Notes", trimmed.
  final String notes;

  /// Index in `Catalogue.plays` of the Ong Log row this video shows: same
  /// [songKey], played within one day of [streamDate]. Null when unknown.
  final int? playId;

  /// [streamDate] if known, else [uploadDate]: the date to display.
  CalendarDate? get date => streamDate ?? uploadDate;

  /// Artist or work part of [title] (see [splitTitle]), may be empty.
  String get artist => splitTitle(title).artist;

  /// Track part of [title] (see [splitTitle]).
  String get track => splitTitle(title).track;

  /// `https://www.youtube.com/watch?v=<id>`, or [link] when there is no id.
  String get url => youtubeId == null ? link : 'https://www.youtube.com/watch?v=$youtubeId';

  /// What finds this highlight again in another catalogue ([id] does not):
  /// [seq], and [songKey] to tell apart the rows that share a [seq]. A change
  /// of case, accents or punctuation in the title keeps it; a renumbering or
  /// another wording of the title gives another key. Stored on the device (the
  /// favourites): a change of this format or of [songKey] forgets them.
  String get key => '$seq $songKey';

  @override
  String toString() => 'Highlight#$id(#$seq $title, $genre, ${date ?? '-'})';
}

/// One song played live: a row of the "Songs" sheet (the Ong Log).
final class Play {
  /// Creates a play; normally only the parser does this.
  const Play({
    required this.id,
    required this.time,
    required this.rowDate,
    required this.titleId,
    required this.title,
    required this.songKey,
    required this.genre,
    required this.type,
    required this.requesterId,
    required this.flag,
    required this.streamId,
    required this.highlightId,
  });

  /// Index in `Catalogue.plays` (sheet order, oldest first).
  final int id;

  /// Time of day written on the row, `HH:MM`, or empty.
  final String time;

  /// The date written on the row. Songs played after midnight carry the next
  /// day: display the stream's date (`Catalogue.streamOf(play).date`) instead.
  final CalendarDate rowDate;

  /// Index in `Catalogue.titles` (distinct titles as written).
  final int titleId;

  /// Title, whitespace collapsed.
  final String title;

  /// [songKey] of [title]; empty when it has no letter or digit.
  final String songKey;

  final Genre genre;
  final PlayType type;

  /// Index in `Catalogue.requesters`, or null when nobody requested it.
  final int? requesterId;

  final PlayFlag flag;

  /// Index in `Catalogue.streams` of the stream this song was played in.
  final int streamId;

  /// Index in `Catalogue.highlights` of a video of this play, or null.
  /// When several highlights point to it, the first one with a YouTube id.
  final int? highlightId;

  /// Artist or work part of [title] (see [splitTitle]), may be empty.
  String get artist => splitTitle(title).artist;

  /// Track part of [title] (see [splitTitle]).
  String get track => splitTitle(title).track;

  @override
  String toString() => 'Play#$id($rowDate $time $title, $genre, $type)';
}

/// A live stream: a contiguous run of plays after a "Stream Start" row.
final class LiveStream {
  /// Creates a stream; normally only the parser does this.
  const LiveStream({
    required this.id,
    required this.date,
    required this.firstPlayId,
    required this.playCount,
    required this.durationMinutes,
    required this.highlightIds,
  });

  /// Index in `Catalogue.streams` (oldest first).
  final int id;

  /// The day the stream started.
  final CalendarDate date;

  /// Id of its first play; its plays are `firstPlayId .. firstPlayId + playCount - 1`.
  final int firstPlayId;

  /// Number of plays, at least 1.
  final int playCount;

  /// Length in minutes: the largest "Uptime" (`h:mm:ss`) of its rows, 0 if none.
  final int durationMinutes;

  /// Ids of the highlights linked to one of its plays, ascending.
  final List<int> highlightIds;

  /// Id of its last play.
  int get lastPlayId => firstPlayId + playCount - 1;

  /// Ids of its plays, in order.
  Iterable<int> get playIds => Iterable.generate(playCount, (i) => firstPlayId + i);

  @override
  String toString() => 'LiveStream#$id($date, $playCount plays, $durationMinutes min)';
}

/// All plays and highlights sharing one [songKey].
final class Song {
  /// Creates a song; normally only the parser does this.
  const Song({
    required this.key,
    required this.title,
    required this.genre,
    required this.playIds,
    required this.highlightIds,
    required this.firstPlayed,
    required this.lastPlayed,
  });

  /// The [songKey], never empty.
  final String key;

  /// Display title: as written on its latest play, else on its first highlight.
  final String title;

  /// The latest known genre other than [Genre.other] (plays first, then highlights).
  final Genre genre;

  /// Ids of its plays, oldest first. May be empty (a video never logged).
  final List<int> playIds;

  /// Ids of its highlights, oldest first. May be empty.
  final List<int> highlightIds;

  /// Stream date of its first play, null when never logged.
  final CalendarDate? firstPlayed;

  /// Stream date of its latest play, null when never logged.
  final CalendarDate? lastPlayed;

  String get artist => splitTitle(title).artist;
  String get track => splitTitle(title).track;

  @override
  String toString() => 'Song($key, ${playIds.length} plays, ${highlightIds.length} videos)';
}

/// Somebody who requested songs. Names are merged case- and accent-insensitively.
final class Requester {
  /// Creates a requester; normally only the parser does this.
  const Requester({required this.id, required this.name, required this.folded, required this.requestCount});

  /// Index in `Catalogue.requesters`.
  final int id;

  /// The most frequent spelling in the sheets.
  final String name;

  /// [fold] of [name]: the merge and lookup key.
  final String folded;

  /// Number of plays they requested (highlights not counted).
  final int requestCount;

  @override
  String toString() => 'Requester#$id($name, $requestCount)';
}
