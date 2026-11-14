import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

void main() {
  test('the snapshot script downloads the same sheets as SheetUrls', () {
    final script = File('tool/sheets_snapshot.sh').readAsStringSync();
    final base = RegExp(r"export_base=\$\{SNAPSHOT_EXPORT_BASE:-'([^']+)'\}").firstMatch(script)![1]!;
    expect(Uri.parse('${base}Youtube%20Catalogue'), SheetUrls.highlights);
    expect(Uri.parse('${base}Songs'), SheetUrls.songs);
    expect(script, contains('Youtube%20Catalogue'));
  });

  test('the page script downloads the same sheets as SheetUrls', () {
    final script = prefetchScript();
    final base = RegExp(r"var base = '([^']+)';").firstMatch(script)![1]!;
    expect(Uri.parse("${base}Youtube%20Catalogue"), SheetUrls.highlights);
    expect(Uri.parse('${base}Songs'), SheetUrls.songs);
    expect(script, contains("get(base + 'Youtube%20Catalogue')"));
    expect(script, contains("get(base + 'Songs')"));
  });

  test('the page script reads the cache of WebSheetCache with the age limit of the app', () {
    final script = prefetchScript();
    expect(script, contains('var maxAge = ${catalogueMaxAge.inMilliseconds};'));
    // sheet_cache_web.dart only compiles for the web: compare with its source
    final cache = File('lib/src/data/sheet_cache_web.dart').readAsStringSync();
    final name = RegExp(r"cacheName = '([^']+)'").firstMatch(cache)![1]!;
    final meta = RegExp(r"_meta = '([^']+)'").firstMatch(cache)![1]!;
    expect(script, contains("caches.open('$name')"));
    expect(script, contains("cache.match('$meta')"));
  });

  test('the page script downloads the snapshot from the default address of SnapshotUrls, on a first visit only', () {
    final script = prefetchScript();
    final base = RegExp(r"var snapshotBase = '([^']+)';").firstMatch(script)![1]!;
    expect(base, SnapshotUrls.base, reason: 'run without SHEETS_SNAPSHOT_URL: the default');
    final snapshot = script.substring(script.indexOf('window.ongMusicSnapshotPrefetch'));
    expect(snapshot, contains('base: snapshotBase,'));
    expect(Uri.parse('${base}highlights.csv'), SnapshotUrls.highlights);
    expect(snapshot, contains("highlights: get(snapshotBase + 'highlights.csv')"));
    expect(Uri.parse('${base}songs.csv'), SnapshotUrls.songs);
    expect(snapshot, contains("songs: get(snapshotBase + 'songs.csv')"));
    expect(Uri.parse('${base}snapshot.json'), SnapshotUrls.meta);
    expect(snapshot, contains("meta: get(snapshotBase + 'snapshot.json')"));
    // the time of the cache read by the sheets download: any time kept, no snapshot
    expect(
      snapshot,
      startsWith('window.ongMusicSnapshotPrefetch = kept.then(function (meta) {\n        if (meta) return null;'),
    );
    expect(script, contains('window.ongMusicSheetPrefetch = kept.then('));
  });

  test('nothing is prefetched on native platforms', () async {
    expect(await takePrefetchedSheets(), isNull);
    expect(await takePrefetchedSnapshot(), isNull);
  });
}
