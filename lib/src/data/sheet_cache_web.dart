import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../logger.dart';
import 'sheet_cache.dart';
import 'sheets.dart';

/// Web: the browser Cache API.
SheetCache createPlatformSheetCache() => const WebSheetCache();

/// [SheetCache] in the browser Cache API (`window.caches`).
///
/// Degrades to "no cache" without throwing when the API is missing (non-secure
/// context) or refused (some private modes).
final class WebSheetCache implements SheetCache {
  /// Creates the cache.
  const WebSheetCache();

  /// Name of the cache in `window.caches`.
  static const cacheName = 'ong-music-sheets-v1';

  // keys are resolved against the page URL; never fetched
  static const _highlights = 'ong-music-cache/highlights.csv',
      _songs = 'ong-music-cache/songs.csv',
      _meta = 'ong-music-cache/fetched_at.txt';

  static Future<web.Cache?> _open() async {
    if (!globalContext.has('caches') || globalContext['caches'] == null) return null;
    return web.window.caches.open(cacheName).toDart;
  }

  static Future<String?> _get(web.Cache cache, String key) async {
    final response = await cache.match(key.toJS).toDart;
    if (response == null) return null;
    return (await response.text().toDart).toDart;
  }

  static Future<void> _put(web.Cache cache, String key, String text) =>
      cache.put(key.toJS, web.Response(text.toJS)).toDart;

  @override
  Future<CachedSheets?> read() async {
    try {
      final cache = await _open();
      if (cache == null) return null;
      final meta = await _get(cache, _meta);
      final fetchedAt = meta == null ? null : DateTime.tryParse(meta.trim());
      if (fetchedAt == null) return null;
      final highlights = await _get(cache, _highlights);
      final songs = await _get(cache, _songs);
      if (highlights == null || songs == null) return null;
      return CachedSheets(
        sheets: RawSheets(highlightsCsv: highlights, songsCsv: songs),
        fetchedAt: fetchedAt.toUtc(),
      );
    } catch (e) {
      logger.w('Cannot read the sheet cache: $e');
      return null;
    }
  }

  @override
  Future<void> write(CachedSheets sheets) async {
    try {
      final cache = await _open();
      if (cache == null) return;
      await cache.delete(_meta.toJS).toDart;
      await _put(cache, _highlights, sheets.sheets.highlightsCsv);
      await _put(cache, _songs, sheets.sheets.songsCsv);
      await _put(cache, _meta, sheets.fetchedAt.toUtc().toIso8601String());
    } catch (e) {
      logger.w('Cannot write the sheet cache: $e');
    }
  }

  @override
  Future<void> clear() async {
    try {
      if (!globalContext.has('caches') || globalContext['caches'] == null) return;
      await web.window.caches.delete(cacheName).toDart;
    } catch (e) {
      logger.w('Cannot clear the sheet cache: $e');
    }
  }
}
