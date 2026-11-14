/// Loading the catalogue from the cache or the network.
library;

import '../logger.dart';
import 'catalogue.dart';
import 'page_thread.dart';
import 'parser.dart';
import 'sheet_cache.dart';
import 'sheet_snapshot.dart';
import 'sheets.dart';
import 'slices.dart';

/// Parses raw sheets into a catalogue, possibly on another isolate, or in slices.
/// Throws [CatalogueFormatException] for an invalid payload.
///
/// [isAbandoned], when given, tells that the catalogue is no longer wanted (the state that asked for it is gone): a
/// parser that can stop halfway then throws [LoadAbandoned] instead of going on for nothing. [background] tells that
/// a catalogue is already on the screen: a parser that shares the thread of the page then lets its frames come first
/// (a list being scrolled); otherwise the user waits for it.
typedef CatalogueParser = Future<Catalogue> Function(RawSheets sheets, {bool Function()? isAbandoned, bool background});

/// Computes the [SheetsFingerprint] of raw sheets; [isAbandoned] and [background] as for [CatalogueParser].
typedef SheetsFingerprinter =
    Future<SheetsFingerprint> Function(RawSheets sheets, {bool Function()? isAbandoned, bool background});

/// Parses on the calling isolate, in one go (tests, scripts).
Future<Catalogue> parseOnCurrentIsolate(
  RawSheets sheets, {
  bool Function()? isAbandoned,
  bool background = false,
}) async => parseCatalogue(sheets.highlightsCsv, sheets.songsCsv);

/// Parses on the calling thread in slices, letting the browser draw a frame between two of them ([yieldToBrowser]):
/// the web, where there is no other thread to parse on, and the megabytes of the sheets would freeze the page for a
/// fifth of a second on a fast laptop, a second on a modest phone. The catalogue is that of [parseOnCurrentIsolate]
/// (see [CatalogueLoad]).
///
/// Slices of [sliceBudget]; when nothing is shown yet (not [background]), longer ones on a device whose frames are
/// costly, up to [longestSlice] (see [runInSlices]). [pause] and [clock] are those of [runInSlices], replaced by
/// tests only.
Future<Catalogue> parseInSlices(
  RawSheets sheets, {
  bool Function()? isAbandoned,
  bool background = false,
  Future<void> Function() pause = yieldToBrowser,
  int Function()? clock,
}) async {
  final load = CatalogueLoad(sheets.highlightsCsv, sheets.songsCsv);
  await runInSlices(load.step, pause: pause, clock: clock, maxBudget: _maxBudget(background), isAbandoned: isAbandoned);
  return load.catalogue;
}

Duration _maxBudget(bool background) => background ? sliceBudget : longestSlice;

/// [RawSheets.fingerprint], at once: native platforms, where `String.hashCode` is computed natively and kept.
Future<SheetsFingerprint> fingerprintAtOnce(
  RawSheets sheets, {
  bool Function()? isAbandoned,
  bool background = false,
}) async => sheets.fingerprint;

/// A fingerprint of the sheets in slices, as [parseInSlices] does: on the web `String.hashCode`, which
/// [RawSheets.fingerprint] takes, is a loop over the code units, a dozen milliseconds for the Songs sheet. The hashes
/// are those of [TextHash]: compare its fingerprints only with each other (the repository takes both sides of every
/// comparison from the function it was given). [pause] and [clock] as for [parseInSlices].
Future<SheetsFingerprint> fingerprintInSlices(
  RawSheets sheets, {
  bool Function()? isAbandoned,
  bool background = false,
  Future<void> Function() pause = yieldToBrowser,
  int Function()? clock,
}) async {
  final highlights = TextHash(sheets.highlightsCsv), songs = TextHash(sheets.songsCsv);
  await runInSlices(
    () => highlights.add(unitsPerPause) || songs.add(unitsPerPause),
    pause: pause,
    clock: clock,
    maxBudget: _maxBudget(background),
    isAbandoned: isAbandoned,
  );
  return (
    highlightsLength: sheets.highlightsCsv.length,
    highlightsHash: highlights.value,
    songsLength: sheets.songsCsv.length,
    songsHash: songs.value,
  );
}

/// A catalogue and the time its sheets were downloaded.
final class LoadedCatalogue {
  /// Bundles a catalogue, its download time and the identity of its sheets.
  const LoadedCatalogue(this.catalogue, this.fetchedAt, this.fingerprint, {this.isSnapshot = false});

  final Catalogue catalogue;

  /// When its sheets were downloaded (UTC); for a snapshot, when the copy was made.
  final DateTime fetchedAt;

  /// Identity of the raw sheets [catalogue] was parsed from.
  final SheetsFingerprint fingerprint;

  /// Whether the sheets come from the daily copy ([SnapshotFetcher]), not from Google.
  final bool isSnapshot;
}

/// Cache and network access, without policy (that is `CatalogueNotifier`'s).
final class CatalogueRepository {
  /// Creates the repository. [clock] gives the current time (UTC).
  CatalogueRepository({
    required this.fetcher,
    required this.cache,
    required this.parse,
    this.snapshots = const NoSnapshot(),
    this.fingerprint = fingerprintAtOnce,
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());

  final SheetFetcher fetcher;
  final SheetCache cache;

  /// The daily copy of the sheets ([loadSnapshot]).
  final SnapshotFetcher snapshots;
  final CatalogueParser parse;
  final SheetsFingerprinter fingerprint;
  final DateTime Function() clock;

  /// The cached catalogue, or null when there is no cache. A cache that no
  /// longer parses is deleted and reads as null.
  ///
  /// [isAbandoned]: see [CatalogueParser]. An abandoned load throws [LoadAbandoned] and keeps the cache.
  Future<LoadedCatalogue?> loadCached({bool Function()? isAbandoned}) async {
    final cached = await cache.read();
    if (cached == null) return null;
    final Catalogue catalogue;
    try {
      catalogue = await _parse(cached.sheets, isAbandoned);
    } on FormatException {
      await cache.clear();
      return null;
    }
    return LoadedCatalogue(catalogue, cached.fetchedAt, await fingerprint(cached.sheets, isAbandoned: isAbandoned));
  }

  /// The daily copy of the sheets, parsed: a [LoadedCatalogue.isSnapshot] dated when the copy was made. Nothing is
  /// cached. Throws when there is none or it does not parse (then a [CatalogueFormatException]); an abandoned load
  /// ([isAbandoned], asked once the files are in and at each pause of the parser) throws [LoadAbandoned].
  Future<LoadedCatalogue> loadSnapshot({bool Function()? isAbandoned}) async {
    final snapshot = await snapshots.fetch();
    if (isAbandoned?.call() ?? false) throw const LoadAbandoned();
    final catalogue = await _parse(snapshot.sheets, isAbandoned);
    return LoadedCatalogue(
      catalogue,
      snapshot.fetchedAt,
      await fingerprint(snapshot.sheets, isAbandoned: isAbandoned),
      isSnapshot: true,
    );
  }

  /// [parse], whose failures on a payload it was not written for (a
  /// [StateError], an [ArgumentError] such as a [RangeError], a [TypeError]:
  /// bugs met on unexpected input) count as a [CatalogueFormatException]. Any other failure is not
  /// about the payload (the isolate could not start, no memory left) and
  /// is thrown as it is: the cache it was reading is good and must be kept.
  Future<Catalogue> _parse(RawSheets sheets, bool Function()? isAbandoned, {bool background = false}) async {
    try {
      return await parse(sheets, isAbandoned: isAbandoned, background: background);
    } on StateError catch (e) {
      throw CatalogueFormatException('Unreadable sheets: $e');
    } on ArgumentError catch (e) {
      throw CatalogueFormatException('Unreadable sheets: $e');
    } on TypeError catch (e) {
      throw CatalogueFormatException('Unreadable sheets: $e');
    }
  }

  /// Downloads and parses both sheets, then caches them. Throws (and caches
  /// nothing) when a download fails or a payload is invalid
  /// ([CatalogueFormatException]); a failure to cache only loses the cache.
  ///
  /// [current] gives the catalogue in use, if any, read once the sheets are downloaded. It makes two things possible:
  /// - when the download is identical to its sheets, its catalogue is returned
  ///   as is (same instance) with the new download time: nothing is parsed
  ///   again (megabytes, on the page's only thread on web) and the ids held by the UI
  ///   stay valid. That is the common case, the sheets change a few times a week;
  /// - a download with less than half its highlights or plays is rejected: the
  ///   sheets only grow, so that is most likely a wrong answer or a sheet being
  ///   edited. Only while [current] is younger than [collapseGuard] though: a
  ///   sheet that really shrank (rows archived) must not be refused for ever.
  ///   Never against a snapshot: Google's answer always replaces it, as it
  ///   would have been taken without it.
  ///
  /// [isAbandoned] and [background]: see [CatalogueParser]; a [current] catalogue is on the screen, and counts as
  /// [background] too. An abandoned fetch throws [LoadAbandoned] and caches nothing. [downloaded] is called once the
  /// sheets are downloaded, before they are parsed.
  Future<LoadedCatalogue> fetch({
    LoadedCatalogue? Function()? current,
    bool Function()? isAbandoned,
    bool background = false,
    void Function()? downloaded,
  }) async {
    final sheets = await fetcher.fetch();
    downloaded?.call();
    final shown = current?.call();
    // a catalogue on the screen, the snapshot shown meanwhile among them: its frames come first
    final inBackground = background || shown != null;
    final fingerprint = await this.fingerprint(sheets, isAbandoned: isAbandoned, background: inBackground);
    final Catalogue catalogue;
    if (shown != null && shown.fingerprint == fingerprint) {
      catalogue = shown.catalogue;
    } else {
      catalogue = await _parse(sheets, isAbandoned, background: inBackground);
      // abs: a download time in the future (clock changed) must not keep the guard on for ever
      if (shown != null && !shown.isSnapshot && clock().difference(shown.fetchedAt).abs() < collapseGuard) {
        _checkNotCollapsed(shown.catalogue, catalogue);
      }
    }
    final fetchedAt = clock();
    try {
      await cache.write(CachedSheets(sheets: sheets, fetchedAt: fetchedAt));
    } catch (e, st) {
      // SheetCache implementations should not throw; the download stays good anyway
      logger.w('Cannot cache the sheets', error: e, stackTrace: st);
    }
    return LoadedCatalogue(catalogue, fetchedAt, fingerprint);
  }

  /// How long a download much smaller than the catalogue in use is refused,
  /// counted from the download of that catalogue.
  static const Duration collapseGuard = Duration(days: 1);

  static void _checkNotCollapsed(Catalogue current, Catalogue next) {
    if (next.highlightCount * 2 < current.highlightCount || next.playCount * 2 < current.playCount) {
      throw CatalogueFormatException(
        'Download rejected: ${next.highlightCount} highlights and ${next.playCount} plays, '
        'against ${current.highlightCount} and ${current.playCount} now',
      );
    }
  }

  /// Deletes the cached sheets.
  Future<void> clearCache() => cache.clear();
}
