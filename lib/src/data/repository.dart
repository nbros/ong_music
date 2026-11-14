/// Loading the catalogue from the cache or the network, a sheet at a time.
library;

import '../logger.dart';
import 'catalogue.dart';
import 'page_thread.dart';
import 'parser.dart';
import 'sheet_cache.dart';
import 'sheet_snapshot.dart';
import 'sheets.dart';
import 'slices.dart';

/// Parses the sheets, possibly on another isolate, or in slices: the Highlights sheet alone ([highlights]), then the
/// Songs sheet against the highlights of a catalogue ([songs]). Both throw [CatalogueFormatException] for an invalid
/// payload.
///
/// `isAbandoned`, when given, tells that the result is no longer wanted (the state that asked for it is gone, or
/// another download replaced the text): a parser that can stop halfway then throws [LoadAbandoned] instead of going
/// on for nothing. `background` tells that a catalogue is already on the screen: a parser that shares the thread of
/// the page then lets its frames come first (a list being scrolled); otherwise the user waits for it.
abstract interface class SheetParser {
  /// The catalogue of the highlights alone (`parseHighlights`).
  Future<Catalogue> highlights(String csv, {bool Function()? isAbandoned, bool background = false});

  /// What the Songs sheet adds to [highlights] (`parseSongs`). [hurry] tells, while it runs in the background, that
  /// something now waits for it (the Ong Log): a parser that shares the thread of the page then goes on as for work
  /// the user waits for.
  Future<SongsPart> songs(
    Catalogue highlights,
    String csv, {
    bool Function()? isAbandoned,
    bool background = false,
    bool Function()? hurry,
  });
}

/// Parses on the calling isolate, in one go (tests, scripts).
final class ParseOnCurrentIsolate implements SheetParser {
  /// Creates the parser.
  const ParseOnCurrentIsolate();

  @override
  Future<Catalogue> highlights(String csv, {bool Function()? isAbandoned, bool background = false}) async =>
      parseHighlights(csv);

  @override
  Future<SongsPart> songs(
    Catalogue highlights,
    String csv, {
    bool Function()? isAbandoned,
    bool background = false,
    bool Function()? hurry,
  }) async => parseSongs(highlights, csv);
}

/// Parses on the calling thread in slices, letting the browser draw a frame between two of them: the web, where
/// there is no other thread to parse on, and the megabytes of the Songs sheet would freeze the page for a fifth of a
/// second on a fast laptop, a second on a modest phone. The results are those of [ParseOnCurrentIsolate] (see
/// [HighlightsLoad], [SongsLoad]).
///
/// When nothing is shown yet (not `background`), slices of [sliceBudget], longer ones on a device whose frames are
/// costly, up to [longestSlice] (see [runInSlices]). In the `background`, in the idle time the page leaves between
/// its frames ([idle], see [runWhenIdle]): a list scrolled meanwhile keeps every one of its frames; then as when
/// nothing is shown once `hurry` says so, or after [patience]. [pause], [idle], [clock] and [patience] are replaced
/// by tests only.
final class ParseInSlices implements SheetParser {
  /// Creates the parser.
  const ParseInSlices({this.pause = yieldToBrowser, this.idle = waitForIdle, this.clock, this.patience = idlePatience});

  final Future<void> Function() pause;
  final Future<IdleDeadline> Function() idle;
  final int Function()? clock;
  final Duration patience;

  @override
  Future<Catalogue> highlights(String csv, {bool Function()? isAbandoned, bool background = false}) async {
    final load = HighlightsLoad(csv);
    await _run(load.step, isAbandoned, background);
    return load.catalogue;
  }

  @override
  Future<SongsPart> songs(
    Catalogue highlights,
    String csv, {
    bool Function()? isAbandoned,
    bool background = false,
    bool Function()? hurry,
  }) async {
    final load = SongsLoad(highlights, csv);
    await _run(load.step, isAbandoned, background, hurry);
    return load.songs;
  }

  Future<void> _run(bool Function() step, bool Function()? isAbandoned, bool background, [bool Function()? hurry]) =>
      background
      ? runWhenIdle(
          step,
          idle: idle,
          pause: pause,
          isAbandoned: isAbandoned,
          hurry: hurry,
          clock: clock,
          patience: patience,
        )
      : runInSlices(step, pause: pause, clock: clock, maxBudget: longestSlice, isAbandoned: isAbandoned);
}

/// Computes the [TextFingerprint] of the text of a sheet; `isAbandoned` and `background` as for [SheetParser].
typedef TextFingerprinter =
    Future<TextFingerprint> Function(String text, {bool Function()? isAbandoned, bool background});

/// The fingerprint at once: native platforms, where `String.hashCode` is computed natively and kept.
Future<TextFingerprint> fingerprintAtOnce(String text, {bool Function()? isAbandoned, bool background = false}) async =>
    (length: text.length, hash: text.hashCode);

/// The fingerprint in slices, as [ParseInSlices] does: on the web `String.hashCode` is a loop over the code units, a
/// dozen milliseconds for the Songs sheet. The hashes are those of [TextHash]: compare its fingerprints only with
/// each other (the notifier takes both sides of every comparison from the function it was given). [pause], [idle]
/// and [clock] as for [ParseInSlices].
Future<TextFingerprint> fingerprintInSlices(
  String text, {
  bool Function()? isAbandoned,
  bool background = false,
  Future<void> Function() pause = yieldToBrowser,
  Future<IdleDeadline> Function() idle = waitForIdle,
  int Function()? clock,
}) async {
  final hash = TextHash(text);
  bool step() => hash.add(unitsPerPause);
  await (background
      ? runWhenIdle(step, idle: idle, pause: pause, isAbandoned: isAbandoned, clock: clock)
      : runInSlices(step, pause: pause, clock: clock, maxBudget: longestSlice, isAbandoned: isAbandoned));
  return (length: text.length, hash: hash.value);
}

/// The text of a sheet, its time and its fingerprint: a kept copy, a download, or the daily copy.
final class SheetText {
  /// Bundles them.
  const SheetText(this.text, this.fetchedAt, this.fingerprint, {this.isSnapshot = false});

  final String text;

  /// When it was downloaded (UTC); for a snapshot, when the copy was made.
  final DateTime fetchedAt;
  final TextFingerprint fingerprint;

  /// Whether it comes from the daily copy ([SnapshotFetcher]), not from Google.
  final bool isSnapshot;
}

/// Cache, network and parser access for each sheet, without policy (that is `CatalogueNotifier`'s).
final class CatalogueRepository {
  /// Creates the repository. [clock] gives the current time (UTC).
  CatalogueRepository({
    required this.fetcher,
    required this.cache,
    required this.parser,
    this.snapshots = const NoSnapshot(),
    this.fingerprint = fingerprintAtOnce,
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());

  final SheetFetcher fetcher;
  final SheetCache cache;

  /// The daily copy of the sheets ([snapshot]).
  final SnapshotFetcher snapshots;
  final SheetParser parser;
  final TextFingerprinter fingerprint;
  final DateTime Function() clock;

  /// The kept copy of [sheet], or null when there is none. Its fingerprint is computed in the background when
  /// [background]. [isAbandoned]: see [SheetParser].
  Future<SheetText?> readCache(Sheet sheet, {bool Function()? isAbandoned, bool background = false}) async {
    final kept = await cache.read(sheet);
    if (kept == null) return null;
    final print = await fingerprint(kept.text, isAbandoned: isAbandoned, background: background);
    return SheetText(kept.text, kept.fetchedAt, print);
  }

  /// Downloads [sheet] from Google, timed with [clock] when its download is over. Nothing is kept ([keep] does it
  /// once the text parsed).
  Future<SheetText> download(Sheet sheet, {bool Function()? isAbandoned, bool background = false}) async {
    final text = await fetcher.fetch(sheet);
    final fetchedAt = clock();
    if (isAbandoned?.call() ?? false) throw const LoadAbandoned();
    return SheetText(text, fetchedAt, await fingerprint(text, isAbandoned: isAbandoned, background: background));
  }

  /// The daily copy of [sheet], dated when the copy was made. Never kept. Throws when there is none.
  Future<SheetText> snapshot(Sheet sheet, {bool Function()? isAbandoned, bool background = false}) async {
    final copy = await snapshots.fetch(sheet);
    if (isAbandoned?.call() ?? false) throw const LoadAbandoned();
    final print = await fingerprint(copy.text, isAbandoned: isAbandoned, background: background);
    return SheetText(copy.text, copy.fetchedAt, print, isSnapshot: true);
  }

  /// The catalogue of the highlights of [csv]. See [_parse] for its failures.
  Future<Catalogue> parseHighlights(String csv, {bool Function()? isAbandoned, bool background = false}) =>
      _parse(() => parser.highlights(csv, isAbandoned: isAbandoned, background: background));

  /// [highlights] completed with the Songs sheet [csv] (`Catalogue.withSongs`). See [_parse] for its failures,
  /// [SheetParser.songs] for [hurry].
  Future<Catalogue> parseSongs(
    Catalogue highlights,
    String csv, {
    bool Function()? isAbandoned,
    bool background = false,
    bool Function()? hurry,
  }) async => highlights.withSongs(
    await _parse(
      () =>
          parser.songs(highlights.highlightsOnly, csv, isAbandoned: isAbandoned, background: background, hurry: hurry),
    ),
  );

  /// [parse], whose failures on a payload it was not written for (a
  /// [StateError], an [ArgumentError] such as a [RangeError], a [TypeError]:
  /// bugs met on unexpected input) count as a [CatalogueFormatException]. Any other failure is not
  /// about the payload (the isolate could not start, no memory left) and
  /// is thrown as it is: the cache it was reading is good and must be kept.
  static Future<T> _parse<T>(Future<T> Function() parse) async {
    try {
      return await parse();
    } on StateError catch (e) {
      throw CatalogueFormatException('Unreadable sheet: $e');
    } on ArgumentError catch (e) {
      throw CatalogueFormatException('Unreadable sheet: $e');
    } on TypeError catch (e) {
      throw CatalogueFormatException('Unreadable sheet: $e');
    }
  }

  /// Keeps [text] as the copy of [sheet]. A failure only loses the copy.
  Future<void> keep(Sheet sheet, SheetText text) async {
    try {
      await cache.write(sheet, CachedSheet(text: text.text, fetchedAt: text.fetchedAt));
    } catch (e, st) {
      // SheetCache implementations should not throw; the download stays good anyway
      logger.w('Cannot cache the ${sheet.name} sheet', error: e, stackTrace: st);
    }
  }

  /// How long a download much smaller than the copy of its sheet in use is refused, counted from the download of
  /// that copy.
  static const Duration collapseGuard = Duration(days: 1);

  /// Throws a [CatalogueFormatException] when [next] has less than half the highlights of [current]: the sheets
  /// only grow, so that is most likely a wrong answer or a sheet being edited.
  static void checkHighlightsNotCollapsed(Catalogue current, Catalogue next) {
    if (next.highlightCount * 2 < current.highlightCount) {
      throw CatalogueFormatException(
        'Download rejected: ${next.highlightCount} highlights, against ${current.highlightCount} now',
      );
    }
  }

  /// The same for the plays of the Songs sheet.
  static void checkSongsNotCollapsed(Catalogue current, Catalogue next) {
    if (next.playCount * 2 < current.playCount) {
      throw CatalogueFormatException('Download rejected: ${next.playCount} plays, against ${current.playCount} now');
    }
  }

  /// Deletes the kept copy of [sheet], which no longer parses.
  Future<void> forget(Sheet sheet) => cache.remove(sheet);

  /// Deletes the kept sheets.
  Future<void> clearCache() => cache.clear();
}
