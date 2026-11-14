/// Persistent cache of the raw sheets, behind a tiny interface.
///
/// Only the raw CSV text and the download time of each sheet are cached: parsing fixes then apply to already-cached
/// data, and there is no schema to migrate (the time of both sheets of the versions up to 2.0.0 is read too).
library;

import 'dart:async';

import 'sheets.dart';

import 'sheet_cache_stub.dart'
    if (dart.library.io) 'sheet_cache_io.dart'
    if (dart.library.js_interop) 'sheet_cache_web.dart'
    as platform;

/// Stores the last good download of each sheet, with its time: each sheet is read, written and refreshed on its own
/// (the Highlights list starts from its sheet alone).
///
/// Data kept by versions up to 2.0.0 has one time for both sheets, written last after both texts: it reads as the
/// time of each of them until a sheet is written again, which first gives each sheet that time of its own
/// ([legacyTimeName]).
///
/// Implementations never throw: a storage failure reads as "no cache" and a
/// failed write or clear is logged and ignored.
abstract interface class SheetCache {
  /// The kept copy of [sheet], or null when there is none (or it is unreadable).
  Future<CachedSheet?> read(Sheet sheet);

  /// Replaces the kept copy of [sheet].
  Future<void> write(Sheet sheet, CachedSheet value);

  /// Deletes the kept copy of [sheet] (it no longer parses); the other one stays.
  Future<void> remove(Sheet sheet);

  /// Deletes both.
  Future<void> clear();
}

/// The name of the text of [sheet] in a cache: `highlights.csv`, `songs.csv`.
String sheetTextName(Sheet sheet) => '${sheet.name}.csv';

/// The name of the time of [sheet] in a cache: `highlights_fetched_at.txt`, `songs_fetched_at.txt`.
String sheetTimeName(Sheet sheet) => '${sheet.name}_fetched_at.txt';

/// The name of the time of both sheets in the caches of versions up to 2.0.0.
const legacyTimeName = 'fetched_at.txt';

/// The cache of this platform: files under the application support directory
/// on IO platforms, the browser Cache API on web (or no cache when the browser
/// does not offer it).
///
/// On Android this also deletes, best effort, the SQLite database left by
/// versions before the redesign (`databases/ongLog3.db`). Do not call it while
/// the old `EntryManager` code is still in use.
SheetCache createSheetCache() => platform.createPlatformSheetCache();

/// A cache that keeps nothing.
final class NoSheetCache implements SheetCache {
  /// Creates the cache.
  const NoSheetCache();

  @override
  Future<CachedSheet?> read(Sheet sheet) async => null;

  @override
  Future<void> write(Sheet sheet, CachedSheet value) async {}

  @override
  Future<void> remove(Sheet sheet) async {}

  @override
  Future<void> clear() async {}
}

/// A cache in memory, for tests.
final class MemorySheetCache implements SheetCache {
  /// Creates the cache, optionally filled.
  MemorySheetCache({CachedSheet? highlights, CachedSheet? songs})
    : values = {Sheet.highlights: ?highlights, Sheet.songs: ?songs};

  /// The current content.
  final Map<Sheet, CachedSheet> values;

  /// The sheets read, in order.
  final reads = <Sheet>[];

  /// The sheets written, in order.
  final writes = <Sheet>[];

  /// When set, [read] waits for it.
  Completer<void>? gate;

  @override
  Future<CachedSheet?> read(Sheet sheet) async {
    reads.add(sheet);
    if (gate != null) await gate!.future;
    return values[sheet];
  }

  @override
  Future<void> write(Sheet sheet, CachedSheet value) async {
    writes.add(sheet);
    values[sheet] = value;
  }

  /// The sheets removed, in order.
  final removes = <Sheet>[];

  @override
  Future<void> remove(Sheet sheet) async {
    removes.add(sheet);
    values.remove(sheet);
  }

  /// Number of [clear] calls.
  int clears = 0;

  @override
  Future<void> clear() async {
    clears++;
    values.clear();
  }
}
