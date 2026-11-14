// Browser only: flutter test --platform chrome test/sheet_cache_web_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/sheet_cache.dart';
import 'package:ong_music/src/data/sheet_cache_web.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:web/web.dart' as web;

/// Runs [body] with `window.caches` replaced by [value], then restores the
/// original property (an own accessor of the global object).
Future<void> withCaches(JSAny? value, Future<void> Function() body) async {
  final object = globalContext['Object']! as JSObject;
  final original = object.callMethod<JSObject?>('getOwnPropertyDescriptor'.toJS, globalContext, 'caches'.toJS);
  final replacement = JSObject()
    ..['value'] = value
    ..['configurable'] = true.toJS;
  object.callMethod('defineProperty'.toJS, globalContext, 'caches'.toJS, replacement);
  try {
    await body();
  } finally {
    globalContext.delete('caches'.toJS);
    if (original != null) object.callMethod('defineProperty'.toJS, globalContext, 'caches'.toJS, original);
  }
}

void main() {
  final at = DateTime.utc(2026, 1, 2);
  const highlights = Sheet.highlights, songs = Sheet.songs;
  CachedSheet sheet(String text, [DateTime? time]) => CachedSheet(text: text, fetchedAt: time ?? at);

  Future<web.Cache> raw() => web.window.caches.open(WebSheetCache.cacheName).toDart;
  Future<List<String>> keys() async =>
      [for (final request in (await (await raw()).keys().toDart).toDart) Uri.parse(request.url).pathSegments.last]
        ..sort();

  test('createSheetCache picks the Cache API implementation', () {
    expect(createSheetCache(), isA<WebSheetCache>());
  });

  test('round trip, remove and clear, each sheet on its own', () async {
    const cache = WebSheetCache();
    await cache.write(highlights, sheet('h é'));
    expect(await cache.read(songs), isNull);
    await cache.write(songs, sheet('s ♪', at.add(const Duration(hours: 1))));
    final h = (await cache.read(highlights))!, s = (await cache.read(songs))!;
    expect((h.text, h.fetchedAt, s.text, s.fetchedAt), ('h é', at, 's ♪', at.add(const Duration(hours: 1))));
    expect(await keys(), ['highlights.csv', 'highlights_fetched_at.txt', 'songs.csv', 'songs_fetched_at.txt']);
    await cache.remove(highlights);
    expect(await cache.read(highlights), isNull);
    expect((await cache.read(songs))!.text, 's ♪');
    await cache.clear();
    expect(await cache.read(songs), isNull);
  });

  test('the cache of 2.0.0: both sheets with its one time, which the first write splits', () async {
    // what WebSheetCache of 2.0.0 wrote: both texts, then the time of both
    final cache = await raw();
    final kept = DateTime.utc(2026, 11, 10, 8, 30);
    Future<void> put(String name, String text) =>
        cache.put(WebSheetCache.key(name).toJS, web.Response(text.toJS)).toDart;
    await put('highlights.csv', 'old h');
    await put('songs.csv', 'old s');
    await put('fetched_at.txt', kept.toIso8601String());
    const sheets = WebSheetCache();
    expect(((await sheets.read(highlights))!.text, (await sheets.read(songs))!.fetchedAt), ('old h', kept));
    await sheets.write(highlights, sheet('new h', DateTime.utc(2026, 11, 14)));
    expect(await keys(), ['highlights.csv', 'highlights_fetched_at.txt', 'songs.csv', 'songs_fetched_at.txt']);
    expect((await sheets.read(highlights))!.fetchedAt, DateTime.utc(2026, 11, 14));
    expect(((await sheets.read(songs))!.text, (await sheets.read(songs))!.fetchedAt), ('old s', kept));
    await sheets.clear();
  });

  test('without window.caches (non-secure context) it is a no-op cache', () async {
    await withCaches(null, () async {
      const cache = WebSheetCache();
      await cache.write(highlights, sheet('h'));
      expect(await cache.read(highlights), isNull);
      await cache.remove(songs);
      await cache.clear();
    });
    expect(globalContext['caches'], isNotNull, reason: 'restored');
  });

  test('a Cache API that rejects (private mode) reads as no cache', () async {
    final rejecting = JSObject()
      ..['open'] = ((JSString _) => JSPromise<JSAny?>(
        (JSFunction _, JSFunction reject) {
          reject.callAsFunction(null, 'SecurityError'.toJS);
        }.toJS,
      )).toJS
      ..['delete'] = ((JSString _) => JSPromise<JSAny?>(
        (JSFunction _, JSFunction reject) {
          reject.callAsFunction(null, 'SecurityError'.toJS);
        }.toJS,
      )).toJS;
    await withCaches(rejecting, () async {
      const cache = WebSheetCache();
      await cache.write(songs, sheet('s'));
      expect(await cache.read(songs), isNull);
      await cache.remove(songs);
      await cache.clear();
    });
  });

  test('the real Cache API still works after the fakes', () async {
    const cache = WebSheetCache();
    await cache.write(songs, sheet('s ♪'));
    expect((await cache.read(songs))?.text, 's ♪');
    await cache.clear();
  });
}
