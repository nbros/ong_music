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

/// Sets the global as the page script does: the download of the Highlights sheet, and of the Songs sheet when given
/// (the page starts none, but the app takes what is there).
void prefetch(JSPromise<web.Response>? highlights, [JSPromise<web.Response>? songs]) {
  JSObject? started;
  if (highlights != null) {
    started = JSObject()..['highlights'] = highlights;
    if (songs != null) started['songs'] = songs;
  }
  globalContext[prefetchGlobal] = resolved(started);
}

/// Sets the snapshot global as the page script does, downloaded from [base].
void prefetchSnapshot(String? base, {String meta = '{"madeAt": "2026-11-14T04:23:51Z"}', int status = 200}) {
  globalContext[snapshotPrefetchGlobal] = resolved(
    base == null
        ? null
        : (JSObject()
            ..['base'] = base.toJS
            ..['files'] = (JSObject()
              ..['highlights.csv'] = resolved(response('"Video Title"\n"Pokémon"', status: status))
              ..['snapshot.json'] = resolved(response(meta)))),
  );
}

void main() {
  const highlights = Sheet.highlights, songs = Sheet.songs;

  tearDown(() {
    globalContext.delete(prefetchGlobal.toJS);
    globalContext.delete(snapshotPrefetchGlobal.toJS);
  });

  test('no page script: nothing', () async {
    expect(await takePrefetchedSheet(highlights), isNull);
  });

  test('the page started no download (fresh cache): nothing, and the global is consumed', () async {
    prefetch(null);
    expect(await takePrefetchedSheet(highlights), isNull);
    expect(globalContext.has(prefetchGlobal), isFalse);
  });

  test('takes the response of a sheet once, decoded as UTF-8; the global goes with the last one', () async {
    prefetch(resolved(response('"Video Title"\n"Pokémon"')));
    expect(await takePrefetchedSheet(songs), isNull, reason: 'the page started nothing for the songs');
    expect(await takePrefetchedSheet(highlights), '"Video Title"\n"Pokémon"');
    expect(await takePrefetchedSheet(highlights), isNull, reason: 'only the first download uses it');
    expect(globalContext.has(prefetchGlobal), isFalse);
  });

  test('each sheet takes its own response', () async {
    prefetch(resolved(response('"h"')), resolved(response('"s"')));
    expect(await takePrefetchedSheet(songs), '"s"');
    expect(globalContext.has(prefetchGlobal), isTrue, reason: 'the highlights are still there');
    expect(await takePrefetchedSheet(highlights), '"h"');
    expect(globalContext.has(prefetchGlobal), isFalse);
  });

  test('a discarded download is not taken later', () async {
    // the app started on a fresh cache (another tab wrote it) and downloaded nothing
    prefetch(resolved(response('"old"')));
    discardPrefetchedSheets();
    expect(globalContext.has(prefetchGlobal), isFalse);
    expect(await takePrefetchedSheet(highlights), isNull);
    discardPrefetchedSheets(); // nothing to forget: harmless
  });

  test('an HTTP error is a SheetHttpException', () async {
    prefetch(resolved(response('<html>', status: 500)));
    await expectLater(
      takePrefetchedSheet(highlights),
      throwsA(isA<SheetHttpException>().having((e) => e.statusCode, 'statusCode', 500)),
    );
  });

  test('a web page instead of CSV (Wi-Fi sign-in) is a SheetNotCsvException', () async {
    prefetch(resolved(response('<!DOCTYPE html><html>')));
    await expectLater(
      takePrefetchedSheet(highlights),
      throwsA(isA<SheetNotCsvException>().having((e) => e.uri, 'uri', SheetUrls.highlights)),
    );
  });

  test('a network error is a ClientException', () async {
    prefetch(rejected());
    await expectLater(takePrefetchedSheet(highlights), throwsA(isA<http.ClientException>()));
  });

  group('snapshot', () {
    test('no page script, or something kept: nothing, and the global is consumed', () async {
      expect(await takePrefetchedSnapshotFile('highlights.csv'), isNull);
      prefetchSnapshot(null);
      expect(await takePrefetchedSnapshotFile('highlights.csv'), isNull);
      expect(globalContext.has(snapshotPrefetchGlobal), isFalse);
    });

    test('takes each file once, decoded as UTF-8; HttpSnapshotFetcher reads them', () async {
      prefetchSnapshot(SnapshotUrls.base);
      expect(await takePrefetchedSnapshotFile('songs.csv'), isNull, reason: 'the page starts nothing for the songs');
      expect(await takePrefetchedSnapshotFile('highlights.csv'), '"Video Title"\n"Pokémon"');
      expect(await takePrefetchedSnapshotFile('highlights.csv'), isNull, reason: 'only the first load uses it');
      expect(await takePrefetchedSnapshotFile('snapshot.json'), contains('2026-11-14T04:23:51Z'));
      expect(globalContext.has(snapshotPrefetchGlobal), isFalse, reason: 'gone with its last file');
      prefetchSnapshot(SnapshotUrls.base);
      final got = await HttpSnapshotFetcher().fetch(highlights);
      expect((got.text, got.fetchedAt), ('"Video Title"\n"Pokémon"', DateTime.utc(2026, 11, 14, 4, 23, 51)));
    });

    test('downloaded from another address than that of the app: not taken', () async {
      prefetchSnapshot('https://example.org/elsewhere/');
      expect(await takePrefetchedSnapshotFile('highlights.csv'), isNull);
      expect(globalContext.has(snapshotPrefetchGlobal), isFalse);
    });

    test('no branch yet: the HTTP 404 is a SheetHttpException', () async {
      prefetchSnapshot(SnapshotUrls.base, status: 404);
      await expectLater(
        takePrefetchedSnapshotFile('highlights.csv'),
        throwsA(isA<SheetHttpException>().having((e) => e.uri, 'uri', SnapshotUrls.highlights)),
      );
    });

    test('a time that is not one: HttpSnapshotFetcher fails', () async {
      prefetchSnapshot(SnapshotUrls.base, meta: '{"madeAt": "soon"}');
      await expectLater(HttpSnapshotFetcher().fetch(highlights), throwsFormatException);
    });
  });
}
