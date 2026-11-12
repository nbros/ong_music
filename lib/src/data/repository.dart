/// Loading the catalogue from the cache or the network.
library;

import '../logger.dart';
import 'catalogue.dart';
import 'parser.dart';
import 'sheet_cache.dart';
import 'sheets.dart';

/// Parses raw sheets into a catalogue, possibly on another isolate.
/// Throws [CatalogueFormatException] for an invalid payload.
typedef CatalogueParser = Future<Catalogue> Function(RawSheets sheets);

/// Parses on the calling isolate (tests, scripts).
Future<Catalogue> parseOnCurrentIsolate(RawSheets sheets) async =>
    parseCatalogue(sheets.highlightsCsv, sheets.songsCsv);

/// A catalogue and the time its sheets were downloaded.
final class LoadedCatalogue {
  /// Bundles a catalogue, its download time and the identity of its sheets.
  const LoadedCatalogue(this.catalogue, this.fetchedAt, this.fingerprint);

  final Catalogue catalogue;

  /// When its sheets were downloaded (UTC).
  final DateTime fetchedAt;

  /// Identity of the raw sheets [catalogue] was parsed from.
  final SheetsFingerprint fingerprint;
}

/// Cache and network access, without policy (that is `CatalogueNotifier`'s).
final class CatalogueRepository {
  /// Creates the repository. [clock] gives the current time (UTC).
  CatalogueRepository({required this.fetcher, required this.cache, required this.parse, DateTime Function()? clock})
    : clock = clock ?? (() => DateTime.now().toUtc());

  final SheetFetcher fetcher;
  final SheetCache cache;
  final CatalogueParser parse;
  final DateTime Function() clock;

  /// The cached catalogue, or null when there is no cache. A cache that no
  /// longer parses is deleted and reads as null.
  Future<LoadedCatalogue?> loadCached() async {
    final cached = await cache.read();
    if (cached == null) return null;
    try {
      return LoadedCatalogue(await _parse(cached.sheets), cached.fetchedAt, cached.sheets.fingerprint);
    } on FormatException {
      await cache.clear();
      return null;
    }
  }

  /// [parse], whose failures on a payload it was not written for (a
  /// [StateError], an [ArgumentError] such as a [RangeError], a [TypeError]:
  /// bugs met on unexpected input) count as a [CatalogueFormatException]. Any other failure is not
  /// about the payload (the isolate could not start, no memory left) and
  /// is thrown as it is: the cache it was reading is good and must be kept.
  Future<Catalogue> _parse(RawSheets sheets) async {
    try {
      return await parse(sheets);
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
  /// [current] is the catalogue in use, if any. It makes two things possible:
  /// - when the download is identical to its sheets, its catalogue is returned
  ///   as is (same instance) with the new download time: nothing is parsed
  ///   again (parsing blocks the UI thread on web) and the ids held by the UI
  ///   stay valid. That is the common case, the sheets change a few times a week;
  /// - a download with less than half its highlights or plays is rejected: the
  ///   sheets only grow, so that is most likely a wrong answer or a sheet being
  ///   edited. Only while [current] is younger than [collapseGuard] though: a
  ///   sheet that really shrank (rows archived) must not be refused for ever.
  Future<LoadedCatalogue> fetch({LoadedCatalogue? current}) async {
    final sheets = await fetcher.fetch();
    final fingerprint = sheets.fingerprint;
    final Catalogue catalogue;
    if (current != null && current.fingerprint == fingerprint) {
      catalogue = current.catalogue;
    } else {
      catalogue = await _parse(sheets);
      // abs: a download time in the future (clock changed) must not keep the guard on for ever
      if (current != null && clock().difference(current.fetchedAt).abs() < collapseGuard) {
        _checkNotCollapsed(current.catalogue, catalogue);
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
