/// The data files: those of the branch `data` of the repository, the VODs of the streams (`vods.tsv`), their offsets
/// (`offsets.tsv`) and the groups of names of one requester (`aliases.txt`), edited by hand and by a browser extension;
/// and the links of the songs to their originals (`song_links.tsv`), made each day from the Songs sheet with its
/// snapshot, on the branch `sheets-snapshot` (`lib/src/data/song_links.dart`). Read from raw.githubusercontent.com.
///
/// Downloaded when the sheets are (`CatalogueNotifier`), kept as they are and read again offline. Never needed: when
/// the branch, the network or the cache is missing, the app is as it was before them (no VOD, the table of names it
/// bundles, no link to an original), without a word.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'data_file_cache_stub.dart'
    if (dart.library.io) 'data_file_cache_io.dart'
    if (dart.library.js_interop) 'data_file_cache_web.dart'
    as platform;
import 'page_thread.dart';
import 'sheet_snapshot.dart';
import 'sheets.dart';

/// The largest `vods.tsv` taken, in bytes: today about 100 KB, a line per video (a thousand a decade). Beyond, the
/// download counts as failed: it is read on the thread of the page.
const int maxVodsBytes = 2 * 1024 * 1024;

/// The largest `aliases.txt` taken, in bytes: today about 4 KB.
const int maxAliasesBytes = 256 * 1024;

/// The largest `offsets.tsv` taken, in bytes: a line per stream or per play corrected, a few dozen bytes each.
const int maxOffsetsBytes = 256 * 1024;

/// The largest `song_links.tsv` taken, in bytes: about 470 KB in November 2026 (265 KB on the wire), a line per title
/// of the Songs sheet with a link, which grows by some hundreds of new titles a year.
const int maxSongLinksBytes = 2 * 1024 * 1024;

/// A data file.
enum DataFile {
  /// The VODs of the streams (`VodFile`).
  vods('vods.tsv', maxVodsBytes),

  /// The groups of names of one requester (`RequesterAliases.tryParse`).
  aliases('aliases.txt', maxAliasesBytes),

  /// The offsets of the VODs (`OffsetFile`): where a play is in a recording that does not start with its stream.
  offsets('offsets.tsv', maxOffsetsBytes),

  /// The links of the songs to their originals (`SongLinks`), of the branch `sheets-snapshot`.
  songLinks('song_links.tsv', maxSongLinksBytes, inSnapshot: true);

  const DataFile(this.fileName, this.maxBytes, {this.inSnapshot = false});

  /// Its name in the branch, and in the cache.
  final String fileName;

  /// The largest download of it taken ([maxVodsBytes], [maxAliasesBytes], [maxOffsetsBytes], [maxSongLinksBytes]).
  final int maxBytes;

  /// Whether it is a file of the snapshot of the sheets ([SnapshotUrls.base]), made with it each day, rather than of
  /// the branch `data` ([DataFileUrls.base]).
  final bool inSnapshot;
}

/// A download of a data file larger than its [DataFile.maxBytes]: its body is not read further.
class DataFileTooLargeException implements Exception {
  /// Creates the exception.
  const DataFileTooLargeException(this.file);

  final DataFile file;

  @override
  String toString() => '${file.fileName} larger than ${file.maxBytes} bytes';
}

/// Where the files are read.
abstract final class DataFileUrls {
  /// The directory of the files, ending with `/`: the branch `data` of the repository, unless
  /// `--dart-define=DATA_FILES_URL=<address>/` names another one (tests, a local copy), as `SHEETS_SNAPSHOT_URL`.
  static const base = String.fromEnvironment(
    'DATA_FILES_URL',
    defaultValue: 'https://raw.githubusercontent.com/nbros/ong_music/data/',
  );

  /// The address of [file]: in [base], or beside the snapshot of the sheets ([SnapshotUrls.base]).
  static Uri of(DataFile file) => Uri.parse('${file.inSnapshot ? SnapshotUrls.base : base}${file.fileName}');
}

/// Downloads the files.
abstract interface class DataFileFetcher {
  /// The text of [file]. Throws on any network or HTTP error (404 while the branch does not exist), and for a web
  /// page instead of the file.
  Future<String> fetch(DataFile file);
}

/// No file: [fetch] always fails (tests).
final class NoDataFiles implements DataFileFetcher {
  /// Creates the fetcher.
  const NoDataFiles();

  @override
  Future<String> fetch(DataFile file) async => throw StateError('No data files');
}

/// Whether [text] is larger than [file] may be (`DataFile.maxBytes`), in bytes of UTF-8: counted only when the
/// number of its code units does not tell (a code unit is one to three bytes).
bool dataFileTooLarge(DataFile file, String text) {
  final max = file.maxBytes;
  if (text.length > max) return true;
  if (text.length * 3 <= max) return false;
  return utf8.encode(text).length > max;
}

/// [DataFileFetcher] over HTTP, read as the sheets are (UTF-8 whatever the declared charset, a [SheetHttpException]
/// for an answer that is not a 200, a [SheetNotCsvException] for a web page), and at most [DataFile.maxBytes] of it:
/// beyond, the body is not read further and a [DataFileTooLargeException] is thrown. The files are small: a shorter
/// silence than the sheets', and the whole download within [maxDuration].
final class HttpDataFileFetcher implements DataFileFetcher {
  /// Uses [client] (a new one per fetch when null).
  HttpDataFileFetcher({
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.maxDuration = const Duration(minutes: 2),
  }) : _client = client;

  final http.Client? _client;
  final Duration timeout;
  final Duration maxDuration;

  @override
  Future<String> fetch(DataFile file) async {
    final client = _client ?? http.Client();
    try {
      return await _get(client, file, timeout).timeout(maxDuration);
    } finally {
      if (_client == null) client.close();
    }
  }
}

Future<String> _get(http.Client client, DataFile file, Duration timeout) async {
  final uri = DataFileUrls.of(file);
  final response = await client.send(http.Request('GET', uri)).timeout(timeout);
  if (response.statusCode != 200) {
    unawaited(response.stream.listen(null).cancel());
    throw SheetHttpException(uri, response.statusCode);
  }
  final declared = response.contentLength;
  if (declared != null && declared > file.maxBytes) {
    unawaited(response.stream.listen(null).cancel());
    throw DataFileTooLargeException(file);
  }
  final bytes = BytesBuilder(copy: false);
  // leaving the loop (by the exception) stops listening to the body
  await for (final chunk in response.stream.timeout(timeout)) {
    bytes.add(chunk);
    if (bytes.length > file.maxBytes) throw DataFileTooLargeException(file);
  }
  return sheetCsv(decodeUtf8(bytes.takeBytes()), uri);
}

/// Keeps the last good download of each file, with its time ([CachedSheet]), apart from the sheets: files under
/// the application support directory (`data/`) on IO platforms, the browser Cache API on the web.
///
/// Implementations never throw: a storage failure reads as "nothing kept", a failed write or clear is logged and
/// ignored.
abstract interface class DataFileCache {
  /// The kept copy of [file], or null.
  Future<CachedSheet?> read(DataFile file);

  /// Replaces the kept copy of [file].
  Future<void> write(DataFile file, CachedSheet value);

  /// Deletes every kept file.
  Future<void> clear();
}

/// The name of the time of [file] in a cache: `vods_fetched_at.txt`, `aliases_fetched_at.txt`,
/// `offsets_fetched_at.txt`, `songLinks_fetched_at.txt`.
String dataFileTimeName(DataFile file) => '${file.name}_fetched_at.txt';

/// The cache of this platform (see [DataFileCache]).
DataFileCache createDataFileCache() => platform.createPlatformDataFileCache();

/// A cache that keeps nothing.
final class NoDataFileCache implements DataFileCache {
  /// Creates the cache.
  const NoDataFileCache();

  @override
  Future<CachedSheet?> read(DataFile file) async => null;

  @override
  Future<void> write(DataFile file, CachedSheet value) async {}

  @override
  Future<void> clear() async {}
}

/// A cache in memory, for tests.
final class MemoryDataFileCache implements DataFileCache {
  /// Creates the cache, optionally filled.
  MemoryDataFileCache([Map<DataFile, CachedSheet>? values]) : values = {...?values};

  /// The current content.
  final Map<DataFile, CachedSheet> values;

  /// The files read and written, in order.
  final reads = <DataFile>[];
  final writes = <DataFile>[];

  /// When set, [read] waits for it.
  Completer<void>? gate;

  /// Number of [clear] calls.
  int clears = 0;

  @override
  Future<CachedSheet?> read(DataFile file) async {
    reads.add(file);
    if (gate != null) await gate!.future;
    return values[file];
  }

  @override
  Future<void> write(DataFile file, CachedSheet value) async {
    writes.add(file);
    values[file] = value;
  }

  @override
  Future<void> clear() async {
    clears++;
    values.clear();
  }
}
