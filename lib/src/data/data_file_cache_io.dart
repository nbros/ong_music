import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logger.dart';
import 'data_files.dart';
import 'sheets.dart';

/// IO platforms: files under the application support directory, beside the sheets.
DataFileCache createPlatformDataFileCache() =>
    FileDataFileCache(() async => Directory(p.join((await getApplicationSupportDirectory()).path, 'data')));

/// [DataFileCache] in a directory: per file its text and its time (ISO-8601 UTC), `vods.tsv` and
/// `vods_fetched_at.txt`, the time written last, as `FileSheetCache` does: an interrupted write reads as the previous
/// copy or as none.
final class FileDataFileCache implements DataFileCache {
  /// Uses the directory returned by [directory] (created when needed).
  FileDataFileCache(this.directory);

  final Future<Directory> Function() directory;

  @override
  Future<CachedSheet?> read(DataFile file) async {
    try {
      final dir = await directory();
      final time = File(p.join(dir.path, dataFileTimeName(file)));
      if (!await time.exists()) return null;
      final fetchedAt = DateTime.tryParse((await time.readAsString()).trim());
      if (fetchedAt == null) return null;
      final text = await File(p.join(dir.path, file.fileName)).readAsString();
      return CachedSheet(text: text, fetchedAt: fetchedAt.toUtc());
    } catch (e) {
      logger.w('Cannot read the kept ${file.fileName}: $e');
      return null;
    }
  }

  @override
  Future<void> write(DataFile file, CachedSheet value) async {
    try {
      final dir = await directory();
      await dir.create(recursive: true);
      final time = File(p.join(dir.path, dataFileTimeName(file)));
      if (await time.exists()) await time.delete();
      await _writeAtomically(File(p.join(dir.path, file.fileName)), value.text);
      await _writeAtomically(time, value.fetchedAt.toUtc().toIso8601String());
    } catch (e) {
      logger.w('Cannot keep ${file.fileName}: $e');
    }
  }

  static int _tmpCount = 0;

  /// Writes to a temporary file of this write only, then renames it.
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
      logger.w('Cannot clear the kept data files: $e');
    }
  }
}
