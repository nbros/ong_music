import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ong_music/src/data/sheet_cache_io.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FileSheetCache', () {
    late Directory tmp;
    late FileSheetCache cache;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('ong_cache_test');
      cache = FileSheetCache(() async => Directory(p.join(tmp.path, 'sheets')));
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('round trip, overwrite, clear', () async {
      expect(await cache.read(), isNull);
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      await cache.write(
        CachedSheets(
          sheets: const RawSheets(highlightsCsv: 'h1 é', songsCsv: 's1 ♪'),
          fetchedAt: at,
        ),
      );
      var read = (await cache.read())!;
      expect((read.sheets.highlightsCsv, read.sheets.songsCsv, read.fetchedAt), ('h1 é', 's1 ♪', at));
      await cache.write(
        CachedSheets(
          sheets: const RawSheets(highlightsCsv: 'h2', songsCsv: 's2'),
          fetchedAt: at.add(const Duration(days: 1)),
        ),
      );
      read = (await cache.read())!;
      expect((read.sheets.highlightsCsv, read.fetchedAt.day), ('h2', 3));
      await cache.clear();
      expect(await cache.read(), isNull);
      await cache.clear(); // twice is fine
    });

    test('an incomplete cache reads as none', () async {
      await cache.write(
        CachedSheets(
          sheets: const RawSheets(highlightsCsv: 'h', songsCsv: 's'),
          fetchedAt: DateTime.utc(2026),
        ),
      );
      File(p.join(tmp.path, 'sheets', 'songs.csv')).deleteSync();
      expect(await cache.read(), isNull);
    });

    test('temporary files of a write that never finished are deleted by a later write', () async {
      final dir = Directory(p.join(tmp.path, 'sheets'))..createSync();
      // the app was killed while writing, an hour ago; another instance is writing right now
      final orphan = File(p.join(dir.path, 'songs.csv.4242-7.tmp'))..writeAsStringSync('half a sheet');
      orphan.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
      final running = File(p.join(dir.path, 'songs.csv.4343-0.tmp'))..writeAsStringSync('being written');
      await cache.write(
        CachedSheets(
          sheets: const RawSheets(highlightsCsv: 'h1', songsCsv: 's1'),
          fetchedAt: DateTime.utc(2026),
        ),
      );
      expect(orphan.existsSync(), isFalse);
      expect(running.existsSync(), isTrue, reason: 'a recent temporary file may belong to a write still running');
      expect((await cache.read())!.sheets.songsCsv, 's1');
    });

    test('a write that fails half-way reads as no cache, never as sheets of two downloads', () async {
      await cache.write(
        CachedSheets(
          sheets: const RawSheets(highlightsCsv: 'h1', songsCsv: 's1'),
          fetchedAt: DateTime.utc(2026),
        ),
      );
      // songs.csv cannot be replaced (disk full, file locked...): the write stops after highlights.csv
      final songs = p.join(tmp.path, 'sheets', 'songs.csv');
      File(songs).deleteSync();
      Directory(songs).createSync();
      File(p.join(songs, 'locked')).createSync();
      await cache.write(
        CachedSheets(
          sheets: const RawSheets(highlightsCsv: 'h2', songsCsv: 's2'),
          fetchedAt: DateTime.utc(2026, 2),
        ),
      );
      expect(File(p.join(tmp.path, 'sheets', 'highlights.csv')).readAsStringSync(), 'h2');
      expect(await cache.read(), isNull);
      expect(
        Directory(
          p.join(tmp.path, 'sheets'),
        ).listSync().map((e) => p.basename(e.path)).where((n) => n.endsWith('.tmp')),
        isEmpty,
        reason: 'no temporary file left behind',
      );
    });

    test('a write running at the same time (the app started twice) does not mix into the files', () async {
      final dir = Directory(p.join(tmp.path, 'sheets'))..createSync();
      // the other instance has started writing its highlights to a temporary file, and goes on after ours
      final other = await File(p.join(dir.path, 'highlights.csv.tmp')).open(mode: FileMode.write);
      await other.writeString('OTHER-FIRST-HALF');
      await cache.write(
        CachedSheets(
          sheets: const RawSheets(highlightsCsv: 'highlights of this instance', songsCsv: 'songs'),
          fetchedAt: DateTime.utc(2026),
        ),
      );
      await other.writeString('OTHER-SECOND-HALF');
      await other.close();
      final read = (await cache.read())!;
      expect(read.sheets.highlightsCsv, 'highlights of this instance');
    });

    test('no application directory (path_provider failing): no cache, and nothing throws', () async {
      final broken = FileSheetCache(() async => throw const FileSystemException('No application support directory'));
      await broken.write(
        CachedSheets(
          sheets: const RawSheets(highlightsCsv: 'h', songsCsv: 's'),
          fetchedAt: DateTime.utc(2026),
        ),
      );
      expect(await broken.read(), isNull);
      await broken.clear();
    });

    test('deleteLegacyDatabase removes the old SQLite files only', () async {
      final support = Directory(p.join(tmp.path, 'files'))..createSync();
      final databases = Directory(p.join(tmp.path, 'databases'))..createSync();
      for (final name in ['ongLog3.db', 'ongLog3.db-journal', 'other.db']) {
        File(p.join(databases.path, name)).writeAsStringSync('x');
      }
      await deleteLegacyDatabase(support);
      expect(databases.listSync().map((f) => p.basename(f.path)), ['other.db']);
      await deleteLegacyDatabase(Directory(p.join(tmp.path, 'missing', 'files'))); // silent
    });
  });

  group('HttpSheetFetcher', () {
    test('decodes UTF-8 from the bytes whatever the declared charset', () async {
      final client = MockClient((request) async {
        final sheet = request.url.queryParameters['sheet'];
        return http.Response.bytes(
          utf8.encode('$sheet: Pokémon ♪'),
          200,
          headers: {'content-type': 'text/csv; charset=iso-8859-1'},
        );
      });
      final sheets = await HttpSheetFetcher(client: client).fetch();
      expect(sheets.highlightsCsv, 'Youtube Catalogue: Pokémon ♪');
      expect(sheets.songsCsv, 'Songs: Pokémon ♪');
    });

    test('a non-200 answer throws', () async {
      final client = MockClient((request) async => http.Response('nope', 503));
      expect(HttpSheetFetcher(client: client).fetch(), throwsA(isA<SheetHttpException>()));
    });

    test('times out', () async {
      final client = MockClient((request) => Completer<http.Response>().future);
      expect(
        HttpSheetFetcher(client: client, timeout: const Duration(milliseconds: 10)).fetch(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('a web page instead of CSV (Wi-Fi sign-in, private sheet) is not a format error of the sheets', () async {
      for (final page in ['<!DOCTYPE html><html><body>Sign in</body></html>', '\uFEFF \n<html>']) {
        final client = MockClient((request) async {
          final songs = request.url.queryParameters['sheet'] == 'Songs';
          return http.Response.bytes(utf8.encode(songs ? page : '"Title"\n"a < b"'), 200);
        });
        await expectLater(
          HttpSheetFetcher(client: client).fetch(),
          throwsA(
            isA<SheetNotCsvException>()
                .having((e) => e.uri, 'uri', SheetUrls.songs)
                .having((e) => e, 'not a FormatException', isNot(isA<FormatException>())),
          ),
        );
      }
    });

    group('a slow download', () {
      // Real time, with wide margins: the limit on silence is 1 s, the pieces come every 200 ms.
      const silence = Duration(seconds: 1);
      const pace = Duration(milliseconds: 200);
      late List<StreamController<List<int>>> bodies;
      late MockClient client;

      setUp(() {
        bodies = [];
        client = MockClient.streaming((request, _) async {
          final body = StreamController<List<int>>();
          bodies.add(body);
          return http.StreamedResponse(body.stream, 200);
        });
      });

      /// [count] pieces of each sheet, [pace] apart, once both answers have started.
      Future<void> pieces(int count) async {
        while (bodies.length < 2) {
          await Future<void>.delayed(Duration.zero);
        }
        for (var i = 0; i < count; i++) {
          for (final body in bodies) {
            body.add(utf8.encode('é'));
          }
          await Future<void>.delayed(pace);
        }
      }

      test('arrives, however long it takes, while the server keeps sending', () async {
        final sheets = HttpSheetFetcher(client: client, timeout: silence).fetch();
        // more than twice the limit on silence
        await pieces(12);
        for (final body in bodies) {
          unawaited(body.close());
        }
        expect((await sheets).songsCsv, 'é' * 12);
        expect((await sheets).highlightsCsv, 'é' * 12);
      });

      test('is given up after a silence of the server', () async {
        final watch = Stopwatch()..start();
        final sheets = HttpSheetFetcher(client: client, timeout: silence).fetch();
        unawaited(pieces(3));
        await expectLater(sheets, throwsA(isA<TimeoutException>()));
        // after the last piece, not after the start
        expect(watch.elapsed, greaterThan(pace * 2 + silence));
        expect(bodies.every((body) => !body.hasListener), isTrue, reason: 'the downloads are cancelled');
      });

      test('is given up after the longest time allowed', () async {
        final watch = Stopwatch()..start();
        final sheets = HttpSheetFetcher(client: client, timeout: silence, maxDuration: pace * 3).fetch();
        unawaited(pieces(20));
        await expectLater(sheets, throwsA(isA<TimeoutException>()));
        expect(watch.elapsed, lessThan(pace * 15));
        // what a client of its own gets closed for
        for (final body in bodies) {
          unawaited(body.close());
        }
      });
    });
  });
}
