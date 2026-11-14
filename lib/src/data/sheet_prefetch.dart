/// The sheets download that `web/index.html` starts while the web app loads,
/// when the cache is missing or stale (first visit): the app takes it instead
/// of starting its own, a second or more later. And on a first visit (nothing
/// kept), the download of the daily copy of the sheets (`sheet_snapshot.dart`).
library;

import 'sheets.dart';

import 'sheet_prefetch_stub.dart' if (dart.library.js_interop) 'sheet_prefetch_web.dart' as platform;

/// The sheets downloaded by the page, or null when it started no download
/// (cache fresh, not on the web) or when they were already taken: only the first
/// call can return them. Throws like [HttpSheetFetcher.fetch] when that download
/// failed, or when an answer has not started after [timeout].
Future<RawSheets?> takePrefetchedSheets({Duration timeout = const Duration(seconds: 45)}) =>
    platform.takePrefetchedSheets(timeout: timeout);

/// Forgets the sheets downloaded by the page, if any. To call when the app
/// starts on a cache it finds fresh after all (another tab wrote it while this
/// one was loading) and so downloads nothing: left there, the page's download
/// would be taken by the next refresh, hours later, and pass for the sheets of
/// that moment.
void discardPrefetchedSheets() => platform.discardPrefetchedSheets();

/// Forgets the snapshot downloads started by the page, if any: data is kept, the snapshot is not wanted.
void discardPrefetchedSnapshot() => platform.discardPrefetchedSnapshot();

/// The three files of a snapshot (`SnapshotUrls`), as downloaded.
typedef SnapshotTexts = ({String highlights, String songs, String meta});

/// The snapshot downloaded by the page, or null when it started no download
/// (something is kept, not on the web), when it downloaded from another address
/// than `SnapshotUrls.base` (an app built with another one), or when it was
/// already taken: only the first call can return it. Throws as
/// [takePrefetchedSheets] does.
Future<SnapshotTexts?> takePrefetchedSnapshot({Duration timeout = const Duration(seconds: 45)}) =>
    platform.takePrefetchedSnapshot(timeout: timeout);
