// Browser only: flutter test --platform chrome test/sheet_prefetch_web_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ong_music/src/data/sheet_prefetch.dart';
import 'package:ong_music/src/data/sheet_prefetch_web.dart' show prefetchGlobal;
import 'package:ong_music/src/data/sheets.dart';
import 'package:web/web.dart' as web;

JSPromise<T> resolved<T extends JSAny?>(T value) => JSPromise<T>(
  (JSFunction resolve, JSFunction _) {
    resolve.callAsFunction(null, value);
  }.toJS,
);

JSPromise<web.Response> rejected() => JSPromise<web.Response>(
  (JSFunction _, JSFunction reject) {
    reject.callAsFunction(null, 'TypeError: Failed to fetch'.toJS);
  }.toJS,
);

web.Response response(String body, {int status = 200}) => web.Response(body.toJS, web.ResponseInit(status: status));

/// Sets the global as the page script does.
void prefetch(JSPromise<web.Response>? highlights, JSPromise<web.Response>? songs) {
  globalContext[prefetchGlobal] = resolved(
    highlights == null
        ? null
        : (JSObject()
            ..['highlights'] = highlights
            ..['songs'] = songs),
  );
}

void main() {
  tearDown(() => globalContext.delete(prefetchGlobal.toJS));

  test('no page script: nothing', () async {
    expect(await takePrefetchedSheets(), isNull);
  });

  test('the page started no download (fresh cache): nothing, and the global is consumed', () async {
    prefetch(null, null);
    expect(await takePrefetchedSheets(), isNull);
    expect(globalContext.has(prefetchGlobal), isFalse);
  });

  test('takes the responses once, decoded as UTF-8', () async {
    prefetch(resolved(response('"Video Title"\n"Pokémon"')), resolved(response('"Title"\n"♪"')));
    final sheets = (await takePrefetchedSheets())!;
    expect((sheets.highlightsCsv, sheets.songsCsv), ('"Video Title"\n"Pokémon"', '"Title"\n"♪"'));
    expect(await takePrefetchedSheets(), isNull, reason: 'only the first download uses it');
  });

  test('a discarded download is not taken later', () async {
    // the app started on a fresh cache (another tab wrote it) and downloaded nothing
    prefetch(resolved(response('"old"')), resolved(response('"old"')));
    discardPrefetchedSheets();
    expect(globalContext.has(prefetchGlobal), isFalse);
    expect(await takePrefetchedSheets(), isNull);
    discardPrefetchedSheets(); // nothing to forget: harmless
  });

  test('an HTTP error is a SheetHttpException', () async {
    prefetch(resolved(response('ok')), resolved(response('<html>', status: 500)));
    await expectLater(
      takePrefetchedSheets(),
      throwsA(isA<SheetHttpException>().having((e) => e.statusCode, 'statusCode', 500)),
    );
  });

  test('a network error is a ClientException', () async {
    prefetch(rejected(), resolved(response('ok')));
    await expectLater(takePrefetchedSheets(), throwsA(isA<http.ClientException>()));
  });
}
