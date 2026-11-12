import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/sheet_prefetch.dart';
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
  test('the page script downloads the same sheets as SheetUrls', () {
    final script = prefetchScript();
    final base = RegExp(r"var base = '([^']+)';").firstMatch(script)![1]!;
    expect(Uri.parse("${base}Youtube%20Catalogue"), SheetUrls.highlights);
    expect(Uri.parse('${base}Songs'), SheetUrls.songs);
    expect(script, contains("get('Youtube%20Catalogue')"));
    expect(script, contains("get('Songs')"));
    // dated: the app does not take a download that is minutes old
    expect(script, contains('at: Date.now()'));
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

  test('nothing is prefetched on native platforms', () async {
    expect(await takePrefetchedSheets(), isNull);
  });
}
