import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../logger.dart';
import 'data_files.dart';
import 'sheets.dart';

/// Web: the browser Cache API.
DataFileCache createPlatformDataFileCache() => const WebDataFileCache();

/// [DataFileCache] in the browser Cache API (`window.caches`), a cache of its own beside that of the sheets
/// (`WebSheetCache`), the time of a file written last. Degrades to "nothing kept" without throwing when the API is
/// missing or refused.
final class WebDataFileCache implements DataFileCache {
  /// Creates the cache.
  const WebDataFileCache();

  /// Name of the cache in `window.caches`.
  static const cacheName = 'ong-music-data-v1';

  /// The key of a file of the cache: resolved against the page URL, never fetched.
  static String key(String name) => 'ong-music-cache/data/$name';

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

  @override
  Future<CachedSheet?> read(DataFile file) async {
    try {
      final cache = await _open();
      if (cache == null) return null;
      final time = await _get(cache, dataFileTimeName(file));
      final fetchedAt = time == null ? null : DateTime.tryParse(time.trim());
      if (fetchedAt == null) return null;
      final text = await _get(cache, file.fileName);
      if (text == null) return null;
      return CachedSheet(text: text, fetchedAt: fetchedAt.toUtc());
    } catch (e) {
      logger.w('Cannot read the kept ${file.fileName}: $e');
      return null;
    }
  }

  @override
  Future<void> write(DataFile file, CachedSheet value) async {
    try {
      final cache = await _open();
      if (cache == null) return;
      await cache.delete(key(dataFileTimeName(file)).toJS).toDart;
      await _put(cache, file.fileName, value.text);
      await _put(cache, dataFileTimeName(file), value.fetchedAt.toUtc().toIso8601String());
    } catch (e) {
      logger.w('Cannot keep ${file.fileName}: $e');
    }
  }

  @override
  Future<void> clear() async {
    try {
      if (!globalContext.has('caches') || globalContext['caches'] == null) return;
      await web.window.caches.delete(cacheName).toDart;
    } catch (e) {
      logger.w('Cannot clear the kept data files: $e');
    }
  }
}
