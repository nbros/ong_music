import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../logger.dart';
import 'sheet_cache.dart';
import 'sheets.dart';

/// Web: the browser Cache API.
SheetCache createPlatformSheetCache() => const WebSheetCache();

/// [SheetCache] in the browser Cache API (`window.caches`): the files of [FileSheetCache], under
/// `ong-music-cache/`, the time of a sheet written last.
///
/// Degrades to "no cache" without throwing when the API is missing (non-secure
/// context) or refused (some private modes).
final class WebSheetCache implements SheetCache {
  /// Creates the cache.
  const WebSheetCache();

  /// Name of the cache in `window.caches`.
  static const cacheName = 'ong-music-sheets-v1';

  /// The key of a file of the cache: resolved against the page URL, never fetched.
  static String key(String name) => 'ong-music-cache/$name';

  static Future<web.Cache?> _open() async {
    if (!globalContext.has('caches') || globalContext['caches'] == null) return null;
    return web.window.caches.open(cacheName).toDart;
  }

  static Future<String?> _get(web.Cache cache, String name) async {
    final response = await cache.match(key(name).toJS).toDart;
    if (response == null) return null;
    return (await response.text().toDart).toDart;
  }

  static Future<void> _put(web.Cache cache, String name, String text) =>
      cache.put(key(name).toJS, web.Response(text.toJS)).toDart;

  static Future<void> _delete(web.Cache cache, String name) => cache.delete(key(name).toJS).toDart;

  @override
  Future<CachedSheet?> read(Sheet sheet) async {
    try {
      final cache = await _open();
      if (cache == null) return null;
      // its own time again after the old shared one: a write running meanwhile replaces the latter with the former
      final meta =
          await _get(cache, sheetTimeName(sheet)) ??
          await _get(cache, legacyTimeName) ??
          await _get(cache, sheetTimeName(sheet));
      final fetchedAt = meta == null ? null : DateTime.tryParse(meta.trim());
      if (fetchedAt == null) return null;
      final text = await _get(cache, sheetTextName(sheet));
      if (text == null) return null;
      return CachedSheet(text: text, fetchedAt: fetchedAt.toUtc());
    } catch (e) {
      logger.w('Cannot read the sheet cache: $e');
      return null;
    }
  }

  @override
  Future<void> write(Sheet sheet, CachedSheet value) async {
    try {
      final cache = await _open();
      if (cache == null) return;
      await _splitLegacyTime(cache);
      await _delete(cache, sheetTimeName(sheet));
      await _put(cache, sheetTextName(sheet), value.text);
      await _put(cache, sheetTimeName(sheet), value.fetchedAt.toUtc().toIso8601String());
    } catch (e) {
      logger.w('Cannot write the sheet cache: $e');
    }
  }

  @override
  Future<void> remove(Sheet sheet) async {
    try {
      final cache = await _open();
      if (cache == null) return;
      await _splitLegacyTime(cache);
      await _delete(cache, sheetTimeName(sheet));
      await _delete(cache, sheetTextName(sheet));
    } catch (e) {
      logger.w('Cannot remove from the sheet cache: $e');
    }
  }

  /// As [FileSheetCache] does: the time of both sheets of a version up to 2.0.0 becomes that of each one.
  static Future<void> _splitLegacyTime(web.Cache cache) async {
    final time = await _get(cache, legacyTimeName);
    if (time == null) return;
    for (final sheet in Sheet.values) {
      if (await _get(cache, sheetTimeName(sheet)) == null &&
          (await cache.match(key(sheetTextName(sheet)).toJS).toDart) != null) {
        await _put(cache, sheetTimeName(sheet), time);
      }
    }
    await _delete(cache, legacyTimeName);
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
