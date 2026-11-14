/// Riverpod state of the catalogue: loading, refresh policy, queries.
///
/// Read [catalogueProvider] for a [CatalogueState]; call the methods of
/// `ref.read(catalogueProvider.notifier)` ([CatalogueNotifier]) to refresh.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import '../data/parser.dart';
import '../data/repository.dart';
import '../data/sheet_cache.dart';
import '../data/sheet_prefetch.dart';
import '../data/sheet_snapshot.dart';
import '../data/sheets.dart';
import '../data/slices.dart';
import '../logger.dart';
import 'settings_state.dart';

/// A kept sheet older than this is refreshed in the background.
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

// ------------------------------------------------------------ when the Songs sheet is loaded

/// When the Songs sheet (the Ong Log, 4 MB, seven times the Highlights sheet) is read and downloaded: once the
/// Highlights list is on the screen and the thumbnails of its first rows are in ([songsDeferralProvider]), in the
/// background, in the time its frames leave; at once when something needs it first ([SongsTrigger]). The Highlights
/// list never waits for it: it shows from the Highlights sheet alone, and what the Songs sheet adds to it (the "N in
/// the Ong Log" link of a search, the facts of a fiche taken from the Ong Log) appears when it comes.
///
/// What asks for the Songs sheet ([CatalogueNotifier.songsWanted]).
enum SongsTrigger {
  /// The first frame of the Highlights list is drawn: the Songs sheet comes in the background, after
  /// [songsDeferralProvider].
  highlightsShown,

  /// The Ong Log tab is on the screen, however it was reached: the navigation, the keyboard, the address or the
  /// history of the browser, "Requested by …" in a fiche, the "N in the Ong Log" link.
  ongLog,

  /// The About tab is on the screen: its counts of songs and streams, the requests found under the Twitch name.
  about,
}

/// Waits, once the first frame of the Highlights list is drawn, before the Songs sheet is loaded:
/// until the images that frame asked for (the thumbnails of the first rows) are in, at most two seconds. Its megabyte
/// must not take the bandwidth they need. Overridden in tests.
final songsDeferralProvider = Provider<Future<void> Function()>((ref) => _imagesSettled);

Future<void> _imagesSettled() async {
  final images = PaintingBinding.instance.imageCache;
  final watch = Stopwatch()..start();
  while (images.pendingImageCount > 0 && watch.elapsed < const Duration(seconds: 2)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

// ------------------------------------------------------------ dependencies
// Overridden in tests.

/// Downloads the sheets.
final sheetFetcherProvider = Provider<SheetFetcher>((ref) => HttpSheetFetcher());

/// Downloads the daily copy of the sheets, shown on a first load until Google answers.
final snapshotFetcherProvider = Provider<SnapshotFetcher>((ref) => HttpSnapshotFetcher());

/// Persists the raw sheets (files on IO, Cache API on web).
final sheetCacheProvider = Provider<SheetCache>((ref) => createSheetCache());

/// Forgets the downloads the web page may have started (see
/// [discardPrefetchedSheets]).
final prefetchDiscarderProvider = Provider<void Function()>((ref) => discardPrefetchedSheets);

/// Whether the sheets are loaded on the calling thread in slices, between which it does its other work: the web,
/// where `compute` has no other thread to run on, and would parse in one go. Elsewhere they are loaded on a
/// background isolate. Overridden by the tests of that choice.
final loadsInSlicesProvider = Provider<bool>((ref) => kIsWeb);

/// Parses the sheets: on a background isolate on native platforms ([ParseInBackground]), in slices between frames
/// on web ([ParseInSlices]).
final sheetParserProvider = Provider<SheetParser>(
  (ref) => ref.watch(loadsInSlicesProvider) ? const ParseInSlices() : const ParseInBackground(),
);

/// Fingerprints the text of a sheet: at once on native platforms ([fingerprintAtOnce]), in slices on web
/// ([fingerprintInSlices]).
final textFingerprintProvider = Provider<TextFingerprinter>(
  (ref) => ref.watch(loadsInSlicesProvider) ? fingerprintInSlices : fingerprintAtOnce,
);

/// Parses on a background isolate (`compute`). `isAbandoned` is not asked: the isolate runs to its end, and the
/// result is dropped. `background` changes nothing: the thread of the UI is free anyway. The Songs sheet comes back
/// without the highlights it was parsed against ([SongsPart]): the catalogue completed with it shares them.
final class ParseInBackground implements SheetParser {
  /// Creates the parser.
  const ParseInBackground();

  @override
  Future<Catalogue> highlights(String csv, {bool Function()? isAbandoned, bool background = false}) =>
      compute(parseHighlightsRecord, csv, debugLabel: 'parse highlights');

  @override
  Future<SongsPart> songs(
    Catalogue highlights,
    String csv, {
    bool Function()? isAbandoned,
    bool background = false,
    bool Function()? hurry,
  }) => compute(parseSongsRecord, (highlights: highlights, songsCsv: csv), debugLabel: 'parse songs');
}

/// The current time, UTC.
final clockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

/// The wall time of the device at an instant: the zone the time of a play is shown in (the sheet writes it in US
/// Eastern time; its dates are shown as written). Only the fields of the result (year … minute) are read, never its
/// instant, so a replacement may return a UTC `DateTime` carrying another zone's wall time. Called per instant:
/// nothing keeps an offset, the device's own daylight saving applies to each time.
final wallTimeProvider = Provider<DateTime Function(DateTime instant)>(
  (ref) =>
      (instant) => instant.toLocal(),
);

/// Cache and network access.
final catalogueRepositoryProvider = Provider<CatalogueRepository>(
  (ref) => CatalogueRepository(
    fetcher: ref.watch(sheetFetcherProvider),
    cache: ref.watch(sheetCacheProvider),
    snapshots: ref.watch(snapshotFetcherProvider),
    parser: ref.watch(sheetParserProvider),
    fingerprint: ref.watch(textFingerprintProvider),
    clock: ref.watch(clockProvider),
  ),
);

// ------------------------------------------------------------ state

/// What the UI shows: the current catalogue (if any) and the status of each sheet.
///
/// The Highlights sheet:
/// - [isLoading]: nothing to show yet (cache being read or first download).
/// - [isFailed]: nothing to show and the download failed: show [lastError]
///   and a retry button calling [CatalogueNotifier.refresh].
/// - otherwise [catalogue] is set; [isRefreshing] tells a download of the sheet is running
///   and [lastError] that the last one failed (the data shown is older).
///
/// The Songs sheet, once the catalogue is there: [hasSongs] when it is in the catalogue; until then
/// [isWaitingForSongs] (being read, downloaded or parsed, or not asked for yet) or [isSongsFailed] (show
/// [songsError] and a retry button calling [CatalogueNotifier.retrySongs]). Once in, [isRefreshingSongs] and
/// [songsError] are about its refreshes.
@immutable
final class CatalogueState {
  /// Creates a state.
  const CatalogueState({
    this.catalogue,
    this.fetchedAt,
    this.isRefreshing = false,
    this.lastError,
    this.isSnapshot = false,
    this.songsFetchedAt,
    this.isLoadingSongs = false,
    this.songsError,
    this.isSongsSnapshot = false,
  });

  /// The catalogue shown, null until one is loaded. It may not have the Songs sheet yet ([hasSongs]).
  final Catalogue? catalogue;

  /// When the Highlights sheet of [catalogue] was downloaded (UTC). For the daily copy shown on a first load, when
  /// the copy was made.
  final DateTime? fetchedAt;

  /// A download of the Highlights sheet is running.
  final bool isRefreshing;

  /// The Highlights sheet of [catalogue] is the daily copy, shown on a first load until Google's answer replaces it.
  final bool isSnapshot;

  /// Error of the last download attempt of the Highlights sheet, null when it succeeded. Network errors,
  /// [SheetHttpException], [CatalogueFormatException] (invalid payload)...
  final Object? lastError;

  /// When the Songs sheet of [catalogue] was downloaded, as [fetchedAt]; null without [hasSongs].
  final DateTime? songsFetchedAt;

  /// The Songs sheet is being read, downloaded or parsed.
  final bool isLoadingSongs;

  /// Error of the last attempt to download or parse the Songs sheet, null when it succeeded.
  final Object? songsError;

  /// The Songs sheet of [catalogue] is the daily copy, as [isSnapshot].
  final bool isSongsSnapshot;

  bool get hasData => catalogue != null;
  bool get isLoading => catalogue == null && (isRefreshing || lastError == null);
  bool get isFailed => catalogue == null && !isRefreshing && lastError != null;

  /// Whether the catalogue has the Songs sheet (the Ong Log).
  bool get hasSongs => catalogue?.hasSongs ?? false;

  /// The highlights are there, not the Songs sheet, which is on its way or not asked for yet: the Ong Log waits.
  bool get isWaitingForSongs => hasData && !hasSongs && !isSongsFailed;

  /// The highlights are there, and the Songs sheet could not be loaded: the Ong Log shows [songsError].
  bool get isSongsFailed => hasData && !hasSongs && !isLoadingSongs && songsError != null;

  /// The Songs sheet is in and being downloaded again.
  bool get isRefreshingSongs => hasSongs && isLoadingSongs;

  /// A download of either sheet is running ("Updating…").
  bool get isUpdating => isRefreshing || isLoadingSongs;

  /// When the data on the screen was downloaded ("Updated …"): the older of the two sheets, the Highlights sheet
  /// alone until the Songs sheet is in. Null without data.
  DateTime? get updatedAt {
    final songs = hasSongs ? songsFetchedAt : null;
    final highlights = fetchedAt;
    if (songs == null || highlights == null) return highlights ?? songs;
    return songs.isBefore(highlights) ? songs : highlights;
  }

  /// The error of the last attempt that failed, of either sheet, the Highlights sheet first; null when the last
  /// attempt of each one succeeded.
  Object? get anyError => lastError ?? songsError;

  /// Counts for the About page, 0 without data.
  int get highlightCount => catalogue?.highlightCount ?? 0;
  int get playCount => catalogue?.playCount ?? 0;
  int get streamCount => catalogue?.streamCount ?? 0;

  @override
  String toString() =>
      'CatalogueState(${catalogue == null ? 'no data' : '${catalogue!.highlightCount} highlights, ${catalogue!.playCount} plays'}, '
      'fetchedAt: $fetchedAt, refreshing: $isRefreshing, error: $lastError, '
      'songsFetchedAt: $songsFetchedAt, loadingSongs: $isLoadingSongs, songsError: $songsError)';
}

/// The catalogue state and its refresh policy.
final catalogueProvider = NotifierProvider<CatalogueNotifier, CatalogueState>(CatalogueNotifier.new);

/// What the notifier knows of one sheet.
final class _Sheet {
  _Sheet(this.sheet);

  final Sheet sheet;

  /// The copy taken last (kept, downloaded or the daily copy): its time, whether it is the daily copy, its
  /// fingerprint. Null until one is parsed.
  DateTime? fetchedAt;
  bool isSnapshot = false;
  TextFingerprint? fingerprint;

  /// The same for the copy on the screen: the Highlights sheet may wait for the Songs sheet to be parsed again
  /// against it before it shows.
  DateTime? shownAt;
  bool shownSnapshot = false;

  /// Failed attempts in a row, when the last download started, the error of the last attempt.
  int failures = 0;
  DateTime? attemptAt;
  Object? error;

  /// Reads, downloads and parses running.
  int busy = 0;

  /// The download running, if any.
  Future<void>? download;

  /// Whether a download of this build has brought the sheet: its daily copy is no longer wanted.
  bool downloaded = false;

  /// Whether the next download starts from scratch ("Clear downloaded data"): taken whatever its size.
  bool fromScratch = false;

  void took(SheetText text) {
    fetchedAt = text.fetchedAt;
    isSnapshot = text.isSnapshot;
    fingerprint = text.fingerprint;
  }

  void show() {
    shownAt = fetchedAt;
    shownSnapshot = isSnapshot;
  }
}

/// A text of the Songs sheet waiting to be parsed, and whether it is the kept copy.
final class _SongsInput {
  _SongsInput(this.text, {this.kept = false, this.fromScratch = false});

  final SheetText text;

  /// Read from the cache: never kept again, dropped from it when it does not parse, never refused for its size.
  final bool kept;

  /// Downloaded after "Clear downloaded data": never refused for its size either.
  final bool fromScratch;
}

/// Refresh policy, for each sheet on its own:
/// - on start, the kept copy of the Highlights sheet is shown at once, without the Songs sheet, which is read and
///   downloaded once the list is on the screen, or something needs it ([songsWanted]): its kept copy is then shown
///   at once too, completing the
///   catalogue. Without a kept copy a sheet is downloaded (the Highlights sheet: loading, then data or failure). On a
///   first visit (nothing kept) the daily copy of each sheet ([SnapshotFetcher]) is asked at the same time as its
///   download: shown when it comes before Google's answer, which then replaces it, as a refresh does. It is never
///   cached, never stops or delays a download (data shown from it is always due for one), and its failures are not
///   reported;
/// - a sheet older than [catalogueMaxAge] is refreshed in the background, at start (the Songs sheet: once wanted),
///   when the app resumes ([refreshIfStale]) and while it stays in the foreground ([setForeground]);
/// - a failed download (no data, or data older than [catalogueMaxAge]) is tried again by itself after
///   [catalogueRetryDelays], while the app is in the foreground, each sheet with its own count of failures; a
///   download refused for its content (a [FormatException]: a sheet the app cannot read, or half emptied) is not a
///   passing failure, and megabytes each time: its next attempt, by the timer or when the app resumes, waits
///   [catalogueMaxAge] (a manual [refresh] does not);
/// - a refresh never blanks the UI: the current catalogue stays until a new one downloaded and parsed successfully
///   replaces it at once; on failure it stays and the error of the sheet is set. Once the Songs sheet is on the
///   screen it stays: new highlights show with it, parsed again against them;
/// - a refresh that finds a sheet unchanged keeps the same [Catalogue] instance and only moves its time.
///
/// To retry or reload, call [refresh]; `ref.invalidate(catalogueProvider)` also
/// works but drops the catalogue in memory, so the UI goes back to loading.
class CatalogueNotifier extends Notifier<CatalogueState> {
  Future<void>? _start;
  bool _started = false;

  late _Sheet _highlights, _songs;

  /// Highlights parsed while a complete catalogue is on the screen: they show once the Songs sheet is parsed again
  /// against them ([_songsWork]).
  Catalogue? _pendingHighlights;

  /// A text of the Songs sheet to parse against the highlights.
  _SongsInput? _songsInput;

  /// The daily copy of the Songs sheet on the screen, kept to be parsed again against new highlights (Google's
  /// answer for them, on a first visit): it is in no cache.
  _SongsInput? _shownSongsSnapshot;

  /// The parse of the Songs sheet running or done last ([_songsWork]), and whether it must look again once done.
  Future<void>? _songsRun;
  bool _songsAgain = false;

  /// Whether this run started with nothing kept: the only one that asks for the daily copies.
  bool _firstVisit = false;

  /// Whether the Songs sheet was asked for ([songsWanted]), and whether by something on the screen waiting for it.
  bool _songsWanted = false;
  bool _songsUrgent = false;
  bool _songsDeferred = false;

  /// The next automatic check ([_refreshIfDue]).
  Timer? _timer;
  bool _foreground = true;

  // The notifier object survives `ref.invalidate` and `ref` then designates the
  // new build, so `ref.mounted` cannot tell an asynchronous operation that the
  // build it started in is gone. Each build has a generation instead; work of
  // an older generation drops its result.
  int _generation = 0;
  bool _disposed = false;

  CatalogueRepository get _repo => ref.read(catalogueRepositoryProvider);

  _Sheet _of(Sheet sheet) => sheet == Sheet.highlights ? _highlights : _songs;

  @override
  CatalogueState build() {
    final generation = ++_generation;
    _disposed = false;
    _started = false;
    _highlights = _Sheet(Sheet.highlights);
    _songs = _Sheet(Sheet.songs);
    _pendingHighlights = null;
    _songsInput = null;
    _shownSongsSnapshot = null;
    _songsRun = null;
    _songsRunning = false;
    _songsAgain = false;
    _firstVisit = false;
    _songsWanted = false;
    _songsUrgent = false;
    _songsDeferred = false;
    _timer?.cancel();
    _timer = null;
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

  /// The state from what is known of each sheet, [catalogue] on the screen (the current one when null).
  void _publish([Catalogue? catalogue]) {
    final shown = catalogue ?? state.catalogue;
    final h = _highlights, s = _songs;
    state = CatalogueState(
      catalogue: shown,
      fetchedAt: h.shownAt,
      isRefreshing: h.busy > 0,
      lastError: h.error,
      isSnapshot: h.shownSnapshot,
      songsFetchedAt: (shown?.hasSongs ?? false) ? s.shownAt : null,
      isLoadingSongs: s.busy > 0,
      songsError: s.error,
      isSongsSnapshot: (shown?.hasSongs ?? false) && s.shownSnapshot,
    );
  }

  Future<void> _load(int generation) async {
    if (generation != _generation) return;
    SheetText? cached;
    Catalogue? catalogue;
    // false once the cache was read and holds nothing usable; not when it could not be read
    var kept = true;
    try {
      cached = await _repo.readCache(Sheet.highlights, isAbandoned: () => generation != _generation);
      if (cached != null) {
        try {
          catalogue = await _repo.parseHighlights(cached.text, isAbandoned: () => generation != _generation);
        } on FormatException catch (e) {
          logger.w('The kept highlights no longer parse: $e');
          await _repo.forget(Sheet.highlights);
          cached = null;
        }
      }
      kept = cached != null;
    } on LoadAbandoned {
      return;
    } catch (e, st) {
      cached = null;
      logger.w('Cannot load the kept highlights', error: e, stackTrace: st);
    }
    if (generation != _generation) return;
    _started = true;
    // nothing kept of the highlights: the daily copy of the highlights is asked for, even when the songs are kept
    // (the list would wait for Google otherwise), and that of the songs only if they are not kept either
    _firstVisit = !kept;
    if (kept) discardPrefetchedSnapshot();
    if (cached != null && catalogue != null && state.catalogue == null) {
      logger.i('Highlights loaded from cache (${cached.fetchedAt})');
      _highlights
        ..took(cached)
        ..show();
      _publish(catalogue);
    }
    if (cached == null || _isStale(cached.fetchedAt)) {
      unawaited(_downloadOnce(Sheet.highlights));
      // first launch: the daily copy may be on the screen a second or more before Google's answer
      if (!kept) unawaited(_showSnapshot(Sheet.highlights, generation));
    } else {
      // no download now: the one the page started, if any, must not wait for the next refresh
      ref.read(prefetchDiscarderProvider)();
    }
    try {
      if (_songsWanted) await _startSongs(generation);
    } finally {
      _scheduleCheck();
    }
  }

  bool _isStale(DateTime? fetchedAt) =>
      fetchedAt == null || ref.read(clockProvider)().difference(fetchedAt).abs() >= catalogueMaxAge;

  /// Whether [sheet] calls for a download now: none taken, the daily copy (only Google's answer counts, however
  /// recent the copy), or older than [catalogueMaxAge]. The Songs sheet: never before it is wanted; a text of it
  /// waiting to be parsed (for the highlights to come) counts as taken, with its own time; wanted and neither on the
  /// screen nor waiting, it is due (at the delays of its own failures, [_untilDue]).
  bool _isDue(Sheet sheet) {
    final s = _of(sheet);
    if (sheet == Sheet.songs) {
      if (!_songsWanted) return false;
      final waiting = _songsInput;
      if (waiting != null) return waiting.text.isSnapshot || _isStale(waiting.text.fetchedAt);
      if (!(state.catalogue?.hasSongs ?? false) || _pendingHighlights != null) return true;
    }
    return s.isSnapshot || _isStale(s.fetchedAt);
  }

  // ---------------------------------------------------------------- the Songs sheet

  /// [trigger] happened: loads the Songs sheet, at once, or after [songsDeferralProvider] for the first frame of the
  /// Highlights list. Its kept copy is read first, then it is downloaded when that copy is missing or stale. Does
  /// nothing once it was asked for (but a tab asking for it then makes a parse running in the background hurry).
  void songsWanted(SongsTrigger trigger) {
    if (_disposed) return;
    if (trigger != SongsTrigger.highlightsShown) {
      _wantSongs(urgent: true);
      return;
    }
    if (_songsWanted || _songsDeferred) return;
    _songsDeferred = true;
    final generation = _generation;
    unawaited(
      ref.read(songsDeferralProvider)().then((_) {
        if (generation == _generation) _wantSongs(urgent: false);
      }),
    );
  }

  void _wantSongs({required bool urgent}) {
    if (urgent) _songsUrgent = true;
    if (_songsWanted) return;
    _songsWanted = true;
    // before the start is over, it starts them itself
    if (_started) unawaited(_track(_startSongs(_generation)));
  }

  Future<void> _startSongs(int generation) async {
    final s = _songs;
    s.busy++;
    _publish();
    SheetText? cached;
    try {
      // its frames first: the Highlights list may be scrolled meanwhile
      cached = await _repo.readCache(
        Sheet.songs,
        isAbandoned: () => generation != _generation,
        background: !_songsUrgent,
      );
    } on LoadAbandoned {
      return;
    } catch (e, st) {
      logger.w('Cannot read the kept songs', error: e, stackTrace: st);
    } finally {
      s.busy--;
    }
    if (generation != _generation) return;
    if (cached != null && s.fetchedAt == null && _songsInput == null) {
      logger.i('Songs loaded from cache (${cached.fetchedAt})');
      _songsInput = _SongsInput(cached, kept: true);
      // on the screen before a download can replace it, as the highlights at the start: it is what the download is
      // compared with, and what stays when it fails
      await _songsWork(generation);
      if (generation != _generation) return;
    } else {
      _publish();
    }
    // a kept copy waiting for the highlights is taken: not downloaded again meanwhile (one that failed to parse
    // asked for Google's itself)
    if (cached == null || _isStale(cached.fetchedAt)) unawaited(_downloadOnce(Sheet.songs));
    // the copy of a first visit only: one that started with nothing kept of the highlights, and has nothing of the
    // songs either
    if (cached == null && _firstVisit) unawaited(_showSnapshot(Sheet.songs, generation));
  }

  /// The highlights the Songs sheet is to be parsed against: those waiting for it, else those on the screen.
  Catalogue? get _target => _pendingHighlights ?? state.catalogue?.highlightsOnly;

  /// Parses the Songs sheet against the highlights until the catalogue on the screen has both as they were last
  /// taken: the text taken last ([_songsInput]), or, for new highlights under a complete catalogue, the copy of the
  /// Songs sheet on the screen again (kept, or the daily copy). One at a time: called while it runs, it looks again
  /// once done.
  Future<void> _songsWork(int generation) {
    if (generation != _generation) return Future.value();
    if (_songsRunning) {
      _songsAgain = true;
      return _songsRun ?? Future.value();
    }
    _songsRunning = true;
    final s = _songs;
    s.busy++;
    final run = () async {
      try {
        do {
          _songsAgain = false;
          await _songsPass(generation);
        } while (_songsAgain && generation == _generation);
      } finally {
        // in the same task as the last look at [_songsAgain]: a call in between would be lost
        _songsRunning = false;
        s.busy--;
        if (generation == _generation) _publish();
      }
    }();
    return _songsRun = run;
  }

  bool _songsRunning = false;

  /// One pass of [_songsWork]; sets [_songsAgain] when another one is needed.
  Future<void> _songsPass(int generation) async {
    final s = _songs;
    final target = _target;
    final shown = state.catalogue;
    if (!_songsWanted || target == null || shown == null) return;
    var input = _songsInput;
    if (input == null) {
      // nothing new: the catalogue on the screen is up to date, unless new highlights wait for the songs, or the
      // songs wanted are not there (a download refused: the kept copy, if any)
      if (shown.hasSongs && identical(shown.highlightsOnly, target)) return;
      input = _shownSongsSnapshot;
      if (input == null) {
        var kept = await _keptSongs(generation);
        if (generation != _generation) return;
        // never back in time: a copy older than the songs on the screen (another tab, a write that failed) is not
        // parsed against the new highlights
        final shownAt = s.shownAt;
        if (kept != null && shownAt != null && kept.fetchedAt.isBefore(shownAt)) {
          logger.i('The kept songs (${kept.fetchedAt}) are older than those on the screen ($shownAt): not taken');
          kept = null;
        }
        input = kept == null ? null : _SongsInput(kept, kept: true);
      }
      if (input == null) {
        // no copy of them to parse again: Google's, the highlights waiting for it while it downloads; after a failed
        // download, they show without the songs rather than stay hidden until it succeeds
        if (s.download != null) return;
        if (s.failures == 0) {
          unawaited(_downloadOnce(Sheet.songs));
        } else {
          _showPendingWithoutSongs();
        }
        _scheduleCheck();
        return;
      }
      // something newer may have come meanwhile
      if (_songsInput != null) {
        _songsAgain = true;
        return;
      }
      _songsInput = input;
    }
    final text = input.text;
    final Catalogue complete;
    try {
      complete = await _repo.parseSongs(
        target,
        text.text,
        // the Highlights list is on the screen: its frames come first, unless the Ong Log waits for the songs, now or
        // once it asks for them meanwhile
        background: shown.hasSongs || !_songsUrgent,
        hurry: () => _songsUrgent && !(state.catalogue?.hasSongs ?? false),
        isAbandoned: () => generation != _generation || !identical(_songsInput, input) || !identical(_target, target),
      );
      // a download, against the songs in use: not half of them
      final current = shown.hasSongs ? shown : null;
      if (!input.kept &&
          !input.fromScratch &&
          !text.isSnapshot &&
          current != null &&
          !s.isSnapshot &&
          ref.read(clockProvider)().difference(s.fetchedAt!).abs() < CatalogueRepository.collapseGuard) {
        CatalogueRepository.checkSongsNotCollapsed(current, complete);
      }
    } on LoadAbandoned {
      // another text or other highlights came meanwhile
      if (generation == _generation) _songsAgain = true;
      return;
    } on FormatException catch (e) {
      if (generation != _generation) return;
      logger.w('Songs refused: $e');
      if (identical(_songsInput, input)) _songsInput = null;
      if (input.kept) {
        // as for the highlights: a kept copy that no longer parses goes, and Google is asked
        unawaited(_repo.forget(Sheet.songs));
        unawaited(_downloadOnce(Sheet.songs));
      } else if (!text.isSnapshot) {
        // a download refused for its content counts as a failed download of the sheet
        _fail(s, e);
      }
      // new highlights waiting for the songs, or none on the screen: with the copy kept or on the screen, then
      if ((_pendingHighlights != null || !shown.hasSongs) && !input.kept) _songsAgain = true;
      return;
    } catch (e, st) {
      // not about the payload (the isolate could not start, no memory left): a failed load, tried again at the
      // delays of a failure; a kept copy stays kept
      if (generation != _generation) return;
      logger.w('Songs not parsed', error: e, stackTrace: st);
      if (identical(_songsInput, input)) _songsInput = null;
      _fail(s, e);
      _showPendingWithoutSongs();
      _scheduleCheck();
      return;
    }
    if (generation != _generation) return;
    // a parse that ran to its end (a background isolate) after another text or other highlights came: for nothing
    if (!identical(_songsInput, input) || !identical(_target, target)) {
      _songsAgain = true;
      return;
    }
    _songsInput = null;
    if (input.kept || text.isSnapshot) {
      s.took(text);
    } else {
      _done(s, text, keep: true);
    }
    s.show();
    _shownSongsSnapshot = text.isSnapshot ? input : null;
    if (identical(_pendingHighlights, target)) {
      _pendingHighlights = null;
      _highlights.show();
    }
    logger.i('Songs in: ${complete.playCount} plays');
    _publish(complete);
  }

  /// Shows the highlights waiting for the songs ([_pendingHighlights]) without them: no copy of the songs could be
  /// parsed against them. Better than hiding new highlights until a download of the songs succeeds (hours, after a
  /// refusal): the Ong Log then says the songs could not be had, and they are tried again at their own delays.
  void _showPendingWithoutSongs() {
    final pending = _pendingHighlights;
    if (pending == null) return;
    logger.w('New highlights shown without the songs: no copy of the songs to parse against them');
    _pendingHighlights = null;
    _shownSongsSnapshot = null;
    _highlights.show();
    _publish(pending);
  }

  /// The kept copy of the Songs sheet, read again to parse it against new highlights; null when there is none.
  Future<SheetText?> _keptSongs(int generation) async {
    try {
      return await _repo.readCache(Sheet.songs, isAbandoned: () => generation != _generation, background: true);
    } on LoadAbandoned {
      return null;
    } catch (e, st) {
      logger.w('Cannot read the kept songs', error: e, stackTrace: st);
      return null;
    }
  }

  // ---------------------------------------------------------------- downloads

  /// Downloads the sheets now (user request, retry): the Highlights sheet, and the Songs sheet once it was asked
  /// for. Returns when done, or when the Highlights sheet is done when not [waitForSongs]; never throws, the outcome
  /// is in [state]. Joins the downloads already running.
  Future<void> refresh({bool waitForSongs = true}) {
    if (_disposed) return Future<void>.value();
    final highlights = _downloadOnce(Sheet.highlights);
    // a text of the Songs sheet waiting for the highlights, and recent enough, is not downloaded again
    final songsWait = _songsInput != null && !_isDue(Sheet.songs);
    final songs = _songsWanted && !songsWait ? _downloadOnce(Sheet.songs) : null;
    return waitForSongs && songs != null ? Future.wait([highlights, songs]) : highlights;
  }

  /// Downloads the Songs sheet now (the Retry of the Ong Log), asking for it if it was not yet.
  Future<void> retrySongs() {
    if (_disposed) return Future<void>.value();
    if (!_songsWanted) {
      _wantSongs(urgent: true);
      return idle;
    }
    return _downloadOnce(Sheet.songs);
  }

  /// Runs the download of [sheet], or joins the one already running.
  Future<void> _downloadOnce(Sheet sheet) {
    if (_disposed) return Future<void>.value();
    final s = _of(sheet);
    final running = s.download;
    if (running != null) return running;
    late final Future<void> tracked;
    tracked = _track(_download(sheet, _generation)).whenComplete(() {
      if (identical(s.download, tracked)) s.download = null;
    });
    return s.download = tracked;
  }

  /// Work that [idle] waits for.
  final Set<Future<void>> _running = {};

  Future<void> _track(Future<void> work) {
    _running.add(work);
    return work.whenComplete(() => _running.remove(work));
  }

  Future<void> _download(Sheet sheet, int generation) async {
    final s = _of(sheet);
    s.busy++;
    s.attemptAt = ref.read(clockProvider)();
    _publish();
    try {
      final text = await _repo.download(
        sheet,
        isAbandoned: () => generation != _generation,
        // a catalogue on the screen: the list may be scrolled meanwhile, its frames come first
        background: state.catalogue != null,
      );
      if (generation != _generation) return;
      s.downloaded = true;
      if (sheet == Sheet.highlights) {
        await _takeHighlights(text, generation);
      } else {
        await _takeSongs(text, generation);
      }
    } on LoadAbandoned {
      // superseded (the provider was rebuilt or disposed): the generation that asked for it has gone
      return;
    } catch (e, st) {
      logger.w('Download of the ${sheet.name} sheet failed', error: e, stackTrace: st);
      if (generation != _generation) return;
      _fail(s, e);
      // new highlights waiting for this download, with no copy of the songs to parse against them
      if (sheet == Sheet.songs && _songsInput == null && !_songsRunning) _showPendingWithoutSongs();
    } finally {
      s.busy--;
      if (generation == _generation) {
        _publish();
        _scheduleCheck();
      }
    }
  }

  void _fail(_Sheet s, Object error) {
    s
      ..failures += 1
      ..error = error;
  }

  /// Google's answer for the Highlights sheet: the catalogue on the screen kept when it is the same, else parsed and
  /// shown (with the Songs sheet parsed again against it, when on the screen). Throws when refused.
  Future<void> _takeHighlights(SheetText text, int generation) async {
    final h = _highlights;
    final current = _target;
    if (current != null && h.fingerprint == text.fingerprint) {
      logger.i('Highlights downloaded: unchanged');
      _done(h, text, keep: true);
      if (_pendingHighlights == null) h.show();
      _publish();
      return;
    }
    final catalogue = await _repo.parseHighlights(
      text.text,
      isAbandoned: () => generation != _generation,
      background: state.catalogue != null,
    );
    // abs: a download time in the future (clock changed) must not keep the guard on for ever; never against a
    // snapshot: Google's answer always replaces it, as it would have been taken without it; nor after a clear
    final fromScratch = h.fromScratch;
    h.fromScratch = false;
    if (current != null &&
        !fromScratch &&
        !h.isSnapshot &&
        ref.read(clockProvider)().difference(h.fetchedAt!).abs() < CatalogueRepository.collapseGuard) {
      CatalogueRepository.checkHighlightsNotCollapsed(current, catalogue);
    }
    if (generation != _generation) return;
    logger.i('Highlights downloaded: ${catalogue.highlightCount}');
    _done(h, text, keep: true);
    await _showHighlights(catalogue, generation);
  }

  /// [text] taken as the copy of the sheet of [s]: its failures are over, and a download is kept.
  void _done(_Sheet s, SheetText text, {required bool keep}) {
    s
      ..took(text)
      ..failures = 0
      ..error = null;
    if (keep) unawaited(_repo.keep(s.sheet, text));
  }

  /// Shows [catalogue], highlights alone: at once while the Songs sheet is not on the screen (then parsed against
  /// them if it waits), else once it is parsed again against them.
  Future<void> _showHighlights(Catalogue catalogue, int generation) async {
    if (!(state.catalogue?.hasSongs ?? false)) {
      _pendingHighlights = null;
      _highlights.show();
      _publish(catalogue);
      if (_songsInput != null) await _songsWork(generation);
    } else {
      _pendingHighlights = catalogue;
      await _songsWork(generation);
    }
  }

  /// Google's answer for the Songs sheet: the catalogue on the screen kept when it is the same, else parsed against
  /// the highlights and shown.
  Future<void> _takeSongs(SheetText text, int generation) async {
    final s = _songs;
    // (new highlights waiting for the songs: this text is parsed against them)
    if (state.hasSongs && s.fingerprint == text.fingerprint && _songsInput == null && _pendingHighlights == null) {
      logger.i('Songs downloaded: unchanged');
      _done(s, text, keep: true);
      s.show();
      _shownSongsSnapshot = null;
      _publish();
      return;
    }
    _songsInput = _SongsInput(text, fromScratch: s.fromScratch);
    s.fromScratch = false;
    await _songsWork(generation);
  }

  /// Shows the daily copy of [sheet], unless a download brought the sheet first (or this build is gone): the first
  /// load, while nothing of the sheet is on the screen. Its failures are logged only: without it, the first load is
  /// as it was before it existed. A download that failed before it came keeps its error, shown as after any failed
  /// refresh.
  Future<void> _showSnapshot(Sheet sheet, int generation) async {
    final s = _of(sheet);
    bool unwanted() => generation != _generation || s.downloaded || s.fetchedAt != null;
    final SheetText copy;
    try {
      copy = await _repo.snapshot(sheet, isAbandoned: unwanted, background: state.catalogue != null);
    } on LoadAbandoned {
      return;
    } catch (e) {
      logger.i('No snapshot of the ${sheet.name} sheet: $e');
      return;
    }
    if (unwanted()) return;
    if (sheet == Sheet.songs) {
      if (_songsInput != null) return;
      logger.i('Songs shown from the snapshot of ${copy.fetchedAt}');
      _songsInput = _SongsInput(copy);
      await _songsWork(generation);
      return;
    }
    final Catalogue catalogue;
    try {
      catalogue = await _repo.parseHighlights(copy.text, isAbandoned: unwanted);
    } on LoadAbandoned {
      return;
    } catch (e) {
      logger.i('The snapshot of the highlights does not parse: $e');
      return;
    }
    if (unwanted() || state.catalogue != null) return;
    logger.i('Highlights shown from the snapshot of ${copy.fetchedAt}');
    s.took(copy);
    await _showHighlights(catalogue, generation);
  }

  // ---------------------------------------------------------------- the automatic refresh

  /// How long until the next automatic download of [sheet]: zero when it is missing or stale, unless its last
  /// download failed less than its retry delay ago. Null for the Songs sheet until it is wanted.
  Duration? _untilDue(Sheet sheet) {
    if (sheet == Sheet.songs && !_songsWanted) return null;
    final s = _of(sheet);
    final now = ref.read(clockProvider)();
    // the time of the text that decides (_isDue): one waiting for the highlights, else the one taken
    final takenAt = (sheet == Sheet.songs ? _songsInput?.text.fetchedAt : null) ?? s.fetchedAt;
    var wait = _isDue(sheet) ? Duration.zero : catalogueMaxAge - now.difference(takenAt!);
    final attemptAt = s.attemptAt;
    if (s.failures > 0 && attemptAt != null) {
      final delay = s.error is FormatException
          ? catalogueMaxAge
          : catalogueRetryDelays[math.min(s.failures, catalogueRetryDelays.length) - 1];
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
    if (_disposed || !_foreground || !_started) return;
    Duration? wait;
    for (final sheet in Sheet.values) {
      final until = _untilDue(sheet);
      if (until != null && (wait == null || until < wait)) wait = until;
    }
    if (wait == null) return;
    if (wait > _maxTimerWait) wait = _maxTimerWait;
    if (wait < const Duration(seconds: 1)) wait = const Duration(seconds: 1);
    _timer = Timer(wait, _refreshIfDue);
  }

  /// The automatic check: downloads each sheet [_untilDue] says so, unless it is being read, downloaded or parsed.
  void _refreshIfDue() {
    _timer = null;
    if (_disposed || !_started) return;
    for (final sheet in Sheet.values) {
      final until = _untilDue(sheet);
      if (until != null && until <= Duration.zero && _of(sheet).busy == 0) unawaited(_downloadOnce(sheet));
    }
    _scheduleCheck();
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

  /// Refreshes each sheet older than [catalogueMaxAge], or missing because its first download failed (or only its
  /// daily copy is there); the Songs sheet once it was asked for. Call it when the app resumes.
  Future<void> refreshIfStale() async {
    if (_disposed || !_started) return;
    final downloads = [
      for (final sheet in Sheet.values)
        if (_of(sheet).download case final running?)
          running
        else if (_untilDue(sheet) != null && _isDue(sheet) && _of(sheet).busy == 0)
          // refused for its content: not again at each return to the app (see [_untilDue]); "Retry" still does
          if (!(_of(sheet).error is FormatException && _untilDue(sheet)! > Duration.zero)) _downloadOnce(sheet),
    ];
    await Future.wait(downloads);
  }

  /// "Clear downloaded data": deletes the cache, then downloads and parses
  /// again from scratch (the Songs sheet once it was asked for). The catalogue in memory stays visible meanwhile
  /// (and if the download fails).
  Future<void> clearDownloadedData() async {
    if (_disposed) return;
    final generation = _generation;
    await idle;
    if (generation != _generation) return;
    // Deleting runs as the current download of the Highlights sheet: a refresh requested meanwhile joins it
    // instead of racing the deletion.
    final h = _highlights;
    late final Future<void> tracked;
    tracked =
        _track(() async {
          h.busy++;
          _publish();
          try {
            await _repo.clearCache();
          } catch (e, st) {
            logger.w('Cannot clear the cache', error: e, stackTrace: st);
          } finally {
            h.busy--;
          }
          if (generation != _generation) return;
          // parsed again whatever they hold, taken whatever their size
          h
            ..fingerprint = null
            ..fromScratch = true;
          _songs
            ..fingerprint = null
            ..fromScratch = true;
          _shownSongsSnapshot = null;
          if (identical(h.download, tracked)) h.download = null;
          await Future.wait([_downloadOnce(Sheet.highlights), if (_songsWanted) _downloadOnce(Sheet.songs)]);
        }()).whenComplete(() {
          if (identical(h.download, tracked)) h.download = null;
        });
    h.download = tracked;
    return tracked;
  }

  /// Completes when the start sequence and the reads, downloads and parses it started are over (not the daily
  /// copies, nor the wait of [songsDeferralProvider]).
  Future<void> get idle async {
    await _start;
    while (_running.isNotEmpty || _songsRunning) {
      await Future.wait([..._running, ?_songsRun]);
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
