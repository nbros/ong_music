// The daily copy of the sheets (the snapshot) on a first load: what is asked, what is shown, in which order, with
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

/// Google: each call answers the next of [results] (sheets, or an error to throw), once [gate] (when set) completes.
class FakeGoogle implements SheetFetcher {
  final results = <Object>[];
  int calls = 0;
  Completer<void>? gate;

  @override
  Future<RawSheets> fetch() async {
    calls++;
    if (gate != null) await gate!.future;
    final r = results.removeAt(0);
    if (r is RawSheets) return r;
    throw r;
  }
}

/// The snapshot: [result] (sheets with their time, or an error to throw), once [gate] (when set) completes.
class FakeSnapshot implements SnapshotFetcher {
  FakeSnapshot(this.result);

  Object result;
  int calls = 0;
  Completer<void>? gate;

  @override
  Future<CachedSheets> fetch() async {
    calls++;
    if (gate != null) await gate!.future;
    final r = result;
    if (r is CachedSheets) return r;
    throw r;
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 12, 12);
  // two hours old: younger than catalogueMaxAge, which must not make it count as fresh data
  final madeAt = now.subtract(const Duration(hours: 2));
  late DateTime clock;
  late FakeGoogle google;
  late FakeSnapshot snapshot;
  late MemorySheetCache cache;
  late ProviderContainer container;
  late List<CatalogueState> states;
  late List<String> parsed;
  // the isAbandoned and the background of each parse, in order
  late List<bool Function()?> abandoned;
  late List<bool> backgrounds;
  Completer<void>? snapshotParseGate;
  // the snapshot parse runs to its end whatever it is told, as on a background isolate (parseInBackground)
  var snapshotParseDeaf = false;

  CachedSheets snapshotOf({String tag = 'snapshot', int extraPlays = 0}) => CachedSheets(
    sheets: sampleSheets(tag: tag, extraPlays: extraPlays),
    fetchedAt: madeAt,
  );

  CatalogueNotifier notifier() => container.read(catalogueProvider.notifier);
  CatalogueState state() => container.read(catalogueProvider);
  String? title([CatalogueState? s]) => (s ?? state()).catalogue?.highlights.first.title;
  List<String?> titlesShown() => [
    for (final s in states)
      if (s.hasData) title(s),
  ].fold<List<String?>>([], (list, t) => list.isNotEmpty && list.last == t ? list : [...list, t]);

  void startWith({CachedSheets? cached}) {
    cache = MemorySheetCache(cached);
    parsed = [];
    abandoned = [];
    backgrounds = [];
    container = ProviderContainer.test(
      overrides: [
        sheetFetcherProvider.overrideWithValue(google),
        snapshotFetcherProvider.overrideWithValue(snapshot),
        sheetCacheProvider.overrideWithValue(cache),
        catalogueParserProvider.overrideWithValue((sheets, {isAbandoned, background = false}) async {
          // the title of the first highlight, after the header ("Video Title")
          final tag = RegExp(r'"Video (\w+)"').allMatches(sheets.highlightsCsv).skip(1).firstOrNull?[1] ?? '?';
          parsed.add(tag);
          abandoned.add(isAbandoned);
          backgrounds.add(background);
          if (tag == 'snapshot' && snapshotParseGate != null) await snapshotParseGate!.future;
          if (!(tag == 'snapshot' && snapshotParseDeaf) && (isAbandoned?.call() ?? false)) throw const LoadAbandoned();
          return parseOnCurrentIsolate(sheets);
        }),
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
    snapshot = FakeSnapshot(snapshotOf());
    snapshotParseGate = null;
    snapshotParseDeaf = false;
  });

  group('first load', () {
    test('the snapshot first: shown while Google is asked, then replaced by its answer, never blank', () async {
      startWith();
      google
        ..gate = Completer()
        ..results.add(sampleSheets(tag: 'google'));
      await pumpEventQueue();
      expect((google.calls, snapshot.calls), (1, 1), reason: 'both asked at once');
      expect(title(), 'Video snapshot');
      expect(state().fetchedAt, madeAt, reason: 'the time of the copy, not now');
      expect(state().isRefreshing, isTrue, reason: "Google's download still runs: the thin bar of a refresh");
      expect(state().lastError, isNull);
      expect(cache.writes, 0, reason: 'the snapshot is never kept');
      google.gate!.complete();
      await notifier().idle;
      expect(title(), 'Video google');
      expect(state().fetchedAt, now);
      expect(state().isRefreshing, isFalse);
      expect((cache.writes, cache.value!.fetchedAt), (1, now));
      expect(cache.value!.sheets.highlightsCsv, contains('Video google'));
      expect(titlesShown(), ['Video snapshot', 'Video google']);
      // the snapshot on the screen may be scrolled while Google's answer is parsed: its frames come first
      expect(parsed, ['snapshot', 'google']);
      expect(backgrounds, [false, true]);
      expect(states.skipWhile((s) => !s.hasData).every((s) => s.hasData), isTrue, reason: 'never blanks');
    });

    test('Google first: the snapshot that comes after is ignored, and not even parsed', () async {
      startWith();
      snapshot.gate = Completer();
      google.results.add(sampleSheets(tag: 'google'));
      await notifier().idle;
      expect(title(), 'Video google');
      snapshot.gate!.complete();
      await pumpEventQueue();
      expect(title(), 'Video google');
      expect(state().fetchedAt, now);
      expect(titlesShown(), ['Video google']);
      expect(parsed, ['google']);
    });

    test("Google's sheets come while the snapshot is being parsed: that parse is abandoned", () async {
      startWith();
      snapshotParseGate = Completer();
      google
        ..gate = Completer()
        ..results.add(sampleSheets(tag: 'google'));
      await pumpEventQueue();
      expect(parsed, ['snapshot']);
      expect(abandoned.single!(), isFalse);
      google.gate!.complete();
      await pumpEventQueue();
      expect(abandoned.first!(), isTrue, reason: "Google's answer comes within a parse: the snapshot cannot win");
      snapshotParseGate!.complete();
      await notifier().idle;
      await pumpEventQueue();
      expect(titlesShown(), ['Video google']);
    });

    test('a snapshot parsed to its end after Google\'s answer (a background isolate) is dropped', () async {
      startWith();
      snapshotParseGate = Completer();
      snapshotParseDeaf = true;
      google
        ..gate = Completer()
        ..results.add(sampleSheets(tag: 'google'));
      await pumpEventQueue();
      expect(parsed, ['snapshot'], reason: 'the snapshot is being parsed');
      google.gate!.complete();
      await notifier().idle;
      expect(title(), 'Video google');
      expect(parsed, ['snapshot', 'google']);
      snapshotParseGate!.complete();
      await pumpEventQueue();
      expect(title(), 'Video google');
      expect(state().fetchedAt, now);
      expect(titlesShown(), ['Video google']);
    });

    for (final (name, Object error) in [
      ('missing (HTTP 404: no branch yet)', SheetHttpException(SnapshotUrls.songs, 404)),
      ('unreachable', const SocketException('offline')),
      ('too slow', TimeoutException('silence')),
      ('a web page', SheetNotCsvException(SnapshotUrls.highlights)),
      ('without a valid time', const FormatException('No UTC time in the snapshot')),
    ]) {
      test('a snapshot $name: the first load as without it, nothing reported', () async {
        startWith();
        snapshot.result = error;
        google
          ..gate = Completer()
          ..results.add(sampleSheets(tag: 'google'));
        await pumpEventQueue();
        expect(state().isLoading, isTrue);
        expect(state().lastError, isNull);
        google.gate!.complete();
        await notifier().idle;
        expect(title(), 'Video google');
        expect(states.every((s) => s.lastError == null), isTrue);
        expect(states.every((s) => s.hasData || s.isLoading), isTrue);
      });
    }

    for (final (name, RawSheets sheets) in [
      ('HTML', RawSheets(highlightsCsv: '<html><body>Not Found</body></html>', songsCsv: sampleSheets().songsCsv)),
      (
        'without the header of a sheet',
        RawSheets(highlightsCsv: '"A","B"\n"1","2"', songsCsv: sampleSheets().songsCsv),
      ),
      ('with no row', RawSheets(highlightsCsv: highlightsCsv([]), songsCsv: sampleSheets().songsCsv)),
      ('cut in a quoted cell', RawSheets(highlightsCsv: '"', songsCsv: sampleSheets().songsCsv)),
    ]) {
      test('a snapshot $name is ignored silently, and deletes no cache', () async {
        // the real parser: what it refuses in a download, it refuses in the snapshot
        cache = MemorySheetCache();
        snapshot.result = CachedSheets(sheets: sheets, fetchedAt: madeAt);
        container = ProviderContainer.test(
          overrides: [
            sheetFetcherProvider.overrideWithValue(google),
            snapshotFetcherProvider.overrideWithValue(snapshot),
            sheetCacheProvider.overrideWithValue(cache),
            catalogueParserProvider.overrideWithValue(parseOnCurrentIsolate),
            clockProvider.overrideWithValue(() => clock),
          ],
        );
        states = [];
        container.listen(catalogueProvider, (_, next) => states.add(next), fireImmediately: true);
        google
          ..gate = Completer()
          ..results.add(sampleSheets(tag: 'google'));
        await pumpEventQueue();
        expect(snapshot.calls, 1);
        expect(state().isLoading, isTrue);
        google.gate!.complete();
        await notifier().idle;
        expect(title(), 'Video google');
        expect(states.every((s) => s.lastError == null), isTrue);
        expect(cache.clears, 0);
      });
    }

    test('Google fails after the snapshot: it stays, with the error of a failed refresh, never kept', () async {
      startWith();
      google
        ..gate = Completer()
        ..results.add(const SocketException('offline'));
      await pumpEventQueue();
      expect(title(), 'Video snapshot');
      google.gate!.complete();
      await notifier().idle;
      expect(title(), 'Video snapshot');
      expect(state().fetchedAt, madeAt);
      expect(state().lastError, isA<SocketException>());
      expect((state().isFailed, state().isRefreshing), (false, false));
      expect(cache.value, isNull);
      expect(cache.writes, 0);
    });

    test('Google fails before the snapshot comes: the snapshot is shown, the error kept', () async {
      startWith();
      snapshot.gate = Completer();
      google.results.add(SheetHttpException(SheetUrls.songs, 503));
      await notifier().idle;
      expect(state().isFailed, isTrue);
      snapshot.gate!.complete();
      await pumpEventQueue();
      expect(title(), 'Video snapshot');
      expect(state().fetchedAt, madeAt);
      expect(state().lastError, isA<SheetHttpException>());
      expect(state().isFailed, isFalse);
    });

    test("both fail: the failure of the first load, Google's error", () async {
      startWith();
      snapshot.result = SheetHttpException(SnapshotUrls.meta, 404);
      google.results.add(const SocketException('offline'));
      await notifier().idle;
      await pumpEventQueue();
      expect(state().isFailed, isTrue);
      expect(state().lastError, isA<SocketException>());
    });

    test("Google's answer identical to the snapshot: the catalogue on the screen is kept, parsed once", () async {
      startWith();
      snapshot.result = CachedSheets(
        sheets: sampleSheets(tag: 'same'),
        fetchedAt: madeAt,
      );
      google
        ..gate = Completer()
        ..results.add(sampleSheets(tag: 'same'));
      await pumpEventQueue();
      final shown = state().catalogue;
      expect(shown, isNotNull);
      google.gate!.complete();
      await notifier().idle;
      expect(identical(state().catalogue, shown), isTrue);
      expect(parsed, ['same'], reason: 'nothing parsed again');
      expect(state().fetchedAt, now, reason: "it is Google's answer now");
      expect((cache.writes, cache.value!.fetchedAt), (1, now));
    });

    test("Google's answer much smaller than the snapshot is taken: the snapshot keeps no download out", () async {
      startWith();
      snapshot.result = snapshotOf(extraPlays: 4);
      google
        ..gate = Completer()
        ..results.add(sampleSheets(tag: 'google'));
      await pumpEventQueue();
      expect(state().playCount, 5);
      google.gate!.complete();
      await notifier().idle;
      expect(title(), 'Video google');
      expect(state().playCount, 1);
      expect(state().lastError, isNull);
    });

    test('rebuilt or disposed while the snapshot comes: it is dropped', () async {
      startWith();
      snapshot.gate = Completer();
      google
        ..gate = Completer()
        ..results.addAll([sampleSheets(tag: 'first'), sampleSheets(tag: 'second')]);
      await pumpEventQueue();
      container.invalidate(catalogueProvider);
      expect(state().isLoading, isTrue);
      await pumpEventQueue();
      expect(snapshot.calls, 2, reason: 'the new build has nothing kept either');
      snapshot.gate!.complete();
      await pumpEventQueue();
      expect(title(), 'Video snapshot', reason: "the new build's own snapshot");
      expect(states.where((s) => s.hasData), hasLength(1), reason: 'shown once, by the new build only');
      final n = notifier();
      container.dispose();
      google.gate!.complete();
      await pumpEventQueue();
      await n.idle;
    });
  });

  group('returning visitors', () {
    for (final (name, age) in [
      ('a fresh cache', const Duration(hours: 1)),
      ('a stale cache', const Duration(hours: 7)),
      ('a cache older than the snapshot', const Duration(days: 30)),
    ]) {
      test('$name: no snapshot asked, the kept data shown', () async {
        startWith(
          cached: CachedSheets(
            sheets: sampleSheets(tag: 'kept'),
            fetchedAt: now.subtract(age),
          ),
        );
        google
          ..gate = Completer()
          ..results.add(sampleSheets(tag: 'google'));
        await pumpEventQueue();
        expect(title(), 'Video kept');
        expect(state().fetchedAt, now.subtract(age));
        google.gate!.complete();
        await notifier().idle;
        expect(snapshot.calls, 0);
        expect(titlesShown().contains('Video snapshot'), isFalse);
      });
    }

    test('a cache that cannot be read (a failure that is not about its content): no snapshot', () async {
      startWith(
        cached: CachedSheets(
          sheets: sampleSheets(tag: 'kept'),
          fetchedAt: now,
        ),
      );
      var parses = 0;
      container = ProviderContainer.test(
        overrides: [
          sheetFetcherProvider.overrideWithValue(google),
          snapshotFetcherProvider.overrideWithValue(snapshot),
          sheetCacheProvider.overrideWithValue(cache),
          catalogueParserProvider.overrideWithValue(
            (sheets, {isAbandoned, background = false}) =>
                ++parses == 1 ? throw Exception('Unable to spawn isolate') : parseOnCurrentIsolate(sheets),
          ),
          clockProvider.overrideWithValue(() => clock),
        ],
      );
      google.results.add(sampleSheets(tag: 'google'));
      container.read(catalogueProvider);
      await notifier().idle;
      expect(snapshot.calls, 0);
      expect(title(), 'Video google');
    });

    test('clear downloaded data asks for no snapshot: the data in memory stays meanwhile', () async {
      startWith(
        cached: CachedSheets(
          sheets: sampleSheets(tag: 'kept'),
          fetchedAt: now,
        ),
      );
      await notifier().idle;
      google.results.add(sampleSheets(tag: 'google'));
      await notifier().clearDownloadedData();
      expect(title(), 'Video google');
      expect(snapshot.calls, 0);
    });
  });

  group('the snapshot never delays a download', () {
    testWidgets('Google failed: tried again after 15 seconds, however recent the copy', (tester) async {
      startWith();
      google.results.addAll([const SocketException('offline'), sampleSheets(tag: 'google')]);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(title(), 'Video snapshot');
      expect(state().lastError, isA<SocketException>());
      expect(google.calls, 1);
      clock = clock.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      expect(google.calls, 2);
      expect(title(), 'Video google');
      expect(state().lastError, isNull);
      container.dispose();
    });

    testWidgets('the snapshot came after the failure: the retry is still at 15 seconds', (tester) async {
      startWith();
      snapshot.gate = Completer();
      google.results.addAll([const SocketException('offline'), sampleSheets(tag: 'google')]);
      await tester.pump(Duration.zero);
      expect(state().isFailed, isTrue);
      clock = clock.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      snapshot.gate!.complete();
      await tester.pump(Duration.zero);
      expect(title(), 'Video snapshot');
      clock = clock.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      expect(google.calls, 2);
      expect(title(), 'Video google');
      container.dispose();
    });

    testWidgets("Google's answer identical to the snapshot is fresh data: nothing is asked again", (tester) async {
      startWith();
      snapshot.result = CachedSheets(
        sheets: sampleSheets(tag: 'same'),
        fetchedAt: madeAt,
      );
      google
        ..gate = Completer()
        ..results.add(sampleSheets(tag: 'same'));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(state().catalogue, isNotNull);
      google.gate!.complete();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(state().fetchedAt, now);
      for (var i = 0; i < 10; i++) {
        clock = clock.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(google.calls, 1, reason: 'the same catalogue kept on the screen no longer counts as the snapshot');
      container.dispose();
    });

    test('back to the app with the snapshot on the screen: Google is asked at once', () async {
      startWith();
      google.results.addAll([const SocketException('offline'), sampleSheets(tag: 'google')]);
      await notifier().idle;
      await pumpEventQueue();
      expect(title(), 'Video snapshot');
      await notifier().refreshIfStale();
      expect(google.calls, 2);
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
    });

    test('reads the three files, as UTF-8 whatever the declared charset, with the time of the copy', () async {
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
      final got = await HttpSnapshotFetcher(client: client).fetch();
      expect(asked.toSet(), {SnapshotUrls.highlights, SnapshotUrls.songs, SnapshotUrls.meta});
      expect((got.sheets.highlightsCsv, got.sheets.songsCsv), ('"Video Title"\n"Pokémon"', '"Title"\n"♪"'));
      expect(got.fetchedAt, DateTime.utc(2026, 11, 14, 4, 23, 51));
    });

    test('no branch yet (HTTP 404), a web page: errors', () async {
      await expectLater(
        HttpSnapshotFetcher(client: MockClient((_) async => http.Response('404: Not Found', 404))).fetch(),
        throwsA(isA<SheetHttpException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
      await expectLater(
        HttpSnapshotFetcher(client: MockClient((_) async => http.Response('<!DOCTYPE html>', 200))).fetch(),
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

  test('the repository parses the snapshot as it parses the cache, and caches nothing', () async {
    final cache = MemorySheetCache();
    final repository = CatalogueRepository(
      fetcher: FakeGoogle(),
      cache: cache,
      parse: parseOnCurrentIsolate,
      snapshots: FakeSnapshot(snapshotOf()),
    );
    final loaded = await repository.loadSnapshot();
    expect(
      (loaded.isSnapshot, loaded.fetchedAt, loaded.catalogue.highlights.single.title),
      (true, madeAt, 'Video snapshot'),
    );
    expect(loaded.fingerprint, sampleSheets(tag: 'snapshot').fingerprint);
    expect((cache.writes, cache.clears), (0, 0));
    await expectLater(
      CatalogueRepository(
        fetcher: FakeGoogle(),
        cache: cache,
        parse: parseOnCurrentIsolate,
        snapshots: FakeSnapshot(
          CachedSheets(
            sheets: const RawSheets(highlightsCsv: 'x', songsCsv: 'y'),
            fetchedAt: madeAt,
          ),
        ),
      ).loadSnapshot(),
      throwsA(isA<CatalogueFormatException>()),
    );
    await expectLater(repository.loadSnapshot(isAbandoned: () => true), throwsA(isA<LoadAbandoned>()));
    await expectLater(const NoSnapshot().fetch(), throwsStateError);
  });

  test('without a snapshot fetcher, the repository has none', () async {
    final repository = CatalogueRepository(
      fetcher: FakeGoogle(),
      cache: MemorySheetCache(),
      parse: parseOnCurrentIsolate,
    );
    await expectLater(repository.loadSnapshot(), throwsStateError);
  });
}
