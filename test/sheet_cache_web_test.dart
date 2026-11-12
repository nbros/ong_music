// Browser only: flutter test --platform chrome test/sheet_cache_web_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/sheet_cache.dart';
import 'package:ong_music/src/data/sheet_cache_web.dart';
import 'package:ong_music/src/data/sheets.dart';

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
  final sample = CachedSheets(
    sheets: const RawSheets(highlightsCsv: 'h é', songsCsv: 's ♪'),
    fetchedAt: DateTime.utc(2026, 1, 2),
  );

  test('createSheetCache picks the Cache API implementation', () {
    expect(createSheetCache(), isA<WebSheetCache>());
  });

  test('round trip and clear', () async {
    const cache = WebSheetCache();
    await cache.write(sample);
    final back = (await cache.read())!;
    expect((back.sheets.highlightsCsv, back.sheets.songsCsv, back.fetchedAt), ('h é', 's ♪', sample.fetchedAt));
    await cache.clear();
    expect(await cache.read(), isNull);
  });

  test('without window.caches (non-secure context) it is a no-op cache', () async {
    await withCaches(null, () async {
      const cache = WebSheetCache();
      await cache.write(sample);
      expect(await cache.read(), isNull);
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
      await cache.write(sample);
      expect(await cache.read(), isNull);
      await cache.clear();
    });
  });

  test('the real Cache API still works after the fakes', () async {
    const cache = WebSheetCache();
    await cache.write(sample);
    expect((await cache.read())?.sheets.songsCsv, 's ♪');
    await cache.clear();
  });
}
