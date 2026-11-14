import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/sheet_cache.dart';
import 'package:ong_music/src/data/sheet_prefetch.dart';
import 'package:ong_music/src/data/sheet_snapshot.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/state/catalogue_state.dart';

/// The script of web/index.html that starts the sheets download.
String prefetchScript() {
  final html = File('web/index.html').readAsStringSync();
  final start = html.indexOf('window.ongMusicSheetPrefetch');
  expect(start, greaterThan(0), reason: 'the prefetch script is in web/index.html');
  return html.substring(html.lastIndexOf('<script>', start), html.indexOf('</script>', start));
}

/// The script without its comments.
String code(String script) => script.split('\n').where((line) => !line.trim().startsWith('//')).join('\n');

void main() {
  test('the snapshot script downloads the same sheets as SheetUrls', () {
    final script = File('tool/sheets_snapshot.sh').readAsStringSync();
    final base = RegExp(r"export_base=\$\{SNAPSHOT_EXPORT_BASE:-'([^']+)'\}").firstMatch(script)![1]!;
    expect(Uri.parse('${base}Youtube%20Catalogue'), SheetUrls.highlights);
    expect(Uri.parse('${base}Songs'), SheetUrls.songs);
    expect(script, contains('Youtube%20Catalogue'));
  });

  test('the page script downloads the Highlights sheet of SheetUrls, never the Songs sheet', () {
    final script = code(prefetchScript());
    final base = RegExp(r"var base = '([^']+)';").firstMatch(script)![1]!;
    expect(Uri.parse('${base}Youtube%20Catalogue'), SheetUrls.highlights);
    expect(script, contains("return { highlights: get(base + 'Youtube%20Catalogue') };"));
    // the app downloads the Songs sheet once the list is on screen: the page starts no download of it
    expect(script, isNot(contains('Songs')));
    expect(script, isNot(contains('songs')));
  });

  test('the page script reads the time of the Highlights sheet of WebSheetCache, else the one of 2.0.0, '
      'with the age limit of the app', () {
    final script = code(prefetchScript());
    expect(script, contains('var maxAge = ${catalogueMaxAge.inMilliseconds};'));
    // sheet_cache_web.dart only compiles for the web: compare with its source
    final cache = File('lib/src/data/sheet_cache_web.dart').readAsStringSync();
    final name = RegExp(r"cacheName = '([^']+)'").firstMatch(cache)![1]!;
    final prefix = RegExp(r"'(ong-music-cache/)\$name'").firstMatch(cache)![1]!;
    expect(script, contains("caches.open('$name')"));
    expect(script, contains("cache.match('$prefix${sheetTimeName(Sheet.highlights)}')"));
    expect(script, contains("return response || cache.match('$prefix$legacyTimeName');"));
  });

  test('the page script downloads the copy of the Highlights sheet and its time from the default address of '
      'SnapshotUrls, on a first visit only', () {
    final script = code(prefetchScript());
    final base = RegExp(r"var snapshotBase = '([^']+)';").firstMatch(script)![1]!;
    expect(base, SnapshotUrls.base, reason: 'run without SHEETS_SNAPSHOT_URL: the default');
    final snapshot = script.substring(script.indexOf('window.ongMusicSnapshotPrefetch'));
    expect(snapshot, contains('base: snapshotBase,'));
    expect(Uri.parse('${base}highlights.csv'), SnapshotUrls.highlights);
    expect(snapshot, contains("'highlights.csv': get(snapshotBase + 'highlights.csv')"));
    expect(Uri.parse('${base}snapshot.json'), SnapshotUrls.meta);
    expect(snapshot, contains("'snapshot.json': get(snapshotBase + 'snapshot.json')"));
    // the time of the cache read by the sheets download: any time kept, no snapshot
    expect(
      snapshot,
      startsWith('window.ongMusicSnapshotPrefetch = kept.then(function (meta) {\n        if (meta) return null;'),
    );
    expect(script, contains('window.ongMusicSheetPrefetch = kept.then('));
  });

  test('nothing is prefetched on native platforms', () async {
    for (final sheet in Sheet.values) {
      expect(await takePrefetchedSheet(sheet), isNull);
    }
    expect(await takePrefetchedSnapshotFile('highlights.csv'), isNull);
    expect(await takePrefetchedSnapshotFile('snapshot.json'), isNull);
  });
}
