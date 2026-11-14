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

/// [SheetCache] in a directory: per sheet its text and its time (ISO-8601 UTC), `highlights.csv` and
/// `highlights_fetched_at.txt`, `songs.csv` and `songs_fetched_at.txt`, the time written last so that an interrupted
/// write reads as the previous copy of the sheet or as none. A `fetched_at.txt` left by a version up to 2.0.0 is the
/// time of both sheets, until the first write gives each one its own.
final class FileSheetCache implements SheetCache {
  /// Uses the directory returned by [directory] (created when needed).
  FileSheetCache(this.directory);

  /// The cache directory.
  final Future<Directory> Function() directory;

  @override
  Future<CachedSheet?> read(Sheet sheet) async {
    try {
      final dir = await directory();
      // its own time again after the old shared one: a write running meanwhile replaces the latter with the former
      final own = File(p.join(dir.path, sheetTimeName(sheet)));
      final fetchedAt = await _time(own) ?? await _time(File(p.join(dir.path, legacyTimeName))) ?? await _time(own);
      if (fetchedAt == null) return null;
      final text = await File(p.join(dir.path, sheetTextName(sheet))).readAsString();
      return CachedSheet(text: text, fetchedAt: fetchedAt.toUtc());
    } catch (e) {
      logger.w('Cannot read the sheet cache: $e');
      return null;
    }
  }

  static Future<DateTime?> _time(File file) async =>
      await file.exists() ? DateTime.tryParse((await file.readAsString()).trim()) : null;

  @override
  Future<void> write(Sheet sheet, CachedSheet value) async {
    try {
      final dir = await directory();
      await dir.create(recursive: true);
      await _deleteStaleTemporaryFiles(dir);
      await _splitLegacyTime(dir);
      final meta = File(p.join(dir.path, sheetTimeName(sheet)));
      if (await meta.exists()) await meta.delete();
      await _writeAtomically(File(p.join(dir.path, sheetTextName(sheet))), value.text);
      await _writeAtomically(meta, value.fetchedAt.toUtc().toIso8601String());
    } catch (e) {
      logger.w('Cannot write the sheet cache: $e');
    }
  }

  @override
  Future<void> remove(Sheet sheet) async {
    try {
      final dir = await directory();
      if (!await dir.exists()) return;
      await _splitLegacyTime(dir);
      for (final name in [sheetTimeName(sheet), sheetTextName(sheet)]) {
        final file = File(p.join(dir.path, name));
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      logger.w('Cannot remove from the sheet cache: $e');
    }
  }

  /// The time of both sheets left by a version up to 2.0.0, if any, becomes the time of each one that has none of
  /// its own; then it goes, before a sheet is written alone: it would date the other one too.
  ///
  /// Two writes may do it at once (both sheets downloaded together, another instance): the file one of them deletes
  /// first is gone for the other, which then has nothing left to do.
  static Future<void> _splitLegacyTime(Directory dir) async {
    final legacy = File(p.join(dir.path, legacyTimeName));
    final String time;
    try {
      time = await legacy.readAsString();
    } on FileSystemException {
      return; // none, or split by another write meanwhile
    }
    for (final sheet in Sheet.values) {
      final own = File(p.join(dir.path, sheetTimeName(sheet)));
      if (!await own.exists() && await File(p.join(dir.path, sheetTextName(sheet))).exists()) {
        await _writeAtomically(own, time);
      }
    }
    try {
      await legacy.delete();
    } on FileSystemException {
      // deleted by another write meanwhile
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
