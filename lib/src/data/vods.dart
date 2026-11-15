/// The full recordings of the streams (the VODs) and the links from a play to its moment in them.
///
/// Pure Dart. The VODs are unlisted YouTube videos, listed by `vods.tsv`, a file of the branch `data` of the
/// repository (see its README.md), downloaded and kept as the sheets are (`DataFiles`). A line of the file names a
/// stream by the date of its start in Sydney, that of the title of the VOD, and its rank among the streams of that
/// date ([StreamKey]); a play is opened at its uptime, moved by the offset `offsets.tsv` gives it when the recording
/// does not start with the stream ([OffsetFile]), in the part of the VOD it falls in ([VodLinks]).
library;

import 'catalogue.dart';
import 'model.dart';
import 'sydney_zone.dart';
import 'vod_offsets.dart';

/// A stream as `vods.tsv` names it: the date of its start in Sydney, and its rank among the streams of the sheet
/// that started on that date (1 for the first). Written `2022-05-08`, `2022-05-08#2` for the second.
final class StreamKey {
  /// The key of the [rank]th stream of [date] (rank 1 or more).
  const StreamKey(this.date, [this.rank = 1]);

  final CalendarDate date;
  final int rank;

  /// The key of a `date` cell of `vods.tsv`: `YYYY-MM-DD`, optionally followed by `#` and a rank (`#1` is the first,
  /// as no rank). Null for anything else, an empty cell among them.
  static StreamKey? tryParse(String cell) {
    final text = cell.trim();
    if (text.length < 10 || !_isDate(text)) return null;
    var rank = 1;
    if (text.length > 10) {
      if (text.codeUnitAt(10) != 0x23 || text.length == 11) return null;
      final digits = text.substring(11);
      if (!_allDigits(digits) || digits.length > 4) return null;
      rank = int.parse(digits);
      if (rank < 1) return null;
    }
    final date = CalendarDate.parseCell(text.substring(0, 10));
    // (parseCell also reads 2024/3/5: the file has one form)
    if (date == null || date.minute != null || date.date.toIso() != text.substring(0, 10)) return null;
    return StreamKey(date.date, rank);
  }

  static bool _isDate(String text) {
    for (var i = 0; i < 10; i++) {
      final unit = text.codeUnitAt(i);
      final dash = i == 4 || i == 7;
      if (dash ? unit != 0x2D : unit < 0x30 || unit > 0x39) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) => other is StreamKey && other.date == date && other.rank == rank;

  @override
  int get hashCode => Object.hash(date, rank);

  /// As written in `vods.tsv`.
  @override
  String toString() => rank == 1 ? date.toIso() : '${date.toIso()}#$rank';
}

bool _allDigits(String text) {
  if (text.isEmpty) return false;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit < 0x30 || unit > 0x39) return false;
  }
  return true;
}

/// One line of `vods.tsv` that reads: a video, the stream it records and which part of it it is.
final class VodLine {
  /// Creates a line; normally only [VodFile.parse] does this.
  const VodLine({
    required this.lineNumber,
    required this.key,
    required this.part,
    required this.id,
    required this.seconds,
    this.posted = '',
    this.title = '',
  });

  /// Its line in the file, from 1.
  final int lineNumber;

  /// The stream it records.
  final StreamKey key;

  /// 1 for the only video of a stream or the first of several, 2 for the second...
  final int part;

  /// The YouTube video id (11 characters).
  final String id;

  /// The length of the video in whole seconds, null when unknown.
  final int? seconds;

  /// When the link was posted on Discord, as written (information only).
  final String posted;

  /// The title of the video (information only).
  final String title;

  @override
  String toString() => 'VodLine#$lineNumber($key part $part $id ${seconds ?? '?'} s)';
}

/// A line of `vods.tsv` that does not count, and why: for the check of the file (`tool/vods_check.dart`).
typedef VodFileNote = ({int lineNumber, String reason, String text});

/// The content of `vods.tsv`: its lines that read, the VOD of each stream.
///
/// Read tolerantly: a line that does not read is left out ([ignored] says why), never an error for the whole file.
/// The file: UTF-8, tab-separated, a header line, then one line per video: `date`, `part`, `id`, `seconds`, `posted`,
/// `title`. Lines beginning with `#` and blank lines are ignored, and the columns after the sixth.
final class VodFile {
  VodFile._(this.lines, this.ignored, this.notes, this.replaced, this.afterHole, this._vods);

  /// A file without any line.
  static final empty = VodFile.parse('');

  /// Whether [text] is a `vods.tsv` at all: its first line that is neither blank nor a comment is the header, which
  /// begins with the cells `date`, `part`, `id` (trimmed, any case). Anything else (a message of a proxy, a page of
  /// an error answered with status 200) is no file, not a file without VOD: a download of it counts as failed. The
  /// header alone is a real file without any line.
  static bool isFile(String text) {
    for (var line in text.split('\n')) {
      if (line.startsWith('\uFEFF')) line = line.substring(1);
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final cells = line.split('\t');
      return cells.length >= 3 &&
          cells[0].trim().toLowerCase() == 'date' &&
          cells[1].trim().toLowerCase() == 'part' &&
          cells[2].trim().toLowerCase() == 'id';
    }
    return false;
  }

  /// Reads [text], the content of `vods.tsv`.
  factory VodFile.parse(String text) {
    final lines = <VodLine>[];
    final ignored = <VodFileNote>[];
    final notes = <VodFileNote>[];
    final rows = text.split('\n');
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      if (i == 0 && row.startsWith('\uFEFF')) row = row.substring(1);
      if (row.endsWith('\r')) row = row.substring(0, row.length - 1);
      final number = i + 1;
      if (row.trim().isEmpty || row.trimLeft().startsWith('#')) continue;
      final cells = row.split('\t');
      // the header (written first, but any line naming the columns is no video)
      if (cells.first.trim().toLowerCase() == 'date') continue;
      void ignore(String reason) => ignored.add((lineNumber: number, reason: reason, text: row));
      if (cells.length < 3) {
        ignore('fewer than three columns');
        continue;
      }
      final dateCell = cells[0].trim();
      final id = cells[2].trim();
      final partCell = cells[1].trim();
      if (!_isVideoId(id)) {
        ignore('the id is not 11 characters of A-Z a-z 0-9 _ -');
        continue;
      }
      if (!_allDigits(partCell) || partCell.length > 4 || int.parse(partCell) < 1) {
        ignore('the part is not a positive integer');
        continue;
      }
      if (dateCell.isEmpty) {
        ignore('no date');
        continue;
      }
      final key = StreamKey.tryParse(dateCell);
      if (key == null) {
        ignore('the date does not read (YYYY-MM-DD, or YYYY-MM-DD#2)');
        continue;
      }
      final secondsCell = cells.length > 3 ? cells[3].trim() : '';
      int? seconds;
      if (secondsCell.isNotEmpty) {
        // at most a year: beyond, no video
        if (_allDigits(secondsCell) && secondsCell.length <= 8 && int.parse(secondsCell) > 0) {
          seconds = int.parse(secondsCell);
        } else {
          notes.add((lineNumber: number, reason: 'the duration does not read: taken as unknown', text: row));
        }
      }
      lines.add(
        VodLine(
          lineNumber: number,
          key: key,
          part: int.parse(partCell),
          id: id,
          seconds: seconds,
          posted: cells.length > 4 ? cells[4].trim() : '',
          title: cells.length > 5 ? cells[5].trim() : '',
        ),
      );
    }
    // the later line of a stream and part wins
    final byPart = <StreamKey, Map<int, VodLine>>{};
    final replaced = <(VodLine, VodLine)>[];
    for (final line in lines) {
      final parts = byPart.putIfAbsent(line.key, () => {});
      final previous = parts[line.part];
      if (previous != null) replaced.add((previous, line));
      parts[line.part] = line;
    }
    // parts 1..n without a hole
    final vods = <StreamKey, List<VodLine>>{};
    final afterHole = <VodLine>[];
    byPart.forEach((key, parts) {
      final vod = <VodLine>[];
      for (var next = parts[1]; next != null; next = parts[vod.length + 1]) {
        vod.add(next);
      }
      for (final line in parts.values) {
        if (line.part > vod.length) afterHole.add(line);
      }
      if (vod.isNotEmpty) vods[key] = List.unmodifiable(vod);
    });
    afterHole.sort((a, b) => a.lineNumber.compareTo(b.lineNumber));
    return VodFile._(
      List.unmodifiable(lines),
      List.unmodifiable(ignored),
      List.unmodifiable(notes),
      List.unmodifiable(replaced),
      List.unmodifiable(afterHole),
      vods,
    );
  }

  static bool _isVideoId(String id) {
    if (id.length != 11) return false;
    for (var i = 0; i < id.length; i++) {
      final unit = id.codeUnitAt(i);
      final ok =
          (unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x5A) ||
          (unit >= 0x61 && unit <= 0x7A) ||
          unit == 0x5F ||
          unit == 0x2D;
      if (!ok) return false;
    }
    return true;
  }

  /// The lines that read, in their order.
  final List<VodLine> lines;

  /// The lines left out, and why (comments, blank lines and the header are not among them).
  final List<VodFileNote> ignored;

  /// The lines that read with something left out: a duration that does not read.
  final List<VodFileNote> notes;

  /// The lines replaced by a later one of the same stream and part: (the earlier, the later).
  final List<(VodLine, VodLine)> replaced;

  /// The parts that come after a missing part of their stream: left out.
  final List<VodLine> afterHole;

  final Map<StreamKey, List<VodLine>> _vods;

  /// The streams that have a VOD.
  Iterable<StreamKey> get keys => _vods.keys;

  /// The VOD of the stream [key]: its parts 1..n, or null when the file has none for it.
  List<VodLine>? vodOf(StreamKey key) => _vods[key];

  /// Whether the file names no stream.
  bool get isEmpty => _vods.isEmpty;
}

/// The key of each stream of [catalogue], by id ([StreamKey]): the date in Sydney of the instant of its "Stream
/// Start" row (`LiveStream.startMinute`), or its date as written when the row gives no time; its rank among the
/// streams of that date, in the order of the sheet.
List<StreamKey> streamKeys(Catalogue catalogue) {
  final ranks = <CalendarDate, int>{};
  return [
    for (final s in catalogue.streams)
      () {
        final minute = s.startMinute;
        final date = minute == null ? s.date : SydneyZone.dateOf(minute);
        final rank = ranks[date] = (ranks[date] ?? 0) + 1;
        return StreamKey(date, rank);
      }(),
  ];
}

/// Where a play is in a VOD: its part (from 1), the video, and the second in it.
typedef VodPosition = ({int part, VodLine video, int seconds});

/// The VODs of the streams of one catalogue: the link of each play and of each stream. Valid only with the catalogue
/// it was made for, as its ids.
final class VodLinks {
  /// The VODs [file] gives the streams of [catalogue], with the offsets of [offsets] (none when null).
  VodLinks(this.catalogue, this.file, [OffsetFile? offsets])
    : offsets = offsets ?? OffsetFile.empty,
      keys = streamKeys(catalogue) {
    _vods = [for (final key in keys) file.vodOf(key)];
    _offsets = [for (final key in keys) this.offsets.of(key)];
  }

  final Catalogue catalogue;
  final VodFile file;
  final OffsetFile offsets;

  /// The key of each stream, by id.
  final List<StreamKey> keys;

  late final List<List<VodLine>?> _vods;
  late final List<StreamOffsets?> _offsets;

  /// The parts of the VOD of [stream], null when it has none.
  List<VodLine>? vodOf(LiveStream stream) => _vods[stream.id];

  /// The offsets of [stream] that count, null when `offsets.tsv` has none for it.
  StreamOffsets? offsetsOf(LiveStream stream) => _offsets[stream.id];

  /// The line of `offsets.tsv` that applies to [play] ([StreamOffsets.at]), null when none does (its offset is 0) or
  /// the play has no uptime (or `0:00:00`).
  VodOffset? offsetOf(Play play) {
    final uptime = catalogue.uptimeOf(play);
    if (uptime == null || uptime == 0) return null;
    return _offsets[play.streamId]?.at(uptime);
  }

  /// Where [play] is in the VOD of its stream, or null: at its uptime `u` plus its offset ([offsetOf], 0 when none
  /// applies), placed in the parts by [placeInVod]. No margin is added: the uptimes are those the moderators typed.
  /// None when the stream has no VOD, the play no uptime (or `0:00:00`, the placeholder of the rows typed without one:
  /// no song starts a stream), the position is negative (before the start of the recording), or [placeInVod] places
  /// it nowhere.
  VodPosition? positionOf(Play play) {
    final vod = _vods[play.streamId];
    final uptime = catalogue.uptimeOf(play);
    if (vod == null || uptime == null || uptime == 0) return null;
    return placeInVod(vod, uptime + (offsetOf(play)?.seconds ?? 0));
  }

  /// The link of [play] in the VOD of its stream ([positionOf]), or null.
  Uri? linkOf(Play play) {
    final at = positionOf(play);
    return at == null ? null : vodUrl(at.video.id, at.seconds);
  }

  /// The links of the parts of the VOD of [stream], each from its start; empty when it has none. The first is the
  /// stream's.
  List<Uri> streamLinks(LiveStream stream) => [
    for (final part in _vods[stream.id] ?? const <VodLine>[]) vodUrl(part.id),
  ];
}

/// Where the position [at] (seconds from the start of the VOD, all its parts end to end) is in [vod], or null: in
/// part 1 at [at] when it is before the end of part 1, or when the VOD has one part; otherwise in part 2 at [at] minus
/// the length of part 1, when that is before the end of part 2 or part 2 is the last; and so on: the parts follow each
/// other without a gap. Null when [at] is negative (before the start of the recording), a length needed for the
/// subtraction is unknown, or the position is not before the end of a part whose length is known.
VodPosition? placeInVod(List<VodLine> vod, int at) {
  if (at < 0) return null;
  for (var i = 0; i < vod.length; i++) {
    final length = vod[i].seconds;
    if (i == vod.length - 1) return length == null || at < length ? (part: i + 1, video: vod[i], seconds: at) : null;
    if (length == null) return null;
    if (at < length) return (part: i + 1, video: vod[i], seconds: at);
    at -= length;
  }
  return null;
}

/// `https://youtu.be/<id>?t=<seconds>`, without `t` at 0.
Uri vodUrl(String id, [int seconds = 0]) =>
    Uri.parse(seconds > 0 ? 'https://youtu.be/$id?t=$seconds' : 'https://youtu.be/$id');
