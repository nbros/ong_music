import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/parser.dart';
import 'package:ong_music/src/data/repository.dart';
import 'package:ong_music/src/data/sheet_cache.dart';
import 'package:ong_music/src/data/sheet_snapshot.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// Answers with the queued results (RawSheets or an error to throw).
class FakeFetcher implements SheetFetcher {
  final results = <Object>[];
  int calls = 0;
  Completer<void>? gate;
  void Function()? onFetch;

  @override
  Future<RawSheets> fetch() async {
    calls++;
    onFetch?.call();
    if (gate != null) await gate!.future;
    final r = results.removeAt(0);
    if (r is RawSheets) return r;
    throw r;
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 12, 12);
  late DateTime clock;
  void Function()? clockReadHook;
  late FakeFetcher fetcher;
  late MemorySheetCache cache;
  late ProviderContainer container;
  late List<CatalogueState> states;
  late int parses;

  CatalogueNotifier notifier() => container.read(catalogueProvider.notifier);
  CatalogueState state() => container.read(catalogueProvider);
  String firstTitle() => state().catalogue!.highlights.first.title;

  void startWith({CachedSheets? cached, SharedPreferences? prefs}) {
    cache = MemorySheetCache(cached);
    parses = 0;
    container = ProviderContainer.test(
      overrides: [
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
        sheetFetcherProvider.overrideWithValue(fetcher),
        snapshotFetcherProvider.overrideWithValue(const NoSnapshot()),
        sheetCacheProvider.overrideWithValue(cache),
        catalogueParserProvider.overrideWithValue((sheets, {isAbandoned, background = false}) {
          parses++;
          return parseOnCurrentIsolate(sheets);
        }),
        clockProvider.overrideWithValue(() {
          clockReadHook?.call();
          return clock;
        }),
      ],
    );
    states = [];
    container.listen(catalogueProvider, (_, next) => states.add(next), fireImmediately: true);
  }

  setUp(() {
    clock = now;
    clockReadHook = null;
    fetcher = FakeFetcher();
  });

  test('fresh cache: shown, no download', () async {
    startWith(
      cached: CachedSheets(
        sheets: sampleSheets(tag: 'cached'),
        fetchedAt: now.subtract(const Duration(hours: 1)),
      ),
    );
    expect(states.single.isLoading, isTrue);
    await notifier().idle;
    expect(firstTitle(), 'Video cached');
    expect(state().fetchedAt, now.subtract(const Duration(hours: 1)));
    expect(state().isRefreshing, isFalse);
    expect(fetcher.calls, 0);
    expect((state().highlightCount, state().playCount, state().streamCount), (1, 1, 1));
  });

  test('stale cache: shown at once, refreshed in the background, swapped on success', () async {
    startWith(
      cached: CachedSheets(
        sheets: sampleSheets(tag: 'old'),
        fetchedAt: now.subtract(const Duration(hours: 7)),
      ),
    );
    fetcher
      ..gate = Completer()
      ..results.add(sampleSheets(tag: 'new'));
    await pumpEventQueue();
    expect(firstTitle(), 'Video old');
    expect(state().isRefreshing, isTrue);
    fetcher.gate!.complete();
    await notifier().idle;
    expect(firstTitle(), 'Video new');
    expect(state().fetchedAt, now);
    expect(state().isRefreshing, isFalse);
    expect(cache.value!.fetchedAt, now);
    expect(cache.value!.sheets.highlightsCsv, contains('Video new'));
    expect(states.skipWhile((s) => !s.hasData).every((s) => s.hasData), isTrue, reason: 'never blanks');
  });

  test('no cache: loading, then data, then cached', () async {
    startWith();
    fetcher.results.add(sampleSheets());
    await notifier().idle;
    expect(states.first.isLoading, isTrue);
    expect(states.any((s) => s.isLoading && s.isRefreshing), isTrue);
    expect(firstTitle(), 'Video v1');
    expect(cache.writes, 1);
  });

  test('no cache and download fails: failed state, retry succeeds', () async {
    startWith();
    fetcher.results.addAll([const SocketException('offline'), sampleSheets()]);
    await notifier().idle;
    expect(state().isFailed, isTrue);
    expect(state().isLoading, isFalse);
    expect(state().lastError, isA<SocketException>());
    final retry = notifier().refresh();
    expect(state().isLoading, isTrue);
    await retry;
    expect(state().hasData, isTrue);
    expect(state().lastError, isNull);
  });

  test('failed refresh keeps the data and records the error', () async {
    final cached = CachedSheets(
      sheets: sampleSheets(tag: 'old'),
      fetchedAt: now.subtract(const Duration(hours: 7)),
    );
    startWith(cached: cached);
    fetcher.results.add(const SocketException('offline'));
    await notifier().idle;
    expect(firstTitle(), 'Video old');
    expect(state().fetchedAt, cached.fetchedAt);
    expect(state().lastError, isA<SocketException>());
    expect(state().isRefreshing, isFalse);
    expect(state().isFailed, isFalse);
    expect(identical(cache.value, cached), isTrue);
  });

  test('invalid payload (HTML with status 200) is rejected', () async {
    startWith(
      cached: CachedSheets(
        sheets: sampleSheets(tag: 'old'),
        fetchedAt: now.subtract(const Duration(hours: 7)),
      ),
    );
    fetcher.results.add(
      RawSheets(highlightsCsv: '<html><body>Sign in</body></html>', songsCsv: sampleSheets().songsCsv),
    );
    await notifier().idle;
    expect(firstTitle(), 'Video old');
    expect(state().lastError, isA<CatalogueFormatException>());
    expect(cache.writes, 0);
  });

  test('refreshIfStale only downloads stale data', () async {
    startWith(
      cached: CachedSheets(
        sheets: sampleSheets(tag: 'old'),
        fetchedAt: now,
      ),
    );
    await notifier().idle;
    await notifier().refreshIfStale();
    expect(fetcher.calls, 0);
    clock = now.add(const Duration(hours: 6, minutes: 1));
    fetcher.results.add(sampleSheets(tag: 'new'));
    await notifier().refreshIfStale();
    expect(fetcher.calls, 1);
    expect(firstTitle(), 'Video new');
  });

  test('refreshIfStale retries when the first download failed', () async {
    startWith();
    fetcher.results.addAll([const SocketException('offline'), sampleSheets()]);
    await notifier().idle;
    await notifier().refreshIfStale();
    expect(state().hasData, isTrue);
  });

  test('concurrent refreshes share one download', () async {
    startWith(
      cached: CachedSheets(sheets: sampleSheets(), fetchedAt: now),
    );
    await notifier().idle;
    fetcher.results.add(sampleSheets(tag: 'new'));
    await Future.wait([notifier().refresh(), notifier().refresh(), notifier().refreshIfStale()]);
    expect(fetcher.calls, 1);
  });

  test('clear downloaded data: wipes the cache, then downloads again', () async {
    startWith(
      cached: CachedSheets(
        sheets: sampleSheets(tag: 'old'),
        fetchedAt: now,
      ),
    );
    await notifier().idle;
    CachedSheets? cacheAtFetch = cache.value;
    fetcher
      ..onFetch = () {
        cacheAtFetch = cache.value;
      }
      ..results.add(sampleSheets(tag: 'new'));
    await notifier().clearDownloadedData();
    expect(cacheAtFetch, isNull);
    expect(firstTitle(), 'Video new');
    expect(cache.value!.sheets.highlightsCsv, contains('Video new'));
  });

  test('a cache that no longer parses is deleted, then a download is tried', () async {
    startWith(
      cached: CachedSheets(
        sheets: const RawSheets(highlightsCsv: 'garbage', songsCsv: 'garbage'),
        fetchedAt: now,
      ),
    );
    fetcher.results.addAll([const SocketException('offline'), sampleSheets()]);
    await notifier().idle;
    expect(cache.clears, 1);
    expect(cache.value, isNull, reason: 'the download failed, so only the deletion explains the empty cache');
    expect(state().isFailed, isTrue);
    await notifier().refresh();
    expect(firstTitle(), 'Video v1');
    expect(cache.value, isNotNull);
  });

  test('a refresh that finds the sheets unchanged keeps the catalogue instance and parses nothing', () async {
    startWith(
      cached: CachedSheets(sheets: sampleSheets(), fetchedAt: now.subtract(const Duration(hours: 7))),
    );
    fetcher.results.add(sampleSheets());
    await pumpEventQueue();
    final before = state().catalogue;
    expect(before, isNotNull);
    await notifier().idle;
    expect(fetcher.calls, 1);
    expect(parses, 1, reason: 'only the cache was parsed');
    expect(identical(state().catalogue, before), isTrue);
    expect(state().fetchedAt, now);
    expect(state().lastError, isNull);
    expect(cache.value!.fetchedAt, now, reason: 'the cache remembers the new download time');
  });

  test('a download with less than half the rows is rejected', () async {
    startWith(
      cached: CachedSheets(
        sheets: sampleSheets(tag: 'old', extraPlays: 4),
        fetchedAt: now.subtract(const Duration(hours: 7)),
      ),
    );
    fetcher.results.add(sampleSheets(tag: 'truncated'));
    await notifier().idle;
    expect(firstTitle(), 'Video old');
    expect(state().playCount, 5);
    expect(state().lastError, isA<CatalogueFormatException>());
    expect(cache.writes, 0);
  });

  test('a much smaller download is accepted once the data in use is a day old', () async {
    // the sheet really shrank: refusing it for ever would freeze the app on old data
    startWith(
      cached: CachedSheets(
        sheets: sampleSheets(tag: 'old', extraPlays: 4),
        fetchedAt: now.subtract(CatalogueRepository.collapseGuard),
      ),
    );
    fetcher.results.add(sampleSheets(tag: 'archived'));
    await notifier().idle;
    expect(firstTitle(), 'Video archived');
    expect(state().playCount, 1);
    expect(state().lastError, isNull);
    expect(state().fetchedAt, now);
  });

  test(
    'clear downloaded data starts from scratch: a smaller sheet is accepted, an identical one parsed again',
    () async {
      startWith(
        cached: CachedSheets(
          sheets: sampleSheets(tag: 'old', extraPlays: 4),
          fetchedAt: now,
        ),
      );
      await notifier().idle;
      fetcher.results.add(sampleSheets(tag: 'small'));
      await notifier().clearDownloadedData();
      expect(firstTitle(), 'Video small');
      expect(state().lastError, isNull);
      fetcher.results.add(sampleSheets(tag: 'small'));
      final before = parses;
      await notifier().clearDownloadedData();
      expect(parses, before + 1);
    },
  );

  test('a refresh requested while data is being cleared joins it', () async {
    startWith(
      cached: CachedSheets(
        sheets: sampleSheets(tag: 'old'),
        fetchedAt: now,
      ),
    );
    await notifier().idle;
    fetcher
      ..gate = Completer()
      ..results.add(sampleSheets(tag: 'new'));
    final clearing = notifier().clearDownloadedData();
    await pumpEventQueue();
    final joined = notifier().refresh();
    fetcher.gate!.complete();
    await Future.wait([clearing, joined]);
    expect(fetcher.calls, 1);
    expect(firstTitle(), 'Video new');
    expect(cache.value!.sheets.highlightsCsv, contains('Video new'));
  });

  test('invalidating the provider during a download: the old download is dropped, the new one wins', () async {
    startWith();
    fetcher
      ..gate = Completer()
      ..results.addAll([sampleSheets(tag: 'first'), sampleSheets(tag: 'second')]);
    await pumpEventQueue();
    expect(fetcher.calls, 1);
    container.invalidate(catalogueProvider);
    expect(state().isLoading, isTrue);
    await pumpEventQueue();
    expect(fetcher.calls, 2, reason: 'the new build downloads on its own');
    fetcher.gate!.complete();
    await notifier().idle;
    expect(firstTitle(), 'Video second');
    expect(state().isRefreshing, isFalse);
    expect(states.where((s) => s.hasData).map((s) => s.catalogue!.highlights.first.title).toSet(), {'Video second'});
    // the state machine is intact: one more refresh is one more download
    fetcher
      ..gate = null
      ..results.add(sampleSheets(tag: 'third'));
    await notifier().refresh();
    expect(fetcher.calls, 3);
    expect(firstTitle(), 'Video third');
  });

  test('disposal during a download, and calls after disposal, do not throw', () async {
    startWith();
    fetcher
      ..gate = Completer()
      ..results.add(sampleSheets());
    final n = notifier();
    await pumpEventQueue();
    expect(fetcher.calls, 1);
    container.dispose();
    fetcher.gate!.complete();
    await pumpEventQueue();
    await n.refresh();
    await n.refreshIfStale();
    await n.clearDownloadedData();
    expect(fetcher.calls, 1);
  });

  group('automatic refresh', () {
    // fake time (testWidgets); the container is created inside the fake zone and disposed at the end, with its timer

    testWidgets('no network at the first launch: tried again by itself, less and less often', (tester) async {
      startWith();
      fetcher.results.addAll([
        const SocketException('offline'),
        const SocketException('offline'),
        const SocketException('offline'),
        sampleSheets(),
      ]);
      await tester.pump(Duration.zero);
      expect(fetcher.calls, 1);
      expect(state().isFailed, isTrue);
      Future<void> wait(Duration d) async {
        clock = clock.add(d);
        await tester.pump(d);
      }

      await wait(const Duration(seconds: 14));
      expect(fetcher.calls, 1);
      await wait(const Duration(seconds: 1));
      expect(fetcher.calls, 2, reason: 'first retry after 15 seconds');
      await wait(const Duration(seconds: 59));
      expect(fetcher.calls, 2);
      await wait(const Duration(seconds: 1));
      expect(fetcher.calls, 3, reason: 'then after a minute');
      await wait(const Duration(minutes: 5));
      expect(fetcher.calls, 4, reason: 'then after 5 minutes');
      expect(firstTitle(), 'Video v1');
      expect(state().lastError, isNull);
      await wait(const Duration(hours: 5));
      expect(fetcher.calls, 4, reason: 'fresh data: nothing more until it is 6 hours old');
      container.dispose();
    });

    testWidgets('an app left open refreshes every 6 hours without any lifecycle event', (tester) async {
      startWith(
        cached: CachedSheets(
          sheets: sampleSheets(tag: 'old'),
          fetchedAt: now,
        ),
      );
      fetcher.results.addAll([sampleSheets(tag: 'new'), sampleSheets(tag: 'newer')]);
      await tester.pump(Duration.zero);
      expect(firstTitle(), 'Video old');
      for (var hour = 1; hour <= 6; hour++) {
        clock = now.add(Duration(hours: hour));
        await tester.pump(const Duration(hours: 1));
      }
      expect(fetcher.calls, 1);
      expect(firstTitle(), 'Video new');
      clock = clock.add(const Duration(hours: 6));
      await tester.pump(const Duration(hours: 6));
      expect(fetcher.calls, 2);
      expect(firstTitle(), 'Video newer');
      container.dispose();
    });

    testWidgets('a failed refresh of stale data is tried again; fresh data after a failed refresh is not', (
      tester,
    ) async {
      startWith(
        cached: CachedSheets(
          sheets: sampleSheets(tag: 'old'),
          fetchedAt: now.subtract(const Duration(hours: 7)),
        ),
      );
      fetcher.results.addAll([const SocketException('offline'), sampleSheets(tag: 'new'), const SocketException('x')]);
      await tester.pump(Duration.zero);
      expect(state().lastError, isA<SocketException>());
      clock = clock.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      expect(fetcher.calls, 2);
      expect(firstTitle(), 'Video new');
      // a manual refresh of fresh data fails: no automatic retry, the data is fresh
      await notifier().refresh();
      expect(fetcher.calls, 3);
      clock = clock.add(const Duration(hours: 1));
      await tester.pump(const Duration(hours: 1));
      expect(fetcher.calls, 3);
      container.dispose();
    });

    testWidgets('nothing automatic in the background; resuming refreshes at once', (tester) async {
      startWith(
        cached: CachedSheets(
          sheets: sampleSheets(tag: 'old'),
          fetchedAt: now,
        ),
      );
      fetcher.results.add(sampleSheets(tag: 'new'));
      await tester.pump(Duration.zero);
      notifier().setForeground(false);
      clock = clock.add(const Duration(hours: 12));
      await tester.pump(const Duration(hours: 12));
      expect(fetcher.calls, 0);
      notifier().setForeground(true);
      await notifier().refreshIfStale();
      expect(fetcher.calls, 1);
      expect(firstTitle(), 'Video new');
      container.dispose();
    });

    testWidgets('no timer runs in the background, and the check that came due runs back in the foreground', (
      tester,
    ) async {
      startWith(
        cached: CachedSheets(
          sheets: sampleSheets(tag: 'old'),
          fetchedAt: now,
        ),
      );
      fetcher.results.add(sampleSheets(tag: 'new'));
      await tester.pump(Duration.zero);
      var clockReads = 0;
      final time = clock.add(const Duration(hours: 12));
      notifier().setForeground(false);
      // the clock is only read by the automatic checks here
      clockReadHook = () => clockReads++;
      clock = time;
      await tester.pump(const Duration(hours: 12));
      expect(clockReads, 0, reason: 'a check ran in the background');
      expect(fetcher.calls, 0);
      clockReadHook = null;
      notifier().setForeground(true);
      await tester.pump(const Duration(seconds: 1));
      expect(fetcher.calls, 1);
      expect(firstTitle(), 'Video new');
      // a pending timer at the end of a test is an error: none must be left in the background
      notifier().setForeground(false);
    });

    testWidgets('a web page instead of the sheets (Wi-Fi sign-in) is tried again like a network failure', (
      tester,
    ) async {
      startWith();
      final page = SheetNotCsvException(SheetUrls.songs);
      fetcher.results.addAll([page, page, sampleSheets()]);
      await tester.pump(Duration.zero);
      expect(fetcher.calls, 1);
      expect(state().lastError, isA<SheetNotCsvException>());
      expect(state().isFailed, isTrue);
      // signed in to the network meanwhile or not: after 15 seconds, and at each return to the app
      clock = clock.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      expect(fetcher.calls, 2);
      await notifier().refreshIfStale();
      expect(fetcher.calls, 3);
      expect(state().hasData, isTrue);
      container.dispose();
    });

    testWidgets('a download refused for its content waits for the next refresh, not for the retry delays', (
      tester,
    ) async {
      startWith();
      // sheets that are no longer what the app reads, twice, then the sheets
      const html = RawSheets(highlightsCsv: '"Recipe","Minutes"\n"Soup","20"', songsCsv: '"Recipe"\n"Soup"');
      fetcher.results.addAll([html, html, sampleSheets()]);
      await tester.pump(Duration.zero);
      expect(fetcher.calls, 1);
      expect(state().lastError, isA<FormatException>());
      Future<void> wait(Duration d) async {
        clock = clock.add(d);
        await tester.pump(d);
      }

      // megabytes each time: not after 15 seconds, a minute, 5 minutes...
      await wait(const Duration(minutes: 10));
      expect(fetcher.calls, 1);
      // ...nor at each return to the app
      await notifier().refreshIfStale();
      expect(fetcher.calls, 1);
      await wait(catalogueMaxAge - const Duration(minutes: 11));
      expect(fetcher.calls, 1);
      await wait(const Duration(minutes: 1));
      expect(fetcher.calls, 2);
      await wait(catalogueMaxAge);
      expect(fetcher.calls, 3);
      expect(state().hasData, isTrue);
      container.dispose();
    });

    testWidgets('the clock set back by days does not stop the retries', (tester) async {
      startWith();
      fetcher.results.addAll([const SocketException('offline'), sampleSheets()]);
      await tester.pump(Duration.zero);
      expect(fetcher.calls, 1);
      clock = clock.subtract(const Duration(days: 3));
      await tester.pump(const Duration(seconds: 15));
      expect(fetcher.calls, 2);
      expect(state().hasData, isTrue);
      container.dispose();
    });
  });

  group('faults of the cache and the payload', () {
    test('a cache that cannot be written: the download is still used', () async {
      container = ProviderContainer.test(
        overrides: [
          sheetFetcherProvider.overrideWithValue(fetcher),
          snapshotFetcherProvider.overrideWithValue(const NoSnapshot()),
          sheetCacheProvider.overrideWithValue(_ThrowingCache()),
          catalogueParserProvider.overrideWithValue(parseOnCurrentIsolate),
          clockProvider.overrideWithValue(() => clock),
        ],
      );
      fetcher.results.add(sampleSheets());
      container.read(catalogueProvider);
      await notifier().idle;
      expect(state().hasData, isTrue);
      expect(state().lastError, isNull);
    });

    test('a cache the parser chokes on with an error that is not a FormatException is deleted', () async {
      startWith(
        cached: CachedSheets(
          sheets: RawSheets(highlightsCsv: '"', songsCsv: sampleSheets().songsCsv),
          fetchedAt: now,
        ),
      );
      fetcher.results.add(sampleSheets(tag: 'downloaded'));
      await notifier().idle;
      expect(cache.clears, 1);
      expect(firstTitle(), 'Video downloaded');
    });

    test('a download the parser chokes on is reported as an unexpected format', () async {
      startWith();
      fetcher.results.add(RawSheets(highlightsCsv: '"', songsCsv: sampleSheets().songsCsv));
      await notifier().idle;
      expect(state().isFailed, isTrue);
      expect(state().lastError, isA<CatalogueFormatException>());
      expect(cache.writes, 0);
    });

    for (final Error error in [StateError('no element'), RangeError.index(3, const []), TypeError()]) {
      test('a parser failing on the payload with a ${error.runtimeType} counts as an unexpected format', () async {
        cache = MemorySheetCache(
          CachedSheets(
            sheets: sampleSheets(tag: 'cached'),
            fetchedAt: now,
          ),
        );
        var parses = 0;
        container = ProviderContainer.test(
          overrides: [
            sheetFetcherProvider.overrideWithValue(fetcher),
            snapshotFetcherProvider.overrideWithValue(const NoSnapshot()),
            sheetCacheProvider.overrideWithValue(cache),
            // the cache, then the first download: both unreadable
            catalogueParserProvider.overrideWithValue(
              (sheets, {isAbandoned, background = false}) =>
                  ++parses <= 2 ? throw error : parseOnCurrentIsolate(sheets),
            ),
            clockProvider.overrideWithValue(() => clock),
          ],
        );
        fetcher.results.add(sampleSheets(tag: 'downloaded'));
        container.read(catalogueProvider);
        await notifier().idle;
        expect(cache.clears, 1, reason: 'a cache that cannot be read is deleted');
        expect(state().lastError, isA<CatalogueFormatException>());
        expect(state().hasData, isFalse);
      });
    }

    test(
      'a fresh cache at start forgets the download the page may have started; a stale or missing one does not',
      () async {
        var discards = 0;
        Future<void> start(CachedSheets? cached) async {
          container = ProviderContainer.test(
            overrides: [
              sheetFetcherProvider.overrideWithValue(fetcher),
              snapshotFetcherProvider.overrideWithValue(const NoSnapshot()),
              sheetCacheProvider.overrideWithValue(MemorySheetCache(cached)),
              catalogueParserProvider.overrideWithValue(parseOnCurrentIsolate),
              clockProvider.overrideWithValue(() => clock),
              prefetchDiscarderProvider.overrideWithValue(() => discards++),
            ],
          );
          container.read(catalogueProvider);
          await notifier().idle;
          container.dispose();
        }

        // fresh: nothing is downloaded now, and the next refresh must not get sheets hours old
        await start(CachedSheets(sheets: sampleSheets(), fetchedAt: now.subtract(const Duration(hours: 1))));
        expect((discards, fetcher.calls), (1, 0));
        // stale, or no cache: the download that starts takes it
        fetcher.results.addAll([sampleSheets(), sampleSheets()]);
        await start(CachedSheets(sheets: sampleSheets(), fetchedAt: now.subtract(const Duration(hours: 7))));
        await start(null);
        expect((discards, fetcher.calls), (1, 2));
      },
    );

    test('a failure that is not about the payload (the isolate could not start) keeps the cache', () async {
      cache = MemorySheetCache(
        CachedSheets(
          sheets: sampleSheets(tag: 'cached'),
          fetchedAt: now,
        ),
      );
      var parses = 0;
      container = ProviderContainer.test(
        overrides: [
          sheetFetcherProvider.overrideWithValue(fetcher),
          snapshotFetcherProvider.overrideWithValue(const NoSnapshot()),
          sheetCacheProvider.overrideWithValue(cache),
          catalogueParserProvider.overrideWithValue(
            (sheets, {isAbandoned, background = false}) =>
                ++parses == 1 ? throw Exception('Unable to spawn isolate') : parseOnCurrentIsolate(sheets),
          ),
          clockProvider.overrideWithValue(() => clock),
        ],
      );
      // offline: with the cache deleted, nothing would be left for the next start
      fetcher.results.add(const SocketException('offline'));
      container.read(catalogueProvider);
      await notifier().idle;
      expect(cache.clears, 0);
      expect(cache.value!.sheets.highlightsCsv, sampleSheets(tag: 'cached').highlightsCsv);
      expect(state().lastError, isA<SocketException>());
    });

    test('clear downloaded data offline: the cache is gone, the data in memory stays with the error', () async {
      startWith(
        cached: CachedSheets(
          sheets: sampleSheets(tag: 'old'),
          fetchedAt: now,
        ),
      );
      await notifier().idle;
      fetcher.results.add(const SocketException('offline'));
      await notifier().clearDownloadedData();
      expect(cache.value, isNull);
      expect(firstTitle(), 'Video old');
      expect(state().lastError, isA<SocketException>());
      expect(state().isRefreshing, isFalse);
    });

    test('a cache dated in the future (clock changed) does not keep a smaller sheet out', () async {
      startWith(
        cached: CachedSheets(
          sheets: sampleSheets(tag: 'old', extraPlays: 4),
          fetchedAt: now.add(const Duration(days: 30)),
        ),
      );
      fetcher.results.add(sampleSheets(tag: 'archived'));
      await notifier().idle;
      expect(fetcher.calls, 1, reason: 'a download time far from now is stale');
      expect(firstTitle(), 'Video archived');
      expect(state().lastError, isNull);
    });
  });

  test('query providers follow the catalogue', () async {
    // the counts of the Highlights chips read the Twitch name and the favourites
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    startWith(
      cached: CachedSheets(sheets: sampleSheets(extraPlays: 2), fetchedAt: now),
      prefs: prefs,
    );
    expect(container.read(playResultsProvider(const PlayFilter())), isNull);
    await notifier().idle;
    expect(container.read(playResultsProvider(const PlayFilter(query: 'extra')))!.length, 2);
    expect(container.read(highlightResultsProvider(const HighlightFilter(query: 'video')))!.length, 1);
    expect(container.read(playCountForQueryProvider('song')), 1);
  });
}

/// A cache whose writes throw (a broken [SheetCache] implementation).
class _ThrowingCache implements SheetCache {
  @override
  Future<CachedSheets?> read() async => null;

  @override
  Future<void> write(CachedSheets sheets) async => throw const FileSystemException('No space left on device');

  @override
  Future<void> clear() async {}
}
