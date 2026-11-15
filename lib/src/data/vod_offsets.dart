/// The offsets of the VODs: where a play is in a recording that does not start with its stream.
///
/// Pure Dart. `offsets.tsv`, a file of the branch `data` beside `vods.tsv` (see its README.md), downloaded and kept
/// as it is (`DataFiles`), gives a stream, or the plays of a stream from an uptime on, or the plays of one exact
/// uptime, a number of seconds added to their uptime to give their position in the VOD ([OffsetFile]). Written by
/// the tool of the browser extension, one stream at a time ([OffsetFile.replace]); read by `VodLinks`.
library;

import 'vods.dart';

/// What the plays of a stream a line of `offsets.tsv` is for: its `uptime` cell.
enum VodOffsetKind {
  /// The whole stream (an empty cell, or `0:00:00+`).
  stream,

  /// The plays from an uptime on (`h:mm:ss+`): uptime at least it.
  from,

  /// The plays of exactly that uptime (`h:mm:ss`), and only them.
  play,
}

/// An offset: the seconds added to the uptime of the plays it is for ([kind], [uptime]) to give their position in
/// the VOD (all its parts end to end). Negative when the recording starts after the stream.
final class VodOffset {
  /// An offset of [seconds] for the plays [kind] and [uptime] say ([uptime] null for the whole stream, and only
  /// then). A [VodOffsetKind.from] of uptime 0 is the whole stream: made one.
  factory VodOffset({required VodOffsetKind kind, int? uptime, required int seconds, String note = ''}) {
    if ((kind == VodOffsetKind.stream) != (uptime == null)) {
      throw ArgumentError.value(uptime, 'uptime', 'null for the whole stream, and only then');
    }
    if (uptime != null && (uptime < 0 || uptime > maxVodOffsetUptime)) {
      throw RangeError.range(uptime, 0, maxVodOffsetUptime, 'uptime');
    }
    if (seconds.abs() > maxVodOffsetSeconds) {
      throw RangeError.range(seconds, -maxVodOffsetSeconds, maxVodOffsetSeconds, 'seconds');
    }
    if (kind == VodOffsetKind.from && uptime == 0) return VodOffset._(VodOffsetKind.stream, null, seconds, note);
    return VodOffset._(kind, uptime, seconds, note);
  }

  const VodOffset._(this.kind, this.uptime, this.seconds, this.note);

  final VodOffsetKind kind;

  /// The uptime of the line in seconds, null for the whole stream.
  final int? uptime;

  /// Added to the uptime of the plays it is for.
  final int seconds;

  /// Free text (information only).
  final String note;

  /// Whether [other] is for the same plays: of the same `uptime` cell (the later line of a stream wins).
  bool sameCell(VodOffset other) => other.kind == kind && other.uptime == uptime;

  /// Its `uptime` cell: empty, `h:mm:ss+` or `h:mm:ss`.
  String get uptimeCell => switch (kind) {
    VodOffsetKind.stream => '',
    VodOffsetKind.from => '${formatVodUptime(uptime!)}+',
    VodOffsetKind.play => formatVodUptime(uptime!),
  };

  @override
  bool operator ==(Object other) =>
      other is VodOffset && sameCell(other) && other.seconds == seconds && other.note == note;

  @override
  int get hashCode => Object.hash(kind, uptime, seconds, note);

  @override
  String toString() => 'VodOffset(${kind.name} ${uptime ?? '-'} ${seconds >= 0 ? '+' : ''}$seconds)';
}

/// The largest offset either way, in seconds: a day. Beyond, the cell does not read.
const int maxVodOffsetSeconds = 86400;

/// The largest uptime of a line, in seconds (99,999 hours): beyond, the cell does not read.
const int maxVodOffsetUptime = 99999 * 3600 + 59 * 60 + 59;

/// [seconds] as `h:mm:ss`, as the uptimes of the Songs sheet are written.
String formatVodUptime(int seconds) {
  final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60, s = seconds % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// One line of `offsets.tsv` that reads.
final class VodOffsetLine {
  /// Creates a line; normally only [OffsetFile.parse] does this.
  const VodOffsetLine({required this.lineNumber, required this.key, required this.offset});

  /// Its line in the file, from 1.
  final int lineNumber;

  /// The stream it is for.
  final StreamKey key;

  final VodOffset offset;

  @override
  String toString() => 'VodOffsetLine#$lineNumber($key $offset)';
}

/// The offsets of one stream that count: for each `uptime` cell, the last line of it.
final class StreamOffsets {
  StreamOffsets._(List<VodOffset> offsets) : lines = List.unmodifiable(_sorted(offsets)) {
    for (final o in lines) {
      switch (o.kind) {
        case VodOffsetKind.stream:
          _whole = o;
        case VodOffsetKind.from:
          _from.add(o);
        case VodOffsetKind.play:
          _exact[o.uptime!] = o;
      }
    }
  }

  static List<VodOffset> _sorted(List<VodOffset> offsets) => [...offsets]..sort(_byUptime);

  /// The whole stream first, then by uptime, a "from" line before the line of exactly its uptime.
  static int _byUptime(VodOffset a, VodOffset b) {
    final ua = a.uptime ?? -1, ub = b.uptime ?? -1;
    return ua != ub ? ua.compareTo(ub) : a.kind.index.compareTo(b.kind.index);
  }

  /// The lines that count, in order of uptime ([VodOffsetKind.stream] first; at one uptime, "from" before "play").
  final List<VodOffset> lines;

  VodOffset? _whole;

  /// The "from" lines, by uptime.
  final List<VodOffset> _from = [];
  final Map<int, VodOffset> _exact = {};

  /// The offset of a play of [uptime] (seconds), or null when none applies (its offset is then 0):
  /// 1. the line of exactly [uptime];
  /// 2. else the "from" line of the largest uptime at most [uptime], the whole-stream line counting as from 0;
  /// 3. else none.
  VodOffset? at(int uptime) {
    final exact = _exact[uptime];
    if (exact != null) return exact;
    // the last "from" line at or before the uptime
    var low = 0, high = _from.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_from[mid].uptime! <= uptime) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low > 0 ? _from[low - 1] : _whole;
  }
}

/// A line of `offsets.tsv` that does not count, and why: for the check of the file (`tool/vods_check.dart`).
typedef OffsetFileNote = VodFileNote;

/// The content of `offsets.tsv`: its lines that read, the offsets of each stream.
///
/// Read tolerantly, as `vods.tsv` ([VodFile]): a line that does not read is left out ([ignored] says why), never an
/// error for the whole file. The file: UTF-8, tab-separated, a header line ([header]), then one line per offset:
/// - `date`: the stream, as the `date` cell of `vods.tsv` ([StreamKey]);
/// - `uptime`: empty for the whole stream, `h:mm:ss+` for the plays from that uptime on, `h:mm:ss` for the plays of
///   exactly that uptime; `0:00:00+` is the whole stream;
/// - `offset`: whole seconds, signed (`-1140`, `+12`, `0`), at most a day either way ([maxVodOffsetSeconds]);
/// - `note`: free text.
///
/// Lines beginning with `#` and blank lines are ignored, and the columns after the fourth. When two lines name the
/// same stream and `uptime` cell, the later one wins ([replaced]).
final class OffsetFile {
  OffsetFile._(this.lines, this.ignored, this.replaced, this._streams);

  /// The header of the file.
  static const header = 'date\tuptime\toffset\tnote';

  /// A file without any line.
  static final empty = OffsetFile.parse('');

  /// Whether [text] is an `offsets.tsv` at all: its first line that is neither blank nor a comment is the header,
  /// which begins with the cells `date`, `uptime`, `offset` (trimmed, any case). Anything else is no file (a failed
  /// download), not a file without offset. The header alone is a real file without any line.
  static bool isFile(String text) {
    for (var line in text.split('\n')) {
      if (line.startsWith('﻿')) line = line.substring(1);
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final cells = line.split('\t');
      return cells.length >= 3 &&
          cells[0].trim().toLowerCase() == 'date' &&
          cells[1].trim().toLowerCase() == 'uptime' &&
          cells[2].trim().toLowerCase() == 'offset';
    }
    return false;
  }

  /// Reads [text], the content of `offsets.tsv`.
  factory OffsetFile.parse(String text) {
    final lines = <VodOffsetLine>[];
    final ignored = <OffsetFileNote>[];
    final rows = text.split('\n');
    for (var i = 0; i < rows.length; i++) {
      final row = _clean(rows[i], i);
      final read = _readRow(row, i + 1);
      switch (read) {
        case VodOffsetLine():
          lines.add(read);
        case String():
          ignored.add((lineNumber: i + 1, reason: read, text: row));
        case null:
          break;
      }
    }
    // the later line of a stream and uptime cell wins
    final byStream = <StreamKey, List<VodOffsetLine>>{};
    final replaced = <(VodOffsetLine, VodOffsetLine)>[];
    for (final line in lines) {
      final ofStream = byStream.putIfAbsent(line.key, () => []);
      final at = ofStream.indexWhere((l) => l.offset.sameCell(line.offset));
      if (at < 0) {
        ofStream.add(line);
      } else {
        replaced.add((ofStream[at], line));
        ofStream[at] = line;
      }
    }
    return OffsetFile._(List.unmodifiable(lines), List.unmodifiable(ignored), List.unmodifiable(replaced), {
      for (final MapEntry(:key, :value) in byStream.entries) key: StreamOffsets._([for (final l in value) l.offset]),
    });
  }

  /// [row] without its line end and, on the first line, the byte order mark.
  static String _clean(String row, int index) {
    if (index == 0 && row.startsWith('﻿')) row = row.substring(1);
    if (row.endsWith('\r')) row = row.substring(0, row.length - 1);
    return row;
  }

  /// The line [row] (number [number]) gives: a [VodOffsetLine], the reason why it is ignored (a [String]), or null
  /// for a blank line, a comment or the header.
  static Object? _readRow(String row, int number) {
    if (row.trim().isEmpty || row.trimLeft().startsWith('#')) return null;
    final cells = row.split('\t');
    // the header (written first, but any line naming the columns is no offset)
    if (cells.first.trim().toLowerCase() == 'date') return null;
    if (cells.length < 3) return 'fewer than three columns';
    final dateCell = cells[0].trim();
    if (dateCell.isEmpty) return 'no date';
    final key = StreamKey.tryParse(dateCell);
    if (key == null) return 'the date does not read (YYYY-MM-DD, or YYYY-MM-DD#2)';
    final uptimeCell = cells[1].trim();
    final VodOffsetKind kind;
    int? uptime;
    if (uptimeCell.isEmpty) {
      kind = VodOffsetKind.stream;
    } else {
      final from = uptimeCell.endsWith('+');
      uptime = _readUptime(from ? uptimeCell.substring(0, uptimeCell.length - 1) : uptimeCell);
      if (uptime == null) return 'the uptime does not read (empty, h:mm:ss+ or h:mm:ss)';
      kind = from ? VodOffsetKind.from : VodOffsetKind.play;
    }
    final seconds = _readOffset(cells[2].trim());
    if (seconds == null) return 'the offset does not read (whole seconds, at most a day either way)';
    final note = cells.length > 3 ? cells[3].trim() : '';
    return VodOffsetLine(
      lineNumber: number,
      key: key,
      offset: VodOffset(kind: kind, uptime: uptime, seconds: seconds, note: note),
    );
  }

  /// `h:mm:ss` (minutes and seconds below 60) in seconds, or null.
  static int? _readUptime(String cell) {
    final parts = cell.split(':');
    if (parts.length != 3) return null;
    final [h, m, s] = parts;
    if (!_digits(h, 1, 5) || !_digits(m, 2, 2) || !_digits(s, 2, 2)) return null;
    final minutes = int.parse(m), seconds = int.parse(s);
    if (minutes > 59 || seconds > 59) return null;
    return int.parse(h) * 3600 + minutes * 60 + seconds;
  }

  /// Whole seconds, signed (`-1140`, `+12`, `0`), at most [maxVodOffsetSeconds] either way, or null.
  static int? _readOffset(String cell) {
    final sign = cell.startsWith('-') ? -1 : 1;
    final digits = cell.startsWith('-') || cell.startsWith('+') ? cell.substring(1) : cell;
    if (!_digits(digits, 1, 6)) return null;
    final value = int.parse(digits);
    return value > maxVodOffsetSeconds ? null : sign * value;
  }

  static bool _digits(String text, int min, int max) {
    if (text.length < min || text.length > max) return false;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit < 0x30 || unit > 0x39) return false;
    }
    return true;
  }

  /// The lines that read, in their order.
  final List<VodOffsetLine> lines;

  /// The lines left out, and why (comments, blank lines and the header are not among them).
  final List<OffsetFileNote> ignored;

  /// The lines replaced by a later one of the same stream and `uptime` cell: (the earlier, the later).
  final List<(VodOffsetLine, VodOffsetLine)> replaced;

  final Map<StreamKey, StreamOffsets> _streams;

  /// The streams that have an offset line.
  Iterable<StreamKey> get keys => _streams.keys;

  /// The offsets of the stream [key], or null when the file has none for it.
  StreamOffsets? of(StreamKey key) => _streams[key];

  /// Whether the file names no stream.
  bool get isEmpty => _streams.isEmpty;

  /// The text of `offsets.tsv` [text] with the lines of the stream [key] replaced by [offsets]: its lines that read
  /// are removed and the new ones written where the first of them was, or at the end of the file; every other line,
  /// comment and blank line stays byte for byte, a line of the stream that does not read among them. [offsets] is
  /// written as [StreamOffsets.lines] would list it, the last of a same `uptime` cell only; the note on one line
  /// (tabs and line breaks made spaces). An empty [text] (no file yet) gives a file of its header and the new lines.
  ///
  /// Throws a [FormatException] when [text] is not empty and is no `offsets.tsv` ([isFile]).
  static String replace(String text, StreamKey key, Iterable<VodOffset> offsets) {
    final kept = <VodOffset>[];
    for (final o in offsets) {
      kept.removeWhere(o.sameCell);
      kept.add(o);
    }
    final written = [for (final o in StreamOffsets._(kept).lines) _format(key, o)];
    if (text.trim().isEmpty) return '${[header, ...written].join('\n')}\n';
    if (!isFile(text)) throw const FormatException('Not an offsets.tsv: its first line is not its header');
    final rows = text.split('\n');
    final out = <String>[];
    var placed = false;
    for (var i = 0; i < rows.length; i++) {
      final read = _readRow(_clean(rows[i], i), i + 1);
      if (read is VodOffsetLine && read.key == key) {
        if (!placed) out.addAll(written);
        placed = true;
        continue;
      }
      out.add(rows[i]);
    }
    if (!placed && written.isNotEmpty) {
      // at the end: before the empty string after the last line end, or after a last line without one
      if (out.last.isEmpty) {
        out.insertAll(out.length - 1, written);
      } else {
        out
          ..addAll(written)
          ..add('');
      }
    }
    return out.join('\n');
  }

  static String _format(StreamKey key, VodOffset o) {
    final note = o.note.replaceAll(RegExp(r'[\t\r\n]'), ' ').trim();
    return '$key\t${o.uptimeCell}\t${o.seconds}\t$note';
  }
}
