// Browser only: flutter test --platform chrome test/sheet_prefetch_web_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ong_music/src/data/sheet_prefetch.dart';
import 'package:ong_music/src/data/sheet_prefetch_web.dart' show prefetchGlobal, prefetchMaxAge;
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

/// Sets the global as the page script does, for a download started [age] ago.
void prefetch(JSPromise<web.Response>? highlights, JSPromise<web.Response>? songs, {Duration age = Duration.zero}) {
  globalContext[prefetchGlobal] = resolved(
    highlights == null
        ? null
        : (JSObject()
            ..['at'] = (DateTime.now().millisecondsSinceEpoch - age.inMilliseconds).toJS
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

  test('a download started minutes ago is not used: the app downloads again', () async {
    // the app found a fresh cache at its start (another tab wrote it) and only downloads hours later
    prefetch(
      resolved(response('"old"')),
      resolved(response('"old"')),
      age: prefetchMaxAge + const Duration(seconds: 1),
    );
    expect(await takePrefetchedSheets(), isNull);
    expect(globalContext.has(prefetchGlobal), isFalse);
    // within the limit: used
    prefetch(
      resolved(response('"new"')),
      resolved(response('"new"')),
      age: prefetchMaxAge - const Duration(seconds: 30),
    );
    expect((await takePrefetchedSheets())!.highlightsCsv, '"new"');
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
