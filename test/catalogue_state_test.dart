import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/parser.dart';
import 'package:ong_music/src/data/repository.dart';
import 'package:ong_music/src/data/sheet_cache.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/state/catalogue_state.dart';

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
  late FakeFetcher fetcher;
  late MemorySheetCache cache;
  late ProviderContainer container;
  late List<CatalogueState> states;
  late int parses;

  CatalogueNotifier notifier() => container.read(catalogueProvider.notifier);
  CatalogueState state() => container.read(catalogueProvider);
  String firstTitle() => state().catalogue!.highlights.first.title;

  void startWith({CachedSheets? cached}) {
    cache = MemorySheetCache(cached);
    parses = 0;
    container = ProviderContainer.test(
      overrides: [
        sheetFetcherProvider.overrideWithValue(fetcher),
        sheetCacheProvider.overrideWithValue(cache),
        catalogueParserProvider.overrideWithValue((sheets) {
          parses++;
          return parseOnCurrentIsolate(sheets);
        }),
        clockProvider.overrideWithValue(() => clock),
      ],
    );
    states = [];
    container.listen(catalogueProvider, (_, next) => states.add(next), fireImmediately: true);
  }

  setUp(() {
    clock = now;
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

  test('query providers follow the catalogue', () async {
    startWith(
      cached: CachedSheets(sheets: sampleSheets(extraPlays: 2), fetchedAt: now),
    );
    expect(container.read(playResultsProvider(const PlayFilter())), isNull);
    await notifier().idle;
    expect(container.read(playResultsProvider(const PlayFilter(query: 'extra')))!.length, 2);
    expect(container.read(highlightResultsProvider(const HighlightFilter(query: 'video')))!.length, 1);
    expect(container.read(playCountForQueryProvider('song')), 1);
  });
}
