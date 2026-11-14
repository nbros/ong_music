// The daily copy of each sheet (the snapshot) on a first load: what is asked, what is shown, in which order, with
// which age, and what is kept.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ong_music/src/data/parser.dart';
import 'package:ong_music/src/data/repository.dart';
import 'package:ong_music/src/data/sheet_cache.dart';
import 'package:ong_music/src/data/sheet_snapshot.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/data/slices.dart';
import 'package:ong_music/src/state/catalogue_state.dart';

import 'fixtures.dart';
import 'sheet_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12, 12);
  // two hours old: younger than catalogueMaxAge, which must not make it count as fresh data
  final madeAt = now.subtract(const Duration(hours: 2));
  late DateTime clock;
  late FakeGoogle google;
  late FakeSnapshot snapshot;
  late MemorySheetCache cache;
  late RecordingParser parser;
  late ProviderContainer container;
  late List<CatalogueState> states;

  void copy({String tag = 'snapshot', int extraPlays = 0}) =>
      snapshot.set(sampleSheets(tag: tag, extraPlays: extraPlays), madeAt);

  CatalogueNotifier notifier() => container.read(catalogueProvider.notifier);
  CatalogueState state() => container.read(catalogueProvider);
  String? title([CatalogueState? s]) => (s ?? state()).catalogue?.highlights.first.title;
  String? song([CatalogueState? s]) => (s ?? state()).hasSongs ? (s ?? state()).catalogue!.plays.first.title : null;
  List<String?> shown(String? Function(CatalogueState s) what) => [
    for (final s in states)
      if (s.hasData) what(s),
  ].fold<List<String?>>([], (list, t) => list.isNotEmpty && list.last == t ? list : [...list, t]);
  List<String?> titlesShown() => shown(title);
  List<String?> songsShown() => shown(song);
  void wantSongs([SongsTrigger trigger = SongsTrigger.ongLog]) => notifier().songsWanted(trigger);

  void startWith({MemorySheetCache? cached, SheetParser? parse}) {
    cache = cached ?? MemorySheetCache();
    parser = RecordingParser();
    container = ProviderContainer.test(
      overrides: [
        sheetFetcherProvider.overrideWithValue(google),
        snapshotFetcherProvider.overrideWithValue(snapshot),
        sheetCacheProvider.overrideWithValue(cache),
        sheetParserProvider.overrideWithValue(parse ?? parser),
        songsDeferralProvider.overrideWithValue(() async {}),
        clockProvider.overrideWithValue(() => clock),
        prefetchDiscarderProvider.overrideWithValue(() {}),
      ],
    );
    states = [];
    container.listen(catalogueProvider, (_, next) => states.add(next), fireImmediately: true);
  }

  setUp(() {
    clock = now;
    google = FakeGoogle();
    snapshot = FakeSnapshot();
    copy();
  });

  group('first load, the Highlights sheet', () {
    test('the snapshot first: shown while Google is asked, then replaced by its answer, never blank', () async {
      startWith();
      final gate = google.gate(highlights);
      google.add(sampleSheets(tag: 'google'));
      await pumpEventQueue();
      expect((google.calls[highlights], snapshot.calls[highlights]), (1, 1), reason: 'both asked at once');
      expect(snapshot.calls[songs], 0, reason: 'the copy of the songs waits for the songs');
      expect(title(), 'Video snapshot');
      expect(state().fetchedAt, madeAt, reason: 'the time of the copy, not now');
      expect(state().isSnapshot, isTrue);
      expect(state().isRefreshing, isTrue, reason: "Google's download still runs: the thin bar of a refresh");
      expect(state().lastError, isNull);
      expect(cache.writes, isEmpty, reason: 'the snapshot is never kept');
      gate.complete();
      await notifier().idle;
      expect(title(), 'Video google');
      expect(state().fetchedAt, now);
      expect(state().isSnapshot, isFalse);
      expect(state().isRefreshing, isFalse);
      expect(cache.writes, [highlights]);
      expect(cache.values[highlights]!.fetchedAt, now);
      expect(cache.values[highlights]!.text, contains('Video google'));
      expect(titlesShown(), ['Video snapshot', 'Video google']);
      // the snapshot on the screen may be scrolled while Google's answer is parsed: its frames come first
      expect(parser.of(highlights), ['snapshot', 'google']);
      expect(parser.calls.map((c) => c.background), [false, true]);
      expect(states.skipWhile((s) => !s.hasData).every((s) => s.hasData), isTrue, reason: 'never blanks');
    });

    test('Google first: the snapshot that comes after is ignored, and not even parsed', () async {
      startWith();
      final gate = snapshot.gate(highlights);
      google.add(sampleSheets(tag: 'google'));
      await notifier().idle;
      expect(title(), 'Video google');
      gate.complete();
      await pumpEventQueue();
      expect(title(), 'Video google');
      expect(state().fetchedAt, now);
      expect(titlesShown(), ['Video google']);
      expect(parser.of(highlights), ['google']);
    });

    test("Google's sheet comes while the snapshot is being parsed: that parse is abandoned", () async {
      startWith();
      final parse = parser.gates[(highlights, 'snapshot')] = Completer();
      final gate = google.gate(highlights);
      google.add(sampleSheets(tag: 'google'));
      await pumpEventQueue();
      expect(parser.of(highlights), ['snapshot']);
      expect(parser.calls.single.isAbandoned!(), isFalse);
      gate.complete();
      await pumpEventQueue();
      expect(parser.calls.first.isAbandoned!(), isTrue, reason: "Google's answer within a parse: the copy cannot win");
      parse.complete();
      await notifier().idle;
      await pumpEventQueue();
      expect(titlesShown(), ['Video google']);
    });

    test('a snapshot parsed to its end after Google\'s answer (a background isolate) is dropped', () async {
      startWith();
      final parse = parser.gates[(highlights, 'snapshot')] = Completer();
      parser.deaf.add((highlights, 'snapshot'));
      final gate = google.gate(highlights);
      google.add(sampleSheets(tag: 'google'));
      await pumpEventQueue();
      expect(parser.of(highlights), ['snapshot'], reason: 'the snapshot is being parsed');
      gate.complete();
      await notifier().idle;
      expect(title(), 'Video google');
      expect(parser.of(highlights), ['snapshot', 'google']);
      parse.complete();
      await pumpEventQueue();
      expect(title(), 'Video google');
      expect(state().fetchedAt, now);
      expect(titlesShown(), ['Video google']);
    });

    for (final (name, Object error) in [
      ('missing (HTTP 404: no branch yet)', SheetHttpException(SnapshotUrls.highlights, 404)),
      ('unreachable', const SocketException('offline')),
      ('too slow', TimeoutException('silence')),
      ('a web page', SheetNotCsvException(SnapshotUrls.highlights)),
      ('without a valid time', const FormatException('No UTC time in the snapshot')),
    ]) {
      test('a snapshot $name: the first load as without it, nothing reported', () async {
        startWith();
        snapshot.results[highlights] = error;
        snapshot.results[songs] = error;
        final gate = google.gate(highlights);
        google.add(sampleSheets(tag: 'google'));
        await pumpEventQueue();
        expect(state().isLoading, isTrue);
        expect(state().lastError, isNull);
        gate.complete();
        await notifier().idle;
        expect(title(), 'Video google');
        wantSongs();
        await notifier().idle;
        expect(song(), 'Song google');
        expect(states.every((s) => s.lastError == null && s.songsError == null), isTrue);
        expect(states.every((s) => s.hasData || s.isLoading), isTrue);
      });
    }

    for (final (name, String text) in [
      ('HTML', '<html><body>Not Found</body></html>'),
      ('without the header of a sheet', '"A","B"\n"1","2"'),
      ('with no row', highlightsCsv([])),
      ('cut in a quoted cell', '"'),
    ]) {
      test('a snapshot $name is ignored silently, and deletes no cache', () async {
        // the real parser: what it refuses in a download, it refuses in the snapshot
        snapshot.results[highlights] = CachedSheet(text: text, fetchedAt: madeAt);
        snapshot.results[songs] = CachedSheet(text: text, fetchedAt: madeAt);
        startWith(parse: const ParseOnCurrentIsolate());
        final gate = google.gate(highlights);
        google.add(sampleSheets(tag: 'google'));
        await pumpEventQueue();
        expect(snapshot.calls[highlights], 1);
        expect(state().isLoading, isTrue);
        gate.complete();
        await notifier().idle;
        expect(title(), 'Video google');
        final songsGate = google.gate(songs);
        wantSongs();
        await pumpEventQueue();
        expect(snapshot.calls[songs], 1);
        songsGate.complete();
        await notifier().idle;
        expect(song(), 'Song google');
        expect(states.every((s) => s.lastError == null && s.songsError == null), isTrue);
        expect(cache.clears, 0);
        expect(cache.removes, isEmpty);
      });
    }

    test('Google fails after the snapshot: it stays, with the error of a failed refresh, never kept', () async {
      startWith();
      final gate = google.gate(highlights);
      google.add(const SocketException('offline'));
      await pumpEventQueue();
      expect(title(), 'Video snapshot');
      gate.complete();
      await notifier().idle;
      expect(title(), 'Video snapshot');
      expect(state().fetchedAt, madeAt);
      expect(state().lastError, isA<SocketException>());
      expect((state().isFailed, state().isRefreshing), (false, false));
      expect(cache.values, isEmpty);
      expect(cache.writes, isEmpty);
    });

    test('Google fails before the snapshot comes: the snapshot is shown, the error kept', () async {
      startWith();
      final gate = snapshot.gate(highlights);
      google.add(SheetHttpException(SheetUrls.highlights, 503));
      await notifier().idle;
      expect(state().isFailed, isTrue);
      gate.complete();
      await pumpEventQueue();
      expect(title(), 'Video snapshot');
      expect(state().fetchedAt, madeAt);
      expect(state().lastError, isA<SheetHttpException>());
      expect(state().isFailed, isFalse);
    });

    test("both fail: the failure of the first load, Google's error", () async {
      startWith();
      snapshot.results[highlights] = SheetHttpException(SnapshotUrls.meta, 404);
      google.add(const SocketException('offline'));
      await notifier().idle;
      await pumpEventQueue();
      expect(state().isFailed, isTrue);
      expect(state().lastError, isA<SocketException>());
    });

    test("Google's answer identical to the snapshot: the catalogue on the screen is kept, parsed once", () async {
      copy(tag: 'same');
      startWith();
      final gate = google.gate(highlights);
      google.add(sampleSheets(tag: 'same'));
      await pumpEventQueue();
      final before = state().catalogue;
      expect(before, isNotNull);
      gate.complete();
      await notifier().idle;
      expect(identical(state().catalogue, before), isTrue);
      expect(parser.of(highlights), ['same'], reason: 'nothing parsed again');
      expect(state().fetchedAt, now, reason: "it is Google's answer now");
      expect(state().isSnapshot, isFalse);
      expect(cache.writes, [highlights]);
      expect(cache.values[highlights]!.fetchedAt, now);
    });

    test("Google's answer much smaller than the snapshot is taken: the snapshot keeps no download out", () async {
      snapshot.results[highlights] = CachedSheet(
        text: highlightsCsv([for (var i = 0; i < 6; i++) hRow(title: 'Video snapshot$i')]),
        fetchedAt: madeAt,
      );
      startWith();
      final gate = google.gate(highlights);
      google.add(sampleSheets(tag: 'google'));
      await pumpEventQueue();
      expect(state().highlightCount, 6);
      gate.complete();
      await notifier().idle;
      expect(title(), 'Video google');
      expect(state().highlightCount, 1);
      expect(state().lastError, isNull);
    });

    test('rebuilt or disposed while the snapshot comes: it is dropped', () async {
      startWith();
      final copyGate = snapshot.gate(highlights);
      final gate = google.gate(highlights);
      google
        ..add(sampleSheets(tag: 'first'))
        ..add(sampleSheets(tag: 'second'));
      await pumpEventQueue();
      container.invalidate(catalogueProvider);
      expect(state().isLoading, isTrue);
      await pumpEventQueue();
      expect(snapshot.calls[highlights], 2, reason: 'the new build has nothing kept either');
      copyGate.complete();
      await pumpEventQueue();
      expect(title(), 'Video snapshot', reason: "the new build's own snapshot");
      expect(states.where((s) => s.hasData), hasLength(1), reason: 'shown once, by the new build only');
      final n = notifier();
      container.dispose();
      gate.complete();
      await pumpEventQueue();
      await n.idle;
    });
  });

  group('first load, the Songs sheet', () {
    test('asked for when the songs are, with Google: shown first, then replaced by its answer', () async {
      startWith();
      google.add(sampleSheets(tag: 'google'));
      await notifier().idle;
      expect(snapshot.calls[songs], 0);
      final gate = google.gate(songs);
      wantSongs(SongsTrigger.highlightsShown);
      await pumpEventQueue();
      expect((google.calls[songs], snapshot.calls[songs]), (1, 1), reason: 'both asked at once');
      expect(song(), 'Song snapshot');
      expect(state().isSongsSnapshot, isTrue);
      expect(state().songsFetchedAt, madeAt);
      expect(state().updatedAt, madeAt);
      expect(state().isRefreshingSongs, isTrue);
      expect(cache.writes, [highlights], reason: 'the snapshot is never kept');
      gate.complete();
      await notifier().idle;
      expect(song(), 'Song google');
      expect((state().songsFetchedAt, state().isSongsSnapshot), (now, false));
      expect(cache.writes, [highlights, songs]);
      expect(songsShown(), [null, 'Song snapshot', 'Song google']);
      expect(
        identical(state().catalogue!.highlights, states.firstWhere((s) => s.hasData).catalogue!.highlights),
        isTrue,
      );
    });

    test('Google first: the copy of the songs that comes after is ignored, and not even parsed', () async {
      startWith();
      google.add(sampleSheets(tag: 'google'));
      final copyGate = snapshot.gate(songs);
      wantSongs();
      await notifier().idle;
      expect(song(), 'Song google');
      copyGate.complete();
      await pumpEventQueue();
      expect(song(), 'Song google');
      expect(parser.of(songs), ['google']);
    });

    test(
      'both copies first, then Google for the highlights: the songs are parsed again against them, never gone',
      () async {
        startWith();
        final h = google.gate(highlights), s = google.gate(songs);
        google.add(sampleSheets(tag: 'google'));
        wantSongs();
        await pumpEventQueue();
        expect((title(), song()), ('Video snapshot', 'Song snapshot'));
        h.complete();
        await pumpEventQueue();
        expect((title(), song()), ('Video google', 'Song snapshot'), reason: 'the copy of the songs, in memory');
        expect(cache.reads, [highlights, songs], reason: 'not from a cache: it is in none');
        s.complete();
        await notifier().idle;
        expect((title(), song()), ('Video google', 'Song google'));
        expect(states.skipWhile((s) => !s.hasSongs).every((s) => s.hasSongs), isTrue, reason: 'songs never go');
        expect(parser.of(songs), ['snapshot', 'snapshot', 'google']);
      },
    );

    test('Google fails for the songs after their copy: it stays, with the error, never kept', () async {
      startWith();
      google
        ..addFor(highlights, sampleSheets(tag: 'google').highlightsCsv)
        ..addFor(songs, const SocketException('offline'));
      final copyGate = snapshot.gate(songs);
      wantSongs();
      await notifier().idle;
      expect(state().isSongsFailed, isTrue);
      copyGate.complete();
      await notifier().idle;
      await pumpEventQueue();
      expect(song(), 'Song snapshot');
      expect(state().songsError, isA<SocketException>());
      expect(state().isSongsFailed, isFalse);
      expect(state().anyError, isA<SocketException>());
      expect(cache.values.keys, [highlights]);
    });

    test("Google's songs identical to their copy: kept on the screen, parsed once, no longer the copy", () async {
      copy(tag: 'same');
      startWith();
      final s = google.gate(songs);
      google.add(sampleSheets(tag: 'same'));
      wantSongs();
      await pumpEventQueue();
      await pumpEventQueue();
      final before = state().catalogue;
      expect(before!.hasSongs, isTrue);
      s.complete();
      await notifier().idle;
      expect(identical(state().catalogue, before), isTrue);
      expect(parser.of(songs), ['same']);
      expect((state().songsFetchedAt, state().isSongsSnapshot), (now, false));
      expect(cache.values[songs]!.fetchedAt, now);
    });

    test("Google's songs much smaller than their copy are taken", () async {
      copy(extraPlays: 4);
      startWith();
      final s = google.gate(songs);
      google.add(sampleSheets(tag: 'google'));
      wantSongs();
      await pumpEventQueue();
      await pumpEventQueue();
      expect(state().playCount, 5);
      s.complete();
      await notifier().idle;
      expect(state().playCount, 1);
      expect(state().songsError, isNull);
    });
  });

  group('returning visitors', () {
    for (final (name, age) in [
      ('a fresh cache', const Duration(hours: 1)),
      ('a stale cache', const Duration(hours: 7)),
      ('a cache older than the snapshot', const Duration(days: 30)),
    ]) {
      test('$name: no snapshot asked, the kept data shown', () async {
        startWith(cached: cacheOf(sampleSheets(tag: 'kept'), now.subtract(age)));
        final gate = google.gate(highlights);
        google.add(sampleSheets(tag: 'google'));
        wantSongs();
        await pumpEventQueue();
        expect(title(), 'Video kept');
        expect(state().fetchedAt, now.subtract(age));
        gate.complete();
        await notifier().idle;
        expect(snapshot.calls, {highlights: 0, songs: 0});
        expect(titlesShown().contains('Video snapshot'), isFalse);
        expect(songsShown().contains('Song snapshot'), isFalse);
      });
    }

    test(
      'the highlights kept, not the songs (the last visit left before they came): no copy of the songs either',
      () async {
        startWith(cached: cacheOf(sampleSheets(tag: 'kept'), now, withSongs: false));
        google.add(sampleSheets(tag: 'google'));
        wantSongs();
        await notifier().idle;
        expect(snapshot.calls, {highlights: 0, songs: 0});
        expect(song(), 'Song google');
      },
    );

    test('a cache that cannot be read (a failure that is not about its content): no snapshot', () async {
      startWith(cached: cacheOf(sampleSheets(tag: 'kept'), now));
      parser.failures[highlights]!.add(Exception('Unable to spawn isolate'));
      google.add(sampleSheets(tag: 'google'));
      await notifier().idle;
      expect(snapshot.calls[highlights], 0);
      expect(title(), 'Video google');
    });

    test('clear downloaded data asks for no snapshot: the data in memory stays meanwhile', () async {
      startWith(cached: cacheOf(sampleSheets(tag: 'kept'), now));
      wantSongs();
      await notifier().idle;
      google.add(sampleSheets(tag: 'google'));
      await notifier().clearDownloadedData();
      expect(title(), 'Video google');
      expect(song(), 'Song google');
      expect(snapshot.calls, {highlights: 0, songs: 0});
    });
  });

  group('the snapshot never delays a download', () {
    testWidgets('Google failed: tried again after 15 seconds, however recent the copy', (tester) async {
      startWith();
      google
        ..add(const SocketException('offline'))
        ..add(sampleSheets(tag: 'google'));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(title(), 'Video snapshot');
      expect(state().lastError, isA<SocketException>());
      expect(google.calls[highlights], 1);
      clock = clock.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      expect(google.calls[highlights], 2);
      expect(title(), 'Video google');
      expect(state().lastError, isNull);
      container.dispose();
    });

    testWidgets('the same for the songs: their copy counts as due', (tester) async {
      startWith();
      google
        ..addFor(highlights, sampleSheets(tag: 'google').highlightsCsv)
        ..addFor(songs, const SocketException('offline'))
        ..addFor(songs, sampleSheets(tag: 'google').songsCsv);
      await tester.pump(Duration.zero);
      wantSongs();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(song(), 'Song snapshot');
      expect(google.calls[songs], 1);
      clock = clock.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      expect(google.calls[songs], 2);
      expect(song(), 'Song google');
      container.dispose();
    });

    testWidgets('the snapshot came after the failure: the retry is still at 15 seconds', (tester) async {
      startWith();
      final copyGate = snapshot.gate(highlights);
      google
        ..add(const SocketException('offline'))
        ..add(sampleSheets(tag: 'google'));
      await tester.pump(Duration.zero);
      expect(state().isFailed, isTrue);
      clock = clock.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      copyGate.complete();
      await tester.pump(Duration.zero);
      expect(title(), 'Video snapshot');
      clock = clock.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      expect(google.calls[highlights], 2);
      expect(title(), 'Video google');
      container.dispose();
    });

    testWidgets("Google's answer identical to the snapshot is fresh data: nothing is asked again", (tester) async {
      copy(tag: 'same');
      startWith();
      final gate = google.gate(highlights);
      google.add(sampleSheets(tag: 'same'));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(state().catalogue, isNotNull);
      gate.complete();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(state().fetchedAt, now);
      for (var i = 0; i < 10; i++) {
        clock = clock.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(google.calls[highlights], 1, reason: 'the same catalogue on the screen no longer counts as the snapshot');
      container.dispose();
    });

    test('back to the app with the snapshot on the screen: Google is asked at once', () async {
      startWith();
      google
        ..add(const SocketException('offline'))
        ..add(sampleSheets(tag: 'google'));
      await notifier().idle;
      await pumpEventQueue();
      expect(title(), 'Video snapshot');
      await notifier().refreshIfStale();
      expect(google.calls[highlights], 2);
      expect(title(), 'Video google');
    });
  });

  group('HttpSnapshotFetcher', () {
    String meta(Object? madeAt) => jsonEncode({'madeAt': madeAt, 'highlightsRows': 1, 'songsRows': 2});

    test('the default address is the branch sheets-snapshot of the repository', () {
      expect(SnapshotUrls.base, 'https://raw.githubusercontent.com/nbros/ong_music/sheets-snapshot/');
      expect(SnapshotUrls.highlights.toString(), '${SnapshotUrls.base}highlights.csv');
      expect(SnapshotUrls.songs.toString(), '${SnapshotUrls.base}songs.csv');
      expect(SnapshotUrls.meta.toString(), '${SnapshotUrls.base}snapshot.json');
      expect([for (final sheet in Sheet.values) SnapshotUrls.of(sheet)], [SnapshotUrls.highlights, SnapshotUrls.songs]);
    });

    test(
      'reads the file of a sheet and the time of the copy, as UTF-8 whatever the declared charset; the time once',
      () async {
        final asked = <Uri>[];
        final client = MockClient((request) async {
          asked.add(request.url);
          final body = request.url == SnapshotUrls.highlights
              ? '"Video Title"\n"Pokémon"'
              : request.url == SnapshotUrls.songs
              ? '"Title"\n"♪"'
              : meta('2026-11-14T04:23:51Z');
          return http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'text/plain; charset=latin1'});
        });
        final fetcher = HttpSnapshotFetcher(client: client);
        final got = await fetcher.fetch(highlights);
        expect(asked.toSet(), {SnapshotUrls.highlights, SnapshotUrls.meta}, reason: 'not the songs: not asked for');
        expect(got.text, '"Video Title"\n"Pokémon"');
        expect(got.fetchedAt, DateTime.utc(2026, 11, 14, 4, 23, 51));
        final other = await fetcher.fetch(songs);
        expect(other.text, '"Title"\n"♪"');
        expect(other.fetchedAt, DateTime.utc(2026, 11, 14, 4, 23, 51));
        expect(asked.where((u) => u == SnapshotUrls.meta), hasLength(1), reason: 'the time of the copy read once');
      },
    );

    test('a time that cannot be read is asked again by the next sheet', () async {
      var metas = 0;
      final client = MockClient((request) async {
        if (request.url == SnapshotUrls.meta) {
          return http.Response(metas++ == 0 ? 'oops' : meta('2026-11-14T04:23:51Z'), 200);
        }
        return http.Response('"Title"', 200);
      });
      final fetcher = HttpSnapshotFetcher(client: client);
      await expectLater(fetcher.fetch(highlights), throwsFormatException);
      expect((await fetcher.fetch(songs)).fetchedAt, DateTime.utc(2026, 11, 14, 4, 23, 51));
    });

    test('no branch yet (HTTP 404), a web page: errors', () async {
      await expectLater(
        HttpSnapshotFetcher(client: MockClient((_) async => http.Response('404: Not Found', 404))).fetch(highlights),
        throwsA(isA<SheetHttpException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
      await expectLater(
        HttpSnapshotFetcher(client: MockClient((_) async => http.Response('<!DOCTYPE html>', 200))).fetch(songs),
        throwsA(isA<SheetNotCsvException>()),
      );
    });

    test('the time of the copy: an ISO-8601 time in UTC, nothing else', () {
      expect(snapshotTime(meta('2026-11-14T04:23:51Z')), DateTime.utc(2026, 11, 14, 4, 23, 51));
      for (final bad in [
        'not json',
        '[]',
        '{}',
        meta(null),
        meta(12),
        meta('yesterday'),
        meta('2026-11-14T04:23:51'), // a local time: of which zone?
      ]) {
        expect(() => snapshotTime(bad), throwsFormatException, reason: bad);
      }
      // an offset designates one instant: accepted (the script writes Z)
      expect(snapshotTime(meta('2026-11-14T04:23:51+01:00')), DateTime.utc(2026, 11, 14, 3, 23, 51));
    });
  });

  test('the repository reads the snapshot of a sheet as a download, dated by the copy, and caches nothing', () async {
    final cache = MemorySheetCache();
    snapshot.set(sampleSheets(tag: 'snapshot'), madeAt);
    final repository = CatalogueRepository(
      fetcher: FakeGoogle(),
      cache: cache,
      parser: const ParseOnCurrentIsolate(),
      snapshots: snapshot,
    );
    final loaded = await repository.snapshot(highlights);
    expect(
      (loaded.isSnapshot, loaded.fetchedAt, loaded.text),
      (true, madeAt, sampleSheets(tag: 'snapshot').highlightsCsv),
    );
    expect(loaded.fingerprint, await fingerprintAtOnce(sampleSheets(tag: 'snapshot').highlightsCsv));
    expect(cache.writes, isEmpty);
    expect(cache.clears, 0);
    await expectLater(repository.parseHighlights('x'), throwsA(isA<CatalogueFormatException>()));
    await expectLater(repository.snapshot(songs, isAbandoned: () => true), throwsA(isA<LoadAbandoned>()));
    await expectLater(const NoSnapshot().fetch(highlights), throwsStateError);
  });

  test('without a snapshot fetcher, the repository has none', () async {
    final repository = CatalogueRepository(
      fetcher: FakeGoogle(),
      cache: MemorySheetCache(),
      parser: const ParseOnCurrentIsolate(),
    );
    await expectLater(repository.snapshot(highlights), throwsStateError);
  });

  test('the parser of the app rejects in a snapshot what it rejects in a download', () {
    expect(() => parseHighlights('<html>'), throwsA(isA<CatalogueFormatException>()));
    expect(
      () => parseSongs(parseHighlights(sampleSheets().highlightsCsv), '<html>'),
      throwsA(isA<CatalogueFormatException>()),
    );
  });
}
