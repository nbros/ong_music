/// Persistent cache of the raw sheets, behind a tiny interface.
///
/// Only the raw CSV text and the download time are cached: parsing fixes then
/// apply to already-cached data, and there is no schema to migrate.
library;

import 'sheets.dart';

import 'sheet_cache_stub.dart'
    if (dart.library.io) 'sheet_cache_io.dart'
    if (dart.library.js_interop) 'sheet_cache_web.dart'
    as platform;

/// Stores the last good download of both sheets.
///
/// Implementations never throw: a storage failure reads as "no cache" and a
/// failed write or clear is logged and ignored.
abstract interface class SheetCache {
  /// The cached sheets, or null when there is none (or it is unreadable).
  Future<CachedSheets?> read();

  /// Replaces the cached sheets.
  Future<void> write(CachedSheets sheets);

  /// Deletes the cached sheets.
  Future<void> clear();
}

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
  Future<CachedSheets?> read() async => null;

  @override
  Future<void> write(CachedSheets sheets) async {}

  @override
  Future<void> clear() async {}
}

/// A cache in memory, for tests.
final class MemorySheetCache implements SheetCache {
  /// Creates the cache, optionally filled.
  MemorySheetCache([this.value]);

  /// The current content.
  CachedSheets? value;

  /// Number of [write] calls.
  int writes = 0;

  @override
  Future<CachedSheets?> read() async => value;

  @override
  Future<void> write(CachedSheets sheets) async {
    writes++;
    value = sheets;
  }

  /// Number of [clear] calls.
  int clears = 0;

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}
