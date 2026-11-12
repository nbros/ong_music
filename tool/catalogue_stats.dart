// Prints statistics of a catalogue built from two CSV exports of the sheets.
//
//   dart run tool/catalogue_stats.dart <highlights.csv> <songs.csv>
//
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/model.dart';
import 'package:ong_music/src/data/parser.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: dart run tool/catalogue_stats.dart <highlights.csv> <songs.csv>');
    exit(64);
  }
  final highlightsCsv = File(args[0]).readAsStringSync();
  final songsCsv = File(args[1]).readAsStringSync();

  // the first build also pays for JIT warm-up: report it and a warm one
  final cold = Stopwatch()..start();
  var c = parseCatalogue(highlightsCsv, songsCsv);
  cold.stop();
  final warm = Stopwatch()..start();
  c = parseCatalogue(highlightsCsv, songsCsv);
  warm.stop();

  final linked = c.highlights.where((h) => h.playId != null).length;
  print('highlights            ${c.highlightCount}');
  print('  linked to a play    $linked');
  print('  with a YouTube id   ${c.highlights.where((h) => h.youtubeId != null).length}');
  print('plays                 ${c.playCount}');
  print('  linked to a video   ${c.plays.where((p) => p.highlightId != null).length}');
  print('streams               ${c.streamCount}');
  print('distinct titles       ${c.titles.length}');
  print('requesters            ${c.requesters.length}');
  print('songs                 ${c.songCount}');
  print('parse+build           ${cold.elapsedMilliseconds} ms (cold), ${warm.elapsedMilliseconds} ms (warm)');
  print('');
  for (final q in ['zelda', 'alinsa loop', 'é', 'a', 'the legend of zelda', 'pokémon', '千と千尋']) {
    _time('plays "$q"', () => c.searchPlays(query: q).length, c);
    _time('highlights "$q"', () => c.searchHighlights(query: q).length, c);
  }
  // the Highlights list and the counts of its chips: "You" is the requester of the most highlights, one highlight in
  // 10 is a favourite
  final me = c.requesters.reduce((a, b) => c.highlightRequestCount(a) >= c.highlightRequestCount(b) ? a : b);
  final favourites = {for (var i = 0; i < c.highlightCount; i += 10) c.highlights[i].key};
  for (final (q, genre, mine, stars) in [
    ('', null, false, false),
    ('a', null, false, false),
    ('zelda', Genre.gameOst, true, true),
    ('the legend of zelda', Genre.popular, false, true),
  ]) {
    _time(
      'highlights "$q" ${genre?.label ?? ''}${mine ? ' You' : ''}${stars ? ' star' : ''} + counts',
      () => c
          .searchHighlights(
            query: q,
            genre: genre,
            requesterId: me.id,
            onlyRequester: mine,
            keys: favourites,
            onlyKeys: stars,
          )
          .length,
      c,
    );
  }
  _time('plays (no query, Loop, with video)', () => c.searchPlays(type: PlayType.loop, withVideo: true).length, c);
  _time('countPlays "zelda"', () => c.countPlays('zelda'), c);
}

void _time(String label, int Function() run, Catalogue c) {
  for (var i = 0; i < 5; i++) {
    run(); // warm-up
  }
  const n = 20;
  final sw = Stopwatch()..start();
  var result = 0;
  for (var i = 0; i < n; i++) {
    result = run();
  }
  sw.stop();
  final ms = sw.elapsedMicroseconds / n / 1000;
  print('${label.padRight(42)} ${result.toString().padLeft(6)} rows  ${ms.toStringAsFixed(2)} ms');
}
