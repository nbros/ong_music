// Checks a vods.tsv (the file of the branch data) against the two sheets, with the app's own code: what the app
// will link, and what a human should look at.
//
//   dart run tool/vods_check.dart <highlights.csv> <songs.csv> <vods.tsv>
//
// The sheets as Google exports them (gviz CSV, see tool/sheets_snapshot.sh), or the copies of the branch
// sheets-snapshot. Prints:
// - the streams with a VOD and without, per year;
// - the plays that get a link, and why the others of the streams with a VOD get none;
// - the VOD lines that match no stream, with the streams of the days around;
// - the dates of several streams, with their VODs;
// - the lines left out and why, those replaced by a later one, the parts after a hole;
// - the parts whose missing duration blocks links;
// - the streams longer than their VOD (the largest uptime past the end of the last part).
//
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/model.dart';
import 'package:ong_music/src/data/parser.dart';
import 'package:ong_music/src/data/sheet_zone.dart';
import 'package:ong_music/src/data/vods.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('usage: dart run tool/vods_check.dart <highlights.csv> <songs.csv> <vods.tsv>');
    exit(64);
  }
  final catalogue = parseCatalogue(File(args[0]).readAsStringSync(), File(args[1]).readAsStringSync());
  final file = VodFile.parse(File(args[2]).readAsStringSync());
  final links = VodLinks(catalogue, file);
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

  int? largestUptime(LiveStream s) {
    int? largest;
    for (final p in catalogue.playsOf(s)) {
      final u = catalogue.uptimeOf(p);
      if (u != null && (largest == null || u > largest)) largest = u;
    }
    return largest;
  }

  String describe(LiveStream s) =>
      '${keys[s.id]}  started ${start(s)}, ${s.playCount} plays, largest uptime ${duration(largestUptime(s))}';

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
  var linked = 0, noUptime = 0, zero = 0, blocked = 0, past = 0, inVodStreams = 0;
  for (final s in withVod) {
    for (final p in catalogue.playsOf(s)) {
      inVodStreams++;
      if (links.linkOf(p) != null) {
        linked++;
        continue;
      }
      final u = catalogue.uptimeOf(p);
      if (u == null) {
        noUptime++;
      } else if (u == 0) {
        zero++;
      } else if (_lengthNeeded(links.vodOf(s)!, u)) {
        blocked++;
      } else {
        past++;
      }
    }
  }
  print('');
  print('Plays: ${catalogue.playCount}, of which in a stream with a VOD: $inVodStreams');
  print('  with a link                        $linked');
  print('  without: no uptime                 $noUptime');
  print('           uptime 0:00:00            $zero');
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
    final largest = largestUptime(s);
    if (largest != null && largest >= total) longer.add((s, largest, total));
  }
  print('Streams whose largest uptime is past the end of their VOD (all its lengths known): ${longer.length}');
  for (final (s, largest, total) in longer) {
    print('  ${describe(s)}, VOD ${duration(total)} (${duration(largest - total)} short)');
    for (final l in links.vodOf(s)!) {
      print(line(l));
    }
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
