// Checks a vods.tsv (the file of the branch data) against the two sheets, with the app's own code: what the app
// will link, and what a human should look at.
//
//   dart run tool/vods_check.dart <highlights.csv> <songs.csv> <vods.tsv> [<offsets.tsv>]
//
// The sheets as Google exports them (gviz CSV, see tool/sheets_snapshot.sh), or the copies of the branch
// sheets-snapshot; offsets.tsv, the offsets of the VODs, when given (none otherwise). Prints:
// - the streams with a VOD and without, per year;
// - the plays that get a link, and why the others of the streams with a VOD get none (with the offsets);
// - the VOD lines that match no stream, with the streams of the days around;
// - the dates of several streams, with their VODs;
// - the lines left out and why, those replaced by a later one, the parts after a hole;
// - the parts whose missing duration blocks links;
// - the streams longer than their VOD (the largest uptime of their rows, markers included, past the end of the last
//   part: their lengths, whatever the offsets);
// - with offsets.tsv: its lines left out and why, those replaced by a later one, those naming a stream that has no
//   VOD (or no stream) or an exact uptime that no play of the stream has, and the plays that get no link because
//   their offset puts them before the start of the recording.
//
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:ong_music/src/data/model.dart';
import 'package:ong_music/src/data/parser.dart';
import 'package:ong_music/src/data/sheet_zone.dart';
import 'package:ong_music/src/data/vod_offsets.dart';
import 'package:ong_music/src/data/vods.dart';

void main(List<String> args) {
  if (args.length != 3 && args.length != 4) {
    stderr.writeln('usage: dart run tool/vods_check.dart <highlights.csv> <songs.csv> <vods.tsv> [<offsets.tsv>]');
    exit(64);
  }
  final catalogue = parseCatalogue(File(args[0]).readAsStringSync(), File(args[1]).readAsStringSync());
  final file = VodFile.parse(File(args[2]).readAsStringSync());
  final offsetsText = args.length > 3 ? File(args[3]).readAsStringSync() : null;
  if (offsetsText != null && offsetsText.trim().isNotEmpty && !OffsetFile.isFile(offsetsText)) {
    stderr.writeln('${args[3]} is no offsets.tsv: its first line is not its header (${OffsetFile.header})');
    exit(65);
  }
  final offsets = offsetsText == null ? null : OffsetFile.parse(offsetsText);
  final links = VodLinks(catalogue, file, offsets);
  final keys = links.keys;
  final streamsByKey = {for (final s in catalogue.streams) keys[s.id]: s};

  String start(LiveStream s) {
    final minute = s.startMinute;
    if (minute == null) return '${s.date} (no time)';
    final wall = SheetZone.wallTime(
      DateTime.fromMillisecondsSinceEpoch(minute * Duration.millisecondsPerMinute, isUtc: true),
    );
    return '${wall.toIso8601String().substring(0, 16).replaceFirst('T', ' ')} ET';
  }

  String duration(int? seconds) {
    if (seconds == null) return '?';
    final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60, s = seconds % 60;
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String describe(LiveStream s) =>
      '${keys[s.id]}  started ${start(s)}, ${s.playCount} plays, length ${duration(s.durationSeconds)}';

  String line(VodLine l) =>
      '    line ${l.lineNumber}: part ${l.part} ${l.id} ${duration(l.seconds)} posted ${l.posted}  ${l.title}';

  // ---------------------------------------------------------------- per year
  print('Streams with a VOD, per year (year of the stream\'s date in the sheet)');
  final years = <int, List<int>>{};
  for (final s in catalogue.streams) {
    final counts = years.putIfAbsent(s.date.year, () => [0, 0]);
    counts[links.vodOf(s) == null ? 1 : 0]++;
  }
  print('  year   with  without');
  for (final year in years.keys.toList()..sort()) {
    print('  $year  ${years[year]![0].toString().padLeft(5)}  ${years[year]![1].toString().padLeft(7)}');
  }
  final withVod = catalogue.streams.where((s) => links.vodOf(s) != null).toList();
  print(
    '  total  ${withVod.length.toString().padLeft(5)}  ${(catalogue.streamCount - withVod.length).toString().padLeft(7)}',
  );

  // ---------------------------------------------------------------- plays
  var linked = 0, noUptime = 0, zero = 0, blocked = 0, past = 0, inVodStreams = 0, moved = 0;
  final beforeStart = <(LiveStream, Play, int, VodOffset)>[];
  for (final s in withVod) {
    for (final p in catalogue.playsOf(s)) {
      inVodStreams++;
      final offset = links.offsetOf(p);
      if (links.linkOf(p) != null) {
        linked++;
        if (offset != null && offset.seconds != 0) moved++;
        continue;
      }
      final u = catalogue.uptimeOf(p);
      if (u == null) {
        noUptime++;
      } else if (u == 0) {
        zero++;
      } else if (u + (offset?.seconds ?? 0) < 0) {
        beforeStart.add((s, p, u, offset!));
      } else if (_lengthNeeded(links.vodOf(s)!, u + (offset?.seconds ?? 0))) {
        blocked++;
      } else {
        past++;
      }
    }
  }
  print('');
  print('Plays: ${catalogue.playCount}, of which in a stream with a VOD: $inVodStreams');
  print('  with a link                        $linked');
  if (offsets != null) print('    of which moved by an offset      $moved');
  print('  without: no uptime                 $noUptime');
  print('           uptime 0:00:00            $zero');
  if (offsets != null) print('           before the start (offset) ${beforeStart.length}');
  print('           a length needed unknown   $blocked');
  print('           past the end of the VOD   $past');

  // ---------------------------------------------------------------- lines matching no stream
  print('');
  final orphans = [
    for (final key in file.keys)
      if (!streamsByKey.containsKey(key)) key,
  ]..sort((a, b) => a.date != b.date ? a.date.compareTo(b.date) : a.rank.compareTo(b.rank));
  print('VODs that match no stream: ${orphans.length}');
  for (final key in orphans) {
    print('  $key');
    for (final l in file.vodOf(key)!) {
      print(line(l));
    }
    for (final s in catalogue.streams) {
      final days = key.date.daysUntil(keys[s.id].date);
      if (days.abs() <= 1) {
        final vod = links.vodOf(s) == null ? 'no VOD' : 'has a VOD';
        print(
          '    ${days < 0
              ? 'a day before'
              : days > 0
              ? 'a day after '
              : 'same date   '}: ${describe(s)}, $vod',
        );
      }
    }
  }

  // ---------------------------------------------------------------- dates of several streams
  print('');
  final byDate = <CalendarDate, List<LiveStream>>{};
  for (final s in catalogue.streams) {
    byDate.putIfAbsent(keys[s.id].date, () => []).add(s);
  }
  final several = byDate.entries.where((e) => e.value.length > 1).toList();
  print('Dates (Sydney) of several streams: ${several.length}');
  for (final e in several) {
    print('  ${e.key}');
    for (final s in e.value) {
      final vod = links.vodOf(s);
      print('    ${describe(s)}${vod == null ? ', no VOD' : ''}');
      for (final l in vod ?? const <VodLine>[]) {
        print('  ${line(l)}');
      }
    }
  }

  // ---------------------------------------------------------------- lines left out
  print('');
  print('Lines left out: ${file.ignored.length}');
  final reasons = <String, int>{};
  for (final n in file.ignored) {
    reasons[n.reason] = (reasons[n.reason] ?? 0) + 1;
  }
  reasons.forEach((reason, count) => print('  $count: $reason'));
  for (final n in file.ignored) {
    print('    line ${n.lineNumber}: ${n.reason}  ${n.text.replaceAll('\t', ' | ')}');
  }
  if (file.notes.isNotEmpty) {
    print('Lines read with something left out: ${file.notes.length}');
    for (final n in file.notes) {
      print('    line ${n.lineNumber}: ${n.reason}  ${n.text.replaceAll('\t', ' | ')}');
    }
  }
  print('Lines replaced by a later one of the same stream and part: ${file.replaced.length}');
  for (final (earlier, later) in file.replaced) {
    print(
      '    line ${earlier.lineNumber} (${earlier.id}) by line ${later.lineNumber} (${later.id}), ${later.key} part ${later.part}',
    );
  }
  print('Parts after a missing part (left out): ${file.afterHole.length}');
  for (final l in file.afterHole) {
    print(line(l));
  }

  // ---------------------------------------------------------------- missing durations
  print('');
  final missing = <(LiveStream, VodLine, int)>[];
  for (final s in withVod) {
    final vod = links.vodOf(s)!;
    final index = vod.indexWhere((l) => l.seconds == null);
    if (index < 0 || index == vod.length - 1) continue;
    var plays = 0;
    for (final p in catalogue.playsOf(s)) {
      final u = catalogue.uptimeOf(p);
      if (u != null && u > 0 && links.linkOf(p) == null) plays++;
    }
    missing.add((s, vod[index], plays));
  }
  print('Parts whose missing duration blocks links: ${missing.length}');
  for (final (s, part, plays) in missing) {
    print('  ${keys[s.id]}: $plays plays without a link');
    print(line(part));
  }

  // ---------------------------------------------------------------- streams longer than their VOD
  print('');
  final longer = <(LiveStream, int, int)>[];
  for (final s in withVod) {
    final vod = links.vodOf(s)!;
    if (vod.any((l) => l.seconds == null)) continue;
    final total = vod.fold(0, (sum, l) => sum + l.seconds!);
    // its length as the app knows it: the largest uptime of its rows, markers included (Concert Grand End...)
    final length = s.durationSeconds;
    if (length > 0 && length >= total) longer.add((s, length, total));
  }
  print(
    'Streams longer than their VOD (all its lengths known; the largest uptime of their rows, markers included): ${longer.length}',
  );
  for (final (s, largest, total) in longer) {
    print('  ${describe(s)}, VOD ${duration(total)} (${duration(largest - total)} short)');
    for (final l in links.vodOf(s)!) {
      print(line(l));
    }
  }

  // ---------------------------------------------------------------- offsets.tsv
  if (offsets == null) return;
  String offsetLine(VodOffsetLine l) {
    final o = l.offset;
    final at = o.kind == VodOffsetKind.stream ? 'whole stream' : '${o.kind.name} ${o.uptimeCell}';
    return 'line ${l.lineNumber}: ${l.key} $at ${o.seconds >= 0 ? '+' : ''}${o.seconds} s${o.note.isEmpty ? '' : '  ${o.note}'}';
  }

  print('');
  final counting = [for (final key in offsets.keys) ...offsets.of(key)!.lines];
  print(
    'offsets.tsv: ${offsets.lines.length} lines read, ${counting.length} that count, for ${offsets.keys.length} streams',
  );
  print('Lines of offsets.tsv left out: ${offsets.ignored.length}');
  for (final n in offsets.ignored) {
    print('    line ${n.lineNumber}: ${n.reason}  ${n.text.replaceAll('\t', ' | ')}');
  }
  print('Lines of offsets.tsv replaced by a later one of the same stream and uptime cell: ${offsets.replaced.length}');
  for (final (earlier, later) in offsets.replaced) {
    print('    ${offsetLine(earlier)}, by line ${later.lineNumber}');
  }
  final replacedLines = {for (final (earlier, _) in offsets.replaced) earlier.lineNumber};
  final noVod = <(VodOffsetLine, String)>[];
  final noPlay = <VodOffsetLine>[];
  for (final l in offsets.lines) {
    if (replacedLines.contains(l.lineNumber)) continue;
    final s = streamsByKey[l.key];
    if (s == null) {
      noVod.add((l, 'no stream of the sheet'));
      continue;
    }
    if (links.vodOf(s) == null) {
      noVod.add((l, 'a stream without VOD: ${describe(s)}'));
      continue;
    }
    if (l.offset.kind == VodOffsetKind.play &&
        !catalogue.playsOf(s).any((p) => catalogue.uptimeOf(p) == l.offset.uptime)) {
      noPlay.add(l);
    }
  }
  print('Lines of offsets.tsv naming a stream that has no VOD: ${noVod.length}');
  for (final (l, why) in noVod) {
    print('    ${offsetLine(l)}  ($why)');
  }
  print('Lines of offsets.tsv of an exact uptime that no play of the stream has: ${noPlay.length}');
  for (final l in noPlay) {
    print('    ${offsetLine(l)}');
  }
  print('Plays without a link: their offset puts them before the start of the recording: ${beforeStart.length}');
  for (final (s, p, u, o) in beforeStart) {
    final at = o.kind == VodOffsetKind.stream ? 'whole stream' : '${o.kind.name} ${o.uptimeCell}';
    print(
      '    ${keys[s.id]} ${formatVodUptime(u)} ${p.title}: offset ${o.seconds} s ($at), position ${u + o.seconds} s',
    );
  }
}

/// Whether a play at [uptime] gets no link for want of a length of [vod] (not because it is past the end).
bool _lengthNeeded(List<VodLine> vod, int uptime) {
  var at = uptime;
  for (var i = 0; i < vod.length - 1; i++) {
    final length = vod[i].seconds;
    if (length == null) return true;
    if (at < length) return false;
    at -= length;
  }
  return false;
}
