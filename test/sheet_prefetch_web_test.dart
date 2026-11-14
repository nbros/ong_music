// Browser only: flutter test --platform chrome test/sheet_prefetch_web_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ong_music/src/data/sheet_prefetch.dart';
import 'package:ong_music/src/data/sheet_prefetch_web.dart' show prefetchGlobal, snapshotPrefetchGlobal;
import 'package:ong_music/src/data/sheet_snapshot.dart';
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

/// Sets the snapshot global as the page script does, downloaded from [base].
void prefetchSnapshot(String? base, {String meta = '{"madeAt": "2026-11-14T04:23:51Z"}', int status = 200}) {
  globalContext[snapshotPrefetchGlobal] = resolved(
    base == null
        ? null
        : (JSObject()
            ..['base'] = base.toJS
            ..['highlights'] = resolved(response('"Video Title"\n"Pokémon"'))
            ..['songs'] = resolved(response('"Title"\n"♪"', status: status))
            ..['meta'] = resolved(response(meta))),
  );
}

void main() {
  tearDown(() {
    globalContext.delete(prefetchGlobal.toJS);
    globalContext.delete(snapshotPrefetchGlobal.toJS);
  });

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

  test('a web page instead of CSV (Wi-Fi sign-in) is a SheetNotCsvException', () async {
    prefetch(resolved(response('"ok"')), resolved(response('<!DOCTYPE html><html>')));
    await expectLater(
      takePrefetchedSheets(),
      throwsA(isA<SheetNotCsvException>().having((e) => e.uri, 'uri', SheetUrls.songs)),
    );
  });

  test('a network error is a ClientException', () async {
    prefetch(rejected(), resolved(response('ok')));
    await expectLater(takePrefetchedSheets(), throwsA(isA<http.ClientException>()));
  });

  group('snapshot', () {
    test('no page script, or something kept: nothing, and the global is consumed', () async {
      expect(await takePrefetchedSnapshot(), isNull);
      prefetchSnapshot(null);
      expect(await takePrefetchedSnapshot(), isNull);
      expect(globalContext.has(snapshotPrefetchGlobal), isFalse);
    });

    test('takes the three files once, decoded as UTF-8; HttpSnapshotFetcher reads them', () async {
      prefetchSnapshot(SnapshotUrls.base);
      final texts = (await takePrefetchedSnapshot())!;
      expect((texts.highlights, texts.songs), ('"Video Title"\n"Pokémon"', '"Title"\n"♪"'));
      expect(texts.meta, contains('2026-11-14T04:23:51Z'));
      expect(await takePrefetchedSnapshot(), isNull, reason: 'only the first load uses it');
      prefetchSnapshot(SnapshotUrls.base);
      final got = await HttpSnapshotFetcher().fetch();
      expect((got.sheets.songsCsv, got.fetchedAt), ('"Title"\n"♪"', DateTime.utc(2026, 11, 14, 4, 23, 51)));
    });

    test('downloaded from another address than that of the app: not taken', () async {
      prefetchSnapshot('https://example.org/elsewhere/');
      expect(await takePrefetchedSnapshot(), isNull);
      expect(globalContext.has(snapshotPrefetchGlobal), isFalse);
    });

    test('no branch yet: the HTTP 404 is a SheetHttpException', () async {
      prefetchSnapshot(SnapshotUrls.base, status: 404);
      await expectLater(
        takePrefetchedSnapshot(),
        throwsA(isA<SheetHttpException>().having((e) => e.uri, 'uri', SnapshotUrls.songs)),
      );
    });

    test('a time that is not one: HttpSnapshotFetcher fails', () async {
      prefetchSnapshot(SnapshotUrls.base, meta: '{"madeAt": "soon"}');
      await expectLater(HttpSnapshotFetcher().fetch(), throwsFormatException);
    });
  });
}
