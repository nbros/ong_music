/// The downloads that `web/index.html` starts while the web app loads: the Highlights sheet when the copy kept of it
/// is missing or stale, and on a first visit (nothing kept) the daily copy of it (`sheet_snapshot.dart`). The app
/// takes them instead of starting its own, a second or more later. The page starts nothing for the Songs sheet: when
/// it is downloaded is the app's choice (`CatalogueNotifier.songsWanted`): after the Highlights list.
library;

import 'sheets.dart';

import 'sheet_prefetch_stub.dart' if (dart.library.js_interop) 'sheet_prefetch_web.dart' as platform;

/// The text of [sheet] downloaded by the page, or null when it started no download of it (kept copy fresh, the Songs
/// sheet, not on the web) or when it was already taken: only the first call for a sheet can return it. Throws like
/// [HttpSheetFetcher.fetch] when that download failed, or when its answer has not started after [timeout].
Future<String?> takePrefetchedSheet(Sheet sheet, {Duration timeout = const Duration(seconds: 45)}) =>
    platform.takePrefetchedSheet(sheet, timeout: timeout);

/// Forgets the sheet downloads started by the page, if any. To call when the app
/// starts on a kept copy it finds fresh after all (another tab wrote it while this
/// one was loading) and so downloads nothing: left there, the page's download
/// would be taken by the next refresh, hours later, and pass for the sheet of
/// that moment.
void discardPrefetchedSheets() => platform.discardPrefetchedSheets();

/// Forgets the snapshot downloads started by the page, if any: data is kept, the snapshot is not wanted.
void discardPrefetchedSnapshot() => platform.discardPrefetchedSnapshot();

/// A file of the snapshot (`SnapshotUrls`) downloaded by the page: `highlights.csv`, `songs.csv` or
/// `snapshot.json`. Null when it started no download of it (something is kept, the Songs sheet, not on the web),
/// when it downloaded from another address than `SnapshotUrls.base` (an app built with another one), or when it was
/// already taken: only the first call for a file can return it. Throws as [takePrefetchedSheet] does.
Future<String?> takePrefetchedSnapshotFile(String name, {Duration timeout = const Duration(seconds: 45)}) =>
    platform.takePrefetchedSnapshotFile(name, timeout: timeout);
