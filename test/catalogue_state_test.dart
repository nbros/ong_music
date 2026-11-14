import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/parser.dart';
import 'package:ong_music/src/data/repository.dart';
import 'package:ong_music/src/data/sheet_cache.dart';
import 'package:ong_music/src/data/sheet_snapshot.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'sheet_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12, 12);
  late DateTime clock;
  void Function()? clockReadHook;
  late FakeGoogle google;
  late MemorySheetCache cache;
  late RecordingParser parser;
  late ProviderContainer container;
  late List<CatalogueState> states;
  // the wait after the first frame of the list before the songs are loaded: none unless a test holds it
  Completer<void>? deferral;
  late int deferrals;

  CatalogueNotifier notifier() => container.read(catalogueProvider.notifier);
  CatalogueState state() => container.read(catalogueProvider);
  String firstTitle() => state().catalogue!.highlights.first.title;
  String? firstSong() => state().hasSongs ? state().catalogue!.plays.first.title : null;
  void wantSongs([SongsTrigger trigger = SongsTrigger.ongLog]) => notifier().songsWanted(trigger);

  void startWith({MemorySheetCache? cached, SharedPreferences? prefs, SheetCache? sheetCache, SheetParser? parse}) {
    cache = cached ?? MemorySheetCache();
    parser = RecordingParser();
    deferrals = 0;
    container = ProviderContainer.test(
      overrides: [
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
        sheetFetcherProvider.overrideWithValue(google),
        snapshotFetcherProvider.overrideWithValue(const NoSnapshot()),
        sheetCacheProvider.overrideWithValue(sheetCache ?? cache),
        sheetParserProvider.overrideWithValue(parse ?? parser),
        songsDeferralProvider.overrideWithValue(() async {
          deferrals++;
          await deferral?.future;
        }),
        clockProvider.overrideWithValue(() {
          clockReadHook?.call();
          return clock;
        }),
        prefetchDiscarderProvider.overrideWithValue(() {}),
      ],
    );
    states = [];
    container.listen(catalogueProvider, (_, next) => states.add(next), fireImmediately: true);
  }

  setUp(() {
    clock = now;
    clockReadHook = null;
    google = FakeGoogle();
    deferral = null;
  });

  group('the Highlights sheet alone first', () {
    test('kept copies: the highlights show at once, without the Songs sheet read or parsed', () async {
      startWith(cached: cacheOf(sampleSheets(tag: 'cached'), now.subtract(const Duration(hours: 1))));
      expect(states.single.isLoading, isTrue);
      await notifier().idle;
      expect(firstTitle(), 'Video cached');
      expect(state().hasSongs, isFalse);
      expect(state().isWaitingForSongs, isTrue);
      expect(cache.reads, [highlights], reason: 'the kept Songs sheet is not even read');
      expect(parser.of(songs), isEmpty);
      expect(google.total, 0);
      expect(state().fetchedAt, now.subtract(const Duration(hours: 1)));
      expect((state().highlightCount, state().playCount, state().streamCount), (1, 0, 0));
    });

    test('then the kept Songs sheet completes the same catalogue: same highlights, no download', () async {
      startWith(cached: cacheOf(sampleSheets(tag: 'cached'), now.subtract(const Duration(hours: 1))));
      await notifier().idle;
      final alone = state().catalogue!;
      wantSongs();
      await notifier().idle;
      expect(firstSong(), 'Song cached');
      expect(identical(state().catalogue!.highlights, alone.highlights), isTrue);
      expect(identical(state().catalogue!.highlightsOnly, alone), isTrue);
      expect(cache.reads, [highlights, songs]);
      expect(google.total, 0);
      expect(state().songsFetchedAt, now.subtract(const Duration(hours: 1)));
      expect((state().highlightCount, state().playCount, state().streamCount), (1, 1, 1));
    });

    test('no cache: loading, then the highlights from Google, kept; the Songs sheet not asked for', () async {
      startWith();
      google.add(sampleSheets());
      await notifier().idle;
      expect(states.first.isLoading, isTrue);
      expect(states.any((s) => s.isLoading && s.isRefreshing), isTrue);
      expect(firstTitle(), 'Video v1');
      expect(google.calls, {highlights: 1, songs: 0});
      expect(cache.writes, [highlights]);
    });

    test('the Songs sheet asked for before the highlights are in: downloaded at once, shown once they are', () async {
      startWith();
      final h = google.gate(highlights);
      google.add(sampleSheets());
      wantSongs();
      await pumpEventQueue();
      expect(google.calls, {highlights: 1, songs: 1});
      expect(state().isLoading, isTrue);
      h.complete();
      await notifier().idle;
      expect(firstTitle(), 'Video v1');
      expect(firstSong(), 'Song v1');
      expect(cache.writes.toSet(), {highlights, songs});
    });

    test('the Songs sheet comes before the highlights: they show first, then with it', () async {
      startWith();
      final h = google.gate(highlights);
      google.add(sampleSheets());
      wantSongs();
      await pumpEventQueue();
      expect(state().hasData, isFalse, reason: 'the Songs sheet alone shows nothing');
      h.complete();
      await notifier().idle;
      expect(states.where((s) => s.hasData).map((s) => s.hasSongs).toSet(), {false, true});
      expect(states.firstWhere((s) => s.hasData).hasSongs, isFalse, reason: 'the highlights do not wait for it');
    });

    test('no cache and download fails: failed state, retry succeeds', () async {
      startWith();
      google.add(const SocketException('offline'));
      google.add(sampleSheets());
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
  });

  group('when the songs are asked for', () {
    test('the first frame of the list asks for it, after the wait for its thumbnails', () async {
      startWith(cached: cacheOf(sampleSheets(), now));
      deferral = Completer();
      await notifier().idle;
      wantSongs(SongsTrigger.highlightsShown);
      await pumpEventQueue();
      expect(deferrals, 1);
      expect(cache.reads, [highlights], reason: 'nothing before the thumbnails are in');
      deferral!.complete();
      await pumpEventQueue();
      await notifier().idle;
      expect(firstSong(), 'Song v1');
      expect(parser.calls.last.background, isTrue, reason: 'the list on the screen: its frames first');
    });

    test('the Ong Log during the wait asks for it at once, parsed as the user waits for it', () async {
      startWith(cached: cacheOf(sampleSheets(), now));
      deferral = Completer();
      await notifier().idle;
      wantSongs(SongsTrigger.highlightsShown);
      await pumpEventQueue();
      wantSongs(SongsTrigger.ongLog);
      await notifier().idle;
      expect(firstSong(), 'Song v1');
      expect(parser.calls.last.background, isFalse);
      deferral!.complete();
      await pumpEventQueue();
      expect(cache.reads, [highlights, songs], reason: 'the end of the wait asks for nothing more');
    });

    test('a parse started in the background hurries once the Ong Log asks for the songs', () async {
      startWith(cached: cacheOf(sampleSheets(), now));
      await notifier().idle;
      final gate = parser.gates[(songs, 'v1')] = Completer();
      wantSongs(SongsTrigger.highlightsShown);
      await pumpEventQueue();
      final parse = parser.calls.last;
      expect((parse.sheet, parse.background, parse.hurry!()), (songs, true, false));
      wantSongs(SongsTrigger.about);
      expect(parse.hurry!(), isTrue, reason: 'the parse running goes on between frames');
      gate.complete();
      await notifier().idle;
      expect(firstSong(), 'Song v1');
      expect(parse.hurry!(), isFalse, reason: 'nothing waits once the songs are in');
    });

    test('the list shown again asks once', () async {
      startWith(cached: cacheOf(sampleSheets(), now));
      await notifier().idle;
      for (var i = 0; i < 3; i++) {
        wantSongs(SongsTrigger.highlightsShown);
      }
      await notifier().idle;
      expect(deferrals, 1);
      expect(cache.reads, [highlights, songs]);
    });
  });

  group('each sheet refreshed on its own', () {
    test('stale highlights, fresh songs: only the highlights are downloaded, swapped with the songs', () async {
      startWith(
        cached: cacheOf(sampleSheets(tag: 'old'), now.subtract(const Duration(hours: 7)), songsAt: now),
      );
      final h = google.gate(highlights);
      google.addFor(highlights, sampleSheets(tag: 'new').highlightsCsv);
      wantSongs();
      await pumpEventQueue();
      expect(firstTitle(), 'Video old');
      expect(firstSong(), 'Song old');
      expect(state().isRefreshing, isTrue);
      h.complete();
      await notifier().idle;
      expect(google.calls, {highlights: 1, songs: 0});
      expect(firstTitle(), 'Video new');
      expect(firstSong(), 'Song old', reason: 'parsed again against the new highlights, from the kept copy');
      expect(state().fetchedAt, now);
      expect(state().songsFetchedAt, now);
      expect(cache.values[highlights]!.text, contains('Video new'));
      expect(states.skipWhile((s) => !s.hasSongs).every((s) => s.hasSongs), isTrue, reason: 'songs never go');
    });

    test('fresh highlights, stale songs: only the songs are downloaded', () async {
      startWith(
        cached: cacheOf(sampleSheets(tag: 'old'), now, songsAt: now.subtract(const Duration(hours: 7))),
      );
      google.addFor(songs, sampleSheets(tag: 'new').songsCsv);
      wantSongs();
      await notifier().idle;
      expect(google.calls, {highlights: 0, songs: 1});
      expect(firstTitle(), 'Video old');
      expect(firstSong(), 'Song new');
      expect(cache.values[songs]!.fetchedAt, now);
      expect(state().updatedAt, now);
    });

    test('"Updated" is the older of the two sheets on the screen; the highlights alone before the songs', () async {
      final h = now.subtract(const Duration(hours: 1)), s = now.subtract(const Duration(hours: 3));
      startWith(cached: cacheOf(sampleSheets(), h, songsAt: s));
      await notifier().idle;
      expect(state().updatedAt, h);
      wantSongs();
      await notifier().idle;
      expect((state().fetchedAt, state().songsFetchedAt, state().updatedAt), (h, s, s));
    });

    test('the Songs sheet fails: the highlights are untouched, the Ong Log says it, Retry downloads it', () async {
      startWith(cached: cacheOf(sampleSheets(), now, withSongs: false));
      await notifier().idle;
      google.addFor(songs, const SocketException('offline'));
      wantSongs();
      await notifier().idle;
      expect(firstTitle(), 'Video v1');
      expect(state().lastError, isNull);
      expect(state().songsError, isA<SocketException>());
      expect(state().isSongsFailed, isTrue);
      expect(state().anyError, isA<SocketException>());
      google.addFor(songs, sampleSheets().songsCsv);
      final retry = notifier().retrySongs();
      expect(state().isWaitingForSongs, isTrue);
      await retry;
      expect(firstSong(), 'Song v1');
      expect(state().songsError, isNull);
      expect(google.calls, {highlights: 0, songs: 2});
    });

    test('the highlights fail, the songs come: the songs are shown with the highlights kept', () async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old'), now.subtract(const Duration(hours: 7))));
      google
        ..addFor(highlights, const SocketException('offline'))
        ..addFor(songs, sampleSheets(tag: 'new').songsCsv);
      wantSongs();
      await notifier().idle;
      expect(firstTitle(), 'Video old');
      expect(firstSong(), 'Song new');
      expect(state().lastError, isA<SocketException>());
      expect(state().songsError, isNull);
      expect(state().updatedAt, now.subtract(const Duration(hours: 7)));
    });

    test('a refresh with both changed: shown together, the songs parsed against the new highlights', () async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old'), now));
      wantSongs();
      await notifier().idle;
      google.add(sampleSheets(tag: 'new'));
      await notifier().refresh();
      expect(firstTitle(), 'Video new');
      expect(firstSong(), 'Song new');
      expect(
        states.where((s) => s.hasData && s.catalogue!.highlights.first.title == 'Video new').every((s) => s.hasSongs),
        isTrue,
        reason: 'new highlights never shown without songs',
      );
    });

    test('new highlights while the kept songs are gone and Google fails for them: shown without the songs', () async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old'), now));
      wantSongs();
      await notifier().idle;
      cache.values.remove(songs);
      google
        ..addFor(highlights, sampleSheets(tag: 'new').highlightsCsv)
        ..addFor(songs, const SocketException('offline'));
      await notifier().refresh(waitForSongs: false);
      await notifier().idle;
      expect(firstTitle(), 'Video new', reason: 'not hidden until a download of the songs succeeds');
      expect(firstSong(), isNull, reason: 'no copy of the songs to parse against them');
      expect(state().isSongsFailed, isTrue);
      expect(state().songsError, isA<SocketException>());
      google.addFor(songs, sampleSheets(tag: 'new').songsCsv);
      await notifier().retrySongs();
      expect(firstTitle(), 'Video new');
      expect(firstSong(), 'Song new');
    });
  });

  group('the Songs sheet waiting for the highlights', () {
    // a first visit opened on the Ong Log (or About): the songs are wanted before any highlight is on the screen
    Future<void> seconds(WidgetTester tester, int n) async {
      for (var i = 0; i < n; i++) {
        clock = clock.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
    }

    void plentyOfSongs() {
      for (var i = 0; i < 200; i++) {
        google.addFor(songs, sampleSheets(tag: 'n$i').songsCsv);
      }
    }

    testWidgets('the highlights failing: the songs downloaded once, not at every check', (tester) async {
      startWith();
      for (var i = 0; i < 20; i++) {
        google.addFor(highlights, const SocketException('offline'));
      }
      plentyOfSongs();
      wantSongs();
      await tester.pump(Duration.zero);
      await seconds(tester, 60);
      expect(google.calls[songs], 1);
      expect(google.calls[highlights], greaterThanOrEqualTo(2), reason: 'the highlights have their own retries');
      container.dispose();
    });

    testWidgets('the highlights refused for their content: the songs downloaded once', (tester) async {
      startWith();
      for (var i = 0; i < 20; i++) {
        google.addFor(highlights, '<html>nope</html>');
      }
      plentyOfSongs();
      wantSongs();
      await tester.pump(Duration.zero);
      await seconds(tester, 120);
      expect(google.calls[songs], 1);
      container.dispose();
    });

    testWidgets('a slow download of the highlights: the songs downloaded once, shown with them', (tester) async {
      startWith();
      final h = google.gate(highlights);
      google.addFor(highlights, sampleSheets(tag: 'h').highlightsCsv);
      plentyOfSongs();
      wantSongs();
      await tester.pump(Duration.zero);
      await seconds(tester, 10);
      h.complete();
      await seconds(tester, 5);
      expect(google.calls[songs], 1);
      expect((firstTitle(), firstSong()), ('Video h', 'Song n0'));
      container.dispose();
    });

    testWidgets('the kept songs waiting for the highlights are not downloaded again', (tester) async {
      startWith(
        cached: MemorySheetCache(
          songs: CachedSheet(text: sampleSheets().songsCsv, fetchedAt: now),
        ),
      );
      final h = google.gate(highlights);
      google.addFor(highlights, sampleSheets().highlightsCsv);
      plentyOfSongs();
      wantSongs();
      await tester.pump(Duration.zero);
      await seconds(tester, 30);
      expect(google.calls[songs], 0);
      h.complete();
      await seconds(tester, 2);
      expect(firstSong(), 'Song v1');
      container.dispose();
    });

    testWidgets('the songs failing while they wait: tried again at the delays of their own failures', (tester) async {
      startWith();
      for (var i = 0; i < 20; i++) {
        google.addFor(highlights, const SocketException('offline'));
      }
      for (var i = 0; i < 20; i++) {
        google.addFor(songs, const SocketException('offline'));
      }
      wantSongs();
      await tester.pump(Duration.zero);
      await seconds(tester, 14);
      expect(google.calls[songs], 1);
      await seconds(tester, 1);
      expect(google.calls[songs], 2, reason: '15 seconds after its failure');
      await seconds(tester, 59);
      expect(google.calls[songs], 2);
      await seconds(tester, 1);
      expect(google.calls[songs], 3, reason: 'then a minute');
      container.dispose();
    });
  });

  group('new highlights while the songs are on the screen', () {
    testWidgets('no copy of the songs to parse against them and Google failing: shown without the songs, which are '
        'tried again at their delays', (tester) async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old'), now));
      await tester.pump(Duration.zero);
      wantSongs();
      await tester.pump(Duration.zero);
      expect(firstSong(), 'Song old');
      cache.values.remove(songs);
      google
        ..addFor(highlights, sampleSheets(tag: 'new').highlightsCsv)
        ..addFor(songs, const SocketException('offline'))
        ..addFor(songs, sampleSheets(tag: 'new').songsCsv);
      unawaited(notifier().refresh());
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(firstTitle(), 'Video new', reason: 'the new highlights are not hidden behind the songs');
      expect(state().hasSongs, isFalse);
      expect(state().isSongsFailed, isTrue);
      expect(state().songsError, isA<SocketException>());
      clock = clock.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      expect(google.calls[songs], 2);
      expect((firstTitle(), firstSong()), ('Video new', 'Song new'));
      container.dispose();
    });

    testWidgets('the same when Google fails for the songs after the new highlights came', (tester) async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old'), now));
      await tester.pump(Duration.zero);
      wantSongs();
      await tester.pump(Duration.zero);
      cache.values.remove(songs);
      final s = google.gate(songs);
      google
        ..addFor(highlights, sampleSheets(tag: 'new').highlightsCsv)
        ..addFor(songs, const SocketException('offline'));
      unawaited(notifier().refresh());
      await tester.pump(Duration.zero);
      expect(firstTitle(), 'Video old', reason: 'waiting for the download of the songs');
      s.complete();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(firstTitle(), 'Video new');
      expect(state().isSongsFailed, isTrue);
      container.dispose();
    });

    test('an older kept copy of the songs is never parsed against them: the songs never go back in time', () async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old'), now.subtract(const Duration(hours: 7))));
      google.add(sampleSheets(tag: 'mid'));
      wantSongs();
      await notifier().idle;
      expect((firstTitle(), firstSong()), ('Video mid', 'Song mid'));
      // another tab (or a failed write) left an older copy of the songs in the cache
      cache.values[songs] = CachedSheet(
        text: sampleSheets(tag: 'old').songsCsv,
        fetchedAt: now.subtract(const Duration(hours: 7)),
      );
      final s = google.gate(songs);
      google
        ..addFor(highlights, sampleSheets(tag: 'new').highlightsCsv)
        ..addFor(songs, sampleSheets(tag: 'new').songsCsv);
      final since = states.length;
      Iterable<String> songsShown() =>
          states.skip(since).where((s) => s.hasSongs).map((s) => s.catalogue!.plays.first.title);
      final refresh = notifier().refresh();
      await pumpEventQueue();
      expect(firstTitle(), 'Video mid', reason: 'the new highlights wait for the download of the songs');
      expect(songsShown(), isNot(contains('Song old')));
      s.complete();
      await refresh;
      await notifier().idle;
      expect((firstTitle(), firstSong()), ('Video new', 'Song new'));
      expect(songsShown(), isNot(contains('Song old')));
    });
  });

  group('a parse failing for another reason than its content', () {
    testWidgets('of the kept songs at the start: reported as a failed load, the automatic refresh still armed', (
      tester,
    ) async {
      startWith(cached: cacheOf(sampleSheets(), now));
      parser.failures[songs]!.add(Exception('Unable to spawn isolate'));
      google.addFor(songs, sampleSheets(tag: 'later').songsCsv);
      wantSongs();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(state().songsError, isA<Exception>());
      expect(cache.removes, isEmpty, reason: 'not about the payload: the kept copy stays');
      clock = clock.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      expect(firstSong(), isNotNull, reason: 'tried again at the delay of a failure');
      container.dispose();
    });
  });

  test('failed refresh keeps the data and records the error of its sheet', () async {
    final cached = cacheOf(sampleSheets(tag: 'old'), now.subtract(const Duration(hours: 7)));
    final kept = cached.values[highlights];
    startWith(cached: cached);
    google.add(const SocketException('offline'));
    wantSongs();
    await notifier().idle;
    expect(firstTitle(), 'Video old');
    expect(firstSong(), 'Song old');
    expect(state().fetchedAt, now.subtract(const Duration(hours: 7)));
    expect(state().lastError, isA<SocketException>());
    expect(state().songsError, isA<SocketException>());
    expect(state().isRefreshing, isFalse);
    expect(state().isFailed, isFalse);
    expect(state().isSongsFailed, isFalse, reason: 'the kept songs are on the screen');
    expect(identical(cache.values[highlights], kept), isTrue);
  });

  test('invalid payloads (HTML with status 200) are rejected, each for its sheet', () async {
    startWith(cached: cacheOf(sampleSheets(tag: 'old'), now.subtract(const Duration(hours: 7))));
    google
      ..addFor(highlights, '<html><body>Sign in</body></html>')
      ..addFor(songs, '<html><body>Sign in</body></html>');
    wantSongs();
    await notifier().idle;
    expect(firstTitle(), 'Video old');
    expect(firstSong(), 'Song old');
    expect(state().lastError, isA<CatalogueFormatException>());
    expect(state().songsError, isA<CatalogueFormatException>());
    expect(cache.writes, isEmpty);
  });

  test('refreshIfStale only downloads stale data, sheet by sheet', () async {
    startWith(cached: cacheOf(sampleSheets(tag: 'old'), now));
    wantSongs();
    await notifier().idle;
    await notifier().refreshIfStale();
    expect(google.total, 0);
    clock = now.add(const Duration(hours: 6, minutes: 1));
    google.add(sampleSheets(tag: 'new'));
    await notifier().refreshIfStale();
    expect(google.calls, {highlights: 1, songs: 1});
    expect(firstTitle(), 'Video new');
    expect(firstSong(), 'Song new');
  });

  test('refreshIfStale retries when the first download failed', () async {
    startWith();
    google
      ..add(const SocketException('offline'))
      ..add(sampleSheets());
    await notifier().idle;
    await notifier().refreshIfStale();
    expect(state().hasData, isTrue);
  });

  test('concurrent refreshes share one download of each sheet', () async {
    startWith(cached: cacheOf(sampleSheets(), now));
    wantSongs();
    await notifier().idle;
    google.add(sampleSheets(tag: 'new'));
    await Future.wait([
      notifier().refresh(),
      notifier().refresh(),
      notifier().retrySongs(),
      notifier().refreshIfStale(),
    ]);
    expect(google.calls, {highlights: 1, songs: 1});
  });

  test('clear downloaded data: wipes the cache, then downloads both again', () async {
    startWith(cached: cacheOf(sampleSheets(tag: 'old'), now));
    wantSongs();
    await notifier().idle;
    final cacheAtFetch = <Sheet, bool>{};
    google
      ..onFetch = (sheet) {
        cacheAtFetch[sheet] = cache.values.isEmpty;
      }
      ..add(sampleSheets(tag: 'new'));
    await notifier().clearDownloadedData();
    expect(cacheAtFetch, {highlights: true, songs: true});
    expect(firstTitle(), 'Video new');
    expect(firstSong(), 'Song new');
    expect(cache.values[highlights]!.text, contains('Video new'));
    expect(cache.values[songs]!.text, contains('Song new'));
  });

  test('a kept sheet that no longer parses is deleted, then a download is tried', () async {
    startWith(
      cached: MemorySheetCache(
        highlights: CachedSheet(text: 'garbage', fetchedAt: now),
        songs: CachedSheet(text: 'garbage', fetchedAt: now),
      ),
    );
    google
      ..addFor(highlights, const SocketException('offline'))
      ..addFor(highlights, sampleSheets().highlightsCsv);
    await notifier().idle;
    expect(cache.removes, [highlights]);
    expect(cache.values[highlights], isNull, reason: 'the download failed, so only the deletion explains it');
    expect(state().isFailed, isTrue);
    await notifier().refresh();
    expect(firstTitle(), 'Video v1');
    expect(cache.values[highlights], isNotNull);
    google.addFor(songs, sampleSheets().songsCsv);
    wantSongs();
    await notifier().idle;
    expect(cache.removes, [highlights, songs]);
    expect(firstSong(), 'Song v1');
    expect(state().songsError, isNull, reason: 'a kept copy that does not parse is no failed download');
  });

  test('a refresh that finds the sheets unchanged keeps the catalogue instance and parses nothing', () async {
    startWith(cached: cacheOf(sampleSheets(), now.subtract(const Duration(hours: 7))));
    google.add(sampleSheets());
    wantSongs();
    await notifier().idle;
    final before = state().catalogue;
    expect(before!.hasSongs, isTrue);
    expect(google.calls, {highlights: 1, songs: 1});
    expect(parser.of(highlights), ['v1'], reason: 'only the kept copy was parsed');
    expect(parser.of(songs), ['v1']);
    expect(identical(state().catalogue, before), isTrue);
    expect(state().fetchedAt, now);
    expect(state().songsFetchedAt, now);
    expect(state().lastError, isNull);
    expect(cache.values[highlights]!.fetchedAt, now, reason: 'the cache remembers the new download time');
    expect(cache.values[songs]!.fetchedAt, now);
  });

  test('a download with less than half the rows of its sheet is rejected', () async {
    startWith(cached: cacheOf(sampleSheets(tag: 'old', extraPlays: 4), now.subtract(const Duration(hours: 7))));
    wantSongs();
    google.add(sampleSheets(tag: 'truncated'));
    await notifier().idle;
    expect(firstTitle(), 'Video truncated', reason: 'the highlights are as many');
    expect(state().playCount, 5);
    expect(state().songsError, isA<CatalogueFormatException>());
    expect(cache.writes, [highlights]);
  });

  test('a download with less than half the highlights is rejected', () async {
    final many = RawSheets(
      highlightsCsv: highlightsCsv([for (var i = 0; i < 6; i++) hRow(title: 'Video old$i')]),
      songsCsv: sampleSheets().songsCsv,
    );
    startWith(cached: cacheOf(many, now.subtract(const Duration(hours: 7))));
    google.add(sampleSheets(tag: 'truncated'));
    await notifier().idle;
    expect(state().highlightCount, 6);
    expect(state().lastError, isA<CatalogueFormatException>());
    expect(cache.writes, isEmpty);
  });

  test('a much smaller download is accepted once the data in use is a day old', () async {
    // the sheet really shrank: refusing it for ever would freeze the app on old data
    startWith(
      cached: cacheOf(sampleSheets(tag: 'old', extraPlays: 4), now.subtract(CatalogueRepository.collapseGuard)),
    );
    google.add(sampleSheets(tag: 'archived'));
    wantSongs();
    await notifier().idle;
    expect(firstTitle(), 'Video archived');
    expect(state().playCount, 1);
    expect(state().lastError, isNull);
    expect(state().songsError, isNull);
    expect(state().fetchedAt, now);
  });

  test(
    'clear downloaded data starts from scratch: a smaller sheet is accepted, an identical one parsed again',
    () async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old', extraPlays: 4), now));
      wantSongs();
      await notifier().idle;
      google.add(sampleSheets(tag: 'small'));
      await notifier().clearDownloadedData();
      expect(firstTitle(), 'Video small');
      expect(state().playCount, 1);
      expect(state().songsError, isNull);
      google.add(sampleSheets(tag: 'small'));
      final before = (parser.of(highlights).length, parser.of(songs).length);
      await notifier().clearDownloadedData();
      expect(parser.of(highlights).length, before.$1 + 1);
      // once more when the songs come before the highlights: parsed against the old ones, then the new ones
      expect(parser.of(songs).length, inInclusiveRange(before.$2 + 1, before.$2 + 2));
    },
  );

  test('a refresh requested while data is being cleared joins it', () async {
    startWith(cached: cacheOf(sampleSheets(tag: 'old'), now));
    await notifier().idle;
    final gate = google.gate(highlights);
    google.add(sampleSheets(tag: 'new'));
    final clearing = notifier().clearDownloadedData();
    await pumpEventQueue();
    final joined = notifier().refresh();
    gate.complete();
    await Future.wait([clearing, joined]);
    expect(google.calls[highlights], 1);
    expect(firstTitle(), 'Video new');
    expect(cache.values[highlights]!.text, contains('Video new'));
  });

  test('invalidating the provider during a download: the old download is dropped, the new one wins', () async {
    startWith();
    final gate = google.gate(highlights);
    google
      ..addFor(highlights, sampleSheets(tag: 'first').highlightsCsv)
      ..addFor(highlights, sampleSheets(tag: 'second').highlightsCsv);
    await pumpEventQueue();
    expect(google.calls[highlights], 1);
    container.invalidate(catalogueProvider);
    expect(state().isLoading, isTrue);
    await pumpEventQueue();
    expect(google.calls[highlights], 2, reason: 'the new build downloads on its own');
    gate.complete();
    await notifier().idle;
    expect(firstTitle(), 'Video second');
    expect(state().isRefreshing, isFalse);
    expect(states.where((s) => s.hasData).map((s) => s.catalogue!.highlights.first.title).toSet(), {'Video second'});
    // the state machine is intact: one more refresh is one more download, and the songs come on the new build
    google.gates.clear();
    google.addFor(highlights, sampleSheets(tag: 'third').highlightsCsv);
    await notifier().refresh();
    expect(google.calls[highlights], 3);
    expect(firstTitle(), 'Video third');
    google.addFor(songs, sampleSheets(tag: 'third').songsCsv);
    wantSongs();
    await notifier().idle;
    expect(firstSong(), 'Song third');
  });

  test('disposal during a download, and calls after disposal, do not throw', () async {
    startWith();
    final gate = google.gate(highlights);
    google.add(sampleSheets());
    final n = notifier();
    await pumpEventQueue();
    expect(google.calls[highlights], 1);
    container.dispose();
    gate.complete();
    await pumpEventQueue();
    await n.refresh();
    await n.retrySongs();
    n.songsWanted(SongsTrigger.ongLog);
    await n.refreshIfStale();
    await n.clearDownloadedData();
    expect(google.total, 1);
  });

  group('automatic refresh', () {
    // fake time (testWidgets); the container is created inside the fake zone and disposed at the end, with its timer

    testWidgets('no network at the first launch: tried again by itself, less and less often', (tester) async {
      startWith();
      for (var i = 0; i < 3; i++) {
        google.add(const SocketException('offline'));
      }
      google.add(sampleSheets());
      await tester.pump(Duration.zero);
      expect(google.calls[highlights], 1);
      expect(state().isFailed, isTrue);
      Future<void> wait(Duration d) async {
        clock = clock.add(d);
        await tester.pump(d);
      }

      await wait(const Duration(seconds: 14));
      expect(google.calls[highlights], 1);
      await wait(const Duration(seconds: 1));
      expect(google.calls[highlights], 2, reason: 'first retry after 15 seconds');
      await wait(const Duration(seconds: 59));
      expect(google.calls[highlights], 2);
      await wait(const Duration(seconds: 1));
      expect(google.calls[highlights], 3, reason: 'then after a minute');
      await wait(const Duration(minutes: 5));
      expect(google.calls[highlights], 4, reason: 'then after 5 minutes');
      expect(firstTitle(), 'Video v1');
      expect(state().lastError, isNull);
      await wait(const Duration(hours: 5));
      expect(google.calls[highlights], 4, reason: 'fresh data: nothing more until it is 6 hours old');
      expect(google.calls[songs], 0, reason: 'never asked for');
      container.dispose();
    });

    testWidgets('the Songs sheet has its own retries, the highlights fresh meanwhile', (tester) async {
      startWith(cached: cacheOf(sampleSheets(), now, withSongs: false));
      google
        ..addFor(songs, const SocketException('offline'))
        ..addFor(songs, const SocketException('offline'))
        ..addFor(songs, sampleSheets(tag: 'late').songsCsv);
      await tester.pump(Duration.zero);
      wantSongs();
      await tester.pump(Duration.zero);
      expect(google.calls, {highlights: 0, songs: 1});
      Future<void> wait(Duration d) async {
        clock = clock.add(d);
        await tester.pump(d);
      }

      await wait(const Duration(seconds: 15));
      expect(google.calls, {highlights: 0, songs: 2});
      await wait(const Duration(minutes: 1));
      expect(google.calls, {highlights: 0, songs: 3});
      expect(firstSong(), 'Song late');
      container.dispose();
    });

    testWidgets('an app left open refreshes every 6 hours without any lifecycle event', (tester) async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old'), now));
      google
        ..add(sampleSheets(tag: 'new'))
        ..add(sampleSheets(tag: 'newer'));
      await tester.pump(Duration.zero);
      wantSongs();
      await tester.pump(Duration.zero);
      expect(firstTitle(), 'Video old');
      for (var hour = 1; hour <= 6; hour++) {
        clock = now.add(Duration(hours: hour));
        await tester.pump(const Duration(hours: 1));
      }
      expect(google.calls, {highlights: 1, songs: 1});
      expect(firstTitle(), 'Video new');
      expect(firstSong(), 'Song new');
      clock = clock.add(const Duration(hours: 6));
      await tester.pump(const Duration(hours: 6));
      expect(google.calls, {highlights: 2, songs: 2});
      expect(firstTitle(), 'Video newer');
      container.dispose();
    });

    testWidgets('a failed refresh of stale data is tried again; fresh data after a failed refresh is not', (
      tester,
    ) async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old'), now.subtract(const Duration(hours: 7))));
      google
        ..addFor(highlights, const SocketException('offline'))
        ..addFor(highlights, sampleSheets(tag: 'new').highlightsCsv)
        ..addFor(highlights, const SocketException('x'));
      await tester.pump(Duration.zero);
      expect(state().lastError, isA<SocketException>());
      clock = clock.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      expect(google.calls[highlights], 2);
      expect(firstTitle(), 'Video new');
      // a manual refresh of fresh data fails: no automatic retry, the data is fresh
      await notifier().refresh();
      expect(google.calls[highlights], 3);
      clock = clock.add(const Duration(hours: 1));
      await tester.pump(const Duration(hours: 1));
      expect(google.calls[highlights], 3);
      container.dispose();
    });

    testWidgets('nothing automatic in the background; resuming refreshes at once', (tester) async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old'), now));
      google.add(sampleSheets(tag: 'new'));
      await tester.pump(Duration.zero);
      wantSongs();
      await tester.pump(Duration.zero);
      notifier().setForeground(false);
      clock = clock.add(const Duration(hours: 12));
      await tester.pump(const Duration(hours: 12));
      expect(google.total, 0);
      notifier().setForeground(true);
      await notifier().refreshIfStale();
      expect(google.calls, {highlights: 1, songs: 1});
      expect(firstTitle(), 'Video new');
      expect(firstSong(), 'Song new');
      container.dispose();
    });

    testWidgets('no timer runs in the background, and the check that came due runs back in the foreground', (
      tester,
    ) async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old'), now));
      google.add(sampleSheets(tag: 'new'));
      await tester.pump(Duration.zero);
      wantSongs();
      await tester.pump(Duration.zero);
      var clockReads = 0;
      final time = clock.add(const Duration(hours: 12));
      notifier().setForeground(false);
      // the clock is only read by the automatic checks here
      clockReadHook = () => clockReads++;
      clock = time;
      await tester.pump(const Duration(hours: 12));
      expect(clockReads, 0, reason: 'a check ran in the background');
      expect(google.total, 0);
      clockReadHook = null;
      notifier().setForeground(true);
      await tester.pump(const Duration(seconds: 1));
      expect(google.calls, {highlights: 1, songs: 1});
      expect(firstTitle(), 'Video new');
      // a pending timer at the end of a test is an error: none must be left in the background
      notifier().setForeground(false);
    });

    testWidgets('a web page instead of the sheets (Wi-Fi sign-in) is tried again like a network failure', (
      tester,
    ) async {
      startWith();
      final page = SheetNotCsvException(SheetUrls.highlights);
      google
        ..add(page)
        ..add(page)
        ..add(sampleSheets());
      await tester.pump(Duration.zero);
      expect(google.calls[highlights], 1);
      expect(state().lastError, isA<SheetNotCsvException>());
      expect(state().isFailed, isTrue);
      // signed in to the network meanwhile or not: after 15 seconds, and at each return to the app
      clock = clock.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      expect(google.calls[highlights], 2);
      await notifier().refreshIfStale();
      expect(google.calls[highlights], 3);
      expect(state().hasData, isTrue);
      container.dispose();
    });

    testWidgets('a download refused for its content waits for the next refresh, not for the retry delays', (
      tester,
    ) async {
      startWith();
      // sheets that are no longer what the app reads, twice, then the sheets
      const html = RawSheets(highlightsCsv: '"Recipe","Minutes"\n"Soup","20"', songsCsv: '"Recipe"\n"Soup"');
      google
        ..add(html)
        ..add(html)
        ..add(sampleSheets());
      await tester.pump(Duration.zero);
      expect(google.calls[highlights], 1);
      expect(state().lastError, isA<FormatException>());
      Future<void> wait(Duration d) async {
        clock = clock.add(d);
        await tester.pump(d);
      }

      // megabytes each time: not after 15 seconds, a minute, 5 minutes...
      await wait(const Duration(minutes: 10));
      expect(google.calls[highlights], 1);
      // ...nor at each return to the app
      await notifier().refreshIfStale();
      expect(google.calls[highlights], 1);
      await wait(catalogueMaxAge - const Duration(minutes: 11));
      expect(google.calls[highlights], 1);
      await wait(const Duration(minutes: 1));
      expect(google.calls[highlights], 2);
      await wait(catalogueMaxAge);
      expect(google.calls[highlights], 3);
      expect(state().hasData, isTrue);
      container.dispose();
    });

    testWidgets('a Songs sheet refused for its content waits too, the highlights unaffected', (tester) async {
      startWith(cached: cacheOf(sampleSheets(), now, withSongs: false));
      google
        ..addFor(songs, '"Recipe"\n"Soup"')
        ..addFor(songs, sampleSheets().songsCsv);
      await tester.pump(Duration.zero);
      wantSongs();
      await tester.pump(Duration.zero);
      expect(state().songsError, isA<FormatException>());
      expect(state().lastError, isNull);
      clock = clock.add(const Duration(hours: 1));
      await tester.pump(const Duration(hours: 1));
      await notifier().refreshIfStale();
      expect(google.calls[songs], 1);
      clock = clock.add(catalogueMaxAge);
      await tester.pump(catalogueMaxAge);
      expect(google.calls[songs], 2);
      expect(firstSong(), 'Song v1');
      container.dispose();
    });

    testWidgets('the clock set back by days does not stop the retries', (tester) async {
      startWith();
      google
        ..add(const SocketException('offline'))
        ..add(sampleSheets());
      await tester.pump(Duration.zero);
      expect(google.calls[highlights], 1);
      clock = clock.subtract(const Duration(days: 3));
      await tester.pump(const Duration(seconds: 15));
      expect(google.calls[highlights], 2);
      expect(state().hasData, isTrue);
      container.dispose();
    });
  });

  group('faults of the cache and the payload', () {
    test('a cache that cannot be written: the downloads are still used', () async {
      startWith(sheetCache: _ThrowingCache());
      google.add(sampleSheets());
      wantSongs();
      await notifier().idle;
      expect(state().hasSongs, isTrue);
      expect(state().lastError, isNull);
      expect(state().songsError, isNull);
    });

    test('a kept sheet the parser chokes on with an error that is not a FormatException is deleted', () async {
      startWith(
        cached: MemorySheetCache(
          highlights: CachedSheet(text: '"', fetchedAt: now),
          songs: CachedSheet(text: '"', fetchedAt: now),
        ),
      );
      google.add(sampleSheets(tag: 'downloaded'));
      wantSongs();
      await notifier().idle;
      expect(cache.removes, [highlights, songs]);
      expect(firstTitle(), 'Video downloaded');
      expect(firstSong(), 'Song downloaded');
    });

    test('a download the parser chokes on is reported as an unexpected format', () async {
      startWith();
      google.add(const RawSheets(highlightsCsv: '"', songsCsv: '"'));
      await notifier().idle;
      expect(state().isFailed, isTrue);
      expect(state().lastError, isA<CatalogueFormatException>());
      expect(cache.writes, isEmpty);
    });

    for (final Error error in [StateError('no element'), RangeError.index(3, const []), TypeError()]) {
      test('a parser failing on the payload with a ${error.runtimeType} counts as an unexpected format', () async {
        startWith(cached: cacheOf(sampleSheets(tag: 'cached'), now));
        // the kept copy, then the first download: both unreadable
        parser.failures[highlights]!.addAll([error, error]);
        parser.failures[songs]!.addAll([error, error]);
        google.add(sampleSheets(tag: 'downloaded'));
        wantSongs();
        await notifier().idle;
        expect(cache.removes, [highlights], reason: 'a kept copy that cannot be read is deleted');
        expect(state().lastError, isA<CatalogueFormatException>());
        expect(state().hasData, isFalse);
      });
    }

    test(
      'fresh kept highlights at start forget the download the page may have started; stale or missing do not',
      () async {
        var discards = 0;
        Future<void> start(MemorySheetCache kept) async {
          container = ProviderContainer.test(
            overrides: [
              sheetFetcherProvider.overrideWithValue(google),
              snapshotFetcherProvider.overrideWithValue(const NoSnapshot()),
              sheetCacheProvider.overrideWithValue(kept),
              sheetParserProvider.overrideWithValue(const ParseOnCurrentIsolate()),
              clockProvider.overrideWithValue(() => clock),
              prefetchDiscarderProvider.overrideWithValue(() => discards++),
            ],
          );
          container.read(catalogueProvider);
          await notifier().idle;
          container.dispose();
        }

        // fresh: nothing is downloaded now, and the next refresh must not get sheets hours old
        await start(cacheOf(sampleSheets(), now.subtract(const Duration(hours: 1))));
        expect((discards, google.total), (1, 0));
        // stale, or no cache: the download that starts takes it
        google
          ..add(sampleSheets())
          ..add(sampleSheets());
        await start(cacheOf(sampleSheets(), now.subtract(const Duration(hours: 7))));
        await start(MemorySheetCache());
        expect((discards, google.calls[highlights]), (1, 2));
      },
    );

    test('a failure that is not about the payload (the isolate could not start) keeps the cache', () async {
      startWith(cached: cacheOf(sampleSheets(tag: 'cached'), now));
      parser.failures[highlights]!.add(Exception('Unable to spawn isolate'));
      parser.failures[songs]!.add(Exception('Unable to spawn isolate'));
      // offline: with the cache deleted, nothing would be left for the next start
      google.add(const SocketException('offline'));
      wantSongs();
      await notifier().idle;
      expect(cache.removes, isEmpty);
      expect(cache.clears, 0);
      expect(cache.values[highlights]!.text, sampleSheets(tag: 'cached').highlightsCsv);
      expect(cache.values[songs]!.text, sampleSheets(tag: 'cached').songsCsv);
      expect(state().lastError, isA<SocketException>());
    });

    test('clear downloaded data offline: the cache is gone, the data in memory stays with the error', () async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old'), now));
      wantSongs();
      await notifier().idle;
      google.add(const SocketException('offline'));
      await notifier().clearDownloadedData();
      expect(cache.values, isEmpty);
      expect(firstTitle(), 'Video old');
      expect(firstSong(), 'Song old');
      expect(state().lastError, isA<SocketException>());
      expect(state().isRefreshing, isFalse);
      expect(state().isUpdating, isFalse);
    });

    test('a cache dated in the future (clock changed) does not keep a smaller sheet out', () async {
      startWith(cached: cacheOf(sampleSheets(tag: 'old', extraPlays: 4), now.add(const Duration(days: 30))));
      google.add(sampleSheets(tag: 'archived'));
      wantSongs();
      await notifier().idle;
      expect(google.calls, {highlights: 1, songs: 1}, reason: 'a download time far from now is stale');
      expect(firstTitle(), 'Video archived');
      expect(state().playCount, 1);
      expect(state().lastError, isNull);
      expect(state().songsError, isNull);
    });
  });

  test('query providers follow the catalogue, the Ong Log ones once the Songs sheet is in', () async {
    // the counts of the Highlights chips read the Twitch name and the favourites
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    startWith(cached: cacheOf(sampleSheets(extraPlays: 2), now), prefs: prefs);
    expect(container.read(playResultsProvider(const PlayFilter())), isNull);
    await notifier().idle;
    expect(container.read(highlightResultsProvider(const HighlightFilter(query: 'video')))!.length, 1);
    expect(container.read(playResultsProvider(const PlayFilter(query: 'extra')))!.length, 0);
    expect(container.read(playCountForQueryProvider('song')), 0, reason: 'no "in the Ong Log" link yet');
    wantSongs();
    await notifier().idle;
    expect(container.read(playResultsProvider(const PlayFilter(query: 'extra')))!.length, 2);
    expect(container.read(playCountForQueryProvider('song')), 1);
  });

  test('a catalogue of the highlights alone keeps the ids of its requesters when completed', () {
    final sheets = RawSheets(
      highlightsCsv: highlightsCsv([
        hRow(title: 'Video a', requester: 'zed'),
        hRow(title: 'Video b', requester: 'amy'),
      ]),
      songsCsv: songsCsv([
        start('2024-01-01'),
        sRow(date: '2024-01-01 20:00:00', title: 'Song x', requester: 'bob'),
        sRow(date: '2024-01-01 20:10:00', title: 'Song y', requester: 'Amy'),
        sRow(date: '2024-01-01 20:20:00', title: 'Song z', requester: 'Amy'),
      ]),
    );
    final alone = parseHighlights(sheets.highlightsCsv);
    final complete = alone.withSongs(parseSongs(alone, sheets.songsCsv));
    expect(alone.hasSongs, isFalse);
    expect(complete.hasSongs, isTrue);
    for (final h in alone.highlights) {
      expect(complete.requester(h.requesterId)!.folded, alone.requester(h.requesterId)!.folded);
    }
    // the spellings of both sheets name the requester once the songs are in
    expect(alone.requesterNamed('amy')!.name, 'amy');
    expect(complete.requesterNamed('amy')!.name, 'Amy');
    expect(complete.requesterNamed('amy')!.requestCount, 2);
    expect(alone.requesterNamed('amy')!.requestCount, 0);
    expect(complete.requesterNamed('bob'), isNotNull);
    expect(alone.requesterNamed('bob'), isNull);
    expect(
      () => parseHighlights(sampleSheets().highlightsCsv).withSongs(parseSongs(alone, sheets.songsCsv)),
      throwsArgumentError,
      reason: 'songs parsed against other highlights',
    );
    expect(identical(complete.withSongs(parseSongs(complete, sheets.songsCsv)).highlights, alone.highlights), isTrue);
    expect(identical(complete.highlightsOnly, alone), isTrue);
    expect(alone.playOf(alone.highlights.first), isNull);
    expect(<Catalogue>[alone, complete].map((c) => c.highlightRequestCount(c.requesterNamed('amy')!)), [1, 1]);
    expect(complete.highlightRequestCount(complete.requesterNamed('bob')!), 0);
  });
}

/// A cache whose writes throw (a broken [SheetCache] implementation).
class _ThrowingCache implements SheetCache {
  @override
  Future<CachedSheet?> read(Sheet sheet) async => null;

  @override
  Future<void> write(Sheet sheet, CachedSheet value) async =>
      throw const FileSystemException('No space left on device');

  @override
  Future<void> remove(Sheet sheet) async {}

  @override
  Future<void> clear() async {}
}
