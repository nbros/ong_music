/// The files of the branch `data` of the repository: the VODs of the streams (`vods.tsv`) and the groups of names of
/// one requester (`aliases.txt`), edited by hand and by a browser extension, read from raw.githubusercontent.com.
///
/// Downloaded when the sheets are (`CatalogueNotifier`), kept as they are and read again offline. Never needed: when
/// the branch, the network or the cache is missing, the app is as it was before them (no VOD, the table of names it
/// bundles), without a word.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'data_file_cache_stub.dart'
    if (dart.library.io) 'data_file_cache_io.dart'
    if (dart.library.js_interop) 'data_file_cache_web.dart'
    as platform;
import 'sheets.dart';

/// A file of the branch `data`.
enum DataFile {
  /// The VODs of the streams (`VodFile`).
  vods('vods.tsv'),

  /// The groups of names of one requester (`RequesterAliases.tryParse`).
  aliases('aliases.txt');

  const DataFile(this.fileName);

  /// Its name in the branch, and in the cache.
  final String fileName;
}

/// Where the files are read.
abstract final class DataFileUrls {
  /// The directory of the files, ending with `/`: the branch `data` of the repository, unless
  /// `--dart-define=DATA_FILES_URL=<address>/` names another one (tests, a local copy), as `SHEETS_SNAPSHOT_URL`.
  static const base = String.fromEnvironment(
    'DATA_FILES_URL',
    defaultValue: 'https://raw.githubusercontent.com/nbros/ong_music/data/',
  );

  /// The address of [file].
  static Uri of(DataFile file) => Uri.parse('$base${file.fileName}');
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

/// [DataFileFetcher] over HTTP, read as the sheets are ([getSheetText]: UTF-8, a web page refused). The files are
/// small (tens of kilobytes): a shorter silence than the sheets', and the whole download within [maxDuration].
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
      return await getSheetText(client, DataFileUrls.of(file), timeout).timeout(maxDuration);
    } finally {
      if (_client == null) client.close();
    }
  }
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

/// The name of the time of [file] in a cache: `vods_fetched_at.txt`, `aliases_fetched_at.txt`.
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
