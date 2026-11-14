/// The daily copy of the two sheets (the "snapshot"): shown on a first load, until Google's own answer replaces it.
///
/// Google takes one to two seconds to start answering the CSV exports, a static file a few tens of milliseconds. Once
/// a day `.github/workflows/sheets_snapshot.yml` (with `tool/sheets_snapshot.sh`) copies both exports, as Google gives
/// them, to the branch `sheets-snapshot` of the repository, read here from raw.githubusercontent.com.
///
/// Only a load with nothing kept asks for it (`CatalogueNotifier`), and Google is asked at the same time, as on
/// every other load: the copy only fills the screen for the second or so before Google's answer, whatever its age
/// (the schedule may have stopped for months). It is never kept (`SheetCache`), and the data it shows counts as due
/// for a download.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sheet_prefetch.dart';
import 'sheets.dart';

/// Where the snapshot is read.
abstract final class SnapshotUrls {
  /// The directory of the three files, ending with `/`: the branch `sheets-snapshot` of the repository, unless
  /// `--dart-define=SHEETS_SNAPSHOT_URL=<address>/` names another one (tests, a local copy). `web/index.html` holds
  /// the default address too, and starts the downloads before the app runs (see [takePrefetchedSnapshot]).
  static const base = String.fromEnvironment(
    'SHEETS_SNAPSHOT_URL',
    defaultValue: 'https://raw.githubusercontent.com/nbros/ong_music/sheets-snapshot/',
  );

  /// The "Youtube Catalogue" sheet, as Google exports it.
  static final Uri highlights = Uri.parse('${base}highlights.csv');

  /// The "Songs" sheet, as Google exports it.
  static final Uri songs = Uri.parse('${base}songs.csv');

  /// When the copy was made: `{"madeAt": "2026-11-14T04:23:51Z", ...}`.
  static final Uri meta = Uri.parse('${base}snapshot.json');
}

/// The time of a snapshot, read from its [SnapshotUrls.meta] file: its `madeAt`, an ISO-8601 time in UTC. Throws a
/// [FormatException] for anything else.
DateTime snapshotTime(String json) {
  final Object? meta;
  try {
    meta = jsonDecode(json);
  } on FormatException {
    throw const FormatException('The time of the snapshot is not JSON');
  }
  final madeAt = meta is Map<String, Object?> ? meta['madeAt'] : null;
  final time = madeAt is String ? DateTime.tryParse(madeAt) : null;
  if (time == null || !time.isUtc) throw FormatException('No UTC time in the snapshot: $madeAt');
  return time;
}

/// Downloads the snapshot.
abstract interface class SnapshotFetcher {
  /// The snapshot and the time it was made ([CachedSheets.fetchedAt]). Throws when there is none (the branch does not
  /// exist: HTTP 404) or it cannot be read; its content is checked by the parser.
  Future<CachedSheets> fetch();
}

/// No snapshot: [fetch] always fails.
final class NoSnapshot implements SnapshotFetcher {
  /// Creates the fetcher.
  const NoSnapshot();

  @override
  Future<CachedSheets> fetch() async => throw StateError('No snapshot');
}

/// [SnapshotFetcher] over HTTP, the three files in parallel, read as the sheets are ([getSheetText]).
final class HttpSnapshotFetcher implements SnapshotFetcher {
  /// Uses [client] (a new one per fetch when null). [timeout] and [maxDuration] as for [HttpSheetFetcher].
  HttpSnapshotFetcher({
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
    this.maxDuration = const Duration(minutes: 10),
  }) : _client = client;

  final http.Client? _client;
  final Duration timeout;
  final Duration maxDuration;

  @override
  Future<CachedSheets> fetch() async {
    // web, first visit: the downloads the page started while the app was loading
    final prefetched = await takePrefetchedSnapshot(timeout: timeout).timeout(maxDuration);
    if (prefetched != null) return _read(prefetched);
    final client = _client ?? http.Client();
    try {
      final texts = await Future.wait([
        getSheetText(client, SnapshotUrls.highlights, timeout),
        getSheetText(client, SnapshotUrls.songs, timeout),
        getSheetText(client, SnapshotUrls.meta, timeout),
      ]).timeout(maxDuration);
      return _read((highlights: texts[0], songs: texts[1], meta: texts[2]));
    } finally {
      if (_client == null) client.close();
    }
  }

  static CachedSheets _read(SnapshotTexts texts) => CachedSheets(
    sheets: RawSheets(highlightsCsv: texts.highlights, songsCsv: texts.songs),
    fetchedAt: snapshotTime(texts.meta),
  );
}
