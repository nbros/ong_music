import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ong_music/src/data/sheet_cache_io.dart';
import 'package:ong_music/src/data/sheets.dart';

import 'sheet_fakes.dart';
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

    CachedSheet sheet(String text, [DateTime? at]) => CachedSheet(text: text, fetchedAt: at ?? DateTime.utc(2026));
    String file(String name) => p.join(tmp.path, 'sheets', name);
    List<String> files() =>
        [for (final e in Directory(p.join(tmp.path, 'sheets')).listSync()) p.basename(e.path)]..sort();

    test('round trip, overwrite, clear, each sheet on its own', () async {
      expect(await cache.read(highlights), isNull);
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      await cache.write(highlights, sheet('h1 é', at));
      expect(await cache.read(songs), isNull, reason: 'the other sheet is not written with it');
      await cache.write(songs, sheet('s1 ♪', at.add(const Duration(hours: 1))));
      var h = (await cache.read(highlights))!, s = (await cache.read(songs))!;
      expect((h.text, h.fetchedAt, s.text, s.fetchedAt), ('h1 é', at, 's1 ♪', at.add(const Duration(hours: 1))));
      await cache.write(highlights, sheet('h2', at.add(const Duration(days: 1))));
      h = (await cache.read(highlights))!;
      s = (await cache.read(songs))!;
      expect((h.text, h.fetchedAt.day, s.text, s.fetchedAt), ('h2', 3, 's1 ♪', at.add(const Duration(hours: 1))));
      expect(files(), ['highlights.csv', 'highlights_fetched_at.txt', 'songs.csv', 'songs_fetched_at.txt']);
      await cache.remove(songs);
      expect(await cache.read(songs), isNull);
      expect((await cache.read(highlights))!.text, 'h2');
      await cache.clear();
      expect(await cache.read(highlights), isNull);
      await cache.clear(); // twice is fine
      await cache.remove(highlights); // and nothing to remove
    });

    test('an incomplete copy of a sheet reads as none, the other sheet as it is', () async {
      await cache.write(highlights, sheet('h'));
      await cache.write(songs, sheet('s'));
      File(file('songs.csv')).deleteSync();
      expect(await cache.read(songs), isNull);
      expect((await cache.read(highlights))!.text, 'h');
    });

    group('the cache of the versions up to 2.0.0', () {
      // what FileSheetCache of 2.0.0 wrote: both texts, then the time of both
      final kept = DateTime.utc(2026, 11, 10, 8, 30);
      void legacy({bool songsText = true}) {
        Directory(p.join(tmp.path, 'sheets')).createSync();
        File(file('highlights.csv')).writeAsStringSync('old h');
        if (songsText) File(file('songs.csv')).writeAsStringSync('old s');
        File(file('fetched_at.txt')).writeAsStringSync(kept.toIso8601String());
      }

      test('both sheets read with its one time: nothing downloaded again for it', () async {
        legacy();
        final h = (await cache.read(highlights))!, s = (await cache.read(songs))!;
        expect((h.text, h.fetchedAt, s.text, s.fetchedAt), ('old h', kept, 'old s', kept));
        expect(files(), ['fetched_at.txt', 'highlights.csv', 'songs.csv'], reason: 'reading changes nothing');
      });

      test('the first write gives each sheet that time, then drops it: the other sheet keeps its age', () async {
        legacy();
        final now = DateTime.utc(2026, 11, 14);
        await cache.write(highlights, sheet('new h', now));
        expect(files(), ['highlights.csv', 'highlights_fetched_at.txt', 'songs.csv', 'songs_fetched_at.txt']);
        final h = (await cache.read(highlights))!, s = (await cache.read(songs))!;
        expect((h.text, h.fetchedAt, s.text, s.fetchedAt), ('new h', now, 'old s', kept));
      });

      test('a sheet removed: the other one keeps that time', () async {
        legacy();
        await cache.remove(highlights);
        expect(await cache.read(highlights), isNull);
        expect((await cache.read(songs))!.fetchedAt, kept);
        expect(files(), ['songs.csv', 'songs_fetched_at.txt']);
      });

      test('two writes at once (both sheets downloaded together): both kept, whichever splits the time', () async {
        legacy();
        final h = DateTime.utc(2026, 11, 14, 1), so = DateTime.utc(2026, 11, 14, 2);
        await Future.wait([cache.write(highlights, sheet('new h', h)), cache.write(songs, sheet('new s', so))]);
        final rh = (await cache.read(highlights))!, rs = (await cache.read(songs))!;
        expect((rh.text, rh.fetchedAt, rs.text, rs.fetchedAt), ('new h', h, 'new s', so));
        expect(files(), ['highlights.csv', 'highlights_fetched_at.txt', 'songs.csv', 'songs_fetched_at.txt']);
      });

      test('a sheet missing from it is not given a time', () async {
        legacy(songsText: false);
        expect(await cache.read(songs), isNull);
        await cache.write(highlights, sheet('new h'));
        expect(files(), ['highlights.csv', 'highlights_fetched_at.txt']);
        expect(await cache.read(songs), isNull);
      });
    });

    test('temporary files of a write that never finished are deleted by a later write', () async {
      final dir = Directory(p.join(tmp.path, 'sheets'))..createSync();
      // the app was killed while writing, an hour ago; another instance is writing right now
      final orphan = File(p.join(dir.path, 'songs.csv.4242-7.tmp'))..writeAsStringSync('half a sheet');
      orphan.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
      final running = File(p.join(dir.path, 'songs.csv.4343-0.tmp'))..writeAsStringSync('being written');
      await cache.write(songs, sheet('s1'));
      expect(orphan.existsSync(), isFalse);
      expect(running.existsSync(), isTrue, reason: 'a recent temporary file may belong to a write still running');
      expect((await cache.read(songs))!.text, 's1');
    });

    test('a write that fails half-way reads as no copy of its sheet, never as the time of another download', () async {
      await cache.write(highlights, sheet('h1'));
      await cache.write(songs, sheet('s1'));
      // songs.csv cannot be replaced (disk full, file locked...): the write stops before its time
      final songsFile = file('songs.csv');
      File(songsFile).deleteSync();
      Directory(songsFile).createSync();
      File(p.join(songsFile, 'locked')).createSync();
      await cache.write(songs, sheet('s2', DateTime.utc(2026, 2)));
      expect(await cache.read(songs), isNull);
      expect((await cache.read(highlights))!.text, 'h1', reason: 'the other sheet untouched');
      expect(files().where((n) => n.endsWith('.tmp')), isEmpty, reason: 'no temporary file left behind');
    });

    test('a write running at the same time (the app started twice) does not mix into the files', () async {
      final dir = Directory(p.join(tmp.path, 'sheets'))..createSync();
      // the other instance has started writing its highlights to a temporary file, and goes on after ours
      final other = await File(p.join(dir.path, 'highlights.csv.tmp')).open(mode: FileMode.write);
      await other.writeString('OTHER-FIRST-HALF');
      await cache.write(highlights, sheet('highlights of this instance'));
      await other.writeString('OTHER-SECOND-HALF');
      await other.close();
      expect((await cache.read(highlights))!.text, 'highlights of this instance');
    });

    test('no application directory (path_provider failing): no cache, and nothing throws', () async {
      final broken = FileSheetCache(() async => throw const FileSystemException('No application support directory'));
      await broken.write(highlights, sheet('h'));
      expect(await broken.read(highlights), isNull);
      await broken.remove(songs);
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
      final fetcher = HttpSheetFetcher(client: client);
      expect(await fetcher.fetch(highlights), 'Youtube Catalogue: Pokémon ♪');
      expect(await fetcher.fetch(songs), 'Songs: Pokémon ♪');
    });

    test('a non-200 answer throws', () async {
      final client = MockClient((request) async => http.Response('nope', 503));
      expect(HttpSheetFetcher(client: client).fetch(highlights), throwsA(isA<SheetHttpException>()));
    });

    test('times out', () async {
      final client = MockClient((request) => Completer<http.Response>().future);
      expect(
        HttpSheetFetcher(client: client, timeout: const Duration(milliseconds: 10)).fetch(songs),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('a web page instead of CSV (Wi-Fi sign-in, private sheet) is not a format error of the sheets', () async {
      for (final page in ['<!DOCTYPE html><html><body>Sign in</body></html>', '\uFEFF \n<html>']) {
        final client = MockClient((request) async {
          final songs = request.url.queryParameters['sheet'] == 'Songs';
          return http.Response.bytes(utf8.encode(songs ? page : '"Title"\n"a < b"'), 200);
        });
        expect(await HttpSheetFetcher(client: client).fetch(highlights), '"Title"\n"a < b"');
        await expectLater(
          HttpSheetFetcher(client: client).fetch(songs),
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

      /// The server that sends the pieces, see [pieces]: over when it has sent them all, or when [serverStopped].
      Future<void>? server;
      var serverStopped = false;

      setUp(() {
        bodies = [];
        server = null;
        serverStopped = false;
        client = MockClient.streaming((request, _) async {
          final body = StreamController<List<int>>();
          bodies.add(body);
          return http.StreamedResponse(body.stream, 200);
        });
      });

      // Nothing of a test may go on after it: a piece sent to a closed answer, later, would fail the test "after it
      // had already completed", and only on a machine slow enough to still be running the file by then.
      tearDown(() async {
        serverStopped = true;
        await server;
        for (final body in bodies) {
          if (!body.isClosed) unawaited(body.close());
        }
      });

      /// [count] pieces of each sheet, [pace] apart, once both answers have started.
      Future<void> pieces(int count) {
        Future<void> send() async {
          while (bodies.length < 2) {
            if (serverStopped) return;
            await Future<void>.delayed(Duration.zero);
          }
          for (var i = 0; i < count && !serverStopped; i++) {
            for (final body in bodies) {
              if (!body.isClosed) body.add(utf8.encode('é'));
            }
            await Future<void>.delayed(pace);
          }
        }

        return server = send();
      }

      test('arrives, however long it takes, while the server keeps sending', () async {
        final fetcher = HttpSheetFetcher(client: client, timeout: silence);
        final sheets = Future.wait([fetcher.fetch(highlights), fetcher.fetch(songs)]);
        // more than twice the limit on silence
        await pieces(12);
        for (final body in bodies) {
          unawaited(body.close());
        }
        expect(await sheets, ['é' * 12, 'é' * 12]);
      });

      test('is given up after a silence of the server', () async {
        final watch = Stopwatch()..start();
        final fetcher = HttpSheetFetcher(client: client, timeout: silence);
        final sheets = Future.wait([fetcher.fetch(highlights), fetcher.fetch(songs)]);
        unawaited(pieces(3));
        await expectLater(sheets, throwsA(isA<TimeoutException>()));
        // after the last piece, not after the start
        expect(watch.elapsed, greaterThan(pace * 2 + silence));
        expect(bodies.every((body) => !body.hasListener), isTrue, reason: 'the downloads are cancelled');
      });

      test('is given up after the longest time allowed', () async {
        final watch = Stopwatch()..start();
        final fetcher = HttpSheetFetcher(client: client, timeout: silence, maxDuration: pace * 3);
        final sheets = Future.wait([fetcher.fetch(highlights), fetcher.fetch(songs)]);
        unawaited(pieces(20));
        await expectLater(sheets, throwsA(isA<TimeoutException>()));
        expect(watch.elapsed, lessThan(pace * 15));
      });

      test('nothing of these tests goes on after them', () async {
        // long enough for a piece sent late by one of the tests above to arrive, and fail that test
        await Future<void>.delayed(pace * 3);
        expect(server, isNull);
      });
    });
  });
}
