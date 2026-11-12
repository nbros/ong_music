/// Riverpod state of the catalogue: loading, refresh policy, queries.
///
/// Read [catalogueProvider] for a [CatalogueState]; call the methods of
/// `ref.read(catalogueProvider.notifier)` ([CatalogueNotifier]) to refresh.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import '../data/parser.dart';
import '../data/repository.dart';
import '../data/sheet_cache.dart';
import '../data/sheet_prefetch.dart';
import '../data/sheets.dart';
import '../logger.dart';
import 'settings_state.dart';

/// A cached catalogue older than this is refreshed in the background.
const Duration catalogueMaxAge = Duration(hours: 6);

/// After a failed download, the automatic attempts wait this long: the first
/// delay after one failure, the second after two, and so on; the last one
/// repeats.
const List<Duration> catalogueRetryDelays = [
  Duration(seconds: 15),
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 15),
  Duration(minutes: 30),
];

/// The automatic refresh checks again at least this often (the clock may have
/// been changed meanwhile).
const Duration _maxTimerWait = Duration(hours: 1);

// ------------------------------------------------------------ dependencies
// Overridden in tests.

/// Downloads the sheets.
final sheetFetcherProvider = Provider<SheetFetcher>((ref) => HttpSheetFetcher());

/// Persists the raw sheets (files on IO, Cache API on web).
final sheetCacheProvider = Provider<SheetCache>((ref) => createSheetCache());

/// Forgets the download the web page may have started (see
/// [discardPrefetchedSheets]).
final prefetchDiscarderProvider = Provider<void Function()>((ref) => discardPrefetchedSheets);

/// Parses sheets: on a background isolate on native platforms, inline on web.
final catalogueParserProvider = Provider<CatalogueParser>(
  (ref) =>
      (sheets) => compute(parseCatalogueRecord, sheets.toRecord(), debugLabel: 'parse catalogue'),
);

/// The current time, UTC.
final clockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

/// Cache and network access.
final catalogueRepositoryProvider = Provider<CatalogueRepository>(
  (ref) => CatalogueRepository(
    fetcher: ref.watch(sheetFetcherProvider),
    cache: ref.watch(sheetCacheProvider),
    parse: ref.watch(catalogueParserProvider),
    clock: ref.watch(clockProvider),
  ),
);

// ------------------------------------------------------------ state

/// What the UI shows: the current catalogue (if any) and the refresh status.
///
/// - [isLoading]: nothing to show yet (cache being read or first download).
/// - [isFailed]: nothing to show and the download failed: show [lastError]
///   and a retry button calling [CatalogueNotifier.refresh].
/// - otherwise [catalogue] is set; [isRefreshing] tells a download is running
///   and [lastError] that the last one failed (the data shown is older).
@immutable
final class CatalogueState {
  /// Creates a state.
  const CatalogueState({this.catalogue, this.fetchedAt, this.isRefreshing = false, this.lastError});

  /// The catalogue shown, null until one is loaded.
  final Catalogue? catalogue;

  /// When the sheets of [catalogue] were downloaded (UTC): "last update".
  final DateTime? fetchedAt;

  /// A download is running.
  final bool isRefreshing;

  /// Error of the last download attempt, null when it succeeded. Network errors,
  /// [SheetHttpException], [CatalogueFormatException] (invalid payload)...
  final Object? lastError;

  bool get hasData => catalogue != null;
  bool get isLoading => catalogue == null && (isRefreshing || lastError == null);
  bool get isFailed => catalogue == null && !isRefreshing && lastError != null;

  /// Counts for the About page, 0 without data.
  int get highlightCount => catalogue?.highlightCount ?? 0;
  int get playCount => catalogue?.playCount ?? 0;
  int get streamCount => catalogue?.streamCount ?? 0;

  CatalogueState _refreshing() =>
      CatalogueState(catalogue: catalogue, fetchedAt: fetchedAt, isRefreshing: true, lastError: lastError);
  CatalogueState _failed(Object error) => CatalogueState(catalogue: catalogue, fetchedAt: fetchedAt, lastError: error);

  @override
  String toString() =>
      'CatalogueState(${catalogue == null ? 'no data' : '${catalogue!.highlightCount} highlights, ${catalogue!.playCount} plays'}, '
      'fetchedAt: $fetchedAt, refreshing: $isRefreshing, error: $lastError)';
}

/// The catalogue state and its refresh policy.
final catalogueProvider = NotifierProvider<CatalogueNotifier, CatalogueState>(CatalogueNotifier.new);

/// Refresh policy:
/// - on start, the cached catalogue is shown at once; without cache the
///   sheets are downloaded (loading, then data or failure);
/// - a cache older than [catalogueMaxAge] is refreshed in the background, at
///   start, when the app resumes ([refreshIfStale]) and while it stays in the
///   foreground ([setForeground]);
/// - a failed download (no data, or data older than [catalogueMaxAge]) is
///   tried again by itself after [catalogueRetryDelays], while the app is in
///   the foreground; a download refused for its content (a [FormatException]:
///   a sheet the app cannot read, or half emptied) is not a passing failure,
///   and megabytes each time: its next attempt, by the timer or when the app
///   resumes, waits [catalogueMaxAge] (a manual [refresh] does not);
/// - a refresh never blanks the UI: the current catalogue stays until a new
///   one downloaded and parsed successfully replaces it at once; on failure it
///   stays and [CatalogueState.lastError] is set;
/// - a refresh that finds the sheets unchanged keeps the same [Catalogue]
///   instance and only moves [CatalogueState.fetchedAt].
///
/// To retry or reload, call [refresh]; `ref.invalidate(catalogueProvider)` also
/// works but drops the catalogue in memory, so the UI goes back to loading.
class CatalogueNotifier extends Notifier<CatalogueState> {
  Future<void>? _start;
  Future<void>? _refresh;
  bool _started = false;
  LoadedCatalogue? _loaded;

  /// The next automatic check ([_refreshIfDue]).
  Timer? _timer;
  bool _foreground = true;

  /// Failed downloads in a row, and when the last download started.
  int _failures = 0;
  DateTime? _attemptAt;

  // The notifier object survives `ref.invalidate` and `ref` then designates the
  // new build, so `ref.mounted` cannot tell an asynchronous operation that the
  // build it started in is gone. Each build has a generation instead; work of
  // an older generation drops its result.
  int _generation = 0;
  bool _disposed = false;

  CatalogueRepository get _repo => ref.read(catalogueRepositoryProvider);

  @override
  CatalogueState build() {
    final generation = ++_generation;
    _disposed = false;
    _started = false;
    _refresh = null;
    _loaded = null;
    _timer?.cancel();
    _timer = null;
    _failures = 0;
    _attemptAt = null;
    ref.onDispose(() {
      if (_generation == generation) {
        _generation++;
        _disposed = true;
        _timer?.cancel();
        _timer = null;
      }
    });
    _start = Future(() => _load(generation));
    return const CatalogueState();
  }

  Future<void> _load(int generation) async {
    if (generation != _generation) return;
    LoadedCatalogue? cached;
    try {
      cached = await _repo.loadCached();
    } catch (e, st) {
      logger.w('Cannot load the cached catalogue', error: e, stackTrace: st);
    }
    if (generation != _generation) return;
    _started = true;
    if (cached != null && state.catalogue == null) {
      logger.i('Catalogue loaded from cache (${cached.fetchedAt})');
      _loaded = cached;
      state = CatalogueState(
        catalogue: cached.catalogue,
        fetchedAt: cached.fetchedAt,
        isRefreshing: state.isRefreshing,
      );
    }
    if (cached == null || _isStale(cached.fetchedAt)) {
      unawaited(refresh());
    } else {
      // no download now: the one the page started, if any, must not wait for the next refresh
      ref.read(prefetchDiscarderProvider)();
      _scheduleCheck();
    }
  }

  bool _isStale(DateTime? fetchedAt) =>
      fetchedAt == null || ref.read(clockProvider)().difference(fetchedAt).abs() >= catalogueMaxAge;

  /// Downloads the sheets now (user request, retry). Returns when done; never
  /// throws, the outcome is in [state]. Joins a download already running.
  Future<void> refresh() => _run(_download);

  /// Runs [work] as the current download, or joins the one already running.
  Future<void> _run(Future<void> Function(int generation) work) {
    if (_disposed) return Future<void>.value();
    final running = _refresh;
    if (running != null) return running;
    late final Future<void> tracked;
    tracked = work(_generation).whenComplete(() {
      if (identical(_refresh, tracked)) _refresh = null;
    });
    return _refresh = tracked;
  }

  Future<void> _download(int generation, {bool compareWithCurrent = true}) async {
    state = state._refreshing();
    _attemptAt = ref.read(clockProvider)();
    try {
      final loaded = await _repo.fetch(current: compareWithCurrent ? _loaded : null);
      if (generation != _generation) return;
      final unchanged = identical(loaded.catalogue, state.catalogue);
      logger.i(
        unchanged
            ? 'Catalogue downloaded: unchanged'
            : 'Catalogue downloaded: ${loaded.catalogue.highlightCount} highlights, ${loaded.catalogue.playCount} plays',
      );
      _loaded = loaded;
      _failures = 0;
      state = CatalogueState(catalogue: loaded.catalogue, fetchedAt: loaded.fetchedAt);
    } catch (e, st) {
      logger.w('Catalogue download failed', error: e, stackTrace: st);
      if (generation != _generation) return;
      _failures++;
      state = state._failed(e);
    }
    _scheduleCheck();
  }

  /// How long until the next automatic download: zero when the data is missing
  /// or stale, unless the last download failed less than its retry delay ago.
  Duration _untilDue() {
    final now = ref.read(clockProvider)();
    final fetchedAt = state.fetchedAt;
    var wait = state.catalogue == null || _isStale(fetchedAt)
        ? Duration.zero
        : catalogueMaxAge - now.difference(fetchedAt!);
    final attemptAt = _attemptAt;
    if (_failures > 0 && attemptAt != null) {
      final delay = state.lastError is FormatException
          ? catalogueMaxAge
          : catalogueRetryDelays[math.min(_failures, catalogueRetryDelays.length) - 1];
      final retryWait = delay - now.difference(attemptAt).abs();
      if (retryWait > wait) wait = retryWait;
    }
    return wait;
  }

  /// Arms [_timer] for the next automatic check. No timer runs in the
  /// background: [setForeground] arms it again.
  void _scheduleCheck() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || !_foreground) return;
    var wait = _untilDue();
    if (wait > _maxTimerWait) wait = _maxTimerWait;
    if (wait < const Duration(seconds: 1)) wait = const Duration(seconds: 1);
    _timer = Timer(wait, _refreshIfDue);
  }

  /// The automatic check: downloads when [_untilDue] says so.
  void _refreshIfDue() {
    _timer = null;
    if (_disposed || !_started || _refresh != null) return;
    if (_untilDue() <= Duration.zero) {
      unawaited(refresh());
    } else {
      _scheduleCheck();
    }
  }

  /// Whether the app is in the foreground (resumed or inactive): only then do
  /// the automatic refreshes and retries run, and their timer. True until told
  /// otherwise. Back in the foreground, a check that came due meanwhile runs
  /// within a second, unless [refreshIfStale] was called first.
  void setForeground(bool foreground) {
    if (_disposed || foreground == _foreground) return;
    _foreground = foreground;
    if (_started) _scheduleCheck();
  }

  /// Refreshes when the data is older than [catalogueMaxAge], or when there is
  /// none because the first download failed. Call it when the app resumes.
  Future<void> refreshIfStale() async {
    if (_disposed || !_started) return;
    final running = _refresh;
    if (running != null) return running;
    if (state.catalogue == null || _isStale(state.fetchedAt)) {
      // refused for its content: not again at each return to the app (see [_untilDue]); "Retry" still does
      if (state.lastError is FormatException && _untilDue() > Duration.zero) return;
      return refresh();
    }
  }

  /// "Clear downloaded data": deletes the cache, then downloads and parses
  /// again from scratch. The catalogue in memory stays visible meanwhile (and
  /// if the download fails).
  Future<void> clearDownloadedData() async {
    if (_disposed) return;
    final generation = _generation;
    await _start;
    while (_refresh != null) {
      await _refresh;
    }
    if (generation != _generation) return;
    // Deleting runs as the current download: a refresh requested meanwhile
    // joins it instead of racing the deletion.
    return _run((generation) async {
      state = state._refreshing();
      try {
        await _repo.clearCache();
      } catch (e, st) {
        logger.w('Cannot clear the cache', error: e, stackTrace: st);
      }
      if (generation != _generation) return;
      await _download(generation, compareWithCurrent: false);
    });
  }

  /// Completes when the start sequence and any running download are over.
  Future<void> get idle async {
    await _start;
    while (_refresh != null) {
      await _refresh;
    }
  }
}

// ------------------------------------------------------------ queries

/// The highlight list filters.
@immutable
final class HighlightFilter {
  /// Creates a filter; the defaults match everything.
  const HighlightFilter({this.query = '', this.genre, this.mine = false, this.favourites = false});

  /// Search text (see `tokenize`).
  final String query;

  /// Only this genre when set.
  final Genre? genre;

  /// Only the user's own requests (the "You" chip, see [myRequesterProvider]).
  final bool mine;

  /// Only the user's favourites (the star chip, see [favouritesProvider]).
  final bool favourites;

  @override
  bool operator ==(Object other) =>
      other is HighlightFilter &&
      other.query == query &&
      other.genre == genre &&
      other.mine == mine &&
      other.favourites == favourites;

  @override
  int get hashCode => Object.hash(query, genre, mine, favourites);
}

/// The Ong Log list filters.
@immutable
final class PlayFilter {
  /// Creates a filter; the defaults match everything.
  const PlayFilter({this.query = '', this.type, this.genre, this.withVideo = false, this.mine = false});

  /// Search text (see `tokenize`).
  final String query;

  /// Only this type when set ([PlayType.piano] / [PlayType.loop] in the UI).
  final PlayType? type;

  /// Only this genre when set.
  final Genre? genre;

  /// Only plays linked to a highlight.
  final bool withVideo;

  /// Only the user's own requests (the "You" chip, see [myRequesterProvider]).
  final bool mine;

  @override
  bool operator ==(Object other) =>
      other is PlayFilter &&
      other.query == query &&
      other.type == type &&
      other.genre == genre &&
      other.withVideo == withVideo &&
      other.mine == mine;

  @override
  int get hashCode => Object.hash(query, type, genre, withVideo, mine);
}

/// The catalogue shown, or null (rebuilds only when it is replaced).
final currentCatalogueProvider = Provider<Catalogue?>((ref) => ref.watch(catalogueProvider.select((s) => s.catalogue)));

/// The requester the Twitch name designates in the current catalogue, the one
/// whose name is shown in orange on their requests (`Catalogue.isRequester`); null
/// without name, catalogue or request under that name.
final myRequesterProvider = Provider<Requester?>((ref) {
  final name = ref.watch(twitchNameProvider);
  return name.isEmpty ? null : ref.watch(currentCatalogueProvider)?.requesterNamed(name);
});

/// How many highlights the user requested: the count of the "You" chip of the
/// Highlights list, which only shows when it is not 0.
final myHighlightCountProvider = Provider<int>((ref) {
  final me = ref.watch(myRequesterProvider);
  return me == null ? 0 : ref.watch(currentCatalogueProvider)!.highlightRequestCount(me);
});

/// How many highlights of the current catalogue are favourites: the count of
/// the star chip of the Highlights list, which only shows when it is not 0.
/// Stored favourites absent from the catalogue do not count.
final favouriteCountProvider = Provider<int>(
  (ref) => ref.watch(currentCatalogueProvider)?.highlightCountWithKeys(ref.watch(favouritesProvider)) ?? 0,
);

/// How many plays the user requested; the "You" chip of the Ong Log only shows
/// when it is not 0.
final myPlayCountProvider = Provider<int>((ref) => ref.watch(myRequesterProvider)?.requestCount ?? 0);

/// The requester id a "You" filter keeps, given the number of the user's
/// requests in the list ([myHighlightCountProvider], [myPlayCountProvider]).
/// Null when [mine] is off, and when the list holds none of them: the chip is
/// gone then, and so is its filter, even before the filter notifier clears it.
int? _myRequesterId(Ref ref, bool mine, Provider<int> count) =>
    mine && ref.watch(count) > 0 ? ref.watch(myRequesterProvider)!.id : null;

/// Highlights matching a filter, newest first, with the counts of the chips
/// ("You" counts the user's requests, the star the favourites); null without
/// catalogue.
final highlightResultsProvider = Provider.autoDispose.family<HighlightResults?, HighlightFilter>((ref, filter) {
  final catalogue = ref.watch(currentCatalogueProvider);
  if (catalogue == null) return null;
  return catalogue.searchHighlights(
    query: filter.query,
    genre: filter.genre,
    requesterId: ref.watch(myRequesterProvider)?.id,
    onlyRequester: _myRequesterId(ref, filter.mine, myHighlightCountProvider) != null,
    keys: ref.watch(favouritesProvider),
    // as for "You": no filter on favourites while the list holds none (the chip is gone)
    onlyKeys: filter.favourites && ref.watch(favouriteCountProvider) > 0,
  );
});

/// Plays matching a filter, newest first; null without catalogue.
final playResultsProvider = Provider.autoDispose.family<PlayResults?, PlayFilter>(
  (ref, filter) => ref
      .watch(currentCatalogueProvider)
      ?.searchPlays(
        query: filter.query,
        type: filter.type,
        genre: filter.genre,
        withVideo: filter.withVideo,
        requesterId: _myRequesterId(ref, filter.mine, myPlayCountProvider),
      ),
);

/// Number of plays matching a query (the "N in the Ong Log" link); 0 without
/// catalogue or for an empty query.
final playCountForQueryProvider = Provider.autoDispose.family<int, String>(
  (ref, query) => ref.watch(currentCatalogueProvider)?.countPlays(query) ?? 0,
);
