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
    final dt = DateTime.utc(year, month, day);
    if (dt.month != month || dt.day != day) return null;
    return CalendarDate._(dt.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay);
  }

  static final _isoLike = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?');
  static final _usLike = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{2}))?');

  /// Parses a sheet cell: `2024-03-05`, `2024/3/5 21:07`, `3/5/2024 9:07`
  /// (month first), optionally followed by a time. Anything after the time,
  /// such as seconds, is ignored. Returns null when the cell is not a date.
  /// The time, when present, is `HH:MM`.
  static ({CalendarDate date, String time})? parseCell(String cell) {
    final text = cell.trim();
    int year, month, day;
    String? hours, minutes;
    var m = _isoLike.firstMatch(text);
    if (m != null) {
      year = int.parse(m[1]!);
      month = int.parse(m[2]!);
      day = int.parse(m[3]!);
    } else {
      m = _usLike.firstMatch(text);
      if (m == null) return null;
      month = int.parse(m[1]!);
      day = int.parse(m[2]!);
      year = int.parse(m[3]!);
    }
    hours = m[4];
    minutes = m[5];
    final date = _tryCreate(year, month, day);
    if (date == null) return null;
    return (date: date, time: hours == null ? '' : '${hours.padLeft(2, '0')}:$minutes');
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
