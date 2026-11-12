import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logger.dart';
import 'sheet_cache.dart';
import 'sheets.dart';

/// IO platforms: files under the application support directory.
SheetCache createPlatformSheetCache() {
  final dir = getApplicationSupportDirectory();
  if (Platform.isAndroid) unawaited(dir.then(deleteLegacyDatabase, onError: (_) {}));
  return FileSheetCache(() async => Directory(p.join((await dir).path, 'sheets')));
}

/// Deletes, best effort and silently, the SQLite database of versions before
/// the redesign: `<appSupportDir>/../databases/ongLog3.db` and its companions.
Future<void> deleteLegacyDatabase(Directory appSupportDir) async {
  final base = p.join(p.dirname(appSupportDir.path), 'databases', 'ongLog3.db');
  for (final suffix in const ['', '-journal', '-wal', '-shm']) {
    try {
      final file = File('$base$suffix');
      if (await file.exists()) {
        await file.delete();
        logger.i('Deleted legacy database file ${file.path}');
      }
    } catch (_) {
      // best effort
    }
  }
}

/// [SheetCache] in a directory: `highlights.csv`, `songs.csv` and
/// `fetched_at.txt` (ISO-8601 UTC), the latter written last so that an
/// interrupted write reads as the previous cache or as no cache.
final class FileSheetCache implements SheetCache {
  /// Uses the directory returned by [directory] (created when needed).
  FileSheetCache(this.directory);

  /// The cache directory.
  final Future<Directory> Function() directory;

  static const _highlights = 'highlights.csv', _songs = 'songs.csv', _meta = 'fetched_at.txt';

  @override
  Future<CachedSheets?> read() async {
    try {
      final dir = await directory();
      final meta = File(p.join(dir.path, _meta));
      if (!await meta.exists()) return null;
      final fetchedAt = DateTime.tryParse((await meta.readAsString()).trim());
      if (fetchedAt == null) return null;
      final texts = await Future.wait([
        File(p.join(dir.path, _highlights)).readAsString(),
        File(p.join(dir.path, _songs)).readAsString(),
      ]);
      return CachedSheets(
        sheets: RawSheets(highlightsCsv: texts[0], songsCsv: texts[1]),
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
      final dir = await directory();
      await dir.create(recursive: true);
      await _deleteStaleTemporaryFiles(dir);
      final meta = File(p.join(dir.path, _meta));
      if (await meta.exists()) await meta.delete();
      await _writeAtomically(File(p.join(dir.path, _highlights)), sheets.sheets.highlightsCsv);
      await _writeAtomically(File(p.join(dir.path, _songs)), sheets.sheets.songsCsv);
      await _writeAtomically(meta, sheets.fetchedAt.toUtc().toIso8601String());
    } catch (e) {
      logger.w('Cannot write the sheet cache: $e');
    }
  }

  /// A temporary file older than this belongs to no write still running.
  static const Duration _temporaryFileMaxAge = Duration(minutes: 10);

  /// Deletes the temporary files of writes that never finished (the app was
  /// killed in the middle): megabytes each, under a name no later write uses
  /// again. Recent ones may belong to a write running in another instance.
  static Future<void> _deleteStaleTemporaryFiles(Directory dir) async {
    try {
      final limit = DateTime.now().subtract(_temporaryFileMaxAge);
      await for (final entry in dir.list()) {
        if (entry is File && entry.path.endsWith('.tmp') && (await entry.lastModified()).isBefore(limit)) {
          await entry.delete();
        }
      }
    } catch (_) {
      // best effort: the next write tries again
    }
  }

  /// Makes the temporary file names unique within the process.
  static int _tmpCount = 0;

  /// Writes to a temporary file of this write only, then renames it: another
  /// write running at the same time (the app started twice, or a download of
  /// an earlier build still finishing) never writes into the same file.
  static Future<void> _writeAtomically(File file, String text) async {
    final tmp = File('${file.path}.$pid-${_tmpCount++}.tmp');
    try {
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      try {
        await tmp.delete();
      } catch (_) {
        // already gone
      }
      rethrow;
    }
  }

  @override
  Future<void> clear() async {
    try {
      final dir = await directory();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      logger.w('Cannot clear the sheet cache: $e');
    }
  }
}
