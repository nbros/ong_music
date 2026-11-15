// Browser only: flutter test --platform chrome test/data_file_cache_web_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/data_file_cache_web.dart';
import 'package:ong_music/src/data/data_files.dart';
import 'package:ong_music/src/data/sheet_cache_web.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:web/web.dart' as web;

void main() {
  final at = DateTime.utc(2026, 1, 2);
  const cache = WebDataFileCache();

  setUp(() async {
    await web.window.caches.delete(WebDataFileCache.cacheName).toDart;
    await web.window.caches.delete(WebSheetCache.cacheName).toDart;
  });

  test('a file written is read back with its time; the other is not there', () async {
    await cache.write(DataFile.vods, CachedSheet(text: 'date\tpart\tid\n', fetchedAt: at));
    final read = (await cache.read(DataFile.vods))!;
    expect(read.text, 'date\tpart\tid\n');
    expect(read.fetchedAt, at);
    expect(await cache.read(DataFile.aliases), isNull);
  });

  test('cleared apart from the sheets, which stay', () async {
    const sheets = WebSheetCache();
    await sheets.write(Sheet.highlights, CachedSheet(text: 'csv', fetchedAt: at));
    await cache.write(DataFile.aliases, CachedSheet(text: 'Amy, Amyy', fetchedAt: at));
    await cache.clear();
    expect(await cache.read(DataFile.aliases), isNull);
    expect((await sheets.read(Sheet.highlights))!.text, 'csv');
    // and the sheets cleared leave the files
    await cache.write(DataFile.aliases, CachedSheet(text: 'Amy, Amyy', fetchedAt: at));
    await sheets.clear();
    expect((await cache.read(DataFile.aliases))!.text, 'Amy, Amyy');
  });

  test('without the Cache API: nothing kept, nothing thrown', () async {
    final object = globalContext['Object']! as JSObject;
    final original = object.callMethod<JSObject?>('getOwnPropertyDescriptor'.toJS, globalContext, 'caches'.toJS);
    object.callMethod(
      'defineProperty'.toJS,
      globalContext,
      'caches'.toJS,
      JSObject()
        ..['value'] = null
        ..['configurable'] = true.toJS,
    );
    try {
      await cache.write(DataFile.vods, CachedSheet(text: 'x', fetchedAt: at));
      expect(await cache.read(DataFile.vods), isNull);
      await cache.clear();
    } finally {
      globalContext.delete('caches'.toJS);
      if (original != null) object.callMethod('defineProperty'.toJS, globalContext, 'caches'.toJS, original);
    }
  });
}
